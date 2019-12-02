#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif

bool gbIsSupport[NEO_MAX_CLIENTS+1];
bool gbFreezeTime;
bool gbHeldKey[NEO_MAX_CLIENTS+1];
bool UsedCloakCharge[NEO_MAX_CLIENTS+1];
float flRoundStartTime;
int giReceivingClients[NEO_MAX_CLIENTS];

Handle ghAntiCamping, ghReuseAllowed = INVALID_HANDLE;
bool gbAntiCamp, ToggleAllowed;
Handle ghMobilityTimer[NEO_MAX_CLIENTS+1] = {INVALID_HANDLE, ...};
int hMyWeapons;
bool gbIsCloaked[NEO_MAX_CLIENTS +1];
bool gbBrokenCloak[NEO_MAX_CLIENTS+1]
float gfCoordsBuffer[NEO_MAX_CLIENTS+1][3];

#define DENIEDSND "buttons/combine_button2.wav"

public Plugin:myinfo =
{
	name = "NEOTOKYO cloak tweaks",
	author = "glub",
	description = "Adds a one-time cloaking ability to supports.",
	version = "0.5",
	url = "https://github.com/glubsy"
};

// Supports get one cloak charge, which lasts forever until it get broken by ennemy damage.
// If toggle is allowed, cloak doesn't turn itself back on by itself (if moving after standing still)
// and can be toggled off by the player at will.
// If anticamp is active, cloak gets disabled while the player stands still.

public void OnPluginStart()
{
	ghAntiCamping = CreateConVar("nt_cloak_anticamp", "1", "Toggle cloak off automatically \
if a  player stands still.", _, true, 0.0, true, 1.0);
	ghReuseAllowed = CreateConVar("nt_cloak_allow_toggle", "1", "Allow toggling cloak on and off \
until it gets broken.", _, true, 0.0, true, 1.0);

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("game_round_end", OnRoundEnd);
	HookEvent("player_hurt", OnPlayerHurt/*, EventHookMode_Pre*/);

	if(!hMyWeapons && (hMyWeapons = FindSendPropInfo("CBasePlayer", "m_hMyWeapons")) == -1)
		ThrowError("Failed to obtain offset: \"m_hMyWeapons\"!");
}


public void OnMapStart()
{
	PrecacheSound(DENIEDSND, true);

	// seems to fix SV_StartSound: ^player/therm_off.wav not precached (0) error message
	PrecacheSound("player/therm_off.wav", true);
	PrecacheSound("^player/therm_off.wav", true);
	// PrecacheSound("sound/player/therm_off.wav", true);

	gbAntiCamp = GetConVarBool(ghAntiCamping);
	ToggleAllowed = GetConVarBool(ghReuseAllowed);
}


public Action OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	// avoid hooking first connection "spawn"
	if (GetClientTeam(client) < 2)
	{
		return Plugin_Continue;
	}

	// avoid hooking spectator spawns
	if (IsPlayerObserving(client))
	{
		return Plugin_Continue;
	}

	int iClass = GetEntProp(client, Prop_Send, "m_iClassType");

	if (iClass == 3)
	{
		gbIsSupport[client] = true;
		UsedCloakCharge[client] = false;
		gbBrokenCloak[client] = false;
		return Plugin_Continue;
	}

	gbIsSupport[client] = false;
	return Plugin_Continue;
}


public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	gbIsSupport[client] = false;

	if (gbAntiCamp)
		ghMobilityTimer[client] = INVALID_HANDLE
}


public void OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	if (!gbAntiCamp)
		return;

	for (int i = MaxClients; i; --i)
	{
		if (IsValidClient(i))
			ghMobilityTimer[i] = INVALID_HANDLE;
	}
}


public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	gbFreezeTime = true;
	flRoundStartTime = GetGameTime();
}


// Prevent accidentally hitting cloak while in freezetime
// TODO: try to check m_bFreezePeriod on neo_gamerules instead?
public void OnGameFrame()
{
	if(gbFreezeTime)
	{
		float gametime = GetGameTime();

		if((gametime - flRoundStartTime) >= 15.0)
			gbFreezeTime = false;
	}
}

public Action OnPlayerHurt(Event event, const char[] name, bool dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	// int health = GetEventInt(event, "health");

	if (!gbIsSupport[client])
		return Plugin_Continue;

	if (gbBrokenCloak[client])
		return Plugin_Continue;

	if (ToggleAllowed)
	{
		if (!gbIsCloaked[client])
			return Plugin_Continue;
	}
	else
	{
		if (!UsedCloakCharge[client])
			return Plugin_Continue;
	}

	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	#if !DEBUG
	if (!attacker || !IsValidClient(attacker))
		return Plugin_Continue;
	#endif

	if (GetClientTeam(client) == GetClientTeam(attacker))
		return Plugin_Continue;

	if (gbAntiCamp)
		ghMobilityTimer[client] = INVALID_HANDLE; // kill timer

	SetEntProp(client, Prop_Send, "m_iThermoptic", 0);

	gbBrokenCloak[client] = true;

	DenyCloakCommand(client);

	return Plugin_Continue;
}


public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (client == 0 || gbFreezeTime || !gbIsSupport[client])
		return Plugin_Continue;

	if (buttons & IN_THERMOPTIC)
	{
		if (!gbHeldKey[client])
		{
			gbHeldKey[client] = true;

			if (gbBrokenCloak[client])
			{
				DenyCloakCommand(client);
				return Plugin_Continue;
			}

			if (ToggleAllowed)
			{
				if (!gbIsCloaked[client])
				{
					SetEntProp(client, Prop_Send, "m_iThermoptic", 1);
					gbIsCloaked[client] = true;
					ToggleShadowOnWeapons(client);

					if (gbAntiCamp && ghMobilityTimer[client] == INVALID_HANDLE)
					{
						ghMobilityTimer[client] = CreateTimer(0.5, timer_CheckMobility,
						EntIndexToEntRef(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
					}
				}
				else
				{
					SetEntProp(client, Prop_Send, "m_iThermoptic", 0);
					gbIsCloaked[client] = false;

					if (gbAntiCamp && ghMobilityTimer[client] != INVALID_HANDLE)
						ghMobilityTimer[client] = INVALID_HANDLE; // kill timer
				}
			}
			else // !ToggleAllowed
			{
				if (!UsedCloakCharge[client])
				{
					SetEntProp(client, Prop_Send, "m_iThermoptic", 1);
					gbIsCloaked[client] = true;
					UsedCloakCharge[client] = true;
					ToggleShadowOnWeapons(client);

					if (gbAntiCamp && ghMobilityTimer[client] == INVALID_HANDLE)
					{
						ghMobilityTimer[client] = CreateTimer(0.5, timer_CheckMobility,
						EntIndexToEntRef(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
					}
				}
				else
				{
					DenyCloakCommand(client);
					return Plugin_Continue;
				}
			}
		}
	}
	else
	{
		gbHeldKey[client] = false;
	}
	return Plugin_Continue;
}


void DenyCloakCommand(int client)
{
	if (ToggleAllowed)
		PrintCenterText(client, "Your cloak has been broken!");
	else
		PrintCenterText(client, "You have aleady used your one-time only cloak.");

	giReceivingClients[0] = client;

	// emitting sound for this one client
	EmitSound(giReceivingClients, 1, DENIEDSND,
	SOUND_FROM_PLAYER, SNDCHAN_AUTO, 50,
	SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);

	int total = 0;
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (!IsClientInGame(i) || i == client)
			continue;
		giReceivingClients[total++] = i;
	}
	if (!total)
		return;

	// emitting for all others from the world
	EmitSound(giReceivingClients, total, DENIEDSND,
	SOUND_FROM_WORLD, SNDCHAN_AUTO, 40,
	SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
}


public Action timer_CheckMobility(Handle timer, int clientref)
{
	int client = EntRefToEntIndex(clientref);

	if (client < 0 || ghMobilityTimer[client] == INVALID_HANDLE)
		return Plugin_Stop;

	if (!IsValidClient(client) || !IsPlayerAlive(client) || gbBrokenCloak[client])
	{
		ghMobilityTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	if (!HasVelocity(client) || IsImmobile(client)) // we're immobile
	{
		if (gbIsCloaked[client])
		{
			SetEntProp(client, Prop_Send, "m_iThermoptic", 0);
			gbIsCloaked[client] = false;
		}

		if (!ToggleAllowed)
			return Plugin_Continue;
		else
		{	// we stop checking and wait for the player's next invocation of the cloak
			ghMobilityTimer[client] = INVALID_HANDLE;
			return Plugin_Stop;
		}
	}
	else if (!ToggleAllowed && !gbIsCloaked[client]) // we're moving
	{
		SetEntProp(client, Prop_Send, "m_iThermoptic", 1);
		gbIsCloaked[client] = true;
		return Plugin_Continue;
	}
	else
	{
		return Plugin_Continue;
	}
}


bool HasVelocity(int client)
{
	float vec;
	vec = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");

	#if DEBUG > 1
	PrintToServer("[cloak] client %N velocity %f", client, vec);
	#endif

	if (FloatCompare(vec, 0.0) == 0) // no velocity detected
		return false;

	return true; // we're _probably_ moving
}


// Weapon shadow are still cast when cloak is active, so we reduce them
// NOTE probably not worth setting them back on again, they still work just fine?
stock void ToggleShadowOnWeapons(int client)
{
	for(int slot = 0; slot <= 5; ++slot)
	{
		int weapon = GetEntDataEnt2(client, hMyWeapons + (slot * 4));

		if(!IsValidEntity(weapon))
			continue;

		DispatchKeyValue(weapon, "shadowcastdist", "3.0");
		// AcceptEntityInput(weapon, "DisableShadow");
	}
}


// Warning: upcon first connection, Health = 100, observermode = 0, and deadflag = 0!
stock bool IsPlayerObserving(int client)
{
	// For some reason, 1 health point means dead, but checking deadflag is probably more reliable!
	// Note: CPlayerResource also seems to keep track of players alive state (netprop)
	if (GetEntProp(client, Prop_Send, "m_iObserverMode") > 0 || IsPlayerReallyDead(client))
	{
		#if DEBUG > 1
		PrintToServer("[nt_cloak] Determined that %N is observing right now. \
m_iObserverMode = %d, deadflag = %d, Health = %d", client,
		GetEntProp(client, Prop_Send, "m_iObserverMode"),
		GetEntProp(client, Prop_Send, "deadflag"),
		GetEntProp(client, Prop_Send, "m_iHealth"));
		#endif
		return true;
	}
	return false;
}


stock bool IsPlayerReallyDead(int client)
{
	if (GetEntProp(client, Prop_Send, "deadflag") || GetEntProp(client, Prop_Send, "m_iHealth") <= 1)
		return true;
	return false;
}


bool VectorsEqual(float vec1[3], float vec2[3], float tolerance=0.0, bool squared=false)
{
	float distance = GetVectorDistance(vec1, vec2, squared);

	return distance <= (tolerance * tolerance);
}


bool IsImmobile(int client)
{
	float currentPos[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", currentPos);

	if (VectorsEqual(currentPos, gfCoordsBuffer[client], 2.0, true))
	{
		#if DEBUG
		PrintToServer("[cloak] %N seems immobile at {%f %f %f}",
		client, currentPos[0], currentPos[1], currentPos[2]);
		#endif
		// gfCoordsBuffer = currentCoords
		return true;
	}

	gfCoordsBuffer[client] = currentPos;
	return false;
}