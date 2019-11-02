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
	"weapon_jitte",
	"weapon_jittescoped",
	"weapon_m41",
	"weapon_m41s",
	"weapon_mpn",
	"weapon_mx",
	"weapon_mx_silenced",
	"weapon_pz",
	"weapon_srm",
	"weapon_srm_s",
	"weapon_zr68c",
	"weapon_zr68s",
	"weapon_zr68l",
	"weapon_srs" }; // NOTE: the 2 last items must be actual sniper rifles!
#define LONGEST_WEP_NAME 18
static int iAffectedWeapons[NEO_MAX_CLIENTS + 1]; // only primary weapons currently
static int iAffectedWeapons_Head = 0;
static int iAttachment[NEO_MAX_CLIENTS+1];
bool g_bNeedUpdateLoop;
bool g_bEmitsLaser[NEO_MAX_CLIENTS+1];
bool gbInZoomState[NEO_MAX_CLIENTS+1]; // laser can be displayed
Handle ghTimerCheckSequence[NEO_MAX_CLIENTS+1] = { INVALID_HANDLE, ...};
bool gbCanSeeBeam[NEO_MAX_CLIENTS+1];
bool gbShouldTransmitDot[NEO_MAX_CLIENTS+1]
bool gbLaserActive[NEO_MAX_CLIENTS+1];


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


// OBJECTIVE: laser beam can only be seen with bare eyes (very thin and transparent), or night vision (thicker, more visible if possible)
// but not with motion or thermal vsion (don't send to of those classes when vision active)
// laser dot visible also only with bare eyes and night vision
// laser beams are always visible to spectators

// TODO: use return GetEntProp(weapon, Prop_Data, "m_iState") to check if weapon is being carried by a player (see smlib/weapons.inc)
// TODO: make checking for in_zoom state a forward (for other plugins to use)
// TODO: Attach a prop to the muzzle of every srs, then raytrace a laser straight in front when tossed in the world

#define ATTACH 0
#define CROTCH 1
#define METHOD CROTCH
// Method 0: teleport entity and get start of beam from it, no parenting needed (not ideal)
// Method 1: no need for prop here, just trace a ray from a fixed point in front of player

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
			SetFailState("[nt_lasersight] LaserWeaponNames %i is too short to hold \
g_sLaserWeaponNames \"%s\" (length: %i) in index %i.", LONGEST_WEP_NAME,
				g_sLaserWeaponNames[i], strlen(g_sLaserWeaponNames[i]), i);
		}
	}

	HookEvent("player_spawn", OnPlayerSpawn);
}

public void OnConfigsExecuted()
{
	#if DEBUG
	// for late loading only
	for (int client = 1; client <= MaxClients; ++client)
	{
		if (!IsValidClient(client) || !IsClientConnected(client))
			continue;

		PrintToServer("[nt_lasersight] Hooking client %d", client);

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

		#if METHOD == ATTACH
		for (int i = sizeof(g_sLaserWeaponNames) - 1 ; i > (GetConVarBool(CVAR_AllWeapons) ? 0 : sizeof(g_sLaserWeaponNames) -2 ); --i)
		{
			if (StrEqual(g_sLaserWeaponNames[i], classname))
			{
				#if DEBUG > 0
				PrintToServer("[nt_lasersight] DEBUG: OnConfigsExecuted() %N currently has weapon %d %s.", client, weapon, classname);
				#endif

				iAttachment[client] = CreateFakeAttachedProp(weapon, client);
				//DispatchLaser(iAttachment[client], client);
			}
		}
		#endif // METHOD == ATTACH
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
	for (int i = 0; i < sizeof(iAffectedWeapons); ++i)
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
	// if (!IsValidEdict(client))
	// 	return;

	g_iLaserDot[client] = 0; // FIXME should be better way
	g_bEmitsLaser[client] = false;
	SDKHook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
}


public void OnClientDisconnect(int client)
{
	// if (!IsValidEdict(client))
	// 	return;

	g_bEmitsLaser[client] = false;
	SDKUnhook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
	SDKUnhook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
	SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKUnhook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
}
#endif //!DEBUG



public void OnClientSpawned_Post(int client)
{
	#if DEBUG
	PrintToServer("[nt_lasersight] OnClientSpawned (%N)", client);
	#endif

	if (!IsPlayerReallyAlive(client)) // avoid potential spectator spawns
		return;

	// need no delay in case player tosses primary weapon
	CreateTimer(1.0, Timer_TestForWeapons, GetClientUserId(client));
}


public Action OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsPlayerReallyAlive(client)) // avoid potential spectator spawns
		return Plugin_Continue;

	// need no delay in case player tosses primary weapon
	CreateTimer(1.0, Timer_TestForWeapons, GetClientUserId(client));
	return Plugin_Continue;
}



// This is redundant if we only affect SLOT_PRIMARY weapons anyway, no need to test here REMOVE?
public Action Timer_TestForWeapons(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (!IsValidClient(client) || IsFakeClient(client))
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] Timer_TestForWeapons: %d client was invalid!", client);
		#endif
		return Plugin_Stop;
	}

	#if DEBUG
	PrintToServer("[nt_lasersight] TestForWeapons: %N", client);
	#endif

	int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);

	if (!IsValidEdict(weapon))
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] TestForWeapons() !IsValidEdict: %i", weapon);
		#endif
		return Plugin_Stop;
	}

	decl String:classname[LONGEST_WEP_NAME + 1]; // Plus one for string terminator.

	if (!GetEdictClassname(weapon, classname, sizeof(classname)))
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] TestForWeapons() !GetEdictClassname: %i", weapon);
		#endif
		return Plugin_Stop;
	}

	// only test the two last wpns if limited to sniper rifles
	int stop_at = (GetConVarBool(CVAR_AllWeapons) ? 0 : sizeof(g_sLaserWeaponNames) - 2)

	for (int i = sizeof(g_sLaserWeaponNames) - 1 ; i > stop_at; --i)
	{
		if (StrEqual(classname, g_sLaserWeaponNames[i]))
		{
			#if DEBUG
			PrintToServer("[nt_lasersight] Store OK: %s is %s. Hooking %s %d",
			classname, g_sLaserWeaponNames[i], classname, weapon);
			#endif

			StoreWeapon(weapon, client);
			break;
		}
		else
		{
			#if DEBUG
			PrintToServer("[nt_lasersight] Store fail: %s is not %s.",
			classname, g_sLaserWeaponNames[i]);
			#endif
		}
	}

	return Plugin_Stop;
}


// Assumes valid input; make sure you're inputting a valid edict.
// this avoids having to compare classname strings in favour of ent ids
void StoreWeapon(int weapon, int client)
{
#if DEBUG
	if (iAffectedWeapons_Head >= sizeof(iAffectedWeapons))
	{
		ThrowError("[nt_lasersight] iAffectedWeapons_Head %i >= sizeof(iAffectedWeapons) %i",
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
	PrintToServer("[nt_lasersight] IsAttachableWeapon: %i", weapon);
	if (weapon == 0)
	{
		// This should never happen; only checking in debug.
		// This may happen if primary weapon failed to be given to a player on spawn
		ThrowError("weapon == 0!!");
	}
	#endif

	int WepsSize = sizeof(iAffectedWeapons);
	for (int i = 0; i < WepsSize; ++i)
	{
		if (weapon == iAffectedWeapons[i])
		{
			#if DEBUG
			PrintToServer("[nt_lasersight] Attachable weapon found: %i", i);
			#endif

			return true;
		}

		#if DEBUG > 2
		PrintToServer("[nt_lasersight] %i not attachable. Compared to iAffectedWeapons[%i] %i",
		weapon, i, iAffectedWeapons[i]);
		#endif
	}

	return false;
}


public void OnWeaponSwitch_Post(int client, int weapon)
{
	#if DEBUG
	if (!IsFakeClient(client)) {  // reduces log output
		PrintToServer("[nt_lasersight] OnWeaponSwitch_Post %N, weapon %d",
		client, weapon);
	}
	#endif
	g_bEmitsLaser[client] = false;
	CheckForUpdateOnWeapon(client, weapon);
}


//FIXME merge with OnWeaponSwitch
public void OnWeaponEquip(int client, int weapon)
{
	#if DEBUG
	if (!IsFakeClient(client)) { // reduces log output
		PrintToServer("[nt_lasersight] OnWeaponEquip %N, weapon %d",
		client, weapon);
	}
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
			#if DEBUG > 2
			PrintToChatAll("[nt_lasersight] g_bEmitsLaser[%N] is true, NeedUpdateLoop()", i);
			#endif
			g_bNeedUpdateLoop = true;
			return;
		}
	}
	g_bNeedUpdateLoop = false;
}




int CreateFakeAttachedProp(int weapon, int client)
{
	#if DEBUG
	PrintToChatAll("[nt_lasersight] Creating attached prop on %N", client);
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


void CreateLaserDot(int client)
{
	if (g_iLaserDot[client] <= 0) // we have not already created a laser dot
	{
		g_iLaserDot[client]	= CreateLaserDotEnt(client);
		gbShouldTransmitDot[client] = false;
		SDKHook(g_iLaserDot[client]	, SDKHook_SetTransmit, Hook_SetTransmitLaserDot);
	}
}

void DestroyLaserDot(int client)
{
	if (g_iLaserDot[client] > 0 && IsValidEntity(g_iLaserDot[client]))
	{
		SDKUnhook(g_iLaserDot[client], SDKHook_SetTransmit, Hook_SetTransmitLaserDot)
		AcceptEntityInput(g_iLaserDot[client], "kill");
		g_iLaserDot[client] = -1;
	}
}


int CreateLaserDotEnt(int client)
{
	// env_sprite always face the player
	int ent = CreateEntityByName("env_glow"); // env_sprite is the same
	if (!IsValidEntity(ent))
		return -1;

	#if DEBUG
	PrintToServer("[nt_lasersight] Created laser dot %d for client %N.", ent, client);
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
	PrintToServer("[nt_lasersight] Setting attachement point for entity %d.", entity);
	#endif

	SetVariantString("muzzle"); //"muzzle" works for when attaching to weapon
	AcceptEntityInput(entity, "SetParentAttachment");
	// SetVariantString("grenade0");
	// AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset");
}

void DispatchLaser(int laser, int client)
{
	#if DEBUG
	PrintToServer("[nt_lasersight] DispatchLaser()")
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

	DestroyLaserDot(client);

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

		// g_bEmitsLaser[client] = true;
		// g_bNeedUpdateLoop = true;
		return;
	}

	// g_bEmitsLaser[client] = false;

	// NeedUpdateLoop();
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

		UpdateTEBeamPosition();

	}
}


void UpdateTEBeamPosition()
{
	for (int client = 1; client <= MaxClients; ++client)
	{
		if(!IsValidClient(client) || !g_bEmitsLaser[client])
			continue;

		float vecPos[3], vecEnd[3];
		GetClientEyePosition(client, vecPos);
		vecPos[2] -= 28.0; 		// roughly starting from "center of mass"

		#if METHOD == ATTACH
		float vecForward[3], vecVel[3], vecEyeAng[3];

		if (iAttachment[client] != -1)
		{
			// GetEntPropVector(iAttachment[client], Prop_Send, "m_vecOrigin", origin);
			// PrintToChatAll("VecPos: %f %f %f", VecPos[0], VecPos[1], VecPos[2]);
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
		#endif // METHOD == ATTACH


		bool didhit = GetEndPositionFromClient(client, vecEnd);


		TE_Start("BeamPoints");
		TE_WriteVector("m_vecStartPoint", vecPos);

		#if METHOD == ATTACH
		// using attached prop as origin
		// TE_SetupBeamPoints(vecPos, GetEndPositionFromWeapon(iAttachment[client], vecPos, vecEyeAng), g_modelLaser, g_modelHalo, 0, 1, 0.1, 0.9, 0.1, 1, 0.1, laser_color, 0);
		TE_WriteVector("m_vecEndPoint", GetEndPositionFromWeapon(iAttachment[client], vecPos, vecEyeAng));
		//TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);
		#else
		#if METHOD == CROTCH
		// NOTE: Halo can be set to 0, needs testing
		// TE_SetupBeamPoints(vecPos, vecEnd, g_modelLaser, g_modelHalo, 0, 1, 0.1, 0.9, 0.1, 1, 0.1, laser_color, 0);
		TE_WriteVector("m_vecEndPoint", vecEnd);
		TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);
		#endif

		TE_WriteNum("m_nModelIndex", g_modelLaser);
		TE_WriteNum("m_nHaloIndex", g_modelHalo);
		TE_WriteNum("m_nStartFrame", 0);
		TE_WriteNum("m_nFrameRate", 1);
		TE_WriteFloat("m_fLife", 0.1);
		TE_WriteFloat("m_fWidth", 0.9);
		TE_WriteFloat("m_fEndWidth", 0.1);
		TE_WriteFloat("m_fAmplitude", 0.1);
		TE_WriteNum("r", laser_color[0]);
		TE_WriteNum("g", laser_color[1]);
		TE_WriteNum("b", laser_color[2]);
		TE_WriteNum("a", laser_color[3]);
		TE_WriteNum("m_nSpeed", 1);
		TE_WriteNum("m_nFadeLength", 1);
		#endif

		int iBeamClients[NEO_MAX_CLIENTS+1], nBeamClients;
		for(int j = 1; j <= NEO_MAX_CLIENTS; ++j)
		{
			if(IsValidClient(j) && (client != j)){ // only draw for others
				// if (IsNotUsingNightVision(j))   // TODO (only if using TE)
				//		continue;
				iBeamClients[nBeamClients++] = j;
			}
		}
		TE_Send(iBeamClients, nBeamClients);

		if (IsValidEntity(g_iLaserDot[client])){
			// TODO: get velocity vector from somewhere?
			TeleportEntity(g_iLaserDot[client], vecEnd, NULL_VECTOR, NULL_VECTOR);
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

// entity emits to client or not
public Action Hook_SetTransmitLaserDot(int entity, int client)
{
	if (entity == g_iLaserDot[client])
		return Plugin_Handled; // hide player's own laser dot from himself

	//TODO hide if is not emitting laser beam

	return Plugin_Continue;
}


public Action Hook_SetTransmitLaserBeam(int entity, int client)
{
	#if DEBUG <= 0
	if (!gbCanSeeBeam[client])
		return Plugin_Handled;
	#endif
}


bool IsActiveWeaponSRS(int client)
{
	decl String:weaponName[20];
	GetClientWeapon(client, weaponName, sizeof(weaponName));
	if (StrEqual(weaponName, "weapon_srs")){
		#if DEBUG
		PrintToServer("[nt_lasersight] %N active weapon is weapon_srs.", client);
		#endif
		return true;
	}
	return false;
}


// these are reload sequences for the world models that we want to look for
// FIXME: check these only on weapon_switch and weapon_equip
// FIXME: it might be better to check view models if possible
int GetIgnoredSequencesForWeapon(int client)
{
	decl String:weaponName[LONGEST_WEP_NAME+1];
	GetClientWeapon(client, weaponName, sizeof(weaponName));

	if (StrEqual(weaponName, "weapon_jitte") ||
		StrEqual(weaponName, "weapon_jittescoped") ||
		StrEqual(weaponName, "weapon_m41") ||
		StrEqual(weaponName, "weapon_m41s") ||
		StrEqual(weaponName, "weapon_pz"))
		return 7;

	if (StrEqual(weaponName, "weapon_mpn") ||
		StrEqual(weaponName, "weapon_srm") ||
		StrEqual(weaponName, "weapon_srm_s") ||
		StrEqual(weaponName, "weapon_zr68c") ||
		StrEqual(weaponName, "weapon_zr68s") ||
		StrEqual(weaponName, "weapon_zr68l") ||
		StrEqual(weaponName, "weapon_mx") ||
		StrEqual(weaponName, "weapon_mx_silenced"))
		return 8;

	if (StrEqual(weaponName, "weapon_srs"))
		return 0;

	// by default ignore all sequences above 0
	return 0;
}


void ToggleZoomState(int client, int weapon)
{
	gbInZoomState[client] = !gbInZoomState[client];
}


public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (!GetConVarBool(CVAR_PluginEnabled) || client == 0)
		return Plugin_Continue;

	if ((buttons & IN_GRENADE1) == IN_GRENADE1) // ZOOM key pressed
	{
		OnZoomKeyPressed(client);
	}


	if ((buttons & IN_ATTACK2) == IN_ATTACK2) // Alt Fire mode key pressed
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] Key IN_ATTACK2 pressed (alt fire).");
		#endif

		int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"); // FIXME: should be cached
		if (IsAttachableWeapon(weapon)){
			// toggle laser beam here for other than SRS
			if (!IsActiveWeaponSRS(client))
				ToggleLaserCompletely(client);
		}
	}

	if ((buttons & IN_RELOAD) == IN_RELOAD)
	{
		OnReloadKeyPressed(client);
	}

	if ((buttons & IN_ATTACK) == IN_ATTACK)
	{
		#if DEBUG > 2
		PrintToServer("[nt_lasersight] Key IN_ATTACK pressed.");
		#endif

		//if SRS, toggle laser off after attack, other weapons, keep active (aimed down sight)
		if (IsActiveWeaponSRS(client)){
			gbInZoomState[client] = false;
			ToggleLaser(client, true);
		}
	}

	// PrintToServer("next attack: %f", GetNextAttack(client));
	return Plugin_Continue;
}



void ToggleLaser(int client, bool forceoff=false)
{
	if (forceoff){
		g_bEmitsLaser[client] = false;
		DestroyLaserDot(client);
		NeedUpdateLoop();
		return;
	}

	if (!gbInZoomState[client])
	{
		g_bEmitsLaser[client] = false;
		DestroyLaserDot(client);
	}
	else
	{
		CreateLaserDot(client);
		g_bEmitsLaser[client] = true;
	}
	NeedUpdateLoop();
}


void OnZoomKeyPressed(int client)
{
	#if DEBUG > 2
	PrintToServer("[nt_lasersight] Key IN_GRENADE1 pressed.");
	#endif

	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"); // FIXME should be cached
	int ViewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");

	#if DEBUG
	PrintToServer("[nt_lasersight] viewmodel index: %d", ViewModel);

	new bAimed = GetEntProp(weapon, Prop_Send, "bAimed");
	PrintToServer("[nt_lasersight] bAimed: %d", bAimed);
	#endif

	if (IsAttachableWeapon(weapon))
	{
		// we have the timer running, so no need to change anything
		if (gbInZoomState[client] && ghTimerCheckSequence[client] != INVALID_HANDLE){
			gbInZoomState[client] = false;
			g_bEmitsLaser[client] = false;
			return;
		}

		if (ghTimerCheckSequence[client] == INVALID_HANDLE)
		{
			gbInZoomState[client] = true;
			g_bEmitsLaser[client] = true;

			DataPack dp = CreateDataPack();

			ghTimerCheckSequence[client] = CreateTimer(0.1, timer_CheckSequence,
			dp, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);

			WritePackCell(dp, client);
			WritePackCell(dp, ViewModel);
			WritePackCell(dp, GetIgnoredSequencesForWeapon(client));
		}
		else
		{
			return;
		}

		if (!gbInZoomState[client]){
			ToggleLaser(client, true);
		}
		else
		{
			g_bEmitsLaser[client] = true;
			ToggleLaser(client);
		}
	}
}


void OnReloadKeyPressed(int client)
{
	#if DEBUG
	PrintToServer("[nt_lasersight] Key IN_RELOAD pressed.");
	SetWeaponAmmo(client, AMMO_PRIMARY, 24);
	#endif

	//check until "m_bInReload" in weapon_srs is released -> TODO in any weapon?
	if (CheckInReload(client))
		ToggleLaser(client, true);
}


bool CheckInReload(int client)
{
	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"); // FIXME: should be cached
	if (GetEntProp(weapon, Prop_Data, "m_bInReload"))
		return true;

	#if DEBUG
	PrintToChatAll("[nt_lasersight] weapon %d is in reload!", weapon);
	#endif

	return false;
}


// Tracks sequence to reset zoom state
public Action timer_CheckSequence(Handle timer, DataPack datapack)
{
	ResetPack(datapack);
	int client = ReadPackCell(datapack);
	int weapon = ReadPackCell(datapack);
	int reload_sequence = ReadPackCell(datapack);

	PrintCenterTextAll("Client %d zoom is %s", client, (gbInZoomState[client] ? "active" : "inactive"));

	if (!IsValidClient(client) || IsFakeClient(client)){
		ghTimerCheckSequence[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	// int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);

	if (!IsValidEdict(weapon))
	{
		#if DEBUG
		PrintToServer("!IsValidEdict: %i", weapon);
		#endif
		ghTimerCheckSequence[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	// gbInZoomState[client] = GetInReload(weapon);
	PrintToServer("m_nSequence: %d", GetEntProp(weapon, Prop_Data, "m_nSequence", 4));

	int iCurrentSequence = GetEntProp(weapon, Prop_Data, "m_nSequence", 4);
	// For SRS: 3 shooting, 4 fire pressed continuously, 6 reloading, 11 bolt
	// m_nSequence == 6 is equivalent to m_bInReload == 1, m_nSequence == 0 means stand-by
	if (reload_sequence > 0)
	{
		if (iCurrentSequence == reload_sequence)
			gbInZoomState[client] = false;
	}
	else{ // ignore everything that is not 0 (for weapon_srs)
		if (iCurrentSequence > 0)
			gbInZoomState[client] = false;
	}

	// PrintToServer("m_bInReload: %d", GetEntProp(weapon, Prop_Data, "m_bInReload", 1));
	// gbInZoomState[client] = !view_as<bool>(GetEntProp(weapon, Prop_Data, "m_bInReload", 1));

	if (!gbInZoomState[client])
	{
		g_bEmitsLaser[client] = false;
		ToggleLaser(client, true);
		ghTimerCheckSequence[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}


// for regular weapons, prevent automatic laser creation on aim down sight
void ToggleLaserCompletely(int client)
{
	gbLaserActive[client] = !gbLaserActive[client];
	#if DEBUG
	PrintToChatAll("[nt_lasersight] Laser toggled %s.", gbLaserActive[client] ? "on" : "off");
	#endif
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


bool IsPlayerReallyAlive(int client)
{
	#if DEBUG
	PrintToServer("[nt_lasersight] Client %N (%d) has %d health.", client, client, GetEntProp(client, Prop_Send, "m_iHealth"));
	#endif

	// For some reason, 1 health point means dead, but checking deadflag is probably more reliable!
	// Note: CPlayerResource also seems to keep track of players alive state (netprop)
	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1 || GetEntProp(client, Prop_Send, "deadflag") || GetEntProp(client, Prop_Send, "m_iObserverMode") > 0)
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] Determined that %N is not alive right now.", client);
		#endif
		return false;
	}

	return true;
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