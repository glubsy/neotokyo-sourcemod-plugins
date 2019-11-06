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
int iAffectedWeapons[NEO_MAX_CLIENTS + 1]; // only primary weapons currently
int iAffectedWeapons_Head = 0;

bool g_bNeedUpdateLoop;
bool g_bEmitsLaser[NEO_MAX_CLIENTS+1];
bool gbInZoomState[NEO_MAX_CLIENTS+1]; // laser can be displayed
Handle ghTimerCheckSequence[NEO_MAX_CLIENTS+1] = { INVALID_HANDLE, ...};
int giHideOwnBeam[NEO_MAX_CLIENTS+1];
bool gbShouldTransmitDot[NEO_MAX_CLIENTS+1]
bool gbLaserActive[NEO_MAX_CLIENTS+1];
int giActiveWeapon[NEO_MAX_CLIENTS+1];
bool gbActiveWeaponIsSRS[NEO_MAX_CLIENTS+1];
bool gbFreezeTime[NEO_MAX_CLIENTS+1];
bool gbIsRecon[NEO_MAX_CLIENTS+1];
bool gbVisionKeyHeld[NEO_MAX_CLIENTS+1];
bool gbVisionActive[NEO_MAX_CLIENTS+1];

//OLD: each entity has an array of affected clients
int giLaserBeam[NEO_MAX_CLIENTS+1]; // per weapon (not client)
int giLaserDot[NEO_MAX_CLIENTS+1]; // per weapon (not client)
int giAttachment[NEO_MAX_CLIENTS+1]; // per weapon (not client)

public Plugin:myinfo =
{
	name = "NEOTOKYO laser sights",
	author = "glub",
	description = "Traces a laser beam from weapons.",
	version = "0.3",
	url = "https://github.com/glubsy"
};


// OBJECTIVE: laser beam can only be seen as spectators, or through night vision (thicker & more visible if possible)
// but not through motion nor thermal vsion (don't send to of those classes when vision active)
// laser dot visible also only with bare eyes and night vision
// laser beams are always visible to spectators

// TODO: use return GetEntProp(weapon, Prop_Data, "m_iState") to check if weapon is being carried by a player (see smlib/weapons.inc)
// TODO: make checking for in_zoom state a forward (for other plugins to use)?
// TODO: Attach a prop to the muzzle of every srs, then raytrace a laser straight in front when tossed in the world
// TODO: setup two beams, a normal one for spectators, a thicker one for night vision.

#define ATTACH 1
#define CROTCH 2
#define METHOD ATTACH
// Method 0: teleport entity and get start of beam from it
// Method 1: no need for (parented) invisible prop here, just trace a ray from a fixed point in front of player

public void OnPluginStart()
{
	CVAR_PluginEnabled = CreateConVar("sm_lasersight_enable", "1",
	"Enable (1) or disable (0) Sniper Laser.", _, true, 0.0, true, 1.0);
	CVAR_LaserAlpha = CreateConVar("sm_lasersight_alpha", "20.0",
	"Transparency amount for laser beam", _, true, 0.0, true, 255.0);
	laser_color[3] = GetConVarInt(CVAR_LaserAlpha); //TODO: hook convar change
	CVAR_AllWeapons = CreateConVar("sm_lasersight_allweapons", "1",
	"Draw laser beam from all weapons, not just sniper rifles.", _, true, 0.0, true, 1.0);

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

	// HookEvent("player_spawn", OnPlayerSpawn); // we'll use SDK hook instead
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("game_round_end", OnRoundEnd);
}

	#if DEBUG
public void OnConfigsExecuted()
{
	// for late loading only
	for (int client = 1; client <= MaxClients; ++client)
	{
		if (!IsValidClient(client) || !IsClientInGame(client))
			continue;

		PrintToServer("[nt_lasersight] Hooking client %d", client);
		SDKHook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
		SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
		SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
		SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);

		// CreateTimer(1.0, timer_LookForWeaponsToTrack, GetClientUserId(client));
	}
}
#endif

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
	// FIXME Is this really necessary? probably not. REMOVE
	for (int i = 0; i < sizeof(iAffectedWeapons); ++i)
		if (iAffectedWeapons[i] == entity)
			iAffectedWeapons[i] = 0;
}


public void OnClientPutInServer(int client)
{
	g_bEmitsLaser[client] = false;

	SDKHook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
}


public void OnClientDisconnect(int client)
{
	g_bEmitsLaser[client] = false;
	// TODO clean up here?

	SDKUnhook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
	SDKUnhook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
	SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKUnhook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
}


public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	if (g_bEmitsLaser[victim])
		ToggleLaser(victim, true);
}


public void OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= sizeof(iAffectedWeapons); ++i)
	{
		giAttachment[i] = 0;
		giLaserDot[i] = 0;
		giLaserBeam[i] = 0;
	}
}


public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; ++i)
		gbFreezeTime[i] = true;

	// CreateTimer(20.0, timer_FreezeTimeOff, -1, TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_FreezeTimeOff(Handle timer, int client)
{
	if (client > 0)
	{
		gbFreezeTime[client] = false;

		// reset our active weapon in case it was overwritten during respawn
		UpdateActiveWeapon(client, GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"));
		return Plugin_Stop;
	}
	return Plugin_Stop;
}


public void OnClientSpawned_Post(int client)
{
	#if DEBUG
	PrintToServer("[nt_lasersight] OnClientSpawned_Post (%N)", client);
	#endif

	if (!IsPlayerReallyAlive(client)) // avoid potential spectator spawns
		return;

	// stop checking for primary wpn after this delay
	CreateTimer(0.5, timer_FreezeTimeOff, client, TIMER_FLAG_NO_MAPCHANGE);

	gbIsRecon[client] = GetEntProp(client, Prop_Send, "m_iClassType") == 1 ? true : false ;
}


public Action timer_CreateLaserEntities(Handle timer, int client)
{
	if (!IsClientInGame(client))
		return Plugin_Stop;

	CreateLaserEntities(client);
	return Plugin_Stop;
}


void CreateLaserEntities(int client)
{
	int weapon_index = GetTrackedWeaponIndex(GetPlayerWeaponSlot(client, SLOT_PRIMARY));

	if (weapon_index < 0)
		ThrowError("[nt_lasersight] Primary weapon returned index -1. Failed creating laser entities!");

	CreateFakeAttachedProp(weapon_index, client);
	CreateLaserDot(weapon_index);
	CreateLaserBeam(weapon_index);
}

// // Redundant with SDKHook's OnClientSpawned_Post
// public Action OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
// {
// 	new client = GetClientOfUserId(GetEventInt(event, "userid"));

// 	#if DEBUG
// 	PrintToServer("[nt_lasersight] OnPlayerSpawn (%N)", client);
// 	#endif

// 	if (!IsPlayerReallyAlive(client)) // avoid potential spectator spawns
// 		return Plugin_Continue;

// 	// need no delay in case player tosses primary weapon
// 	CreateTimer(1.0, timer_LookForWeaponsToTrack, GetClientUserId(client));
// 	return Plugin_Continue;
// }


// This is redundant if we only affect SLOT_PRIMARY weapons anyway, no need to test here REMOVE?
public Action timer_LookForWeaponsToTrack(Handle timer, int userid)
{
	LookForWeaponsToTrack(GetClientOfUserId(userid));
	return Plugin_Stop;
}


// Should be called only once at the start of the round
void LookForWeaponsToTrack(int client)
{
	if (!IsValidClient(client) || !IsClientInGame(client))
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] LookForWeaponsToTrack: client %d is invalid.", client);
		#endif
		return;
	}

	#if DEBUG
	PrintToServer("[nt_lasersight] LookForWeaponsToTrack: %N", client);
	#endif

	int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);

	if (!IsValidEdict(weapon))
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] LookForWeaponsToTrack() !IsValidEdict: %i", weapon);
		#endif
		return;
	}

	decl String:classname[LONGEST_WEP_NAME + 1]; // Plus one for string terminator.

	if (!GetEdictClassname(weapon, classname, sizeof(classname)))
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] LookForWeaponsToTrack() !GetEdictClassname: %i", weapon);
		#endif
		return;
	}

	// only test the two last wpns if limited to sniper rifles
	int stop_at = (GetConVarBool(CVAR_AllWeapons) ? 0 : sizeof(g_sLaserWeaponNames) - 2)

	for (int i = sizeof(g_sLaserWeaponNames) - 1 ; i >= stop_at; --i)
	{
		if (StrEqual(classname, g_sLaserWeaponNames[i]))
		{
			#if DEBUG
			PrintToServer("[nt_lasersight] Store OK: %s is %s. Hooking %s %d",
			classname, g_sLaserWeaponNames[i], classname, weapon);
			#endif

			StoreWeapon(weapon);
			break;
		}
		else
		{
			#if DEBUG > 2
			PrintToServer("[nt_lasersight] Store fail: %s is not %s.",
			classname, g_sLaserWeaponNames[i]);
			#endif
		}
	}
}


// Assumes valid input; make sure you're inputting a valid edict.
// this avoids having to compare classname strings in favour of ent ids
void StoreWeapon(int weapon)
{
	#if DEBUG
	if (iAffectedWeapons_Head >= sizeof(iAffectedWeapons))
	{
		ThrowError("[nt_lasersight] iAffectedWeapons_Head %i >= sizeof(iAffectedWeapons) %i",
			iAffectedWeapons_Head, sizeof(iAffectedWeapons));
	}
	#endif

	iAffectedWeapons[iAffectedWeapons_Head] = weapon;

	#if DEBUG
	PrintToServer("[nt_lasersight] Stored weapon %d at iAffectedWeapons[%d]", weapon, iAffectedWeapons_Head);
	#endif

	// Cycle around the array.
	iAffectedWeapons_Head++;
	iAffectedWeapons_Head %= sizeof(iAffectedWeapons);
}


// Assumes valid input; make sure you're inputting a valid edict.
// Returns index from the tracked weapons array, -1 if not found
int GetTrackedWeaponIndex(int weapon)
{
	#if DEBUG
	if (weapon <= 0){
		// This may happen if primary weapon failed to be given to a player on spawn ?
		ThrowError("[nt_lasersight] GetTrackedWeaponIndex weapon <= 0 !!!");
	}
	#endif

	static int WepsSize = sizeof(iAffectedWeapons);
	for (int i = 0; i < WepsSize; ++i)
	{
		if (weapon == iAffectedWeapons[i])
		{
			#if DEBUG
			PrintToServer("[nt_lasersight] GetTrackedWeaponIndex %d found at iAffectedWeapons[%i]",
			weapon, i);
			#endif

			return i;
		}

		#if DEBUG > 2
		PrintToServer("[nt_lasersight] %i not tracked. Compared to iAffectedWeapons[%i] %i",
		weapon, i, iAffectedWeapons[i]);
		#endif
	}

	#if DEBUG
	PrintToServer("[nt_lasersight] GetTrackedWeaponIndex(%i) returns -1.", weapon);
	#endif
	return -1;
}


public void OnWeaponSwitch_Post(int client, int weapon)
{
	#if DEBUG
	// if (!IsFakeClient(client)) {  // reduces log output
		PrintToServer("[nt_lasersight] OnWeaponSwitch_Post %N (%d), weapon %d",
		client, client, weapon);
	// }
	#endif

	if (gbFreezeTime[client])
		return;

	if (g_bEmitsLaser[client])
	{
		ToggleLaser(client, true);
	}
	UpdateActiveWeapon(client, weapon);
}


public void OnWeaponEquip(int client, int weapon)
{
	#if DEBUG
	// if (!IsFakeClient(client)) { // reduces log output
		PrintToServer("[nt_lasersight] OnWeaponEquip %N (%d), weapon %d",
		client, client, weapon);
	// }
	#endif

	if (gbFreezeTime[client])
	{
		if (GetWeaponSlot(weapon) != SLOT_PRIMARY)
			return;

		#if DEBUG
		char classname[35];
		GetEntityClassname(weapon, classname, sizeof(classname));
		PrintToServer("[nt_lasersight] Found primary weapon %s (%d) for client %N (%d)",
		classname, weapon, client, client);
		#endif

		LookForWeaponsToTrack(client);
		CreateLaserEntities(client);
		gbFreezeTime[client] = false;
		return;
	}

	g_bEmitsLaser[client] = false;
	// UpdateActiveWeapon(client, weapon); // removed
}



// if anyone has a weapon which has a laser, ask for OnGameFrame() coordinates updates
void NeedUpdateLoop()
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (g_bEmitsLaser[i])
		{
			#if DEBUG > 2
			PrintToServer("[nt_lasersight] g_bEmitsLaser[%N] is true, NeedUpdateLoop()", i);
			#endif

			g_bNeedUpdateLoop = true;
			return;
		}
	}
	g_bNeedUpdateLoop = false;
}


void CreateFakeAttachedProp(int weapon, int client)
{
	if (giAttachment[weapon] > 0){
		#if DEBUG
		PrintToServer("[nt_lasersight] Attachment already exists for weapon %d", iAffectedWeapons[weapon]);
		#endif
		return;
	}
	giAttachment[weapon] = CreateEntityByName("info_target");
	#if DEBUG
	// giAttachment[weapon] = CreateEntityByName("prop_dynamic_ornament");
	// giAttachment[weapon] = CreateEntityByName("prop_physics");
	// DispatchKeyValue(giAttachment[weapon], "model", "models/nt/a_lil_tiger.mdl");
	PrintToServer("[nt_lasersight] Created info_target on %N 's weapon (%d)",
	client, iAffectedWeapons[weapon]);
	#endif

	char ent_name[20];
	Format(ent_name, sizeof(ent_name), "info_target%d", weapon); // tag this weapon
	DispatchKeyValue(giAttachment[weapon], "targetname", ent_name);

	DispatchSpawn(giAttachment[weapon]);

	float VecOrigin[3];
	GetClientEyePosition(client, VecOrigin);

	#if METHOD == ATTACH
	MakeParent(giAttachment[weapon], iAffectedWeapons[weapon]);
	CreateTimer(0.1, timer_SetAttachment, giAttachment[weapon]);
	#endif

	// TeleportEntity(giAttachment[weapon], VecOrigin, NULL_VECTOR, NULL_VECTOR);
	TeleportEntity(giAttachment[weapon], NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
}


void MakeParent(int entity, int weapon)
{
	char buffer[64];
	Format(buffer, sizeof(buffer), "weapon%d", weapon);
	DispatchKeyValue(weapon, "targetname", buffer); // redundant?

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", weapon, weapon, 0);
}


public Action timer_SetAttachment(Handle timer, int entity)
{
	#if DEBUG
	PrintToServer("[nt_lasersight] SetParentAttachment to muzzle for attachment %d.", entity);
	#endif

	SetVariantString("muzzle"); // "muzzle" works for when attaching to weapon
	AcceptEntityInput(entity, "SetParentAttachment");
	// SetVariantString("grenade0");
	// AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset");
}


// index of affected weapon in array
void CreateLaserDot(int weapon)
{
	if (giLaserDot[weapon] <= 0) // we have not already created a laser dot
	{
		giLaserDot[weapon] = CreateLaserDotEnt(weapon);
		// gbShouldTransmitDot[client] = false;
		// SDKHook(giLaserDot[weapon], SDKHook_SetTransmit, Hook_SetTransmitLaserDot);
	}
}


// for player disconnect?
void DestroyLaserDot(int client)
{
	if (giLaserDot[giActiveWeapon[client]] > 0 && IsValidEntity(giLaserDot[giActiveWeapon[client]]))
	{
		// SDKUnhook(giLaserDot[client], SDKHook_SetTransmit, Hook_SetTransmitLaserDot)
		AcceptEntityInput(giLaserDot[giActiveWeapon[client]], "kill");
		giLaserDot[giActiveWeapon[client] = -1;
	}
}


void ToggleLaserDot(int client)
{
	if (giLaserDot[giActiveWeapon[client]] < 0
	|| !IsValidEntity(giLaserDot[giActiveWeapon[client]]))
		return;

	#if DEBUG
	PrintToServer("[nt_lasersight] %s laser dot for %N.",
	g_bEmitsLaser[client] ? "Showing" : "Hiding", client);
	#endif

	AcceptEntityInput(giLaserDot[giActiveWeapon[client]],
	g_bEmitsLaser[client] ? "ShowSprite" : "HideSprite");
}


int CreateLaserDotEnt(int weapon)
{
	// env_sprite, env_sprite_oriented, env_glow are the same
	int ent = CreateEntityByName("env_sprite"); // env_sprite always face the player

	if (!IsValidEntity(ent))
		return -1;

	char dot_name[10];
	Format(dot_name, sizeof(dot_name), "dot%d", weapon);
	DispatchKeyValue(ent, "targetname", dot_name);

	#if DEBUG
	PrintToServer("[nt_lasersight] Created laser dot \"%s\" for weapon %d.", dot_name, weapon );
	#endif

	DispatchKeyValue(ent, "model", "materials/sprites/laserdot.vmt");
	DispatchKeyValueFloat(ent, "scale", 0.1); // doesn't seem to work
	// SetEntPropFloat(ent, Prop_Data, "m_flSpriteScale", 0.2); // doesn't seem to work
	DispatchKeyValue(ent, "rendermode", "9"); // 3 glow, makes it smaller?, 9 world space glow 5 additive,
	DispatchKeyValueFloat(ent, "GlowProxySize", 0.2); // not sure if this works
	DispatchKeyValueFloat(ent, "HDRColorScale", 1.0); // needs testing
	DispatchKeyValue(ent, "renderamt", "160"); // transparency
	DispatchKeyValue(ent, "disablereceiveshadows", "1");
	// DispatchKeyValue(ent, "renderfx", "15"); //distort
	DispatchKeyValue(ent, "renderfx", "23"); //cull by distance
	// DispatchKeyValue(ent, "rendercolor", "0 255 0");

	SetVariantFloat(0.1);
	AcceptEntityInput(ent, "SetScale");  // this works!

	// SetVariantFloat(0.2);
	// AcceptEntityInput(ent, "scale"); // doesn't work

	DispatchSpawn(ent);

	return ent;
}


// index of weapon in affected weapons array to tie the beam to
void CreateLaserBeam(int weapon)
{
	if (weapon < 0)
		ThrowError("[nt_lasersight] Weapon -1 in CreateLaserBeam!");

	if (giLaserBeam[weapon] > 0)
	{
		#if DEBUG
		ThrowError("[nt_lasersight] Laser beam already existed for weapon %d!",
		iAffectedWeapons[weapon]);
		#endif
		return;
	}

	giLaserBeam[weapon]	= CreateLaserBeamEnt(weapon);

	SDKHook(giLaserBeam[weapon], SDKHook_SetTransmit, Hook_SetTransmitLaserBeam);
}

void ToggleLaserBeam(int client)
{
	AcceptEntityInput(giLaserBeam[giActiveWeapon[client]], g_bEmitsLaser[client] ? "TurnOn" : "TurnOff");
	#if DEBUG
	PrintToServer("[nt_lasersight] %s laser beam %d for %N",
	g_bEmitsLaser[client] ? "Turned On" : "Turned Off", giLaserBeam[giActiveWeapon[client]], client);
	#endif
}


// maybe needed on player disconnect?
void DestroyLaserBeam(int weapon)
{
	if (!IsValidEntity(giLaserBeam[weapon]))
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] DestroyLaserBeam() laser beam was invalid entity.")
		#endif
		giLaserBeam[weapon] = -1;
		return;
	}
	AcceptEntityInput(giLaserBeam[weapon], "kill");
	giLaserBeam[weapon] = -1;
}


int CreateLaserBeamEnt(int weapon)
{
	int laser_entity = CreateEntityByName("env_beam");

	#if DEBUG
	PrintToServer("[nt_lasersight] Created laser BEAM for weapon %d.", weapon);
	#endif

	char ent_name[20];
	IntToString(weapon, ent_name, sizeof(ent_name));
	DispatchKeyValue(laser_entity, "targetname", ent_name);

	ent_name[0] = '\0';
	Format(ent_name, sizeof(ent_name), "info_target%d", weapon);
	DispatchKeyValue(laser_entity, "LightningStart", ent_name);

	ent_name[0] = '\0';
	Format(ent_name, sizeof(ent_name), "dot%d", weapon);
	DispatchKeyValue(laser_entity, "LightningEnd", ent_name);

	// float vec[3];
	// GetClientEyePosition(client, vec);
	// DispatchKeyValueVector(laser_entity, "targetpoint", vec); // TESTING

	// Positioning
	// DispatchKeyValueVector(laser_entity, "origin", mine_pos);
	// TeleportEntity(laser_entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	// SetEntPropVector(laser_entity, Prop_Data, "m_vecEndPos", beam_end_pos);

	// Setting Appearance
	DispatchKeyValue(laser_entity, "texture", "materials/sprites/laser.vmt");
	DispatchKeyValue(laser_entity, "model", "materials/sprites/laser.vmt");
	DispatchKeyValue(laser_entity, "decalname", "redglowalpha");

	DispatchKeyValue(laser_entity, "renderamt", "120"); // TODO(?): low renderamt, increase when activate
	DispatchKeyValue(laser_entity, "renderfx", "15");
	DispatchKeyValue(laser_entity, "rendercolor", "200 25 25 128");
	DispatchKeyValue(laser_entity, "BoltWidth", "2.0");

	// something else..
	DispatchKeyValue(laser_entity, "life", "0.0");
	DispatchKeyValue(laser_entity, "StrikeTime", "0");
	DispatchKeyValue(laser_entity, "TextureScroll", "35");
	// DispatchKeyValue(laser_entity, "TouchType", "3");

	DispatchSpawn(laser_entity);
	SetEntityModel(laser_entity,  "materials/sprites/laser.vmt");

	ActivateEntity(laser_entity); // not sure what that is (for texture animation?)

	// Link between weapon and laser indirectly. NEEDS TESTING
	// SetEntPropEnt(client, Prop_Send, "m_hEffectEntity", laser_entity);
	// SetEntPropEnt(laser_entity, Prop_Data, "m_hMovePeer", client); // should it be the attachment prop or weapon even?

	return laser_entity;
}



public void OnWeaponDrop(int client, int weapon)
{
	if(!IsValidEdict(weapon) || !IsValidClient(client))
		return;

	if (giActiveWeapon[client] > -1)
	{
		ToggleLaserDot(client);
		ToggleLaser(client);
	}

	g_bEmitsLaser[client] = false;
	NeedUpdateLoop();
}


// Tracks and caches active weapon
void UpdateActiveWeapon(int client, int weapon)
{
	// if(!IsValidEdict(weapon) || !IsValidClient(client))
	// 	return;

	giActiveWeapon[client] = GetTrackedWeaponIndex(weapon);

	// hide the beam that is tied to the active weapon
	if (giActiveWeapon[client] > -1)
		giHideOwnBeam[client] = giLaserBeam[giActiveWeapon[client]];
	else
		giHideOwnBeam[client] = -1;

	if (IsActiveWeaponSRS(weapon))
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] weapon_srs detected for client %N.", client);
		#endif

		gbActiveWeaponIsSRS[client] = true;
		return;
	}

	gbActiveWeaponIsSRS[client] = false;
}


public OnGameFrame()
{
	if(g_bNeedUpdateLoop)
	{
		for (int client = 1; client <= MaxClients; ++client)
		{
			if(!g_bEmitsLaser[client] || !IsValidClient(client))
				continue;

			float vecEnd[3], vecDir[3], vecVel[3];
			GetEndPositionFromClient(client, vecEnd);

			// Update Laser dot sprite position here
			if (IsValidEntity(giLaserDot[giActiveWeapon[client]])){

				// attempts to smooth out position updates by adding velocity?
				GetEntPropVector(giLaserDot[giActiveWeapon[client]], Prop_Send, "m_vecOrigin", vecDir);
				SubtractVectors(vecEnd, vecDir, vecVel);
				ScaleVector(vecVel, 100.0);

				TeleportEntity(giLaserDot[giActiveWeapon[client]], vecEnd, NULL_VECTOR, vecVel);
			}

			float vecStart[3];
			GetBeamPositions(client, vecStart, vecEnd);

			#if METHOD == CROTCH
			int startEnt, endEnt;
			if (IsValidEntity(giAttachment[giActiveWeapon[client]])) // FiXME! will break if -1 (old logic)
			{
				vecStart = NULL_VECTOR;
				startEnt = giAttachment[giActiveWeapon[client]];
			}
			if (IsValidEntity(giLaserDot[giActiveWeapon[client]])) // FiXME! will break
			{
				vecEnd = NULL_VECTOR;
				endEnt = giLaserDot[giActiveWeapon[client]];
			}

			Create_TE_Beam(client, vecStart, vecEnd, startEnt, endEnt);
			#endif // METHOD <= ATTACH
		}
	}
}


void GetBeamPositions(int client, float[3] vecStart, float[3] vecEnd)
{
	GetClientEyePosition(client, vecStart);
	vecStart[2] -= 28.0; 		// roughly starting from "center of mass"

	#if METHOD < -1 // DEBUG temporarily disabled because OLD LOGIC!
	float vecForward[3], vecVel[3], vecEyeAng[3];

	if (giAttachment[client] > 0 && IsValidEntity(giAttachment[client])){
		// GetEntPropVector(giAttachment[client], Prop_Send, "m_vecOrigin", origin);
		// PrintToChatAll("vecStart: %f %f %f", vecStart[0], vecStart[1], vecStart[2]);
		GetClientEyePosition(client, vecStart);
		GetClientEyeAngles(client, vecEyeAng);
		GetAngleVectors(vecEyeAng, vecForward, NULL_VECTOR, NULL_VECTOR);

		vecStart[0]+=vecForward[0]*20.0;
		vecStart[1]+=vecForward[1]*20.0;
		vecStart[2]+=vecForward[2]*10.0;

		SubtractVectors(vecStart, vecForward, vecVel);
		TeleportEntity(giAttachment[client], vecStart, vecEyeAng, NULL_VECTOR);

		GetEntPropVector(giAttachment[client], Prop_Send, "m_vecOrigin", vecStart);

		#if DEBUG
		PrintToChatAll("m_vecOrigin for attached %d: %f %f %f", giAttachment[client], vecStart[0], vecStart[1], vecStart[2]);
		#endif

		// from SM discord: do this OnGameFrame
		// TeleportEntity(giAttachment[client], NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
		GetEntPropVector(giAttachment[client], Prop_Data, "m_vecAbsOrigin", vecStart);
		// AcceptEntityInput(giAttachment[client], "kill");

		#if DEBUG
		PrintToChatAll("m_vecAbsOrigin for attached %d: %f %f %f", giAttachment[client], vecStart[0], vecStart[1], vecStart[2]);
		#endif
	}

	vecEnd = GetEndPositionFromWeapon(giAttachment[client], vecStart, vecEyeAng)
	#endif // METHOD == ATTACH

}


void Create_TE_Beam(int client,
const float[3] vecStart=NULL_VECTOR, const float[3] vecEnd=NULL_VECTOR,
const int iStartEnt=0, const int iEndEnt=0)
{
	// TE_Start("BeamPoints");
	TE_Start("BeamEntPoint");
	TE_WriteVector("m_vecStartPoint", vecStart);
	TE_WriteVector("m_vecEndPoint", vecEnd);
	TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);

	// specific to BeamEntPoint TE
	TE_WriteNum("m_nStartEntity", iStartEnt);
	TE_WriteNum("m_nEndEntity", iEndEnt);

	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo); 	// NOTE: Halo can be set to "0"!
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

	// FIXME do this elsewhere and cache it
	int iBeamClients[NEO_MAX_CLIENTS+1], nBeamClients;
	for(int j = 1; j <= sizeof(iBeamClients); ++j)
	{
		if(IsValidClient(j) && (client != j)){ // only draw for others
			// if (IsNotUsingNightVision(j))   // TODO (only if using TE)
			//		continue;
			iBeamClients[nBeamClients++] = j;
		}
	}
	TE_Send(iBeamClients, nBeamClients);
}


// trace from weapon (for ATTACH method)
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

		// FIXME: remove all this as it might be obsolete now?
		int hit_entity = TR_GetEntityIndex(INVALID_HANDLE);
		if (0 < hit_entity <= MaxClients) // we hit a player
		{
			float hit_normals[3];
			TR_GetPlaneNormal(INVALID_HANDLE, hit_normals);

			// TR_TraceRayFilter(start, angle, (CONTENTS_SOLID|CONTENTS_MOVEABLE|CONTENTS_MONSTER|CONTENTS_DEBRIS|CONTENTS_HITBOX), RayType_Infinite, TraceEntityFilterPlayer, client);

			#if DEBUG > 2
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

			return true;
		}
		else
		{

			int AffectedClients[NEO_MAX_CLIENTS+1], numClients;
			for (int j = 1; j <= MaxClients; ++j)
			{
				if (!IsValidClient(j) || !IsClientConnected(j) /*|| j == client*/) // can't draw for client due to latency :/
					continue;
				AffectedClients[numClients++] = j;
			}

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


// probaby won't use this
public Action Hook_SetTransmitLaserDot(int entity, int client)
{
	if (entity == giLaserDot[client])
		return Plugin_Handled; // hide player's own laser dot from himself

	return Plugin_Continue;
}


// entity emits to client or not
public Action Hook_SetTransmitLaserBeam(int entity, int client)
{
	// hide if not using night vision, or beam comes from our active weapon
	if (!gbVisionActive[client] || giHideOwnBeam[client] == entity)
		return Plugin_Handled;

	return Plugin_Continue;
}


bool IsActiveWeaponSRS(int weapon)
{
	decl String:weaponName[20];
	GetEntityClassname(weapon, weaponName, sizeof(weaponName));
	if (StrEqual(weaponName, "weapon_srs"))
		return true;
	return false;
}


void ToggleZoomState(int client, int weapon)
{
	gbInZoomState[client] = !gbInZoomState[client];
}


public Action OnPlayerRunCmd(int client, int &buttons)
{
	#if DEBUG > 2
	if (IsFakeClient(client))
		return Plugin_Continue;
	char classname[30];
	if (giActiveWeapon[client] > -1){
		GetEntityClassname(iAffectedWeapons[giActiveWeapon[client]], classname, sizeof(classname));
	}
	else{
		int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		if (weapon > 0)
			GetEntityClassname(weapon, classname, sizeof(classname));
	}
	PrintToChatAll("Active weapon for %d: %d %s", client, iAffectedWeapons[giActiveWeapon[client]], classname);
	#endif // DEBUG


	if (!client || IsFakeClient(client) || !GetConVarBool(CVAR_PluginEnabled))
		return Plugin_Continue;

	if (buttons & IN_GRENADE1) // ZOOM key
	{
		if (giActiveWeapon[client] > -1)
			OnZoomKeyPressed(client);
	}

	if (buttons & IN_RELOAD)
	{
		if (giActiveWeapon[client] > -1)
			OnReloadKeyPressed(client);
	}

	if (buttons & IN_SPRINT)
	{
		gbInZoomState[client] = false;
		if (giActiveWeapon[client] > -1 && g_bEmitsLaser[client])
		{
			ToggleLaser(client, true);
		}
	}

	if (buttons & IN_ATTACK)
	{
		#if DEBUG > 2
		PrintToServer("[nt_lasersight] Key IN_ATTACK pressed.");
		#endif

		if (giActiveWeapon[client] > -1)
		{
			// FIXME if player holds attack, don't kill laser until release of button
			if (gbActiveWeaponIsSRS[client] && gbInZoomState[client])
			{
				gbInZoomState[client] = false;
				ToggleLaser(client, true);
				return Plugin_Continue;
			}

			if (ghTimerCheckSequence[client] == INVALID_HANDLE && gbInZoomState[client])
			{
				// check if we're automatically reloading due to empty clip
				DataPack dp = CreateDataPack();
				ghTimerCheckSequence[client] = CreateTimer(2.5,
				timer_CheckSequence, dp, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
				WritePackCell(dp, client);
				WritePackCell(dp, iAffectedWeapons[giActiveWeapon[client]]);
				WritePackCell(dp, GetIgnoredSequencesForWeapon(client)); // FIXME cache this!
			}
		}
	}

	if (buttons & IN_ATTACK2) // Alt Fire mode key (ie. tachi)
	{
		#if DEBUG
		PrintToServer("[nt_lasersight] Key IN_ATTACK2 pressed (alt fire).");
		#endif

		if (giActiveWeapon[client] > -1 && !gbActiveWeaponIsSRS[client]){
			// toggle laser beam here for other than SRS
			TurnOffLaser(client);
		}
	}

	if ((buttons & IN_VISION) && gbIsRecon[client])
	{
		if(gbVisionKeyHeld[client])
		{
			buttons &= ~IN_VISION; // release
		}
		else
		{
			if (gbVisionActive[client])
				// gbVisionActive[client] = GetEntProp(client, Prop_Send, "m_iVision") == 2 ? true : false;
				gbVisionActive[client] = false;
			else
				gbVisionActive[client] = true; // we assume vision is active client-side
			gbVisionKeyHeld[client] = true;
		}
	}
	else if (gbIsRecon[client])
	{
		gbVisionKeyHeld[client] = false;
	}
	#if DEBUG > 2
	PrintToChatAll("Vision %s (%d), (recon: %d)", gbVisionActive[client] ? "ACTIVE" : "inactive",
	GetEntProp(client, Prop_Send, "m_iVision"), gbIsRecon[client]);
	#endif

	return Plugin_Continue;
}



void ToggleLaser(int client, bool forceoff=false)
{
	if (forceoff){
		g_bEmitsLaser[client] = false;
		ToggleLaserDot(client);
		ToggleLaserBeam(client);
		NeedUpdateLoop();
		return;
	}

	if (!gbInZoomState[client])
	{
		g_bEmitsLaser[client] = false;
		ToggleLaserDot(client);
		ToggleLaserBeam(client);
	}
	else
	{
		g_bEmitsLaser[client] = true;
		ToggleLaserDot(client);
		ToggleLaserBeam(client);
	}
	NeedUpdateLoop();
}


void OnZoomKeyPressed(int client)
{
	#if DEBUG > 2
	int ViewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	PrintToServer("[nt_lasersight] viewmodel index: %d", ViewModel);
	#endif

	if (giActiveWeapon[client] > -1)
	{
		#if DEBUG > 2
		new bAimed = GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Send, "bAimed");
		PrintToServer("[nt_lasersight] bAimed: %d", bAimed);
		#endif

		gbInZoomState[client] = !((GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Send, "bAimed") ||
		GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Data, "m_bInReload")));

		if (gbActiveWeaponIsSRS[client] && (GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Data, "m_nSequence", 4) > 0))
		{
			// bolt reload between shots
			return;
		}

		if (!gbInZoomState[client]){
			ToggleLaser(client, true);
			return;
		}
		#if DEBUG
		PrintToServer("[nt_lasersight] %N is toggling laser.", client);
		#endif

		ToggleLaser(client);
	}
}


void OnReloadKeyPressed(int client)
{
	#if DEBUG
	int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
	PrintToServer("[nt_lasersight] Key IN_RELOAD pressed for weapon %d", weapon);
	SetWeaponAmmo(client, GetAmmoType(GetActiveWeapon(client)), 90);
	#endif

	//check until "m_bInReload" in weapon_srs is released -> TODO in any weapon?
	if (view_as<bool>(GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Data, "m_bInReload")))
		ToggleLaser(client, true);
}


// return fire on empty sequences
// FIXME: check these only on weapon_switch and weapon_equip
// FIXME: it might be better to check view models?
int GetIgnoredSequencesForWeapon(int client)
{
	decl String:weaponName[LONGEST_WEP_NAME+1];
	GetClientWeapon(client, weaponName, sizeof(weaponName));

	if (StrEqual(weaponName, "weapon_jitte") ||
		StrEqual(weaponName, "weapon_jittescoped") ||
		StrEqual(weaponName, "weapon_m41") ||
		StrEqual(weaponName, "weapon_m41s") ||
		StrEqual(weaponName, "weapon_pz"))
		return 5;

	if (StrEqual(weaponName, "weapon_mpn") ||
		StrEqual(weaponName, "weapon_srm") ||
		StrEqual(weaponName, "weapon_srm_s") ||
		StrEqual(weaponName, "weapon_zr68c") ||
		StrEqual(weaponName, "weapon_zr68s") ||
		StrEqual(weaponName, "weapon_zr68l") ||
		StrEqual(weaponName, "weapon_mx") ||
		StrEqual(weaponName, "weapon_mx_silenced"))
		return 6;

	// by default ignore all sequences above 0
	return 0;
}

// Tracks sequence to reset zoom state
public Action timer_CheckSequence(Handle timer, DataPack datapack)
{
	ResetPack(datapack);
	int client = ReadPackCell(datapack);
	int weapon = ReadPackCell(datapack); // FIXME weapon might have been dropped by now!
	// int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
	int ignored_sequence = ReadPackCell(datapack);

	if (!IsValidClient(client)){
		ghTimerCheckSequence[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	if (!IsValidEdict(weapon)){
		#if DEBUG
		PrintToServer("[nt_lasersight] !IsValidEdict: %i", weapon);
		#endif
		ghTimerCheckSequence[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	// gbInZoomState[client] = GetInReload(weapon);
	#if DEBUG
	PrintToServer("[nt_lasersight] m_nSequence: %d, ammo: %d",
	GetEntProp(weapon, Prop_Data, "m_nSequence", 4),
	GetWeaponAmmo(client, GetAmmoType(GetActiveWeapon(client))));
	#endif


	if ((GetEntProp(weapon, Prop_Send, "m_iClip1") <= 0) // clip empty
	&& GetWeaponAmmo(client, GetAmmoType(GetActiveWeapon(client))))  // but we still have ammo left in backpack
	{
		int iCurrentSequence = GetEntProp(weapon, Prop_Data, "m_nSequence", 4);
		// For SRS: 3 shooting, 4 fire pressed continuously, 6 reloading, 11 bolt
		// m_nSequence == 6 is equivalent to m_bInReload == 1, m_nSequence == 0 means stand-by
		if (ignored_sequence > 0)
		{
			if (iCurrentSequence != ignored_sequence)
				gbInZoomState[client] = false;
		}

		// gbInZoomState[client] = false; // we're probably reloading by now
	}


	// PrintToServer("m_bInReload: %d", GetEntProp(weapon, Prop_Data, "m_bInReload", 1));
	// gbInZoomState[client] = !view_as<bool>(GetEntProp(weapon, Prop_Data, "m_bInReload", 1));

	if (!gbInZoomState[client])
	{
		ToggleLaser(client, true);
	}

	ghTimerCheckSequence[client] = INVALID_HANDLE;
	return Plugin_Stop;
}



// for regular weapons, prevent automatic laser creation on aim down sight
void TurnOffLaser(int client)
{
	gbLaserActive[client] = !gbLaserActive[client];
	#if DEBUG
	PrintToChatAll("[nt_lasersight] Laser toggled %s.", gbLaserActive[client] ? "on" : "off");
	#endif
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
// void CreateSriteTE(const float[3] pos, const int clients[NEO_MAX_CLIENTS+1], const int numClients)
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