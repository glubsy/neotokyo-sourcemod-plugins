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
bool gbCanCloak[NEO_MAX_CLIENTS+1];
float flRoundStartTime;
int giReceivingClients[NEO_MAX_CLIENTS];

Handle ghAntiCamping = INVALID_HANDLE;
bool gbAntiCamp;
Handle ghTimerCheckVelocity[NEO_MAX_CLIENTS+1] = {INVALID_HANDLE, ...};
int hMyWeapons;
bool gbIsCloaked[NEO_MAX_CLIENTS +1];

#define DENIEDSND "buttons/combine_button2.wav"

public Plugin:myinfo =
{
	name = "NEOTOKYO cloak tweaks",
	author = "glub",
	description = "Adds a one-time cloaking ability to supports.",
	version = "0.4",
	url = "https://github.com/glubsy"
};

// Supports get one cloak use, which lasts forever.
// However, it gets disabled permanently once they take ennemy damage.
// If anticamp is active, cloak gets disabled while the player stands still.

// FIXME? holding aim and hugging wall turns cloak off?
// -> improve immobility detection with coords
// -> allow turning it back on manually?

public void OnPluginStart()
{
	ghAntiCamping = CreateConVar("nt_cloak_anticamp", "1", "Place a light halo around \
immobile cloaked supports.", _, true, 0.0, true, 1.0);

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
		gbCanCloak[client] = true;
		return Plugin_Continue;
	}

	gbIsSupport[client] = false;
	gbCanCloak[client] = false; // FIXME not necessary
	return Plugin_Continue;
}


public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	gbIsSupport[client] = false;

	if (gbAntiCamp)
		ghTimerCheckVelocity[client] = INVALID_HANDLE
}


public void OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	if (!gbAntiCamp)
		return;

	for (int i = MaxClients; i; --i)
	{
		if (IsValidClient(i))
			ghTimerCheckVelocity[i] = INVALID_HANDLE;
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

	if (gbCanCloak[client])
		return Plugin_Continue;

	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (!attacker || !IsValidClient(attacker))
		return Plugin_Continue;

	if (GetClientTeam(client) == GetClientTeam(attacker))
		return Plugin_Continue;

	if (gbAntiCamp)
		ghTimerCheckVelocity[client] = INVALID_HANDLE;

	SetEntProp(client, Prop_Send, "m_iThermoptic", 0);

	return Plugin_Continue;
}


public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (client == 0 || gbFreezeTime || !gbIsSupport[client])
		return Plugin_Continue;

	if (buttons & IN_THERMOPTIC)
	{
		if (gbHeldKey[client])
		{
			buttons &= ~IN_THERMOPTIC;
		}
		else
		{
			gbHeldKey[client] = true;

			if (gbCanCloak[client])
			{
				SetEntProp(client, Prop_Send, "m_iThermoptic", 1);
				gbIsCloaked[client] = true;
				ToggleShadowOnWeapons(client);

				if (gbAntiCamp)
				{
					ghTimerCheckVelocity[client] = CreateTimer(0.5, timer_CheckVelocity,
					EntIndexToEntRef(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
				}

				gbCanCloak[client] = false;

				//PrintCenterText(client, "You have used your one-time only cloak.");
			}
			else
			{
				#if DEBUG
				int prop = GetEntProp(client, Prop_Send, "m_iThermoptic");
				SetEntProp(client, Prop_Send, "m_iThermoptic", prop ? 0 : 1);
				gbIsCloaked[client] = false;
				if (gbAntiCamp)
					ghTimerCheckVelocity[client] = INVALID_HANDLE;
				gbCanCloak[client] = true;
				return Plugin_Continue;
				#endif

				if (gbAntiCamp && ghTimerCheckVelocity[client] != INVALID_HANDLE)
				{
					// KillTimer(ghTimerCheckVelocity[client]);
					ghTimerCheckVelocity[client] = INVALID_HANDLE;
					SetEntProp(client, Prop_Send, "m_iThermoptic", 0);
					gbIsCloaked[client] = false;
					return Plugin_Continue;
				}

				SetEntProp(client, Prop_Send, "m_iThermoptic", 0);
				gbIsCloaked[client] = false;
				DenyCloakCommand(client);
				return Plugin_Continue;
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


public Action timer_CheckVelocity(Handle timer, int clientref)
{
	int client = EntRefToEntIndex(clientref);

	if (client < 0 || ghTimerCheckVelocity[client] == INVALID_HANDLE)
		return Plugin_Stop;

	if (!IsValidClient(client) || !IsPlayerAlive(client))
	{
		ghTimerCheckVelocity[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	float vec;
	vec = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");

	#if DEBUG > 1
	PrintToServer("[cloak] client %N velocity %f", client, vec);
	#endif

	if (FloatCompare(vec, 0.0) == 0) // we're immobile
	{
		if (gbIsCloaked[client])
		{
			SetEntProp(client, Prop_Send, "m_iThermoptic", 0);
			gbIsCloaked[client] = false;
		}
	}
	else // moving
	{
		if (!gbIsCloaked[client])
		{
			SetEntProp(client, Prop_Send, "m_iThermoptic", 1);
			gbIsCloaked[client] = true;
		}
	}

	return Plugin_Continue;
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
