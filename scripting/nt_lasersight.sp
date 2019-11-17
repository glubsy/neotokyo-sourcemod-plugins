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

enum KeyType {
	KEY_VISION = 0,
	KEY_ALTFIRE,
	KEY_SPRINT,
	KEY_ZOOM,
	KEY_RELOAD,
	KEY_ATTACK,
	MAXKEYS
}
enum WeaponType {
	WPN_NONE = -1,
	WPN_jitte = 0,
	WPN_jittescoped,
	WPN_m41,
	WPN_m41s,
	WPN_mpn,
	WPN_mx,
	WPN_mx_silenced,
	WPN_pz,
	WPN_srm,
	WPN_srm_s,
	WPN_zr68c,
	WPN_zr68s,
	WPN_zr68l,
	WPN_srs }

int g_modelLaser, g_modelHalo/*, g_imodelLaserDot*/;
Handle CVAR_LaserAlpha, CVAR_AllWeapons;
int laser_color[4] = {210, 30, 0, 200};

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
int iAffectedWeapons[NEO_MAX_CLIENTS + 1] = {-1, ...}; // only primary weapons currently
int iAffectedWeapons_Head = 0;
WeaponType giWpnType[NEO_MAX_CLIENTS + 1];

bool g_bNeedUpdateLoop;
bool gbShouldEmitLaser[NEO_MAX_CLIENTS+1];
bool gbInZoomState[NEO_MAX_CLIENTS+1]; // laser can be displayed
Handle ghTimerCheckSequence[NEO_MAX_CLIENTS+1] = { INVALID_HANDLE, ...};
Handle ghTimerCheckAimed[NEO_MAX_CLIENTS+1] = { INVALID_HANDLE, ...};
Handle ghTimerCheckSRSSequence[NEO_MAX_CLIENTS+1] = {INVALID_HANDLE, ...};
Handle ghTimerCheckReload[NEO_MAX_CLIENTS+1] = {INVALID_HANDLE, ...};
int giOwnBeam[NEO_MAX_CLIENTS+1];
bool gbLaserEnabled[NEO_MAX_CLIENTS+1];
int giActiveWeapon[NEO_MAX_CLIENTS+1]; // holds index of weapon stored in iAffectedWeapons
WeaponType giActiveWeaponType[NEO_MAX_CLIENTS+1];
bool gbActiveWeaponIsSRS[NEO_MAX_CLIENTS+1];
bool gbActiveWeaponIsZRL[NEO_MAX_CLIENTS+1];
bool gbFreezeTime[NEO_MAX_CLIENTS+1];
bool gbIsRecon[NEO_MAX_CLIENTS+1];
bool gbCanSprint[NEO_MAX_CLIENTS+1];


bool gbHeldKeys[NEO_MAX_CLIENTS+1][MAXKEYS];
bool gbVisionActive[NEO_MAX_CLIENTS+1];
bool gbIsObserver[NEO_MAX_CLIENTS+1];

int giLaserBeam[NEO_MAX_CLIENTS+1]; // per weapon (not client)
int giLaserDot[NEO_MAX_CLIENTS+1]; // per weapon (not client)
int giLaserTarget[NEO_MAX_CLIENTS+1]; // per weapon (not client)
int giAttachment[NEO_MAX_CLIENTS+1]; // per weapon (not client)

// Viewmodel entities
int giViewModelLaserStart[NEO_MAX_CLIENTS+1]; // per client
int giViewModelLaserEnd[NEO_MAX_CLIENTS+1]; // per client
int giViewModelLaserBeam[NEO_MAX_CLIENTS+1];
int giViewModel[NEO_MAX_CLIENTS+1];

public Plugin:myinfo =
{
	name = "NEOTOKYO laser sights",
	author = "glub",
	description = "Traces a laser beam from weapons.",
	version = "0.3",
	url = "https://github.com/glubsy"
};

// TODO: use return GetEntProp(weapon, Prop_Data, "m_iState") to check if weapon is being carried by a player (see smlib/weapons.inc)
// TODO: make checking for in_zoom state a forward (for other plugins to use)?
// TODO: Attach a prop to the muzzle of every srs, then raytrace a laser straight in front when tossed in the world
// TODO: setup two beams, a normal one for spectators, a thicker one for night vision?

//TODO: fire changemode or fireempty animations on toggle laser command
//TODO: look at what texture the L4D2 SDK uses for laser beams (particles)
//TODO: show the entire laser beam to players hit by traceray when pointed directly at their head
//TODO: have laser color / alpha in a convar

//FIXME: SRS first equip doesn't toggle laser on viewmodel

#define TEMP_ENT 1 // use TE every game frame, instead of actual env_beam (obsolete)
#define METHOD 0


public void OnPluginStart()
{
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
			SetFailState("[lasersight] LaserWeaponNames %i is too short to hold \
g_sLaserWeaponNames \"%s\" (length: %i) in index %i.", LONGEST_WEP_NAME,
				g_sLaserWeaponNames[i], strlen(g_sLaserWeaponNames[i]), i);
		}
	}

	// HookEvent("player_spawn", OnPlayerSpawn); // we'll use SDK hook instead
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("game_round_end", OnRoundEnd);
	HookConVarChange(FindConVar("neo_restart_this"), OnNeoRestartThis);
}


#if DEBUG
public void OnConfigsExecuted()
{
	// for late loading only
	for (int client = 1; client <= MaxClients; ++client)
	{
		if (!IsValidClient(client))
			continue;

		PrintToServer("[lasersight] Hooking client %d", client);
		SDKHook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
		SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
		SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
		SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
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
	// g_imodelLaserDot = PrecacheDecal("materials/sprites/laserdot.vmt");
	PrecacheDecal("materials/sprites/redglow1.vmt"); // good!
	// g_imodelLaserDot = PrecacheModel("materials/sprites/laser.vmt");
	// g_imodelLaserDot = PrecacheDecal("materials/decals/Blood5.vmt");
}


public void OnEntityDestroyed(int entity)
{
	// FIXME Is this really necessary? probably not. REMOVE
	for (int i = 0; i < sizeof(iAffectedWeapons); ++i)
	{
		if (iAffectedWeapons[i] == entity)
		{
			iAffectedWeapons[i] = 0;
			giWpnType[i] = WPN_NONE;
		}
	}
}


public void OnClientPutInServer(int client)
{
	gbShouldEmitLaser[client] = false;
	giOwnBeam[client] = -1;
	gbIsObserver[client] = true;

	SDKHook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
}


public void OnClientDisconnect(int client)
{
	gbShouldEmitLaser[client] = false;
	// TODO clean up here?

	// these are probably not needed as they are automatically called on disconnect
	// SDKUnhook(client, SDKHook_SpawnPost, OnClientSpawned_Post);
	// SDKUnhook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch_Post);
	// SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	// SDKUnhook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
}


public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	gbIsObserver[victim] = true;
	gbVisionActive[victim] = true; //hack to enable showing beams

	if (gbShouldEmitLaser[victim])
	{
		gbShouldEmitLaser[victim] = false;
		if (giActiveWeapon[victim] > -1)
			ToggleLaserOff(victim, giActiveWeapon[victim], 0);
	}
}

public void OnNeoRestartThis(ConVar convar, const char[] oldValue, const char[] newValue)
{
	#if DEBUG
	PrintToServer("[lasersight] OnNeoRestartThis()");
	#endif
	for (int i = 1; i < sizeof(iAffectedWeapons); ++i)
	{
		giAttachment[i] = 0;
		giLaserDot[i] = 0;
		giLaserBeam[i] = 0;

		if (giViewModelLaserBeam[i] > 0 && IsValidEdict(giViewModelLaserBeam[i]))
		{
			AcceptEntityInput(giViewModelLaserBeam[i], "kill");
			giViewModelLaserBeam[i] = 0;
		}
		if (giViewModelLaserStart[i] > 0 && IsValidEdict(giViewModelLaserStart[i]))
		{
			AcceptEntityInput(giViewModelLaserStart[i], "kill");
			giViewModelLaserStart[i] = 0;
		}
		if (giViewModelLaserEnd[i] > 0 && IsValidEdict(giViewModelLaserEnd[i]))
		{
			AcceptEntityInput(giViewModelLaserEnd[i], "kill");
			giViewModelLaserEnd[i] = 0;
		}
	}
}


public void OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i < sizeof(iAffectedWeapons); ++i)
	{
		giAttachment[i] = 0;
		giLaserDot[i] = 0;
		giLaserBeam[i] = 0;
		giActiveWeapon[i] = -1;

		#if DEBUG
		if (giViewModelLaserBeam[i] > 0 && IsValidEntity(giViewModelLaserBeam[i]))
		{
			AcceptEntityInput(giViewModelLaserBeam[i], "kill");
			giViewModelLaserBeam[i] = 0;
		}
		if (giViewModelLaserStart[i] > 0 && IsValidEntity(giViewModelLaserStart[i]))
		{
			AcceptEntityInput(giViewModelLaserStart[i], "kill");
			giViewModelLaserStart[i] = 0;
		}
		if (giViewModelLaserEnd[i] > 0 && IsValidEntity(giViewModelLaserEnd[i]))
		{
			AcceptEntityInput(giViewModelLaserEnd[i], "kill");
			giViewModelLaserEnd[i] = 0;
		}
		#endif
	}
}


public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; ++i){
		gbFreezeTime[i] = true;

		#if DEBUG
		if (!IsValidClient(i) || IsFakeClient(i))
			continue;
		SetEntProp(i, Prop_Data, "m_iFrags", 100);
		SetEntProp(i, Prop_Send, "m_iRank", 4);
		#endif
	}
	#if DEBUG
	PrintToChatAll("OnRoundStart()");
	#endif

	// CreateTimer(20.0, timer_FreezeTimeOff, -1, TIMER_FLAG_NO_MAPCHANGE);
}

#if DEBUG
public void OnPluginEnd(){
	for (int i = 1; i <= MaxClients; ++i){
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		if (giViewModelLaserStart[i] > 0)
		{
			AcceptEntityInput(giViewModelLaserStart[i], "kill");
		}
		if (giViewModelLaserEnd[i] > 0)
		{
			AcceptEntityInput(giViewModelLaserEnd[i], "kill");
		}
		if (giViewModelLaserBeam[i] > 0)
		{
			AcceptEntityInput(giViewModelLaserBeam[i], "kill");
		}
		int ViewModel = GetEntPropEnt(i, Prop_Send, "m_hViewModel");
		AcceptEntityInput(ViewModel, "Killhierarchy");

		SDKUnhook(giViewModel[i], SDKHook_SetTransmit, Hook_SetTransmitViewModel);
		SDKUnhook(giViewModelLaserBeam[i], SDKHook_SetTransmit, Hook_SetTransmitViewModel);
	}
}
#endif


public Action timer_FreezeTimeOff(Handle timer, int client)
{
	if (client > 0 && IsValidClient(client))
	{
		gbFreezeTime[client] = false;
		#if DEBUG
		PrintToServer("[lasersight] Freezetime turned off for %N", client);
		#endif

		// reset our active weapon in case it was overwritten during respawn
		UpdateActiveWeapon(client, GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"));

		if (gbActiveWeaponIsSRS[client] || gbActiveWeaponIsZRL[client])
			AcceptEntityInput(giViewModelLaserBeam[client], "TurnOn");

		return Plugin_Stop;
	}
	return Plugin_Stop;
}


// WARNING: this is called right after OnClientPutInServer for some reason!
// Perhaps a workaround would be to use player_spawn event if that would make a difference?
public void OnClientSpawned_Post(int client)
{
	#if DEBUG
	PrintToServer("[lasersight] OnClientSpawned_Post (%N)", client);
	#endif

	// avoid hooking first connection "spawn"
	if (GetClientTeam(client) < 2)
	{
		#if DEBUG
		PrintToServer("[lasersight] OnClientSpawned_Post (%N) team is %d. Ignoring.",
		client, GetClientTeam(client));
		#endif
		gbIsObserver[client] = true;
		gbVisionActive[client] = true;
		return;
	}

	// avoid hooking spectator spawns
	if (IsPlayerObserving(client))
	{
		#if DEBUG
		PrintToServer("[lasersight] OnClientSpawned ignored because %N (%d) is a spectator.",
		client, client);
		#endif
		gbIsObserver[client] = true;
		gbVisionActive[client] = true;
		return;
	}

	// stop checking for primary wpn after this delay
	CreateTimer(0.5, timer_FreezeTimeOff, client, TIMER_FLAG_NO_MAPCHANGE);

	int iClass = GetEntProp(client, Prop_Send, "m_iClassType");
	gbIsRecon[client] = iClass == 1 ? true : false;
	gbCanSprint[client] = iClass == 3 ? false : true;
	gbIsObserver[client] = false;
	gbVisionActive[client] = false;
	gbLaserEnabled[client] = true;
}


// REMOVE actually we probably don't need a timer here
public Action timer_CreateViewModelLaser(Handle timer, int client)
{
	if (!IsValidClient(client) || IsFakeClient(client))
		return Plugin_Stop;

	// CreateViewModelLaserBeam(client, giWpnType[wpnIndex]);
	return Plugin_Stop;
}


void CreateLaserEntities(int client, int weaponEnt, int wpnIndex)
{
	// int wpnIndex = GetTrackedWeaponIndex(GetPlayerWeaponSlot(client, SLOT_PRIMARY));

	if (wpnIndex < 0)
	{
		#if DEBUG
		PrintToServer("[lasersight] Creating only default viewmodel entities for %N", client);
		#endif
		// FIXME pass in the weaponEnt's WeaponType for proper attachment points
		CreateViewModelLaserBeam(client, WPN_NONE);
		return;
	}

	giAttachment[wpnIndex] = CreateInfoTargetProp(weaponEnt, client, "wmodel", true);

	if (giAttachment[wpnIndex])
	{
		#if DEBUG
		PrintToServer("[lasersight] we have attachment %d on weapon index %d. Updating position.\
Calling with type %d",
		giAttachment[wpnIndex], wpnIndex, giWpnType[wpnIndex]);
		#endif
		UpdateAttachementPosition(giWpnType[wpnIndex], giAttachment[wpnIndex], false, false);

		if (CreateLaserDot(wpnIndex, weaponEnt))
			CreateLaserBeam(wpnIndex, weaponEnt)
	}

	// REMOVE (no need for timer)
	// CreateTimer(0.1, timer_CreateViewModelLaser, client);

	CreateViewModelLaserBeam(client, giWpnType[wpnIndex]);
}

// // Redundant with SDKHook's OnClientSpawned_Post
// public Action OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
// {
// 	new client = GetClientOfUserId(GetEventInt(event, "userid"));

// 	#if DEBUG
// 	PrintToServer("[lasersight] OnPlayerSpawn (%N)", client);
// 	#endif

// 	if (!IsPlayerObserving(client)) // avoid potential spectator spawns
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
int LookForWeaponsToTrack(int client)
{
	if (!IsValidClient(client))
	{
		#if DEBUG
		PrintToServer("[lasersight] LookForWeaponsToTrack: client %d is invalid.", client);
		#endif
		return -1;
	}

	#if DEBUG
	PrintToServer("[lasersight] LookForWeaponsToTrack: %N", client);
	#endif

	int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);

	if (!IsValidEdict(weapon))
	{
		#if DEBUG
		PrintToServer("[lasersight] LookForWeaponsToTrack() !IsValidEdict: %i", weapon);
		#endif
		return -1;
	}

	decl String:classname[LONGEST_WEP_NAME + 1]; // Plus one for string terminator.

	if (!GetEdictClassname(weapon, classname, sizeof(classname)))
	{
		#if DEBUG
		PrintToServer("[lasersight] LookForWeaponsToTrack() !GetEdictClassname: %i", weapon);
		#endif
		return -1;
	}

	// only test the two last wpns if limited to sniper rifles
	int stop_at = (GetConVarBool(CVAR_AllWeapons) ? 0 : sizeof(g_sLaserWeaponNames) - 2)

	int index = -1;

	for (int i = sizeof(g_sLaserWeaponNames) - 1 ; i >= stop_at; --i)
	{
		if (StrEqual(classname, g_sLaserWeaponNames[i]))
		{
			#if DEBUG
			PrintToServer("[lasersight] Store OK: %s is %s. Hooking %s %d",
			classname, g_sLaserWeaponNames[i], classname, weapon);
			#endif

			index = StoreWeapon(weapon);
			giWpnType[index] = view_as<WeaponType>(i); // also store it as WeaponType
			break;
		}
		else
		{
			#if DEBUG > 2
			PrintToServer("[lasersight] Store fail: %s is not %s.",
			classname, g_sLaserWeaponNames[i]);
			#endif
		}
	}
	return index;
}


// Assumes valid input; make sure you're inputting a valid edict.
// this avoids having to compare classname strings in favour of ent ids
int StoreWeapon(int weapon)
{
	#if DEBUG
	if (iAffectedWeapons_Head >= sizeof(iAffectedWeapons))
	{
		ThrowError("[lasersight] iAffectedWeapons_Head %i >= sizeof(iAffectedWeapons) %i",
			iAffectedWeapons_Head, sizeof(iAffectedWeapons));
	}
	#endif

	int current_index = iAffectedWeapons_Head;
	iAffectedWeapons[iAffectedWeapons_Head] = weapon;


	#if DEBUG
	PrintToServer("[lasersight] Stored weapon %d at iAffectedWeapons[%d]",
	weapon, iAffectedWeapons_Head);
	#endif

	// Cycle around the array.
	iAffectedWeapons_Head++;
	iAffectedWeapons_Head %= sizeof(iAffectedWeapons);

	return current_index;
}


// Assumes valid input; make sure you're inputting a valid edict.
// Returns index from the tracked weapons array, -1 if not found
int GetTrackedWeaponIndex(int weapon)
{
	#if DEBUG
	if (weapon <= 0){
		// This may happen if primary weapon failed to be given to a player on spawn ?
		ThrowError("[lasersight] GetTrackedWeaponIndex weapon <= 0 !!!");
	}
	#endif

	static int WepsSize = sizeof(iAffectedWeapons);
	for (int i = 0; i < WepsSize; ++i)
	{
		if (weapon == iAffectedWeapons[i])
		{
			#if DEBUG
			PrintToServer("[lasersight] GetTrackedWeaponIndex %d found at iAffectedWeapons[%i]",
			weapon, i);
			#endif

			return i;
		}

		#if DEBUG > 2
		PrintToServer("[lasersight] %i not tracked. Compared to iAffectedWeapons[%i] %i",
		weapon, i, iAffectedWeapons[i]);
		#endif
	}

	#if DEBUG > 2
	PrintToServer("[lasersight] GetTrackedWeaponIndex(%i) returns -1.", weapon);
	#endif
	return -1;
}


// NOTE: this is called once before OnWeaponEquip first!
public void OnWeaponSwitch_Post(int client, int weapon)
{
	#if DEBUG
	if (!IsFakeClient(client)) {  // reduces log output
		PrintToServer("[lasersight] OnWeaponSwitch_Post %N (%d), weapon %d",
		client, client, weapon);
	}
	#endif

	if (gbFreezeTime[client])
	{
		#if DEBUG
		PrintToServer("[lasersight] OnWeaponSwitch_Post ignored because freezetime for %N (%d)",
		client, client);
		#endif
		return;
	}

	gbInZoomState[client] = false;

	if (gbShouldEmitLaser[client]) // was emitting, our next weapon will not emit then
	{
		gbShouldEmitLaser[client] = false;
		ToggleLaserOff(client, giActiveWeapon[client], 0); // our previous weapon
	}

	if (UpdateActiveWeapon(client, weapon)) // here we store our new weapon
	{
		if (gbActiveWeaponIsSRS[client] || gbActiveWeaponIsZRL[client])
		{
			ToggleViewModelLaserBeam(client, 1);
		}
		else
		{
			UpdatePositionOnViewModel(client, giWpnType[giActiveWeapon[client]]);
			ToggleViewModelLaserBeam(client, 0); // we know we have a tracked weapon
		}
	}
	else
	{
		// secondary weapon here, toggle off
		ToggleViewModelLaserBeam(client, 0);
	}
}


public void OnWeaponEquip(int client, int weapon)
{
	#if DEBUG
	// if (!IsFakeClient(client)) { // reduces log output
		PrintToServer("[lasersight] OnWeaponEquip %N (%d), weapon %d",
		client, client, weapon);
	// }
	#endif

	if (gbFreezeTime[client])
	{
		if (GetWeaponSlot(weapon) != SLOT_PRIMARY)
			return; // we only care about primary weapons

		#if DEBUG
		char classname[35];
		GetEntityClassname(weapon, classname, sizeof(classname));
		PrintToServer("[lasersight] Found primary weapon %s (%d) for client %N (%d)",
		classname, weapon, client, client);
		#endif

		int wpnindex = LookForWeaponsToTrack(client);
		CreateLaserEntities(client, weapon, wpnindex);
		gbFreezeTime[client] = false;
		return;
	}

	gbShouldEmitLaser[client] = false;
}



// if anyone has a weapon which has a laser, ask for OnGameFrame() coordinates updates
bool NeedUpdateLoop()
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (gbShouldEmitLaser[i])
		{
			#if DEBUG > 2
			PrintToServer("[lasersight] gbShouldEmitLaser[%N] is true, NeedUpdateLoop()", i);
			#endif
			return true;
		}
	}
	return false;
}


void MakeParent(int entity, int parent)
{
	char buffer[64];
	Format(buffer, sizeof(buffer), "weapon%d", parent);
	DispatchKeyValue(parent, "targetname", buffer);

	SetVariantString("!activator"); // FIXME is this useless?
	AcceptEntityInput(entity, "SetParent", parent, parent, 0);
}


// index of affected weapon in array
bool CreateLaserDot(int weaponIndex, int weaponEnt)
{
	if (giLaserDot[weaponIndex] <= 0) // we have not created a laser dot yet
	{
		giLaserDot[weaponIndex] = CreateLaserDotEnt(weaponEnt);
		giLaserTarget[weaponIndex] = CreateTargetProp(weaponEnt, "dot_");

		SetVariantString("!activator"); // useless?
		AcceptEntityInput(giLaserDot[weaponIndex], "SetParent", giLaserTarget[weaponIndex], giLaserTarget[weaponIndex], 0);
		return true;
	}

	#if DEBUG
	PrintToServer("[lasersight] Error creating laser DOT for weapon index %d! (%d)",
	weaponIndex, weaponEnt);
	#endif
	return false;
}


// for player disconnect? // FIXME
void DestroyLaserDot(int client)
{
	if (giLaserDot[giActiveWeapon[client]] > 0 && IsValidEntity(giLaserDot[giActiveWeapon[client]]))
	{
		SDKUnhook(giLaserDot[giActiveWeapon[client]], SDKHook_SetTransmit, Hook_SetTransmitLaserDot);
		SDKUnhook(giLaserTarget[giActiveWeapon[client]], SDKHook_SetTransmit, Hook_SetTransmitLaserDotTarget);
		AcceptEntityInput(giLaserDot[giActiveWeapon[client]], "kill");
		giLaserDot[giActiveWeapon[client]] = -1;
	}
}


void ToggleLaserDot(int client, int weapon_index, bool activate)
{
	// if (giLaserDot[giActiveWeapon[client]] < 0 || !IsValidEntity(giLaserDot[giActiveWeapon[client]]))
	// 	return;
	if (giLaserDot[weapon_index] < 0 || !IsValidEntity(giLaserDot[weapon_index]))
		return;
	if (giLaserTarget[weapon_index] < 0 || !IsValidEntity(giLaserTarget[weapon_index]))
		return;

	#if DEBUG
	PrintToServer("[lasersight] %s laser dot (dot %d target %d) for %N.",
	activate ? "Showing" : "Hiding", giLaserDot[weapon_index], giLaserTarget[weapon_index], client);
	#endif

	if (activate)
	{
		AcceptEntityInput(giLaserDot[weapon_index], "ShowSprite");
		SDKHook(giLaserDot[weapon_index], SDKHook_SetTransmit, Hook_SetTransmitLaserDot);
		SDKHook(giLaserTarget[weapon_index], SDKHook_SetTransmit, Hook_SetTransmitLaserDotTarget);
	}
	else
	{
		AcceptEntityInput(giLaserDot[weapon_index], "HideSprite");
		SDKUnhook(giLaserDot[weapon_index], SDKHook_SetTransmit, Hook_SetTransmitLaserDot);
		SDKUnhook(giLaserTarget[weapon_index], SDKHook_SetTransmit, Hook_SetTransmitLaserDotTarget);
	}
}



int CreateTargetProp(int weapon, char[] sTag)
{
	// sems to work (in this case) with EF_PARENT_ANIMATES https://developer.valvesoftware.com/wiki/Effect_flags
	int iEnt = CreateEntityByName("info_target");
	// int iEnt = CreateEntityByName("prop_dynamic_override");
	// DispatchKeyValue(iEnt, "model", "models/nt/props_debris/can01.mdl");

	// these hacks were used with prop_dynamic_override and to optimize a bit
	DispatchKeyValue(iEnt,"renderfx","256"); // EF_PARENT_ANIMATES (instead of 0)
	DispatchKeyValue(iEnt,"damagetoenablemotion","0");
	DispatchKeyValue(iEnt,"forcetoenablemotion","0");
	DispatchKeyValue(iEnt,"Damagetype","0");
	DispatchKeyValue(iEnt,"disablereceiveshadows","1");
	DispatchKeyValue(iEnt,"massScale","0");
	DispatchKeyValue(iEnt,"nodamageforces","0");
	DispatchKeyValue(iEnt,"shadowcastdist","0");
	DispatchKeyValue(iEnt,"disableshadows","1");
	DispatchKeyValue(iEnt,"spawnflags","1670");
	DispatchKeyValue(iEnt,"PerformanceMode","1");
	DispatchKeyValue(iEnt,"rendermode","10");
	DispatchKeyValue(iEnt,"physdamagescale","0");
	DispatchKeyValue(iEnt,"physicsmode","2");

	char ent_name[20];
	Format(ent_name, sizeof(ent_name), "%s%d", sTag, weapon); // in case we need for env_beam end ent
	DispatchKeyValue(iEnt, "targetname", ent_name);

	#if DEBUG
	PrintToServer("[lasersight] Created target (%d) on weapon %d :%s",
	iEnt, weapon, ent_name);
	#endif

	DispatchSpawn(iEnt);

	TeleportEntity(iEnt, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	return iEnt;
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
	PrintToServer("[lasersight] Created laser dot \"%s\" for weapon %d.", dot_name, weapon );
	#endif

	// DispatchKeyValue(ent, "model", "materials/sprites/laserdot.vmt");
	DispatchKeyValue(ent, "model", "materials/sprites/redglow1.vmt");
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
bool CreateLaserBeam(int weaponIndex, int weaponEnt)
{
	if (weaponIndex < 0)
		ThrowError("[lasersight] Weapon -1 in CreateLaserBeam!");

	if (giLaserBeam[weaponIndex] > 0){
		#if DEBUG
		ThrowError("[lasersight] Laser beam already existed for weapon %d!",
		iAffectedWeapons[weaponIndex]);
		#endif
		return false; }

	giLaserBeam[weaponIndex] = CreateLaserBeamEnt(weaponEnt);
	return true;
}


void CreateViewModelLaserBeam(int client, WeaponType weapontype)
{
	if (client <= 0)
		ThrowError("[lasersight] Client -1 in CreateViewModelLaserBeam!");

	if (giViewModelLaserBeam[client] > 0)
	{
		#if DEBUG
		ThrowError("[lasersight] View model Laser beam already existed(?) for client %N.",
		client);
		#endif
		return;
	}

	giViewModel[client] = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	#if DEBUG
	PrintToServer("[lasersight] viewmodel index: %d", giViewModel[client]);
	#endif

	giViewModelLaserStart[client] = CreateInfoTargetProp(giViewModel[client], client, "startbeam");
	giViewModelLaserEnd[client] = CreateInfoTargetProp(giViewModel[client], client, "endbeam");
	giViewModelLaserBeam[client] = CreateViewModelLaserBeamEnt(giViewModel[client], client);

	UpdateAttachementPosition(weapontype, giViewModelLaserStart[client], true, true);
	UpdateAttachementPosition(weapontype, giViewModelLaserEnd[client], true, false);

	#if !DEBUG
	SDKHook(giViewModel[client], SDKHook_SetTransmit, Hook_SetTransmitViewModel);
	SDKHook(giViewModelLaserBeam[client], SDKHook_SetTransmit, Hook_SetTransmitViewModel);
	#endif
}


int CreateInfoTargetProp(int parent, int client, char[] tag, bool worldmodel=false)
{
	int iEnt = CreateEntityByName("info_target");
	// int iEnt = CreateEntityByName("prop_physics");
	// DispatchKeyValue(iEnt, "model", "models/nt/a_lil_tiger.mdl");

	char ent_name[20];
	if (worldmodel) // we attach this ent to the world model
	{
		Format(ent_name, sizeof(ent_name), "%s%d", tag, parent); // parent is the weapon ent
		DispatchKeyValue(iEnt, "targetname", ent_name);
	}
	else // these are for the viewmodel
	{
		Format(ent_name, sizeof(ent_name), "%s%d", tag, GetClientUserId(client)); // parents are the viewmodel
		DispatchKeyValue(iEnt, "targetname", ent_name);
	}

	#if DEBUG
	PrintToServer("[lasersight] Created %s info_target (%d \"%s\") on parent (%d)",
	worldmodel ? "worldmodel" : "viewmodel", iEnt, ent_name, parent);
	#endif

	DispatchSpawn(iEnt);

	MakeParent(iEnt, parent);

	TeleportEntity(iEnt, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	return iEnt;
}


void UpdatePositionOnViewModel(int client, WeaponType weapontype)
{
	UpdateAttachementPosition(weapontype, giViewModelLaserStart[client], true, true);
	UpdateAttachementPosition(weapontype, giViewModelLaserEnd[client], true, false);
}


void UpdateAttachementPosition(WeaponType weapontype, int target_ent, bool viewmodel, bool bStartPoint=true)
{
	DataPack dp = CreateDataPack();
	WritePackCell(dp, target_ent);

	switch (weapontype)
	{
		case WPN_jittescoped:
		{
			WritePackString(dp, "eject") // jitte_s model doesn't have muzzle attachment point
			if (viewmodel){
				if (bStartPoint)
				{
					WritePackFloat(dp, 2.0);
					WritePackFloat(dp, 6.0);
					WritePackFloat(dp, 8.0);
				}
				else
				{
					WritePackFloat(dp, 90.0);
					WritePackFloat(dp, 0.0);
					WritePackFloat(dp, -5.0);
				}
			}
			else // world model
			{
				WritePackFloat(dp, -1.0);
				WritePackFloat(dp, 0.9);
				WritePackFloat(dp, 0.0);
			}

			CreateTimer(0.1, timer_SetAttachmentPosition, dp, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
		}

		case WPN_mpn:
		{
			WritePackString(dp, "muzzle")
			if (viewmodel){
				if (bStartPoint)
				{
					WritePackFloat(dp, -1.0);
					WritePackFloat(dp, -6.0);
					WritePackFloat(dp, -1.4);
				}
				else
				{
					WritePackFloat(dp, 80.0);
					WritePackFloat(dp, -3.7);
					WritePackFloat(dp, -2.0);
				}
			}
			else // world model
			{
				WritePackFloat(dp, -1.0);
				WritePackFloat(dp, 0.9);
				WritePackFloat(dp, -5.0);
			}

			CreateTimer(0.1, timer_SetAttachmentPosition, dp, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
		}

		case WPN_m41s:
		{
			WritePackString(dp, "muzzle")
			if (viewmodel){
				if (bStartPoint)
				{
					WritePackFloat(dp, -5.0);
					WritePackFloat(dp, -4.0);
					WritePackFloat(dp, -1.4);
				}
				else
				{
					WritePackFloat(dp, 80.0);
					WritePackFloat(dp, -4.7);
					WritePackFloat(dp, -2.5);
				}
			}
			else // world model
			{
				WritePackFloat(dp, -1.0);
				WritePackFloat(dp, 0.9);
				WritePackFloat(dp, 0.0);
			}

			CreateTimer(0.1, timer_SetAttachmentPosition, dp, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
		}

		case WPN_mx_silenced:
		{
			if (viewmodel)
			{
				WritePackString(dp, "eject") // "muzzle" works for when attaching to most weapon
				if (bStartPoint)
				{
					WritePackFloat(dp, -6.5); // horizontal - left
					WritePackFloat(dp, 40.0); // + backwards
					WritePackFloat(dp, 5.0); // +up -down pitch
				}
				else
				{
					WritePackFloat(dp, -6.5);
					WritePackFloat(dp, 100.5);
					WritePackFloat(dp, 15.0);
				}
			}
			else // world model
			{
				WritePackString(dp, "muzzle") // "muzzle" works for when attaching to most weapon
				WritePackFloat(dp, -1.0);
				WritePackFloat(dp, 0.9);
				WritePackFloat(dp, 0.0);
			}

			CreateTimer(0.1, timer_SetAttachmentPosition, dp, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
		}

		default:
		{
			WritePackString(dp, "muzzle") // "muzzle" works for when attaching to most weapon
			if (viewmodel)
			{
				if (bStartPoint)
				{
					WritePackFloat(dp, -1.0); // forward axis
					WritePackFloat(dp, -4.9); // up/down axis pitch
					WritePackFloat(dp, 1.5); // horizontal yaw
				}
				else
				{
					WritePackFloat(dp, 80.0); // forward axis
					WritePackFloat(dp, -0.5); // up down axis (pitch, + = up)
					WritePackFloat(dp, -1.0); // horizontal (- = left / + = right)
				}
			}
			else // world model
			{
				WritePackFloat(dp, -1.0);
				WritePackFloat(dp, 0.9);
				WritePackFloat(dp, 0.0);
			}

			CreateTimer(0.1, timer_SetAttachmentPosition, dp, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
		}
	}
}


public Action timer_SetAttachmentPosition(Handle timer, DataPack dp)
{
	ResetPack(dp);
	int entId = ReadPackCell(dp);
	char attachpoint[10];
	ReadPackString(dp, attachpoint, sizeof(attachpoint));
	float vecOrigin[3];
	vecOrigin[0] = ReadPackFloat(dp);
	vecOrigin[1] = ReadPackFloat(dp);
	vecOrigin[2] = ReadPackFloat(dp);
	// float vecAngle[3];
	// if (IsPackReadable(dp, 3 * 4)){
	// 	vecAngle[0] = ReadPackFloat(dp);
	// 	vecAngle[1] = ReadPackFloat(dp);
	// 	vecAngle[2] = ReadPackFloat(dp);
	// }
	// PrintToServer("vecAngle {%f %f %f}", vecAngle[0], vecAngle[1], vecAngle[2]);

	SetVariantString(attachpoint);
	AcceptEntityInput(entId, "SetParentAttachment");

	DispatchSpawn(entId);

	SetEntPropVector(entId, Prop_Send, "m_vecOrigin", vecOrigin);

	// if (vecOrigin[0] != 0.0)
	// 	SetEntPropVector(entId, Prop_Data, "m_angAbsRotation", vecAngle);

	#if DEBUG
	PrintToServer("[lasersight] Position of attachment entity %d %.2f %.2f %.2f on %s",
	entId, vecOrigin[0], vecOrigin[1], vecOrigin[2], attachpoint);
	#endif

	return Plugin_Handled;
}



int CreateViewModelLaserBeamEnt(int ViewModel, int client)
{
	int laser_entity = CreateEntityByName("env_beam");

	#if DEBUG
	PrintToServer("[lasersight] Created laser BEAM for VM %d.", ViewModel);
	#endif

	char ent_name[20];
	IntToString(ViewModel, ent_name, sizeof(ent_name));
	DispatchKeyValue(laser_entity, "targetname", ent_name);

	ent_name[0] = '\0';
	Format(ent_name, sizeof(ent_name), "startbeam%d", GetClientUserId(client));
	DispatchKeyValue(laser_entity, "LightningStart", ent_name);

	// Note: there is no "targetpoint" key value like mentioned on the wiki in NT!
	ent_name[0] = '\0';
	Format(ent_name, sizeof(ent_name), "endbeam%d", GetClientUserId(client));
	DispatchKeyValue(laser_entity, "LightningEnd", ent_name);

	// Positioning
	// DispatchKeyValueVector(laser_entity, "origin", mine_pos);
	TeleportEntity(laser_entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	// SetEntPropVector(laser_entity, Prop_Data, "m_vecEndPos", beam_end_pos);

	// Setting Appearance
	DispatchKeyValue(laser_entity, "texture", "materials/sprites/laser.vmt");
	// DispatchKeyValue(laser_entity, "model", "materials/sprites/laser.vmt"); // seems unnecessary
	// SetEntityModel(laser_entity,  "materials/sprites/laser.vmt"); // seems unnecessary
	// DispatchKeyValue(laser_entity, "decalname", "redglowalpha");

	DispatchKeyValue(laser_entity, "renderamt", "255");
	DispatchKeyValue(laser_entity, "renderfx", "14"); // 15 distort, 14 constant glow, 0 normal
	DispatchKeyValue(laser_entity, "rendercolor", "200 25 25");
	// DispatchKeyValue(laser_entity, "rendermode", "1");
	SetVariantInt(190); AcceptEntityInput(laser_entity, "alpha"); // this works! (needs proper renderfx)
	DispatchKeyValue(laser_entity, "BoltWidth", "1.5");
	DispatchKeyValue(laser_entity, "spawnflags", "256"); // fade towards ending entity
	DispatchKeyValue(laser_entity, "life", "0.0");
	DispatchKeyValue(laser_entity, "StrikeTime", "0");
	DispatchKeyValue(laser_entity, "TextureScroll", "35");
	// DispatchKeyValue(laser_entity, "TouchType", "3");

	DispatchSpawn(laser_entity);

	ActivateEntity(laser_entity); // not sure what that is (for texture animation?)

	// Link between weapon and laser indirectly. NEEDS TESTING
	// SetEntPropEnt(client, Prop_Send, "m_hEffectEntity", laser_entity);
	// SetEntPropEnt(laser_entity, Prop_Data, "m_hMovePeer", client); // should it be the attachment prop or weapon even?

	return laser_entity;
}

void ToggleViewModelLaserBeam(int client, int activate=0)
{
	if (giViewModelLaserBeam[client] <= 0){
		#if DEBUG
		PrintToServer("[lasersight] ToggleViewModelLaserBeam() laser beam for %N is invalid!", client);
		#endif
		return; }

	if (activate)
	{
		AcceptEntityInput(giViewModelLaserBeam[client], "TurnOn");
	}
	else if (activate == -1)
	{
		AcceptEntityInput(giViewModelLaserBeam[client], "Toggle");
	}
	else // 0
	{
		AcceptEntityInput(giViewModelLaserBeam[client], "TurnOff");
	}
	#if DEBUG
	PrintToServer("[lasersight] VM laser beam %d for %N: m_active = %d.",
	giViewModelLaserBeam[client], client,
	GetEntProp(giViewModelLaserBeam[client], Prop_Data, "m_active"));
	#endif
}


void ToggleLaserBeam(int client, int weapon, bool activate)
{
	if (activate)
	{
		AcceptEntityInput(giLaserBeam[weapon], "TurnOn");
		SDKHook(giLaserBeam[weapon], SDKHook_SetTransmit, Hook_SetTransmitLaserBeam);
	}
	else
	{
		AcceptEntityInput(giLaserBeam[weapon], "TurnOff");
		SDKUnhook(giLaserBeam[weapon], SDKHook_SetTransmit, Hook_SetTransmitLaserBeam);
	}

	#if DEBUG
	PrintToServer("[lasersight] laser beam %d for %N should be %s.",
	giLaserBeam[weapon], client, 	// giLaserBeam[giActiveWeapon[client]]
	gbShouldEmitLaser[client] ? "Turned On" : "Turned Off");
	#endif
}


// maybe needed on player disconnect?
void DestroyLaserBeam(int weapon)
{
	if (!IsValidEntity(giLaserBeam[weapon]))
	{
		#if DEBUG
		PrintToServer("[lasersight] DestroyLaserBeam() laser beam was invalid entity.")
		#endif
		giLaserBeam[weapon] = -1;
		return;
	}
	SDKUnhook(giLaserBeam[weapon], SDKHook_SetTransmit, Hook_SetTransmitLaserBeam);
	AcceptEntityInput(giLaserBeam[weapon], "kill");
	giLaserBeam[weapon] = -1;
}


int CreateLaserBeamEnt(int weaponEnt)
{
	int laser_entity = CreateEntityByName("env_beam");

	#if DEBUG
	PrintToServer("[lasersight] Created laser BEAM for weapon %d.", weaponEnt);
	#endif

	char ent_name[20];
	IntToString(weaponEnt, ent_name, sizeof(ent_name));
	DispatchKeyValue(laser_entity, "targetname", ent_name);

	ent_name[0] = '\0';
	Format(ent_name, sizeof(ent_name), "wmodel%d", weaponEnt);
	DispatchKeyValue(laser_entity, "LightningStart", ent_name);

	// Note: there is no "targetpoint" key value like mentioned on the wiki in NT!
	ent_name[0] = '\0';
	Format(ent_name, sizeof(ent_name), "dot%d", weaponEnt);
	DispatchKeyValue(laser_entity, "LightningEnd", ent_name);

	// Positioning
	// DispatchKeyValueVector(laser_entity, "origin", mine_pos);
	// TeleportEntity(laser_entity, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	// SetEntPropVector(laser_entity, Prop_Data, "m_vecEndPos", beam_end_pos);

	// Setting Appearance
	DispatchKeyValue(laser_entity, "texture", "materials/sprites/laser.vmt");
	// DispatchKeyValue(laser_entity, "model", "materials/sprites/laser.vmt"); // ?
	DispatchKeyValue(laser_entity, "decalname", "redglowalpha");

	DispatchKeyValue(laser_entity, "renderamt", "100"); // TODO(?): low renderamt, increase when activate
	DispatchKeyValue(laser_entity, "renderfx", "15");
	DispatchKeyValue(laser_entity, "rendercolor", "200 25 25");
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
	if(!IsValidEdict(weapon))
		return;

	if (giActiveWeapon[client] > -1)
	{
		gbShouldEmitLaser[client] = false;
		gbInZoomState[client] = false;
		ToggleLaserOff(client, giActiveWeapon[client], 0)
	}

	g_bNeedUpdateLoop = NeedUpdateLoop(); // FIXME is this needed still?
}


// Tracks and caches active weapon, returns true if tracked weapon is active weapon
bool UpdateActiveWeapon(int client, int weapon)
{
	// if(!IsValidEdict(weapon) || !IsValidClient(client))
	// 	return;

	giActiveWeapon[client] = GetTrackedWeaponIndex(weapon);

	if (giActiveWeapon[client] > -1)
	{
		// hide the beam that is tied to the active weapon
		giOwnBeam[client] = giLaserBeam[giActiveWeapon[client]];
		// cache weapon classname as an integer for optimization
		giActiveWeaponType[client] = giWpnType[giActiveWeapon[client]]
	}
	else
	{
		giOwnBeam[client] = -1;
		giActiveWeaponType[client] = WPN_NONE;
	}

	if (IsActiveWeaponSRS(weapon)) //FIXME cache this?
	{
		#if DEBUG
		PrintToServer("[lasersight] weapon_srs detected for client %N.", client);
		#endif

		gbActiveWeaponIsSRS[client] = true;
		return true;
	}
	else
	{
		gbActiveWeaponIsSRS[client] = false;
	}

	if (IsActiveWeaponZRL(weapon)) //FIXME cache this too?
	{
		gbActiveWeaponIsZRL[client] = true;
		return true;
	}
	else
	{
		gbActiveWeaponIsZRL[client] = false;
	}

	return giActiveWeapon[client] > -1 ? true : false;
}


public void OnGameFrame()
{
	if(g_bNeedUpdateLoop)
	{
		for (int client = MaxClients; client; --client)
		{
			if(!IsClientInGame(client) || !gbShouldEmitLaser[client] || giActiveWeapon[client] < 0)
				continue;

			float vecEnd[3];
			GetEndPositionFromClient(client, vecEnd);

			// Update Laser dot sprite position here
			if (IsValidEntity(giLaserDot[giActiveWeapon[client]])){

				// attempts to smooth out position updates by adding velocity?
				float vecDir[3], vecVel[3];

				// get previous position and apply velocity from new position difference
				GetEntPropVector(giLaserTarget[giActiveWeapon[client]],
				Prop_Data, "m_vecAbsOrigin", vecDir); //vecAbsOrigin or vecOrigin?

				// not sure if this actually works
				SubtractVectors(vecEnd, vecDir, vecVel);
				ScaleVector(vecVel, 1000.0);

				#if DEBUG > 2
				PrintToChatAll("[lasersight] Dot m_vecAbsOrigin: %.3f %.3f %.3f, \
velocity %.3f %.3f %.3f",
				vecDir[0], vecDir[1], vecDir[2], vecVel[0], vecVel[1], vecVel[2]);
				#endif

				TeleportEntity(giLaserTarget[giActiveWeapon[client]], vecEnd, NULL_VECTOR, vecVel);
			}


			#if METHOD TEMP_ENT // not used anymore
			if (IsValidEntity(giAttachment[giActiveWeapon[client]]))
				startEnt = giAttachment[giActiveWeapon[client]];
			if (IsValidEntity(giLaserDot[giActiveWeapon[client]]))
				endEnt = giLaserTarget[giActiveWeapon[client]];

			Create_TE_Beam(client, startEnt, endEnt);
			#endif // METHOD TEMP_ENT
		}
	}
}


stock void Create_TE_Beam(int client, int iStartEnt, int iEndEnt)
{
	// TE_Start("BeamPoints");
	TE_Start("BeamEntPoint");
	// TE_WriteVector("m_vecStartPoint", vecStart);
	// TE_WriteVector("m_vecEndPoint", vecEnd);
	TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);

	// specific to BeamEntPoint TE
	TE_WriteNum("m_nStartEntity", iStartEnt);
	TE_WriteNum("m_nEndEntity", iEndEnt);

	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo); 	// NOTE: Halo can be set to "0"!
	TE_WriteNum("m_nStartFrame", 0);
	TE_WriteNum("m_nFrameRate", 1);
	TE_WriteFloat("m_fLife", 0.0);
	TE_WriteFloat("m_fWidth", 1.9);
	TE_WriteFloat("m_fEndWidth", 1.1);
	TE_WriteFloat("m_fAmplitude", 1.1);
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
		if(IsValidClient(j) /*&& (client != j)*/){ // only draw for others
			// if (!gbVisionActive(j))   // TODO (only if using TE)
			//		continue;
			iBeamClients[nBeamClients++] = j;
		}
	}
	TE_Send(iBeamClients, nBeamClients);
}


// trace from client, return true on hit
stock bool GetEndPositionFromClient(int client, float[3] end)
{
	decl Float:start[3], Float:angle[3];
	GetClientEyePosition(client, start);
	GetClientEyeAngles(client, angle);
	TR_TraceRayFilter(start, angle,
	CONTENTS_SOLID|CONTENTS_MOVEABLE|CONTENTS_MONSTER|CONTENTS_DEBRIS|CONTENTS_HITBOX,
	RayType_Infinite, TraceEntityFilterPlayer, client);

	if (TR_DidHit(INVALID_HANDLE))
	{
		TR_GetEndPosition(end, INVALID_HANDLE);
		return true;
	}
	return false;
}


public bool:TraceEntityFilterPlayer(entity, contentsMask, any:data)
{
	// return entity > MaxClients;
	return entity != data; // only avoid collision with ourself (or data)
}


// Hide dot from self
public Action Hook_SetTransmitLaserDot(int entity, int client)
{
	#if DEBUG > 2
	PrintToServer("Hook_SetTransmitLaserDot dot sprite %d for %N", entity, client);
	#endif

	if (giActiveWeapon[client] == -1)
		return Plugin_Continue;

	if (entity == giLaserDot[giActiveWeapon[client]])
	{
		#if DEBUG
		//PrintToServer("Blocking dot sprite %d for %N", entity, client);
		return Plugin_Continue;
		#endif
		return Plugin_Handled; // hide player's own laser dot from himself
	}
	return Plugin_Continue;
}

// Hide target/dot from self
public Action Hook_SetTransmitLaserDotTarget(int entity, int client)
{
	#if DEBUG > 2
	PrintToServer("Hook_SetTransmitLaserDotTarget dot target %d for %N", entity, client);
	#endif
	if (giActiveWeapon[client] == -1)
		return Plugin_Continue;

	if (entity == giLaserTarget[giActiveWeapon[client]])
	{
		#if DEBUG
		//PrintToServer("Blocking dot target %d for %N", entity, client);
		return Plugin_Continue;
		#endif
		return Plugin_Handled; // hide player's own laser dot from himself
	}
	return Plugin_Continue;
}


// entity emits to client or not
public Action Hook_SetTransmitLaserBeam(int entity, int client)
{
	// hide if not using night vision, or beam comes from our active weapon
	// note: no need to test for observer state since VisionActive is true in that case
	if (!gbVisionActive[client] || entity == giOwnBeam[client])
	{
		#if DEBUG
		//PrintToServer("Blocking beam entity %d for %N", entity, client);
		return Plugin_Continue;
		#endif
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// workaround for viewmodel appearing at {0, 0, 0} when attaching laser to its hierarchy
public Action Hook_SetTransmitViewModel(int entity, int client)
{
	if (entity == giViewModel[client] || entity == giViewModelLaserBeam[client])
	{
		return Plugin_Continue;
	}

	#if DEBUG
	return Plugin_Continue;
	#else
	return Plugin_Handled;
	#endif
}


bool IsActiveWeaponSRS(int weapon)
{
	decl String:weaponName[20];
	GetEntityClassname(weapon, weaponName, sizeof(weaponName));
	if (StrEqual(weaponName, "weapon_srs"))
		return true;
	return false;
}


bool IsActiveWeaponZRL(int weapon)
{
	decl String:weaponName[20];
	GetEntityClassname(weapon, weaponName, sizeof(weaponName));
	if (StrEqual(weaponName, "weapon_zr68l"))
		return true;
	return false;
}


public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (client == 0 || gbIsObserver[client] || IsFakeClient(client))
		return Plugin_Continue;

	if (buttons & IN_RELOAD)
	{
		if (gbHeldKeys[client][KEY_RELOAD])
		{
			buttons &= ~IN_RELOAD;
		}
		else
		{
			gbHeldKeys[client][KEY_RELOAD] = true;

			#if DEBUG > 1
			char classname[30];
			if (giActiveWeapon[client] > -1){
				GetEntityClassname(iAffectedWeapons[giActiveWeapon[client]],
				classname, sizeof(classname));
				PrintToChatAll("Active weapon for %d: %d %s", client,
				iAffectedWeapons[giActiveWeapon[client]], classname);
			}
			else{
				int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
				if (weapon > 0)
					GetEntityClassname(weapon, classname, sizeof(classname));
				PrintToChatAll("Active weapon for %d: %d %s", client, weapon, classname);
			}
			#endif // DEBUG

			if (giActiveWeapon[client] > -1)
				OnReloadKeyPressed(client);
		}
	}
	else
	{
		gbHeldKeys[client][KEY_RELOAD] = false;
	}



	if (buttons & IN_ATTACK)
	{
		gbHeldKeys[client][KEY_ATTACK] = true;

		#if DEBUG > 2
		PrintToServer("[lasersight] Key IN_ATTACK pressed.");
		#endif

		if (giActiveWeapon[client] > -1)
		{
			if (!gbActiveWeaponIsSRS[client])
			{
				if (ghTimerCheckSequence[client] == INVALID_HANDLE && gbInZoomState[client])
				{
					// check if we're automatically reloading due to empty clip
					DataPack dp = CreateDataPack();
					ghTimerCheckSequence[client] = CreateTimer(2.5,
					timer_CheckSequence, dp, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
					WritePackCell(dp, GetClientUserId(client));
					WritePackCell(dp, EntIndexToEntRef(iAffectedWeapons[giActiveWeapon[client]]));
					WritePackCell(dp, GetIgnoredSequencesForWeapon(giActiveWeaponType[client]));
				}
			}
		}
	}
	else
	{
		if (gbActiveWeaponIsSRS[client] && gbHeldKeys[client][KEY_ATTACK])
		{
			gbInZoomState[client] = false;
			ToggleLaserOff(client, giActiveWeapon[client], 1);
		}
		gbHeldKeys[client][KEY_ATTACK] = false;
	}


	if (buttons & IN_ATTACK2) // Alt Fire mode key (ie. tachi)
	{
		if (gbHeldKeys[client][KEY_ALTFIRE])
		{
			buttons &= ~IN_ATTACK2; // FIXME: bad idea, probably not even needed
		}
		else
		{
			#if DEBUG > 1
			PrintToServer("[lasersight] Key IN_ATTACK2 pressed (alt fire).");
			#endif
			gbHeldKeys[client][KEY_ALTFIRE] = true;

			if (giActiveWeapon[client] > -1 &&
			!gbActiveWeaponIsSRS[client] &&
			!gbActiveWeaponIsZRL[client]){
				// toggle laser beam here for other than SRS
				ToggleLaserActivity(client, giActiveWeapon[client]);
			}
		}
	}
	else
	{
		gbHeldKeys[client][KEY_ALTFIRE] = false;
	}


	if ((buttons & IN_VISION) && gbIsRecon[client])
	{
		if(gbHeldKeys[client][KEY_VISION])
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
			gbHeldKeys[client][KEY_VISION] = true;
		}
	}
	else if (gbIsRecon[client])
	{
		gbHeldKeys[client][KEY_VISION] = false;
	}
	#if DEBUG > 2
	PrintToChatAll("Vision %s (%d), (recon: %d)", gbVisionActive[client] ? "ACTIVE" : "inactive",
	GetEntProp(client, Prop_Send, "m_iVision"), gbIsRecon[client]);
	#endif


	if (buttons & IN_SPRINT)
	{
		if (gbCanSprint[client])
		{
			if (!gbHeldKeys[client][KEY_SPRINT])
			{
				if(OnSprintKeyPressed(buttons, client))
				{
					gbHeldKeys[client][KEY_SPRINT] = true; // avoid flooding
					return Plugin_Continue; // block following zoom key commands
				}
				gbHeldKeys[client][KEY_SPRINT] = true; // avoid flooding
			}
		}
	}
	else if (gbCanSprint[client])
	{
		gbHeldKeys[client][KEY_SPRINT] = false;
	}


	if (buttons & IN_GRENADE1) // ZOOM key
	{
		// nt_inputtweaks should already remove extra key presses for us
		// NOTE: the key is already released as soon as this is called!
		OnZoomKeyPressed(client);
	}


	return Plugin_Continue;
}


bool OnSprintKeyPressed(int buttons, int client)
{
	// sprint key only causes zoom out if we move
	if (buttons & IN_FORWARD
	|| buttons & IN_BACK
	|| buttons & IN_MOVELEFT
	|| buttons & IN_MOVERIGHT)
	{
		gbInZoomState[client] = false;
		if (giActiveWeapon[client] > -1)
		{
			if (gbActiveWeaponIsSRS[client] || gbActiveWeaponIsZRL[client])
				ToggleLaserOff(client, giActiveWeapon[client], 1);
			else
				ToggleLaserOff(client, giActiveWeapon[client], 0);
		}
		return true; // block keys normally handled after it
	}
	return false;
}


void OnZoomKeyPressed(int client)
{
	#if DEBUG
	int ViewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
	PrintCenterTextAll("[lasersight] viewmodel index: %d", ViewModel);
	#endif

	if (giActiveWeapon[client] < 0){
		#if DEBUG
		PrintToServer("[lasersight] OnZoom, giActiveWeapon < 0.")
		#endif
		return; }

	#if DEBUG
	new bAimed = GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Send, "bAimed");
	PrintToServer("[lasersight] bAimed: %d", bAimed);
	#endif

	if (gbInZoomState[client]) // we are already zoomed in
	{
		if (gbShouldEmitLaser[client])
			gbShouldEmitLaser[client] = false;
		gbInZoomState[client] = false;
	}
	else
	{
		if (gbLaserEnabled[client]) // explicitly disabled by player
			gbShouldEmitLaser[client] = true;

		#if DEBUG
		PrintToServer("[lasersight] weapon %d is %s!", iAffectedWeapons[giActiveWeapon[client]],
		IsWeaponReloading(iAffectedWeapons[giActiveWeapon[client]]) ? "reloading" : "not reloading");
		#endif

		gbInZoomState[client] = !IsWeaponReloading(iAffectedWeapons[giActiveWeapon[client]]);
	}


	if (gbActiveWeaponIsSRS[client])
	{
		HandleSRSQuirks(client);
	}

	#if DEBUG
	PrintToServer("[lasersight] gbInZoomState for %N is %s -> toggling laser %s.",
	client, gbInZoomState[client] ? "true" : "false", gbInZoomState[client] ? "on" : "off");
	#endif

	if (gbShouldEmitLaser[client])
	{
		if (gbInZoomState[client])
		{
			if (gbActiveWeaponIsSRS[client] || gbActiveWeaponIsZRL[client])
				ToggleLaserOn(client, giActiveWeapon[client], 0);
			else
				ToggleLaserOn(client, giActiveWeapon[client], 1);
		}
		else
		{
			if (gbActiveWeaponIsSRS[client] || gbActiveWeaponIsZRL[client])
				ToggleLaserOff(client, giActiveWeapon[client], 1);
			else
				ToggleLaserOff(client, giActiveWeapon[client], 0);
		}
	}
	else
	{
		if (gbActiveWeaponIsSRS[client] || gbActiveWeaponIsZRL[client])
			ToggleLaserOff(client, giActiveWeapon[client], 1);
		else
			ToggleLaserOff(client, giActiveWeapon[client], 0);
	}

	// ToggleLaser(client, giActiveWeapon[client]);

	// keep checking in case we missed a beat due to their shitty input handling
	if (ghTimerCheckAimed[client] == INVALID_HANDLE && gbShouldEmitLaser[client])
		CreateTimer(0.5, timer_CheckForAimed, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}


void HandleSRSQuirks(int client)
{
	if (gbHeldKeys[client][KEY_ATTACK]){
		if (gbInZoomState[client]){
			// gbShouldEmitLaser[client] = true;
			ToggleLaserOn(client, giActiveWeapon[client], 0);
			return;
		}
		else{
			// gbShouldEmitLaser[client] = false;
			ToggleLaserOff(client, giActiveWeapon[client], 1);
			return;
		}
	}

	// 5 is weapon switching animation, zoom is instantaneous! 4 is weapon empty
	// 11 is rebolting, 3 is fired shot, 6 reloading clip
	int sequence = GetEntProp(iAffectedWeapons[giActiveWeapon[client]],
	Prop_Data, "m_nSequence", 4)

	if (sequence && (sequence == 6 || sequence == 11))
	{
		// sequence 11 (rebolting) might still be running, preventing
		// zoom state detection when spamming Zoom key

		#if DEBUG
		PrintToChatAll("lasersight] SRS is sequence %d. Aborting checks!", sequence);
		#endif

		// Keep checking until the sequence is effectively over and bAimed it true
		if (ghTimerCheckSRSSequence[client] == INVALID_HANDLE)
			ghTimerCheckSRSSequence[client] = CreateTimer(0.1, timer_CheckSRSSequence, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE)

		return; // avoid toggling during bolt reload sequence (between shots)
	}
}



public Action timer_CheckSRSSequence(Handle timer, int client)
{
	if (IsWeaponAimed(iAffectedWeapons[giActiveWeapon[client]])
	&& !IsWeaponReloading(iAffectedWeapons[giActiveWeapon[client]]))
	{
		#if DEBUG
		PrintToChatAll("Aimed weapon.");
		#endif

		gbInZoomState[client] = true;
		ToggleLaserOn(client, giActiveWeapon[client], 0);
		ghTimerCheckSRSSequence[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	int sequence = GetEntProp(giActiveWeapon[client], Prop_Data, "m_nSequence", 4);
	if (sequence && (sequence == 6 || sequence == 11))
		return Plugin_Continue;
	else
		return Plugin_Stop;

	#if DEBUG
	PrintToChatAll("Sequence playing / not aimed weapon.");
	#endif
	return Plugin_Continue; // keep checking
}


// in case we are emitting beam while not actually aimed anymore
public Action timer_CheckForAimed(Handle timer, int client)
{
	if (giActiveWeapon[client] == -1)
	{
		ghTimerCheckAimed[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	#if DEBUG > 2
	PrintToServer("[lasersight] TIMER CHECK for %N (%d) bAimed: %d bInReload: %d",
	client, client,
	GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Send, "bAimed"),
	GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Data, "m_bInReload"));
	#endif

	if (gbShouldEmitLaser[client])
	{
		if (!IsWeaponAimed(iAffectedWeapons[giActiveWeapon[client]])
			|| IsWeaponReloading(iAffectedWeapons[giActiveWeapon[client]]))
			gbInZoomState[client] = false;
	}
	else // ok we've turned it off already
	{
		ghTimerCheckAimed[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	if (gbInZoomState[client])
		return Plugin_Continue; // keep checking while we still emit
	else
	{
		if (gbActiveWeaponIsSRS[client] || gbActiveWeaponIsZRL[client])
			ToggleLaserOff(client, giActiveWeapon[client], 1);
		else
			ToggleLaserOff(client, giActiveWeapon[client], 0);

		ghTimerCheckAimed[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
}


bool IsWeaponAimed(int weapon)
{
	#if DEBUG > 2
	PrintToServer("[lasersight] Weapon %d bAimed is: %d.", weapon,
	GetEntProp(weapon, Prop_Send, "bAimed"));
	#endif
	if (weapon <= 0)
		return false;

	if (GetEntProp(weapon, Prop_Send, "bAimed") == 1)
		return true;
	return false;
}

bool IsWeaponReloading(int weapon)
{
	if (GetEntProp(weapon, Prop_Data, "m_bInReload") == 1)
		return true;
	return false;
}


void OnReloadKeyPressed(int client)
{
	#if DEBUG
	int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
	SetWeaponAmmo(client, GetAmmoType(GetActiveWeapon(client)), 90);
	#endif

	// check if we are still in a reload animation, block accordingly
	if (view_as<bool>(GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Data, "m_bInReload")))
	{
		#if DEBUG
		PrintToServer("[lasersight] IN_RELOAD weapon %d m_bInReload is %d. Blocking.",
		weapon, GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Data, "m_bInReload"));
		#endif
	}

	// the above check will not trigger right after key press, need delay
	if (ghTimerCheckReload[client] == INVALID_HANDLE)
		ghTimerCheckReload[client] = CreateTimer(0.1, timer_CheckForReload, client, TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_CheckForReload(Handle timer, int client)
{
	//check until "m_bInReload" in weapon_srs is released -> TODO in any weapon?
	if (view_as<bool>(GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Data, "m_bInReload")))
	{
		#if DEBUG
		int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
		PrintToServer("[lasersight] IN_RELOAD weapon %d m_bInReload is %d. Toggling laser off.",
		weapon, GetEntProp(iAffectedWeapons[giActiveWeapon[client]], Prop_Data, "m_bInReload"));
		#endif

		gbInZoomState[client] = false;
		gbShouldEmitLaser[client] = false;
		if (gbActiveWeaponIsSRS[client] || gbActiveWeaponIsZRL[client])
			ToggleLaserOff(client, giActiveWeapon[client], 1);
		else
			ToggleLaserOff(client, giActiveWeapon[client], 0);
	}

	ghTimerCheckReload[client] = INVALID_HANDLE;
	return Plugin_Handled;
}


// return "fire on empty clip" sequences
// FIXME: check these only on weapon_switch and weapon_equip and build cache
// note: it might be better to check view models?
int GetIgnoredSequencesForWeapon(WeaponType weapontype)
{
	// if (StrEqual(weaponName, "weapon_jitte") ||
	// 	StrEqual(weaponName, "weapon_jittescoped") ||
	// 	StrEqual(weaponName, "weapon_m41") ||
	// 	StrEqual(weaponName, "weapon_m41s") ||
	// 	StrEqual(weaponName, "weapon_pz"))
	// 	return 5;

	// if (StrEqual(weaponName, "weapon_mpn") ||
	// 	StrEqual(weaponName, "weapon_srm") ||
	// 	StrEqual(weaponName, "weapon_srm_s") ||
	// 	StrEqual(weaponName, "weapon_zr68c") ||
	// 	StrEqual(weaponName, "weapon_zr68s") ||
	// 	StrEqual(weaponName, "weapon_zr68l") ||
	// 	StrEqual(weaponName, "weapon_mx") ||
	// 	StrEqual(weaponName, "weapon_mx_silenced"))
	// 	return 6;

	switch(weapontype)
	{
		case WPN_jitte, WPN_jittescoped, WPN_m41, WPN_m41s, WPN_pz:
		{
			return 5;
		}
		case WPN_mpn, WPN_srm, WPN_srm_s, WPN_zr68c, WPN_zr68s, WPN_zr68l, WPN_mx, WPN_mx_silenced:
		{
			return 6;
		}
		default: // WPN_srs
		{
			return 0;
		}
	}
	return 0;
}


// Tracks sequence to reset zoom state
public Action timer_CheckSequence(Handle timer, DataPack datapack)
{
	ResetPack(datapack);
	int client = GetClientOfUserId(ReadPackCell(datapack));
	int weapon = EntRefToEntIndex(ReadPackCell(datapack)); // FIXME weapon might have been dropped by now!
	// int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
	int ignored_sequence = ReadPackCell(datapack);

	if (!IsValidClient(client)){
		ghTimerCheckSequence[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	if (!IsValidEdict(weapon)){
		#if DEBUG
		PrintToServer("[lasersight] !IsValidEdict: %i", weapon);
		#endif
		ghTimerCheckSequence[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	// gbInZoomState[client] = GetInReload(weapon);
	#if DEBUG
	PrintToServer("[lasersight] m_nSequence: %d, ammo: %d",
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

	if (gbInZoomState[client])
	{
		if (!gbActiveWeaponIsZRL[client])
			ToggleLaserOn(client, GetTrackedWeaponIndex(weapon), 1);
	}
	else
	{
		if (!gbActiveWeaponIsZRL[client])
			ToggleLaserOff(client, GetTrackedWeaponIndex(weapon), 1);
	}

	ghTimerCheckSequence[client] = INVALID_HANDLE;
	return Plugin_Stop;
}


void ToggleLaserOn(int client, int weapon_index, int viewmodel)
{
	ToggleLaserDot(client, weapon_index, true);
	ToggleLaserBeam(client, weapon_index, true);
	ToggleViewModelLaserBeam(client, viewmodel);
	g_bNeedUpdateLoop = NeedUpdateLoop();
}

void ToggleLaserOff(int client, int weapon_index, int viewmodel)
{
	ToggleLaserDot(client, weapon_index, false);
	ToggleLaserBeam(client, weapon_index, false);
	ToggleViewModelLaserBeam(client, viewmodel);
	g_bNeedUpdateLoop = NeedUpdateLoop();
}


// for regular weapons, prevent automatic laser creation on aim down sight
void ToggleLaserActivity(int client, int weapon)
{
	gbLaserEnabled[client] = !gbLaserEnabled[client];
	PrintCenterText(client, "Laser sight toggled %s", gbLaserEnabled[client] ? "on" : "off");

	// check if we're zoomed currently
	// if (!IsWeaponAimed(iAffectedWeapons[giActiveWeapon[client]]) || IsWeaponReloading(iAffectedWeapons[giActiveWeapon[client]]))
	// {
	// 	gbInZoomState[client] = false;
	// 	gbShouldEmitLaser[client] = false;
	// }
	if (gbInZoomState[client])
	{
		#if DEBUG > 2
		PrintToChatAll("%N in zoom?", client);
		#endif
		gbShouldEmitLaser[client] = gbLaserEnabled[client] ? true : false;
	}
	else
	{
		#if DEBUG > 2
		PrintToChatAll("%N not in zoom?", client);
		#endif
		gbShouldEmitLaser[client] = false;
	}

	if (gbShouldEmitLaser[client])
		ToggleLaserOn(client, weapon, 1);
	else
		ToggleLaserOff(client, weapon, 0);
}


// Warning: upcon first connection, Health = 100, observermode = 0, and deadflag = 0!
bool IsPlayerObserving(int client)
{
	#if DEBUG
	PrintToServer("[lasersight] IsPlayerObserving: %N (%d) m_iObserverMode = %d, deadflag = %d, Health = %d",
	client, client,
	GetEntProp(client, Prop_Send, "m_iObserverMode"),
	GetEntProp(client, Prop_Send, "deadflag"),
	GetEntProp(client, Prop_Send, "m_iHealth"));
	#endif

	// For some reason, 1 health point means dead, but checking deadflag is probably more reliable!
	// Note: CPlayerResource also seems to keep track of players alive state (netprop)
	if (GetEntProp(client, Prop_Send, "m_iObserverMode") > 0 || IsPlayerReallyDead(client))
	{
		#if DEBUG
		PrintToServer("[lasersight] Determined that %N is observing right now. \
m_iObserverMode = %d, deadflag = %d, Health = %d", client,
		GetEntProp(client, Prop_Send, "m_iObserverMode"),
		GetEntProp(client, Prop_Send, "deadflag"),
		GetEntProp(client, Prop_Send, "m_iHealth"));
		#endif
		return true;
	}
	return false;
}


bool IsPlayerReallyDead(int client)
{
	if (GetEntProp(client, Prop_Send, "deadflag") || GetEntProp(client, Prop_Send, "m_iHealth") <= 1)
		return true;
	return false;
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