#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif

Handle ghCheckPosTimer = INVALID_HANDLE;
bool gbCheckPosEnabled;
float gfLastValidCoords[10][3];
float gfLastStaticValidCoords[10][3];
float gfLastUsedValidCoords[3];
float gfInitialGhostPosition[3];
int gCursor, gStaticCursor;
float gfCoordsBuffer[3];
int g_iGhostCarrier, g_iGhost;
float gfMinimumHeight;
bool g_bGhostIsHeld;
bool bTeleported;
bool g_bGhostIsCaptured;

public Plugin:myinfo =
{
	name = "NEOTOKYO anti OOB ghost",
	author = "glub",
	description = "Prevent out of bounds ghost positions.",
	version = "0.3",
	url = "https://github.com/glubsy"
};

// Adds up to 20 last known positions coords in circular buffers, then 
// restore position coordinates until a valid one is found

// TODO: check against a set of known hull coordinates which can be problematic
// (ie. nt_skyline_ctg scaffoldings, saitama fire pit, vtol elevators...)

public void OnPluginStart()
{
	// HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("game_round_end", OnRoundEnd);

	#if DEBUG > 2 // not really needed actually, OnRoundStart is actually called
	HookConVarChange(FindConVar("neo_restart_this"), OnNeoRestartThis);
	#endif

	int ghost = FindEntityByClassname(-1, "weapon_ghost");
	if (IsValidEntity(ghost))
	{
		#if DEBUG
		PrintToServer("[ghostpos] Found already existing ghost %d", ghost);
		#endif
		OnGhostSpawn(EntIndexToEntRef(ghost));
	}
}

public void OnConfigsExecuted(){ // perhaps this should simply be OnMapStart

	char currentMap[64];
	GetCurrentMap(currentMap, 64);

	#if DEBUG
	PrintToServer("[ghostpos] Current map: %s", currentMap);
	#endif

	if (StrEqual(currentMap, "nt_skyline_ctg"))
	{
		gfMinimumHeight = -500.0;
		gbCheckPosEnabled = true;
		return;
	}
	if (StrEqual(currentMap, "nt_rise_ctg"))
	{
		gfMinimumHeight = -1000.0;
		gbCheckPosEnabled = true;
		return;
	}
	gbCheckPosEnabled = false;
}


#if DEBUG > 2
// NOTE: beware, this is always called twice on convar changed!
public void OnNeoRestartThis(ConVar convar, const char[] oldValue, const char[] newValue)
{
	#if DEBUG
	PrintToChatAll("[ghostpos] OnNeoRestartThis()");
	#endif

	if (!gbCheckPosEnabled)
		return;
	UpdateGhostRef();
}
#endif


public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	#if !DEBUG
	if (!gbCheckPosEnabled)
		return;
	#endif

	g_bGhostIsCaptured = false;
	ResetCoordArrays();
	UpdateGhostRef();
	// TagGhost();
}


int UpdateGhostRef()
{
	int ghostindex = EntRefToEntIndex(g_iGhost);

	#if DEBUG
	PrintToServer("[ghostpos] UpdateGhostRef(), g_iGhost=%d (index %d)", g_iGhost, ghostindex);
	#endif

	if (!ghostindex || !IsValidEntity(ghostindex))
	{
		#if DEBUG
		PrintToServer("[ghostpos] OnRoundStart, invalid g_iGhost, looking for one...");
		#endif

		int ghost = FindEntityByClassname(-1, "weapon_ghost");
		if (IsValidEntity(ghost))
		{
			#if DEBUG
			PrintToServer("[ghostpos] Found ghost %d", ghost);
			#endif
			OnGhostSpawn(EntIndexToEntRef(ghost));
		}
	}
}


public void OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	#if !DEBUG
	if (!gbCheckPosEnabled)
		return;
	#endif

	if (ghCheckPosTimer != INVALID_HANDLE)
	{
		KillTimer(ghCheckPosTimer);
		ghCheckPosTimer = INVALID_HANDLE;
	}
	// ResetCoordArrays();
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


void ResetCoordArrays()
{
	#if DEBUG
	PrintToServer("[ghostpos] Reset coord arrays");
	#endif

	for (int i; i < sizeof(gfLastValidCoords); ++i)
	{
		gfLastValidCoords[i] = NULL_VECTOR;
	}
	for (int i; i < sizeof(gfLastStaticValidCoords); ++i)
	{
		gfLastStaticValidCoords[i] = NULL_VECTOR;
	}
	gfInitialGhostPosition = NULL_VECTOR;
	gfLastUsedValidCoords = NULL_VECTOR;
}


public void OnGhostSpawn(int entref)
{
	#if !DEBUG
	if (!gbCheckPosEnabled)
		return;
	#endif

	int entity = EntRefToEntIndex(entref);

	if (!IsValidEntity(entity))
	{
		#if DEBUG
		PrintToServer("[ghostpos] OnGhostSpawn() returned invalid entity index: %d!",
		entity);
		#endif
		return;
	}

	#if DEBUG
	PrintToServer("[ghostpos] OnGhostSpawn() valid: %d", entity);
	#endif
	g_iGhost = entref;

	TagGhost(entity);

	CreateTimer(10.0, timer_StoreInitialPos, entref, TIMER_FLAG_NO_MAPCHANGE);

	g_bGhostIsCaptured = false;
	g_bGhostIsHeld = false;
}


public Action timer_StoreInitialPos(Handle timer, int entref)
{
	#if DEBUG
	PrintToServer("[ghostpos] timer_StoreInitialPos got entref = %d", entref);
	#endif

	int ghost = EntRefToEntIndex(entref);
	if (!IsValidEntity(ghost))
	{
		#if DEBUG // FIXME this might be normal (first spawned ghost is removed) no need to log
		LogError("[ghostpos] Ghost (entref %d index %d) was invalid \
when attempting to get its initial position.",
		entref, ghost)
		#endif
		return Plugin_Stop;
	}

	float currentPos[3];
	GetEntPropVector(ghost, Prop_Data, "m_vecAbsOrigin", currentPos);
	// RoundToCeil(currentPos[0]);
	// RoundToCeil(currentPos[1]);
	// RoundToCeil(currentPos[2]);
	StoreStaticCoords(currentPos);

	gfInitialGhostPosition = currentPos;

	#if DEBUG
	PrintToServer("[ghostpos] Stored initial coords {%f %f %f}",
	gfInitialGhostPosition[0], gfInitialGhostPosition[1], gfInitialGhostPosition[2]);
	#endif

	return Plugin_Handled;
}


public void OnTraceAttackPost(int victim, int attacker, int inflictor, float damage,
int damagetype, int ammotype, int hitbox, int hitgroup)
{
	#if DEBUG > 2
	char classname[20];
	if (!GetEntityClassname(victim, classname, sizeof(classname)))
		return;
	PrintToServer("[ghostpos] TakeDamage: %s %d, inflictor %d, attacker %d, \
damage %f, damagetype %d, ammotype %d, hitbox %d, hitgroup %d",
	classname, victim, inflictor, attacker, damage, damagetype,
	ammotype, hitbox, hitgroup);
	#endif

	if (ghCheckPosTimer == INVALID_HANDLE)
	{
		ghCheckPosTimer = CreateTimer(0.5, timer_CheckPos,
		victim, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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

	if (ghCheckPosTimer == INVALID_HANDLE)
		ghCheckPosTimer = CreateTimer(0.5, timer_CheckPos, caller, TIMER_REPEAT);
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
	// UnhookSingleEntityOutput(g_iGhost, "OnPlayerPickup", OnPlayerPickup);
	// SDKUnhook(g_iGhost, SDKHook_TraceAttackPost, OnTraceAttackPost);
	g_bGhostIsCaptured = true;
}


public Action timer_StartCheckingGhostPos(Handle timer)
{
	if (ghCheckPosTimer == INVALID_HANDLE)
		ghCheckPosTimer = CreateTimer(5.0, timer_CheckPos, EntRefToEntIndex(g_iGhost), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}


public Action timer_CheckPos(Handle timer, int ghost)
{
	if (ghost == 0 || !IsValidEntity(ghost) || g_bGhostIsCaptured)
	{
		#if DEBUG
		PrintToServer("[ghostpos] timer_CheckPos Invalid ghost or iscaptured! %d", ghost);
		#endif
		ghCheckPosTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}

	float currentPos[3];
	GetEntPropVector(ghost, Prop_Data, "m_vecAbsOrigin", currentPos);
	// RoundToCeil(currentPos[0]);
	// RoundToCeil(currentPos[1]);
	// RoundToCeil(currentPos[2]);

	#if DEBUG > 1
	int m_hGroundEntity = GetEntPropEnt(ghost, Prop_Data, "m_hGroundEntity");
	// 0 = World (aka on ground) | -1 = In air | Any other positive value = CBaseEntity entity-index below player. (?)
	int m_fFlags = GetEntProp(ghost, Prop_Data, "m_fFlags");
	int m_iEFlags = GetEntProp(ghost, Prop_Data, "m_iEFlags");
	int m_iState = GetEntProp(ghost, Prop_Send, "m_iState");

	PrintToServer("[ghostpos] ghost %d m_fFlags %d, m_hGroundEntity %d m_vecAbsOrigin %f %f %f \
m_iEFlags %d flcompare %d m_iState %d",
	ghost, m_fFlags, m_hGroundEntity, currentPos[0], currentPos[1], currentPos[2],
	m_iEFlags, FloatCompare(currentPos[2], gfMinimumHeight), m_iState);
	// if (m_iEFlags & (1<<12)) //EFL_DIRTY_ABSVELOCITY
	// 	PrintToServer("ghost has EFL_DIRTY_ABSVELOCITY")
	#endif

	if (FloatCompare(currentPos[2], gfMinimumHeight) == -1) // we're too low and not on ground
	{
		// if (!IsImmobile(currentPos)) // probably not needed, let's make it snappier
		// 	return Plugin_Continue;

		#if DEBUG
		PrintToServer("[ghostpos] Ghost seems to be OOB. Getting last known valid coords.");
		#endif

		float fCoords[3];

		while (IsNullVector(fCoords))
		{
			fCoords = GetNextValidCoords(gfLastUsedValidCoords); // get at current cursor

			// if (IsNullVector(fCoords))
			// {
			// 	fCoords = GetNextValidCoordsStatic(lastusedtemp);
			// }
		}

		gfLastUsedValidCoords = fCoords;

		#if DEBUG
		PrintToServer("[ghostpos] Teleporting back to %f %f %f",
		gfLastUsedValidCoords[0], gfLastUsedValidCoords[1], gfLastUsedValidCoords[2]);
		#endif

		float vecVel[3];
		vecVel[2] += 1.0;

		TeleportEntity(ghost, fCoords, NULL_VECTOR, vecVel);
		// ChangeEdictState(ghost);

		bTeleported = true;

		return Plugin_Continue;
	}
	else // valid coords, store them.
	{
		if (g_bGhostIsHeld)
		{
			bool bOnGround = GetEntityFlags(g_iGhostCarrier) & FL_ONGROUND ? true : false;

			#if DEBUG
			PrintToServer("[ghostpos] Ghost carrier: %N (%s)", g_iGhostCarrier,
			bOnGround ? "is on ground" : "is NOT on ground" );
			#endif

			if (bOnGround && !VectorsEqual(gfLastValidCoords[gCursor], currentPos, 80.0, true) /*&& StandsFirm(g_iGhostCarrier)*/) // TODO: only pass if low velocity?
				StoreCoords(currentPos, 20.0); // offset to avoid teleporting in solid

			return Plugin_Continue;
		}

		if (IsImmobile(currentPos)) // wish we could detect props being at rest on the ground :(
		{
			if (!bTeleported)
			{
				StoreStaticCoords(currentPos);
			}

			bTeleported = false;

			ghCheckPosTimer = INVALID_HANDLE;
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}


stock bool AreVectorsEqual(float[3] vec1, float[3] vec2)
{
	if (!FloatCompare(vec1[2], vec2[2])
	   && !FloatCompare(vec1[1], vec2[1])
	   && !FloatCompare(vec1[0], vec2[0]))
		return true;

	return false;
}


bool VectorsEqual(float vec1[3], float vec2[3], float tolerance=0.0, bool squared=false)
{
	float distance = GetVectorDistance(vec1, vec2, squared);

	return distance <= (tolerance * tolerance);
}


bool IsNullVector(float[3] vec)
{
	if (!FloatCompare(vec[2], 0.0)
	   && !FloatCompare(vec[1], 0.0)
	   && !FloatCompare(vec[0], 0.0))
		return true;
	return false;
}


bool IsImmobile(float[3] currentCoords)
{
	// same coords, we can safely store them as we assume the entity is at rest
	if (AreVectorsEqual(currentCoords, gfCoordsBuffer))
	{
		#if DEBUG
		PrintToServer("[ghostpos] seems immobile at {%f %f %f}",
		currentCoords[0], currentCoords[1], currentCoords[2]);
		#endif
		// gfCoordsBuffer = currentCoords
		return true;
	}

	gfCoordsBuffer = currentCoords;
	return false;
}


void StoreStaticCoords(float[3] validCoords)
{
	gStaticCursor++;
	gStaticCursor %= sizeof(gfLastStaticValidCoords);

	gfLastStaticValidCoords[gStaticCursor][0] = validCoords[0];
	gfLastStaticValidCoords[gStaticCursor][1] = validCoords[1];
	gfLastStaticValidCoords[gStaticCursor][2] = validCoords[2];

	#if DEBUG
	PrintToServer("[ghostpos] Stored STATIC coords {%f %f %f} at cursor %d",
	validCoords[0], validCoords[1], validCoords[2], gStaticCursor);
	#endif
	return;
}


void StoreCoords(float[3] validCoords, float offset=0.0)
{
	gCursor++;
	gCursor %= sizeof(gfLastValidCoords);

	gfLastValidCoords[gCursor][0] = validCoords[0];
	gfLastValidCoords[gCursor][1] = validCoords[1];
	gfLastValidCoords[gCursor][2] = validCoords[2] + offset;

	#if DEBUG
	PrintToServer("[ghostpos] Stored CARRIED coords {%f %f %f} at cursor %d",
	validCoords[0], validCoords[1], validCoords[2], gCursor);
	#endif
}


float[3] GetNextValidCoords(float[3] ignored)
{
	float result[3];

	// int attempts;
	// while (AreVectorsEqual(gfLastValidCoords[gCursor], ignored))
	// {
	// 	++attempts;
	// 	if (attempts > sizeof(gfLastValidCoords)){
	// 		#if DEBUG
	// 		PrintToServer("breaking loop after CARRIED attempt %d / %d, cursor %d",
	// 		attempts, sizeof(gfLastValidCoords), gCursor);
	// 		#endif
	// 		break;
	// 	}

	// 	--gCursor;

	// 	if (gCursor < 0)
	// 		gCursor = sizeof(gfLastValidCoords) - 1;
	// }

	if (!IsNullVector(ignored))
	{
		for (int attempts = 0; attempts <= sizeof(gfLastValidCoords); ++attempts)
		{
			if (AreVectorsEqual(gfLastValidCoords[gCursor], ignored))
			{
				--gStaticCursor
				if (gCursor < 0)
					gCursor = sizeof(gfLastValidCoords) - 1;
				continue;
			}
			break;
		}
	}

	result = gfLastValidCoords[gCursor];
	gfLastValidCoords[gCursor] = NULL_VECTOR;

	if (IsNullVector(result))
	{
		#if DEBUG
		PrintToServer("[ghostpos] CARRIED result is null, trying static array with %f %f %f",
		result[0], result[1], result[2]);
		#endif

		result = GetNextValidCoordsStatic(ignored);
		return result;
	}

	#if DEBUG
	PrintToServer("[ghostpos] Got CARRIED coords %f %f %f at cursor %d",
	result[0], result[1], result[2], gCursor);
	#endif

	--gCursor;
	if (gCursor < 0)
		gCursor = sizeof(gfLastValidCoords) - 1;

	return result;
}


float[3] GetNextValidCoordsStatic(float[3] ignored)
{
	float result[3];

	// int attempts;
	// while (AreVectorsEqual(gfLastStaticValidCoords[gStaticCursor], ignored))
	// {
	// 	++attempts;
	// 	if (attempts > sizeof(gfLastStaticValidCoords))
	// 	{
	// 		#if DEBUG
	// 		PrintToServer("breaking loop after STATIC attempt %d / %d, cursor %d",
	// 		attempts, sizeof(gfLastStaticValidCoords), gStaticCursor);
	// 		#endif
	// 		break;
	// 	}

	// 	--gStaticCursor;

	// 	if (gStaticCursor < 0)
	// 		gStaticCursor = sizeof(gfLastStaticValidCoords) - 1;
	// }

	if (!IsNullVector(ignored))
	{
		for (int attempts = 0; attempts <= sizeof(gfLastStaticValidCoords); ++attempts)
		{
			if (AreVectorsEqual(gfLastStaticValidCoords[gStaticCursor], ignored))
			{
				--gStaticCursor
				if (gStaticCursor < 0)
					gStaticCursor = sizeof(gfLastStaticValidCoords) - 1;
				continue;
			}
			break;
		}
	}

	if (IsNullVector(gfLastStaticValidCoords[gStaticCursor]))
	{
		--gStaticCursor;
		if (gStaticCursor < 0)
			gStaticCursor = sizeof(gfLastStaticValidCoords) - 1;

		#if DEBUG
		PrintToServer("[ghostpos] reached the end, returning back to initial ghost pos!")
		#endif
		return gfInitialGhostPosition; // last resort
	}

	result = gfLastStaticValidCoords[gStaticCursor];
	gfLastStaticValidCoords[gStaticCursor] = NULL_VECTOR;

	#if DEBUG
	PrintToServer("[ghostpos] Got STATIC coords %f %f %f at cursor %d",
	result[0], result[1], result[2], gStaticCursor);
	#endif

	--gStaticCursor;
	if (gStaticCursor < 0)
		gStaticCursor = sizeof(gfLastStaticValidCoords) - 1;

	return result;
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
		PrintToServer("[ghostpos] Tracehull HIT");
		#endif
		return true;
	}

	#if DEBUG
	PrintToServer("[ghostpos] Tracehull NO");
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


