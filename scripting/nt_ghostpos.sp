#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif

Handle ghCheckPosTimer, hCheckPosEnabled = INVALID_HANDLE;
float gfLastValidCoords[3];
float gfCoordsBuffer[3];
int g_iGhostCarrier, g_iGhost;
float gfMinimumHeight;
bool gbStopTimer;
bool g_bGhostIsHeld;

public Plugin:myinfo =
{
	name = "NEOTOKYO anti griefing",
	author = "glub",
	description = "Checks ghost coordinates, blocks ghost hopping.",
	version = "0.1",
	url = "https://github.com/glubsy"
};

// Add up to 5 last known position coords in a circular buffer
// restore pos one after the other until the coordinates are valid
// TODO: block more than one jump per 2 seconds ? for ghost carrier.
// TODO: set of known hull coordinates which can be problematic (ie. nt_skyline_ctg scaffholdings) and compare against them

public void OnPluginStart()
{
	hCheckPosEnabled = CreateConVar("nt_checkghostpos", "0",
	"Regularly check for invalid ghost coordinates.", _, true, 0.0, true, 1.0);

	// HookEvent("player_spawn", OnPlayerSpawn); // we'll use SDK hook instead
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookConVarChange(FindConVar("neo_restart_this"), OnNeoRestartThis);
	// HookEvent("game_round_end", OnRoundEnd);


	#if DEBUG
	PrintToServer("[ghostpos] DEBUG: looking for ghost...");
	int ghost = FindEntityByClassname(-1, "weapon_ghost");
	if (IsValidEntity(ghost))
	{
		PrintToServer("[ghostpos] Found ghost %d", ghost);
		OnGhostSpawn(EntIndexToEntRef(ghost));
	}
	#endif
}

public void OnConfigsExecuted(){

	char currentMap[64];
	GetCurrentMap(currentMap, 64);

	#if DEBUG
	PrintToServer("[ghostpos] Current map: %s", currentMap);
	#endif

	// if current map is potential candidate for griefing automatically enable plugin
	if (StrEqual(currentMap, "nt_skyline_ctg"))
	{
		gfMinimumHeight = -500.0;
		SetConVarInt(hCheckPosEnabled, 1);
		return;
	}
	if (StrEqual(currentMap, "nt_rise_ctg"))
	{
		gfMinimumHeight = -500.0; // FIXME
		SetConVarInt(hCheckPosEnabled, 1);
		return;
	}
	if (StrEqual(currentMap, "nt_saitama_ctg"))
	{
		gfMinimumHeight = -500.0; // FIXME
		SetConVarInt(hCheckPosEnabled, 1);
		return;
	}
	SetConVarInt(hCheckPosEnabled, 0);
}


public void OnNeoRestartThis(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// OnRoundStart();
}


public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	//int victim = GetClientOfUserId(GetEventInt(event, "userid"));
}


public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	#if !DEBUG
	if (!GetConVarBool(hCheckPosEnabled))
		return;
	#endif

	// TagGhost();
}


void TagGhost(int entity)
{
	#if DEBUG
	PrintToServer("[ghostpos] TagGhost %d", entity);
	#endif

	SetEntProp(entity, Prop_Data, "m_takedamage", 1); // 0 takes no damage, 1 buddha, 2 mortal, 3 ?

	SDKHook(entity, SDKHook_TraceAttackPost, OnTraceAttackPost);
	HookSingleEntityOutput(entity, "OnPlayerPickup", OnPlayerPickup, false); // works

	ChangeEdictState(entity);
}


public void OnAwakened(const char[] output, int caller, int activator, float delay)
{
	PrintToServer("Prop %d awakened (activator %d)", caller, activator);
}


public void OnGhostSpawn(int entref)
{
	int entity = EntRefToEntIndex(entref);
	if (!IsValidEntity(entity))
	{
		#if DEBUG
		PrintToServer("[ghostpos] OnGhostSpawn() returned INVALID entity index: %d!",
		entity);
		#endif
	}

	#if DEBUG
	PrintToServer("[ghostpos] OnGhostSpawn() valid: %d", entity);
	#endif
	g_iGhost = entref;

	TagGhost(entity);

	CreateTimer(10.0, timer_StoreInitialPos, entref, TIMER_FLAG_NO_MAPCHANGE);

	// g_bGhostIsCaptured = false;
	g_bGhostIsHeld = false;
	// g_bEndOfRound = false;
}


public Action timer_StoreInitialPos(Handle timer, int entref)
{
	int ghost = EntRefToEntIndex(entref);
	if (!IsValidEntity(ghost))
	{
		#if DEBUG
		ThrowError("[ghostpos] Ghost (entref %d index %d) was invalid when attempting to get its initial position.",
		entref, ghost)
		#endif
		return Plugin_Stop;
	}

	float currentPos[3];
	GetEntPropVector(ghost, Prop_Data, "m_vecAbsOrigin", currentPos);
	// RoundToCeil(currentPos[0]);
	// RoundToCeil(currentPos[1]);
	// RoundToCeil(currentPos[2]);
	StoreCoords(currentPos);
	return Plugin_Handled;
}

public void OnTraceAttackPost(int victim, int attacker, int inflictor, float damage,
int damagetype, int ammotype, int hitbox, int hitgroup)
{
	#if DEBUG > 2
	char classname[20];
	if (!GetEntityClassname(victim, classname, sizeof(classname)))
		return;
	PrintToServer("[ghostpos] TakeDamage: %s %d, inflictor %d, attacker %d, damage %f, damagetype %d, ammotype %d, hitbox %d, hitgroup %d",
	classname, victim, inflictor, attacker, damage, damagetype, ammotype, hitbox, hitgroup);
	#endif

	if (ghCheckPosTimer == INVALID_HANDLE)
	{
		ghCheckPosTimer = CreateTimer(0.5, timer_CheckPos, victim, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}


public void OnPlayerPickup(const char[] output, int caller, int activator, float delay)
{
	#if DEBUG
	PrintToServer("[ghostpos] OnPlayerPickup! (caller %d activator %d)",
	caller, activator);
	#endif

	g_bGhostIsHeld = true;
	g_iGhostCarrier = GetEntPropEnt(caller, Prop_Send, "m_hOwnerEntity");

	if (ghCheckPosTimer != INVALID_HANDLE)
	{
		gbStopTimer = true;
	}
	ghCheckPosTimer = CreateTimer(0.5, timer_CheckPos, caller, TIMER_REPEAT);
}


public void OnGhostUsed(const char[] output, int caller, int activator, float delay)
{
	#if DEBUG
	PrintToServer("[ghostpos] OnGhostUsed by %N (%d). (caller %d activator %d)",
	caller, caller, caller, activator);
	#endif
}


public void OnGhostDrop(int client)
{
	#if DEBUG
	PrintToServer("[ghostpos] %N dropped ghost", client);
	#endif

	g_bGhostIsHeld = false;
	g_iGhostCarrier = -1;

	// if (ghCheckPosTimer != INVALID_HANDLE)
	// {
	// 	gbStopTimer = true;
	// }
	if (ghCheckPosTimer == INVALID_HANDLE)
		ghCheckPosTimer = CreateTimer(0.5, timer_CheckPos, EntRefToEntIndex(g_iGhost), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}


public void OnGhostCapture()
{
	UnhookSingleEntityOutput(g_iGhost, "OnPlayerPickup", OnPlayerPickup);
	SDKUnhook(g_iGhost, SDKHook_TraceAttackPost, OnTraceAttackPost);
	// UnhookSingleEntityOutput(g_iGhost, "OnPlayerUse", OnGhostUsed);
}


public Action timer_StartCheckingGhostPos(Handle timer)
{
	if (ghCheckPosTimer == INVALID_HANDLE)
		ghCheckPosTimer = CreateTimer(5.0, timer_CheckPos, g_iGhost, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}


public Action timer_CheckPos(Handle timer, int ghost)
{
	if (gbStopTimer) // FIXME this is bad
	{
		ghCheckPosTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}

	float currentPos[3];
	GetEntPropVector(ghost, Prop_Data, "m_vecAbsOrigin", currentPos);
	// RoundToCeil(currentPos[0]);
	// RoundToCeil(currentPos[1]);
	// RoundToCeil(currentPos[2]);
	int m_hGroundEntity = GetEntPropEnt(ghost, Prop_Data, "m_hGroundEntity");
	// 0 = World (aka on ground) | -1 = In air | Any other positive value = CBaseEntity entity-index below player. (?)

	int m_fFlags = GetEntProp(ghost, Prop_Data, "m_fFlags");
	int m_iEFlags = GetEntProp(ghost, Prop_Data, "m_iEFlags");
	int m_iState = GetEntProp(ghost, Prop_Send, "m_iState");

	#if DEBUG
	PrintToServer("[ghostpos] ghost %d m_fFlags %d, m_hGroundEntity %d m_vecAbsOrigin %f %f %f \
m_iEFlags %d flcompare %d m_iState %d",
	ghost, m_fFlags, m_hGroundEntity, currentPos[0], currentPos[1], currentPos[2],
	m_iEFlags, FloatCompare(currentPos[2], gfMinimumHeight), m_iState);
	// if (m_iEFlags & (1<<12)) //EFL_DIRTY_ABSVELOCITY
	// 	PrintToServer("ghost has EFL_DIRTY_ABSVELOCITY")
	#endif

	gfCoordsBuffer = currentPos;

	if (FloatCompare(currentPos[2], gfMinimumHeight) == -1) // we're too low and not on ground
	{
		if (!IsImmobile(currentPos))
			return Plugin_Continue;

		#if DEBUG
		PrintToServer("[ghostpos] Ghost seems to be OOB. Getting last known valid coords.");
		#endif

		// if (giCoordsBuffer_head > 0)
		// 	giCoordsBuffer_head--;

		// if (gfCoordsBuffer[giCoordsBuffer_head][0] == 0.0
		// && gfCoordsBuffer[giCoordsBuffer_head][1] == 0.0
		// && gfCoordsBuffer[giCoordsBuffer_head][2] == 0.0)
		// {
		// 	ThrowError("[ghostpos] Stored valid coords where NULL_VECTOR. Aborting."); // FIXME: maybe rewind in the array here?
		// 	ghCheckPosTimer = INVALID_HANDLE;
		// 	return Plugin_Stop;
		// }

		#if DEBUG
		PrintToServer("[ghostpos] Teleporting back to %f %f %f",
		gfLastValidCoords[0], gfLastValidCoords[1], gfLastValidCoords[2]);
		#endif

		TeleportEntity(ghost, gfLastValidCoords, NULL_VECTOR, NULL_VECTOR); // FIXME lower z axis to avoid falling?

		return Plugin_Continue;
	}
	else // valid coords, store them.
	{
		if (g_bGhostIsHeld)
		{
			bool bOnGround = GetEntityFlags(g_iGhostCarrier) & FL_ONGROUND ? true : false;
			#if DEBUG
			PrintToServer("owner: %N (%s)",
			g_iGhostCarrier, bOnGround ? "is on ground" : "is NOT on ground" );
			#endif

			if (bOnGround /*&& StandsFirm(g_iGhostCarrier)*/) 
				StoreCoords(currentPos);

			return Plugin_Continue;
		}

		if (IsImmobile(currentPos)) // wish we could detect props being at rest on the ground :(
		{
			StoreCoords(currentPos);
			ghCheckPosTimer = INVALID_HANDLE;
			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}


bool IsImmobile(float[3] currentCoords)
{
	// same coords, we can safely store them as we assume the entity is at rest
	if (!FloatCompare(currentCoords[2], gfCoordsBuffer[2])
	   && !FloatCompare(currentCoords[1], gfCoordsBuffer[1])
	   && !FloatCompare(currentCoords[0], gfCoordsBuffer[0]))
	{
		#if DEBUG
		PrintToServer("[ghostpos] coord seems immobile at {%f %f %f}",
		currentCoords[0], currentCoords[1], currentCoords[2]);
		#endif

		return true;
	}

	return false;
}


void StoreCoords(float[3] validCoords)
{
	#if DEBUG
	PrintToServer("[ghostpos] Storing coords {%f %f %f}",
	validCoords[0], validCoords[1], validCoords[2]);
	#endif
	gfLastValidCoords = validCoords;
}


// trace a hull to see if aread under feet doesn't lead to a fall
// TODO: get surface's normals and check if we are standing on a slope
// TODO: in order to detect a void under a player's feet, we need to trace 4
// thin hulls on each side of the player's "circumference".
stock bool StandsFirm(int client)
{
	float vecPos[3], vecEnd[3], vecMins[3], vecMaxs[3];
	GetClientAbsOrigin(client, vecPos);
	// GetClientEyeAngles(client, vecEnd);
	vecEnd[0] = vecPos[0];
	vecEnd[1] = vecPos[1];
	vecEnd[2] = vecPos[2] - 40.0;
	// vecMins[0] = -10.0;  // player -16.0
	// vecMins[1] = -10.0; // player -16.0
	// vecMins[2] = 0.0; // player 0.0
	// vecMaxs[0] = 10.0; // player 16.0
	// vecMaxs[1] = 10.0; // player 16.0
	// vecMaxs[2] = 0.0; // player 64.0

	GetEntPropVector(client, Prop_Send, "m_vecMins", vecMins);
	GetEntPropVector(client, Prop_Send, "m_vecMaxs", vecMaxs);
	PrintToChatAll("origin %f %f %f vecEnd %f %f %f", vecPos[0], vecPos[1], vecPos[2], vecEnd[0], vecEnd[1], vecEnd[2]);

	Handle trace = TR_TraceHullFilterEx(vecPos, vecEnd, vecMins, vecMaxs, MASK_SOLID_BRUSHONLY, HullFilter, client);

	if(TR_DidHit(trace))
	{
		CloseHandle(trace);
		#if DEBUG
		PrintToServer("[ghostpos] Tracehull HIT")
		#endif
		return true;
	}

	#if DEBUG
	PrintToServer("[ghostpos] Tracehull NO")
	#endif
	CloseHandle(trace);
	return false;
}


public bool HullFilter (int entity, int contentsMask, any data)
{
	return ((entity > MaxClients) || entity == 0);
}


// public Action timer_CheckVelocity(Handle timer, int entindex)
// {
// 	if (HasNotChangedPosition(entindex))
// 	{
// 		ghTimerAwake = INVALID_HANDLE;
// 		return Plugin_Stop;
// 	}

// 	if (ghCheckPosTimer == INVALID_HANDLE)
// 		ghCheckPosTimer = CreateTimer(1.0, timer_CheckPos, entindex, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

// 	return Plugin_Continue;
// }

// bool HasNoVelocity(int entindex) // doesn't work
// {
// 	float vecVel[3];
// 	GetEntPropVector(entindex, Prop_Data, "m_vecAbsVelocity", vecVel);

// 	if (vecVel[0] > 0.0 || vecVel[1] > 0.0 || vecVel[2] > 0.0)
// 	{
// 		#if DEBUG
// 		PrintToServer("[ghostpos] Ghost %d has velocity: %f %f %f",
// 		entindex, vecVel[0], vecVel[1], vecVel[2]);
// 		#endif
// 		return false;
// 	}

// 	#if DEBUG
// 	PrintToServer("[ghostpos] Ghost %d has no velocity: %f %f %f",
// 	entindex, vecVel[0], vecVel[1], vecVel[2]);
// 	#endif
// 	return true;
// }


// public void OnGameFrame()
// {
// 	if(!g_iGhost)
// 		return;

// 	int m_iEFlags = GetEntProp(g_iGhost, Prop_Data, "m_iEFlags");
// 	if (m_iEFlags & (1<<13))
// 		PrintToChatAll("ghost has flag %d", m_iEFlags);
// 	else
// 		PrintToChatAll("ghost no flag %d", m_iEFlags);
// }
