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
Handle gh_AntiCamping = INVALID_HANDLE;
int giSpotLight[NEO_MAX_CLIENTS+1];

#define DENIEDSND "buttons/combine_button2.wav"

public Plugin:myinfo =
{
	name = "NEOTOKYO cloak tweaks",
	author = "glub",
	description = "Adds a one-time cloaking ability to supports.",
	version = "0.3",
	url = "https://github.com/glubsy"
};

// Supports get one cloak use, which lasts forever.
// However, it gets disabled permanently once they take ennemy damage.

//TODO should be able to toggle it off (but can't turn it on again)

public void OnPluginStart()
{
	gh_AntiCamping = CreateConVar("nt_cloak_anticamp", "1", "Prevents supports\
 from camping while cloaked by making them glow.", _, true, 0.0, true, 1.0);

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("player_hurt", OnPlayerHurt/*, EventHookMode_Pre*/);

	RegConsoleCmd("sm_cloaktest", Command_Testlight, "DEBUG test.");

}

public void OnMapStart()
{
	PrecacheSound(DENIEDSND, true);

	// fixes SV_StartSound: ^player/therm_off.wav not precached (0) error message
	PrecacheSound("player/therm_off.wav", true);
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
	gbCanCloak[client] = false; // not necessary
	return Plugin_Continue;
}


public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	gbIsSupport[victim] = false;
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

	SetEntProp(client, Prop_Send, "m_iThermoptic", 0);
	ToggleHighlightEffect(client, true);
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
				#if DEBUG <= 1
				SetEntProp(client, Prop_Send, "m_iThermoptic", 1);
				ToggleHighlightEffect(client);
				gbCanCloak[client] = false;
				#endif
				PrintCenterText(client, "You have used your one-time only cloak.");
			}
			else
			{
				#if DEBUG
				int prop = GetEntProp(client, Prop_Send, "m_iThermoptic");
				SetEntProp(client, Prop_Send, "m_iThermoptic", prop ? 0 : 1);
				ToggleHighlightEffect(client, true);
				gbCanCloak[client] = true;
				return Plugin_Continue;
				#endif

				if (GetEntProp(client, Prop_Send, "m_iThermoptic"))
				{
					SetEntProp(client, Prop_Send, "m_iThermoptic", 0);
					ToggleHighlightEffect(client, true);
					return Plugin_Continue;
				}

				PrintCenterText(client, "You have aleady used your one-time only cloak.");
				giReceivingClients[0] = client;
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
					return Plugin_Continue;

				EmitSound(giReceivingClients, total, DENIEDSND,
				SOUND_FROM_PLAYER, SNDCHAN_AUTO, 50,
				SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL);
			}
		}
	}
	else
	{
		gbHeldKey[client] = false;
	}
	return Plugin_Continue;
}

// Warning: upcon first connection, Health = 100, observermode = 0, and deadflag = 0!
bool IsPlayerObserving(int client)
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


bool IsPlayerReallyDead(int client)
{
	if (GetEntProp(client, Prop_Send, "deadflag") || GetEntProp(client, Prop_Send, "m_iHealth") <= 1)
		return true;
	return false;
}


// For debug only, prefer the spot_light method for more control
stock void ToggleBrightlightEffect(int client, bool turnoff=false)
{
	int m_fEffects = GetEntProp(client , Prop_Data, "m_fEffects");

	if (turnoff)
	{
		m_fEffects &= ~(1 << 1);
		SetEntProp(client, Prop_Data, "m_fEffects", m_fEffects);
		return;
	}

	if (m_fEffects & (1 << 1))
	{
		m_fEffects &= ~(1 << 1); // 4 EF_DIMLIGHT 2 EF_BRIGHTLIGHT
	}
	else
	{
		m_fEffects |= (1 << 1);
	}
	SetEntProp(client, Prop_Data, "m_fEffects", m_fEffects);
}


public Action Command_Testlight(int client, int args)
{
	if (GetCmdArgs() >= 1 && giSpotLight[client] > MaxClients){
		PrintToChatAll("Killing %d", giSpotLight[client]);
		AcceptEntityInput(giSpotLight[client], "kill");
		giSpotLight[client] = -1;
		return Plugin_Handled;
	}

	static int active;
	active = active ? 0 : 1;
	ToggleHighlightEffect(client, active ? true : false);
	return Plugin_Handled;
}


void ToggleHighlightEffect(int client, bool turnoff=false)
{
	if (!GetConVarBool(gh_AntiCamping))
		return;

	CreateLightPoint(client);
	if (giSpotLight[client] <= 0)
		return;

	if (turnoff)
	{
		AcceptEntityInput(giSpotLight[client], "TurnOff");
		PrintToChatAll("TurnOff");
		return;
	}

	AcceptEntityInput(giSpotLight[client], "TurnOn");
	PrintToChatAll("TurnOn");
}

void CreateLightPoint(int client)
{
	if (giSpotLight[client] > 0)
		return;

	int spot_light = CreateEntityByName("light_dynamic");
	PrintToChatAll("created light_dynamic");

	DispatchKeyValueFloat(spot_light, "spotlight_radius", 10.0);
	DispatchKeyValueFloat(spot_light, "distance", 50.0);
	DispatchKeyValue(spot_light, "_inner_cone", "0");
	DispatchKeyValue(spot_light, "_cone", "0");
	DispatchKeyValue(spot_light, "_light", "150 150 150 70");
	DispatchKeyValue(spot_light, "style", "11");
	// DispatchKeyValue(spot_light, "target", "10");
	DispatchKeyValue(spot_light, "brightness", "5");
	// DispatchKeyValue(spot_light, "spawnflags", "1");

	SetVariantString("!activator");
	AcceptEntityInput(spot_light, "SetParent", client, client, 0);

	CreateTimer(0.1, timer_SetAttachement, spot_light);

	DispatchSpawn(spot_light);

	float vecOrigin[3];
	vecOrigin[2] -= 4.0;
	SetEntPropVector(spot_light, Prop_Send, "m_vecOrigin", vecOrigin);
	giSpotLight[client] = spot_light;
}

public Action timer_SetAttachement(Handle timer, int entity)
{
	SetVariantString("grenade2");
	AcceptEntityInput(entity, "SetParentAttachment");
	return Plugin_Handled;
}