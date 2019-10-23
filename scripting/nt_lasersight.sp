#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif
#define IN_NEOZOOM = (1 << 23) //IN_GRENADE1
#define IN_ALTFIRE = (1 << 11) //IN_ATTACK2

int g_modelLaser, g_modelHalo, g_imodelLaserDot;
Handle CVAR_PluginEnabled, CVAR_LaserAlpha, CVAR_AllWeapons;
int laser_color[4] = {210, 10, 0, 20};

// Weapons where laser makes sense
new const String:g_sLaserWeaponNames[][] = {
	"weapon_aa13",
	"weapon_jitte",
	"weapon_jittescoped",
	"weapon_m41",
	"weapon_m41l",
	"weapon_m41s",
	"weapon_mp5",
	"weapon_mpn",
	"weapon_mx",
	"weapon_mx_silenced",
	"weapon_pz",
	"weapon_smac",
	"weapon_srm",
	"weapon_srm_s",
	"weapon_srs",
	"weapon_supa7",
	"weapon_zr68c",
	"weapon_zr68s",
	"weapon_srs",
	"weapon_zr68l" };
#define LONGEST_WEP_NAME 12
static int iAffectedWeapons[NEO_MAX_CLIENTS + 1]; // only primary weapons currently
static int iAffectedWeapons_Head = 0;
static int iAttachment[NEO_MAX_CLIENTS+1];
bool g_bNeedUpdateLoop;
bool g_bEmitsLaser[NEO_MAX_CLIENTS+1];
bool g_bInZoom[NEO_MAX_CLIENTS+1];
Handle g_TimerInZoom[NEO_MAX_CLIENTS+1];


// each entity has an array of affected clients
// int g_iLaserBeam[NEO_MAX_CLIENTS+1][NEO_MAX_CLIENTS+1];
int g_iLaserDot[NEO_MAX_CLIENTS+1];


// credit goes to https://forums.alliedmods.net/showthread.php?p=2121702
// some code stolen from Rain https://github.com/Rainyan/sourcemod-nt-quickswitchlimiter
public Plugin:myinfo =
{
	name = "NEOTOKYO laser sights",
	author = "glub",
	description = "Traces a laser beam from guns",
	version = "0.2",
	url = "https://github.com/glubsy"
};

// TODO:
// -> Attach a prop to the muzzle of every srs, then raytrace a laser straight in front when tossed in the world

// OBJECTIVE: laser beam can only be seen with bare eyes (very thin and transparent), or night vision (thicker, more visible if possible)
// but not with motion or thermal vsion (don't send to of those classes when vision active)
// laser dot visible also only with bare eyes and night vision
// laser beams are always visible to spectators
// TODO: make opt-out
// TODO: make cookie pref menu
// TODO: use return GetEntProp(weapon, Prop_Data, "m_iState") to check if weapon is being carried by a player (see smlib/weapons.inc)

#define ATTACH 0
#define CROTCH 1
#define METHOD CROTCH
// Method 0: teleport entity and get start of beam from it, no parenting needed (not ideal)
// Method 1: no need for prop here, just trace a ray from center of mass and be done with it whatever

public void OnPluginStart()
{
	CVAR_PluginEnabled = CreateConVar("sm_lasersight_enable", "1", "Enable (1) or disable (0) Sniper Laser.", _, true, 0.0, true, 1.0);
	CVAR_LaserAlpha = CreateConVar("sm_lasersight_alpha", "20.0", "Transparency amount for laser beam", _, true, 0.0, true, 255.0);
	laser_color[3] = GetConVarInt(CVAR_LaserAlpha); //TODO: hook convar change
	CVAR_AllWeapons = CreateConVar("sm_lasersight_allweapons", "1", "Draw laser beam from all weapons, not just sniper rifles.", _, true, 0.0, true, 1.0);

	// Make sure we will allocate enough size to hold our weapon names throughout the plugin.
	for (int i = 0; i < sizeof(g_sLaserWeaponNames); i++)
	{
		if (strlen(g_sLaserWeaponNames[i]) > LONGEST_WEP_NAME)
		{
			SetFailState("LaserWeaponNames %i is too short to hold \
g_sLaserWeaponNames \"%s\" (length: %i) in index %i.", LONGEST_WEP_NAME,
				g_sLaserWeaponNames[i], strlen(g_sLaserWeaponNames[i]), i);
		}
	}
}

public void OnConfigsExecuted()
{
	#if DEBUG
	for (int client = MaxClients; client > 0; client--)
	{
		if (!IsValidClient(client) || !IsClientConnected(client))
			continue;

		PrintToServer("Hooking client %d", client);

		// SDKUnhook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
		// SDKUnhook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
		// SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
		// SDKUnhook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
		SDKHook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
		SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
		SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
		SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);

		CreateTimer(5.0, Timer_TestForWeapons, GetClientUserId(client));

		int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

		char classname[30];
		if(weapon < MaxClients || !GetEntityClassname(weapon, classname, sizeof(classname)))
			continue; // Can't get class name


		for (int i = sizeof(g_sLaserWeaponNames); i > (GetConVarBool(CVAR_AllWeapons) ? sizeof(g_sLaserWeaponNames) : sizeof(g_sLaserWeaponNames) -2 ); i--)
		{
			if (StrEqual(g_sLaserWeaponNames[i], classname))
			{
				#if DEBUG > 0
				PrintToServer("[nt_sniper_laser] DEBUG: OnConfigsExecuted() %N currently has weapon %d %s.", client, weapon, classname);
				#endif

				#if METHOD == 0
				iAttachment[client] = CreateFakeAttachedProp(weapon, client);
				//DispatchLaser(iAttachment[client], client);
				#endif
			}
		}
	}
	#endif
}


public OnMapStart()
{
	#if DEBUG
	PrintToChatAll("onmapstart");
	#endif

	// laser beam
	// g_modelLaser = PrecacheModel("sprites/laser.vmt");
	g_modelLaser = PrecacheModel("sprites/laserdot.vmt");

	// laser halo
	g_modelHalo = PrecacheModel("materials/sprites/halo01.vmt");
	// g_modelHalo = PrecacheModel("materials/sprites/autoaim_1a.vmt");
	// g_modelHalo = PrecacheModel("materials/sprites/blackbeam.vmt");
	// g_modelHalo = PrecacheModel("materials/sprites/dot.vmt");
	// g_modelHalo = PrecacheModel("materials/sprites/laserdot.vmt");
	// g_modelHalo = PrecacheModel("materials/sprites/crosshair_h.vmt");
	// g_modelHalo = PrecacheModel("materials/sprites/blood.vmt");

	// laser dot
	g_imodelLaserDot = PrecacheDecal("materials/sprites/laserdot.vmt"); // works!
	// g_imodelLaserDot = PrecacheModel("materials/sprites/laser.vmt");
	// g_imodelLaserDot = PrecacheDecal("materials/decals/Blood5.vmt");
}


public void OnEntityDestroyed(int entity)
{
	for (int i = 0; i < sizeof(iAffectedWeapons); i++)
	{
		if (iAffectedWeapons[i] == entity)
		{
			iAffectedWeapons[i] = 0;
		}
	}
}


#if !DEBUG
public void OnClientPutInServer(int client)
{
	if (!IsValidEdict(client))
		return;

	g_iLaserDot[client] = 0; // FIXME should be better way
	g_bEmitsLaser[client] = false;
	SDKHook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
}


public void OnClientDisconnect(int client)
{
	if (!IsValidEdict(client))
		return;

	g_bEmitsLaser[client] = false;
	SDKUnhook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
	SDKUnhook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
	SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKUnhook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
}
#endif //!DEBUG



public void OnClientSpawned_Post(int client)
{
	CreateTimer(10.0, Timer_TestForWeapons, GetClientUserId(client));
}


public Action Timer_TestForWeapons(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (!IsValidClient(client) || IsFakeClient(client))
		return Plugin_Stop;

	#if DEBUG
	PrintToServer("[nt_sniper_laser] TestForWeapons: %N", client);
	#endif
	int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);

	if (!IsValidEdict(weapon))
	{
		#if DEBUG
		PrintToServer("[nt_sniper_laser] !IsValidEdict: %i", weapon);
		#endif
		return Plugin_Stop;
	}

	decl String:classname[LONGEST_WEP_NAME + 1]; // Plus one for string terminator.
	if (!GetEdictClassname(weapon, classname, sizeof(classname)))
	{
		#if DEBUG
		PrintToServer("[nt_sniper_laser] !GetEdictClassname: %i", weapon);
		#endif
		return Plugin_Stop;
	}

	for (int i = sizeof(g_sLaserWeaponNames); i > (GetConVarBool(CVAR_AllWeapons) ? sizeof(g_sLaserWeaponNames) : sizeof(g_sLaserWeaponNames) - 2) ; i--)
	{
		if (StrEqual(classname, g_sLaserWeaponNames[i]))
		{
			#if DEBUG
			PrintToServer("[nt_sniper_laser] Store OK: %s is %s. Hooking %s %d", classname, g_sLaserWeaponNames[i], classname, weapon);
			#endif

			StoreWeapon(weapon, client);
			break;
		}
		else
		{
			#if DEBUG
			PrintToServer("[nt_sniper_laser] Store fail: %s is not %s", classname, g_sLaserWeaponNames[i]);
			#endif
		}
	}

	return Plugin_Stop;
}


// Assumes valid input; make sure you're inputting a valid edict.
void StoreWeapon(int weapon, int client)
{
#if DEBUG
	if (iAffectedWeapons_Head >= sizeof(iAffectedWeapons))
	{
		ThrowError("[nt_sniper_laser] iAffectedWeapons_Head %i >= sizeof(iAffectedWeapons) %i",
			iAffectedWeapons_Head, sizeof(iAffectedWeapons));
	}
#endif

	iAffectedWeapons[iAffectedWeapons_Head] = weapon;

	// Cycle around the array.
	iAffectedWeapons_Head++;
	iAffectedWeapons_Head %= sizeof(iAffectedWeapons);
}


// Assumes valid input; make sure you're inputting a valid edict.
bool IsAttachableWeapon(int weapon)
{
	#if DEBUG
	PrintToServer("[nt_sniper_laser] IsAttachableWeapon: %i", weapon);
	if (weapon == 0)
	{
		// This should never happen; only checking in debug.
		ThrowError("weapon == 0!!");
	}
	#endif

	int WepsSize = sizeof(iAffectedWeapons);
	for (int i = 0; i < WepsSize; i++)
	{
		if (iAffectedWeapons[i] == weapon)
		{
			#if DEBUG
			PrintToServer("Attachable: %i", i);
			#endif

			return true;
		}

		#if DEBUG > 1
		PrintToServer("[nt_sniper_laser] %i -- not attachable for: %i vs %i", i, weapon, iAffectedWeapons[i]);
		#endif
	}

	return false;
}

public void OnWeaponSwitch_Post(int client, int weapon)
{
	#if DEBUG
	if (!IsFakeClient(client))  // reduces log output
		PrintToServer("[nt_sniper_laser] OnWeaponSwitch_Post %N, weapon %d", client, weapon);
	#endif
	g_bEmitsLaser[client] = false;
	CheckForUpdateOnWeapon(client, weapon);
}


// if anyone has a weapon which has a laser, ask for OnGameFrame() coordinates updates
void NeedUpdateLoop()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bEmitsLaser[i])
		{
			#if DEBUG > 1
			PrintToChatAll("Someone has a laser, we need update loop");
			#endif
			g_bNeedUpdateLoop = true;
			return;
		}
	}
	g_bNeedUpdateLoop = false;
}


public void OnWeaponEquip(int client, int weapon)
{
	#if DEBUG
	if (!IsFakeClient(client)) // reduces log output
		PrintToServer("[nt_sniper_laser] OnWeaponEquip %N, weapon %d", client, weapon);
	#endif
	g_bEmitsLaser[client] = false;
	CheckForUpdateOnWeapon(client, weapon);
}


int CreateFakeAttachedProp(int weapon, int client)
{
	#if DEBUG
	PrintToChatAll("[nt_sniper_laser] Creating attached prop on %N", client);
	#endif

	int entity = CreateEntityByName("info_target");
	// int entity = CreateEntityByName("prop_dynamic_ornament");
	// DispatchKeyValue(entity, "model", "models/nt/a_lil_tiger.mdl");
	DispatchSpawn(entity);

	float VecOrigin[3];
	GetClientEyePosition(client, VecOrigin);

	#if METHOD == 0
	MakeParent(entity, weapon);
	CreateTimer(0.1, timer_SetAttachment, entity);
	#endif

	TeleportEntity(entity, VecOrigin, NULL_VECTOR, NULL_VECTOR);

	//from SM discord:
	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
    GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
    AcceptEntityInput(entity, "kill");

	return entity;
}


int CreateLaserDotEnt(int client)
{
	// env_sprite always face the player
	int ent = CreateEntityByName("env_glow"); // env_sprite is the same
	if (!IsValidEntity(ent))
		return -1;

	#if DEBUG
	PrintToChatAll("[nt_sniper_laser] Created laser dot %d for client %N", ent, client);
	#endif

	DispatchKeyValue(ent, "model", "materials/sprites/laserdot.vmt");
	DispatchKeyValueFloat(ent, "scale", 0.1); // doesn't seem to work
	// SetEntPropFloat(ent, Prop_Data, "m_flSpriteScale", 0.2); // doesn't seem to work
	DispatchKeyValue(ent, "rendermode", "9"); // 3 glow, makes it smaller?, 9 world space glow 5 additive,
	DispatchKeyValueFloat(ent, "GlowProxySize", 0.2); // not sure if this works
	DispatchKeyValueFloat(ent, "HDRColorScale", 1.0); // needs testing
	DispatchKeyValue(ent, "renderamt", "180"); // transparency
	DispatchKeyValue(ent, "disablereceiveshadows", "1");
	DispatchKeyValue(ent, "renderfx", "15");
	// DispatchKeyValue(ent, "rendercolor", "0 255 0");

	SetVariantFloat(0.1);
	AcceptEntityInput(ent, "SetScale");  // this works!

	// SetVariantFloat(0.9);
	// AcceptEntityInput(ent, "scale"); // doesn't work

	DispatchSpawn(ent);

	return ent;

}



void MakeParent(int entity, int weapon)
{
	char Buffer[64];
	Format(Buffer, sizeof(Buffer), "weapon%d", weapon);

	DispatchKeyValue(weapon, "targetname", Buffer);

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", weapon, weapon, 0);
}


public Action timer_SetAttachment(Handle timer, int entity)
{
	#if DEBUG
	PrintToServer("[nt_sniper_laser] Setting attachement point for entity %d.", entity);
	#endif

	SetVariantString("muzzle"); //"muzzle" works for when attaching to weapon
	AcceptEntityInput(entity, "SetParentAttachment");
	// SetVariantString("grenade0");
	// AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset");
}

void DispatchLaser(int laser, int client)
{
	#if DEBUG
	PrintToServer("DispatchLaser()")
	#endif
	float origin[3];
	GetClientEyePosition(client, origin);
	DispatchKeyValueVector(laser, "origin", origin);
	DispatchKeyValue(laser, "rendercolor", "255 120 120");
	DispatchKeyValue(laser, "spotlight_width", "10");
	DispatchKeyValue(laser, "spotlight_length", "200");
	AcceptEntityInput(laser, "LightOn");
	DispatchSpawn(laser);
}


public void OnWeaponDrop(int client, int weapon)
{
	if(!IsValidEdict(weapon) || !IsValidClient(client))
		return;

	g_bEmitsLaser[client] = false;

	NeedUpdateLoop();
}


void CheckForUpdateOnWeapon(int client, int weapon)
{
	if(!IsValidEdict(weapon) || !IsValidClient(client))
		return;

	if (IsAttachableWeapon(weapon))
	{
		#if METHOD == ATTACH
		iAttachment[client] = CreateFakeAttachedProp(weapon, client); // FIXME: MISTAKE HERE, DON'T ASSIGN!
		//DispatchLaser(iAttachment[client], client);
		#endif

		if (!ClientHasCreatedLaserDot(client))
		{
			g_iLaserDot[client]	= CreateLaserDotEnt(client);
			SDKHook(g_iLaserDot[client]	, SDKHook_SetTransmit, Hook_SetTransmit);
		}
		g_bEmitsLaser[client] = true;
		g_bNeedUpdateLoop = true;
		return;
	}

	g_bEmitsLaser[client] = false;

	NeedUpdateLoop();
}


bool ClientHasCreatedLaserDot(int client)
{
	if (g_iLaserDot[client] > 0)
		return true
	return false;
}


public OnGameFrame()
{
	if(g_bNeedUpdateLoop)
	{
		// int weapon = -1;
		// while ((weapon = FindEntityByClassname(weapon, "weapon_srs")) != -1)
		// {
		// 	float weapon_origin[3];
		// 	GetEntPropVector(weapon, Prop_Send, "m_vecOrigin", weapon_origin);
		// 	PrintToChatAll("origin: %f %f %f", weapon_origin[0], weapon_origin[1], weapon_origin[2]);
		// 	TE_SetupBeamPoints(weapon_origin, GetEndPositionWeapon(weapon), g_modelLaser, g_modelHalo, initial_frame, 1, 0.1, 0.1, 0.1, 1, 0.1, laser_color, 0)
		// }

		for (int client = 1; client <= MaxClients; client++)
		{
			if(g_bEmitsLaser[client] && IsValidClient(client))
			{
				float origin[3], end[3];
				GetClientEyePosition(client, origin);
				origin[2] -= 28.0; 		// roughly starting from "center of mass"

				#if METHOD == 0
				float vecForward[3], vecPos[3], vecVel[3];
				float vecEyeAng[3];
				if (iAttachment[client] != -1)
				{
					// GetEntPropVector(iAttachment[client], Prop_Send, "m_vecOrigin", origin);
					// PrintToChatAll("origin: %f %f %f", origin[0], origin[1], origin[2]);
					GetClientEyeAngles(client, vecEyeAng);
					GetAngleVectors(vecEyeAng, vecForward, NULL_VECTOR, NULL_VECTOR);
					GetClientEyePosition(client, vecPos);
					vecPos[0]+=vecForward[0]*20.0;
					vecPos[1]+=vecForward[1]*20.0;
					vecPos[2]+=vecForward[2]*10.0;
					SubtractVectors(vecPos, vecForward, vecVel);
					TeleportEntity(iAttachment[client], vecPos, vecEyeAng, NULL_VECTOR);

					GetEntPropVector(iAttachment[client], Prop_Send, "m_vecOrigin", vecPos);
				}
				#endif // METHOD == 0


				bool didhit = GetEndPositionFromClient(client, end);

				#if METHOD == ATTACH // using attached prop as origin
				// TE_SetupBeamPoints(vecPos, GetEndPositionFromWeapon(iAttachment[client], vecPos, vecEyeAng), g_modelLaser, g_modelHalo, 0, 1, 0.1, 0.9, 0.1, 1, 0.1, laser_color, 0);
				TE_Start("BeamPoints");
				TE_WriteVector("m_vecStartPoint", vecPos);
				TE_WriteVector("m_vecEndPoint", GetEndPositionFromWeapon(iAttachment[client], vecPos, vecEyeAng));
				//TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);
				TE_WriteNum("m_nModelIndex", g_modelLaser);
				TE_WriteNum("m_nHaloIndex", g_modelHalo);
				TE_WriteNum("m_nStartFrame", 0);
				TE_WriteNum("m_nFrameRate", 1);
				TE_WriteFloat("m_fLife", 0.1);
				TE_WriteFloat("m_fWidth", 0.9);
				TE_WriteFloat("m_fEndWidth", 0.1);
				TE_WriteFloat("m_fAmplitude", 0.1);
				TE_WriteNum("r", Color[0]);
				TE_WriteNum("g", Color[1]);
				TE_WriteNum("b", Color[2]);
				TE_WriteNum("a", Color[3]);
				TE_WriteNum("m_nSpeed", 1);
				TE_WriteNum("m_nFadeLength", 1);
				#endif

				#if METHOD == CROTCH // coming from crotch
				// NOTE: Halo can be set to 0, needs testing
				TE_SetupBeamPoints(origin, end, g_modelLaser, g_modelHalo, 0, 1, 0.1, 0.9, 0.1, 1, 0.1, laser_color, 0);
				// add flags manually because sdktools forgot about them (see sdktools_tempents_stocks)
				TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);
				#endif

				new iBeamClients[MaxClients], nBeamClients;
				for(new j = 1; j <= MaxClients; j++)
				{
					if(IsValidClient(j) && (client != j)) // only draw for others
						iBeamClients[nBeamClients++] = j;
				}
				TE_Send(iBeamClients, nBeamClients);

				if (IsValidEntity(g_iLaserDot[client]))
					// TODO: get velocity vector from somewhere?
					TeleportEntity(g_iLaserDot[client], end, NULL_VECTOR, NULL_VECTOR);

			}
		}
	}
}


#if METHOD == ATTACH
// trace from weapon
float GetEndPositionFromWeapon(int entity, float[3] start, float[3] angle)
{
	// int client;
	// client = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");

	decl Float:end[3];

	TR_TraceRayFilter(start, angle, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer, entity);
	if (TR_DidHit(INVALID_HANDLE))
	{
		TR_GetEndPosition(end, INVALID_HANDLE);
	}
	// adjusting alignment
	end[0] += 5.0;
	end[1] += 5.0;
	end[2] += 5.0;
	return end;
}
#endif //METHOD == 0


// trace from client, return true on hit
stock bool GetEndPositionFromClient(int client, float[3] end)
{
	decl Float:start[3], Float:angle[3];
	GetClientEyePosition(client, start);
	GetClientEyeAngles(client, angle);
	TR_TraceRayFilter(start, angle, (CONTENTS_SOLID|CONTENTS_MOVEABLE|CONTENTS_MONSTER|CONTENTS_DEBRIS|CONTENTS_HITBOX), RayType_Infinite, TraceEntityFilterPlayer, client);
	if (TR_DidHit(INVALID_HANDLE))
	{
		TR_GetEndPosition(end, INVALID_HANDLE);

		int hit_entity = TR_GetEntityIndex(INVALID_HANDLE);
		if (0 < hit_entity <= MaxClients) // we hit a player
		{
			float hit_normals[3];
			TR_GetPlaneNormal(INVALID_HANDLE, hit_normals);

			// TR_TraceRayFilter(start, angle, (CONTENTS_SOLID|CONTENTS_MOVEABLE|CONTENTS_MONSTER|CONTENTS_DEBRIS|CONTENTS_HITBOX), RayType_Infinite, TraceEntityFilterPlayer, client);

			#if DEBUG > 1
			PrintToChatAll("We hit: %N, normals: %f %f %f", hit_entity, hit_normals[0], hit_normals[1], hit_normals[2]);
			#endif

			// filter the targeted player to avoid blinding them and filter out the rifle holder

			int AffectedClients[NEO_MAX_CLIENTS+1], numClients;
			for (int j = MaxClients; j > 0; j--)
			{
				if (j == hit_entity || !IsValidClient(j) || !IsClientConnected(j) /* || j == client*/) // DEBUG!
					continue;
				AffectedClients[numClients++] = j;
			}

			if (!numClients) // shouldn't happen
				return false;

			// old method for testing
			// CreateLaserDotSpriteTE(end, AffectedClients, numClients);
			return true;
		}
		else
		{

			int AffectedClients[NEO_MAX_CLIENTS+1], numClients;
			for (int j = MaxClients; j > 0; j--)
			{
				if (!IsValidClient(j) || !IsClientConnected(j) /*|| j == client*/) // can't draw for client due to latency :/
					continue;
				AffectedClients[numClients++] = j;
			}

			// old method for testing
			// CreateLaserDotSpriteTE(end, AffectedClients, numClients);
			return true;
		}
	}
	// adjusting alignment
	// end[0] += 5.0;
	// end[1] += 5.0;
	// end[2] += 5.0;
	return false;
}


public bool:TraceEntityFilterPlayer(entity, contentsMask, any:data)
{
	// return entity > MaxClients;
	return entity != data; // only avoid collision with ourself (or data)
}



//filter the client
bool BuildArrayFilterClient(int clients[NEO_MAX_CLIENTS+1], int numClients)
{
	int clients[MaxClients];
	int total = 0;

	for (new i=1; i<=MaxClients; i++)
	{
		if (IsClientInGame(i) && i !)
		{
			clients[total++] = i;
		}
	}
	if (!total)
	{
		return false;
	}
	return true
}


public Action Hook_SetTransmit(int entity, int client)
{
	if(entity == g_iLaserDot[client])
		return Plugin_Handled; // hide player's own laser dot from himself

	//TODO make more conditions here for vision modes

	return Plugin_Continue;
}


public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (!GetConVarBool(CVAR_PluginEnabled) || client > MaxClients || client <= 0)
		return Plugin_Continue;

	if ((buttons & IN_GRENADE1) == IN_GRENADE1) // ZOOM key pressed
	{
		PrintToServer("Key IN_GRENADE1 pressed (neozoom?) %d", GetActiveWeapon(client));

		decl String:weaponName[19];
		GetClientWeapon(client, weaponName, sizeof(weaponName));

		if (StrEqual(weaponName, "weapon_srs"))
		{
			g_bInZoom[client] = !g_bInZoom[client];
			if (g_TimerInZoom[client] != INVALID_HANDLE)
				g_TimerInZoom[client] = CreateTimer(0.1, timer_UpdateZoomKey, client, TIMER_REPEAT);
			// toggle laser beam here
		}
	}


	if ((buttons & IN_ATTACK2) == IN_ATTACK2) // Alt Fire mode key pressed
	{
		PrintToServer("Key IN_ATTACK2 pressed (altfire?)");
		decl String:weaponName[19];
		GetClientWeapon(client, weaponName, sizeof(weaponName));
		if (StrEqual(weaponName, "weapon_srs"))
		{
			// toggle laser beam here?
		}
	}

	if ((buttons & IN_RELOAD) == IN_RELOAD)
	{
		PrintToServer("Key IN_RELOAD pressed");
		SetWeaponAmmo(client, AMMO_PRIMARY, 24);
		// check until "m_bInReload" in weapon_srs is released

	}

	if ((buttons & IN_ATTACK) == IN_ATTACK)
	{
		g_bInZoom[client] = false;
	}
	// PrintToServer("next attack: %f", GetNextAttack(client));

	return Plugin_Continue;
}


public Action timer_UpdateZoomKey(Handle timer, int client)
{
	PrintCenterTextAll("Client zoom is %s", (g_bInZoom[client] ? "active" : "inactive"));
	PrintToChat(client, "Client zoom is %s", (g_bInZoom[client] ? "active" : "inactive"));

	if (!IsValidClient(client) || IsFakeClient(client))
		return Plugin_Stop;
	int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
	if (!IsValidEdict(weapon))
	{
		#if DEBUG
		PrintToServer("!IsValidEdict: %i", weapon);
		#endif
		return Plugin_Stop;
	}
	decl String:classname[30];
	if (!GetEdictClassname(weapon, classname, sizeof(classname)))
	{
		#if DEBUG
		PrintToServer("!GetEdictClassname: %i", weapon);
		#endif
		return Plugin_Stop;
	}

	// g_bInZoom[client] = GetInReload(weapon);
	PrintToServer("m_nSequence: %d", GetEntProp(weapon, Prop_Data, "m_nSequence", 4));

	int iSequence = GetEntProp(weapon, Prop_Data, "m_nSequence", 4);
	// 3 shooting, 4 fire pressed continuously, 6 reloading, 11 bolt
	// m_nSequence == 6 is equivalent to m_bInReload == 1
	if (iSequence > 0)
		g_bInZoom[client] = false;

	// PrintToServer("m_bInReload: %d", GetEntProp(weapon, Prop_Data, "m_bInReload", 1));
	// g_bInZoom[client] = !view_as<bool>(GetEntProp(weapon, Prop_Data, "m_bInReload", 1));

	if (!g_bInZoom[client])
	{
		g_TimerInZoom[client] = INVALID_HANDLE;
		KillTimer(timer);
	}
	return Plugin_Continue;
}


float GetNextAttack(int client)
{
	static int ptrHandle = 0;
	new const String:sOffsetName[] = "m_flNextAttack";

	if ((!ptrHandle) && (ptrHandle = FindSendPropInfo(
		"CNEOPlayer", sOffsetName)) == -1)
	{
		SetFailState("Failed to obtain offset: \"%s\"!", sOffsetName);
	}

	return GetEntDataFloat(client, ptrHandle);
}


// Projected Decals half work, but never disappear as TE, don't show actual model
// Glow Sprite load a model from a different precache table (can be actual player models too, weird)
// Sprite spray half works, doesn't do transparency(?) then "falls off" in a direction and disappears
// Sprite doesn't seem to render anything
// World Decal doesn't work

// at position pos, for the clients in this array
// void CreateLaserDotSpriteTE(const float[3] pos, const int clients[NEO_MAX_CLIENTS+1], const int numClients)
// {
// 	#if DEBUG
// 	PrintToChatAll("Creating Sprite at %f %f %f", pos[0], pos[1], pos[2]);
// 	#endif
// 	float dir[3];
//  dir[0] += 100.0;
//  dir[1] += 100.0;
//  dir[2] += 100.0;
// 	TE_Start("Sprite Spray");
// 	TE_WriteVector("m_vecOrigin", pos);
// 	TE_WriteVector("m_vecDirection", dir);
// 	TE_WriteNum("m_nModelIndex", g_imodelLaserDot);
// 	TE_WriteFloat("m_fNoise", 6.0);
// 	TE_WriteNum("m_nSpeed", 10);
// 	TE_WriteNum("m_nCount", 4);
// 	TE_Send(clients, numClients);
// }