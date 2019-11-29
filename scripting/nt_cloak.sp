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
int giSpotLight[NEO_MAX_CLIENTS+1] = { -1, ...};
Handle ghTimerCheckVelocity[NEO_MAX_CLIENTS+1] = {INVALID_HANDLE, ...};
bool gbLightIsActive[NEO_MAX_CLIENTS+1];
int hMyWeapons;
int giLight[NEO_MAX_CLIENTS] = { -1, ...}
int giLightCursor;

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

	// fixes SV_StartSound: ^player/therm_off.wav not precached (0) error message
	PrecacheSound("player/therm_off.wav", true);

	gbAntiCamp = GetConVarBool(ghAntiCamping);

	if (gbAntiCamp)
	{
		for (int i = 0; i < sizeof(giLight); ++i)
		{
			giLight[i] = INVALID_ENT_REFERENCE;
		}
		giLightCursor = 0;
	}
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
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	gbIsSupport[client] = false;

	if (ghTimerCheckVelocity[client] != INVALID_HANDLE)
		CloseHandle(ghTimerCheckVelocity[client]);

	Cleanup(client);
}


// NOTE killing light_dynamic (or removing edict) doesn't remove them!
void Cleanup(int client)
{
	int entIndex = giSpotLight[client];

	if (entIndex > MaxClients && IsValidEntity(entIndex))
	{
		#if DEBUG
		char classname[50];
		GetEntityClassname(entIndex, classname, sizeof(classname));
		PrintToServer("[cloak] Cleanup for %N: %d (%s)",
		client, entIndex, classname);
		#endif

		MoveEntAway(entIndex);
	}
	giSpotLight[client] = -1;
}


void MoveEntAway(int entIndex)
{
	#if DEBUG
	PrintToServer("[cloak] Moving %d awayyy~", entIndex);
	#endif

	AcceptEntityInput(entIndex, "ClearParent");

	#if !DEBUG
	float vec[3] = {-999999.0, 999999.0, -999999.0};
	#else
	float vec[3] = {-3097.843750, 1288.937500, 140.031250};
	#endif

	TeleportEntity(entIndex, vec, NULL_VECTOR, NULL_VECTOR);

	#if !DEBUG
	int flags = GetEntProp(entIndex, Prop_Send, "m_fEffects");
	flags |= (1 << 5); // add EF_NODRAW
	SetEntProp(entIndex, Prop_Send, "m_fEffects", flags);

	AcceptEntityInput(entIndex, "TurnOff");

	// if we kill them, they toggle back on client-side!
	// this is an old known bug which we have to work around
	AcceptEntityInput(entIndex, "Kill");
	// RemoveEdict(entIndex);
	#endif
}


// public void OnEntityDestroyed(int entity)
// {
// 	for (int i = MaxClients; i; --i)
// 	{
// 		if (giSpotLight[i] == entity)
// 		{
// 			char classname[15];
// 			GetEntityClassname(entity, classname, sizeof(classname));
// 			PrintToServer("Calling moveaway on entity destroyed %d %s", entity, classname);
// 			MoveEntAway(entity);
// 		}
// 	}
// }


public void OnClientDisconnect(int client)
{
	Cleanup(client);
}


public void OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	for (int i = MaxClients; i; --i)
	{
		// Cleanup(i); // too late!?

		if (IsValidClient(i))
			ghTimerCheckVelocity[i] = INVALID_HANDLE;
	}
}


public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	gbFreezeTime = true;
	flRoundStartTime = GetGameTime();
	// SeekPreviousLightEnts();
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

	if (gbAntiCamp)
	{
		ghTimerCheckVelocity[client] = INVALID_HANDLE;
		ToggleHighlightEffect(client, true);
	}
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

				if (gbAntiCamp)
				{
					ToggleHighlightEffect(client);

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
				if (gbAntiCamp)
				{
					KillTimer(ghTimerCheckVelocity[client]);
					ToggleHighlightEffect(client, true);
				}
				gbCanCloak[client] = true;
				return Plugin_Continue;
				#endif

				if (GetEntProp(client, Prop_Send, "m_iThermoptic"))
				{
					SetEntProp(client, Prop_Send, "m_iThermoptic", 0);
					if (gbAntiCamp)
					{
						KillTimer(ghTimerCheckVelocity[client]);
						ToggleHighlightEffect(client, true);
					}
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


// For debug only, prefer the light_dynamic method for more control
// stock void DEBUG_ToggleBrightlightEffect(int client, bool turnoff=false)
// {
// 	int m_fEffects = GetEntProp(client , Prop_Data, "m_fEffects");

// 	if (turnoff)
// 	{
// 		m_fEffects &= ~(1 << 1);
// 		SetEntProp(client, Prop_Data, "m_fEffects", m_fEffects);
// 		return;
// 	}

// 	if (m_fEffects & (1 << 1))
// 	{
// 		m_fEffects &= ~(1 << 1); // 4 EF_DIMLIGHT 2 EF_BRIGHTLIGHT
// 	}
// 	else
// 	{
// 		m_fEffects |= (1 << 1);
// 	}
// 	SetEntProp(client, Prop_Data, "m_fEffects", m_fEffects);
// }


// We don't store them fore reuse anymore since we now kill them anyway
stock void StoreLightEnt(int light)
{
	if (giLightCursor > sizeof(giLight))
		ThrowError("Attempted to store a light_dynamic out of array bounds!")
	
	if (giLight[giLightCursor] != -1)
		++giLightCursor;
	
	#if DEBUG
	PrintToServer("[cloak] Storing light entref %d at cursor %d", light, giLightCursor);
	#endif

	giLight[giLightCursor] = light;
}

// stock void SeekPreviousLightEnts()
// {
// 	#if DEBUG
// 	PrintToServer("[cloak] Looking for previous light_dynamic in the map...");
// 	#endif

// 	int light = INVALID_ENT_REFERENCE;
// 	while ((light = FindEntityByClassname(light, "light_dynamic")) != INVALID_ENT_REFERENCE)
// 	{
// 		#if DEBUG
// 		PrintToServer("[cloak] Found light_dynamic %d, checking target...", light);
// 		#endif
// 		char targetname[10];
// 		GetEntPropString(light, Prop_Send, "m_target", targetname, sizeof(targetname));
// 		if (StrEqual("ntlight", targetname))
// 		{
// 			StoreLightEnt(EntIndexToEntRef(light));
// 		}
// 	}
// }


int GetLightEnt()
{
	if (giLightCursor == 0 && giLight[giLightCursor] == -1)
		return CreateLightPoint();

	int lightref = giLight[giLightCursor];
	giLight[giLightCursor] = -1;

	#if DEBUG
	PrintToServer("[cloak] Getting light ref %d at cursor %d", lightref, giLightCursor);
	#endif

	if (giLightCursor > 0)
		--giLightCursor;

	return lightref;
}


void ToggleHighlightEffect(int client, bool turnoff=false)
{
	if (!gbAntiCamp)
		return;

	if (giSpotLight[client] == -1)
	{
		giSpotLight[client] = GetLightEnt();

		#if DEBUG
		char classname[60];
		GetEntityClassname(giSpotLight[client], classname, sizeof(classname));
		PrintToServer("[cloak] GetLightEnt returned a %s.", classname);
		#endif

		MakeParent(giSpotLight[client], client);
	}

	if (giSpotLight[client] == -1)
	{
		ThrowError("Couldn't create a new light_dynamic entity! Aborting.")
		return;
	}

	if (turnoff)
	{
		AcceptEntityInput(giSpotLight[client], "TurnOff");
		gbLightIsActive[client] = false;
		#if DEBUG
		PrintToChatAll("[cloak] Light TurnOff for %N (%d), light %d", 
		client, client, giSpotLight[client]);
		#endif
		return;
	}

	if (!gbLightIsActive[client])
	{
		AcceptEntityInput(EntRefToEntIndex(giSpotLight[client]), "TurnOn");
		gbLightIsActive[client] = true;
		#if DEBUG
		PrintToChatAll("[cloak] Light TurnOn for %N (%d), light %d", 
		client, client, giSpotLight[client]);
		#endif
		ToggleShadowOnWeapons(client);
	}
}

// Weapon shadow are still cast when cloak is active, so we reduce them
// NOTE probably not worth setting them back on again, they still work just fine?
void ToggleShadowOnWeapons(int client)
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

	if (FloatCompare(vec, 0.0) == 0) // we're immobile, activate halo
		ToggleHighlightEffect(client, false);
	else if (gbLightIsActive[client])
		ToggleHighlightEffect(client, true);

	return Plugin_Continue;
}


// NOTE: use r_drawlights to debug
int CreateLightPoint()
{
	int lightEnt = CreateEntityByName("light_dynamic");

	#if DEBUG
	PrintToServer("[cloak] Created light_dynamic %d", lightEnt);
	#endif

	DispatchKeyValueFloat(lightEnt, "spotlight_radius", 5.0);
	DispatchKeyValueFloat(lightEnt, "distance", 40.0);
	DispatchKeyValue(lightEnt, "_inner_cone", "0"); // 0 = omnidirectional, 89
	DispatchKeyValue(lightEnt, "_cone", "0");  // 0 = omnidirectional, 89
	// DispatchKeyValue(lightEnt, "pitch","89");
	DispatchKeyValue(lightEnt, "_light", "150 150 220 90");
	DispatchKeyValue(lightEnt, "style", "11");
	// DispatchKeyValue(lightEnt, "target", "10");
	DispatchKeyValue(lightEnt, "brightness", "10");
	// DispatchKeyValue(lightEnt, "spawnflags", "1");

	DispatchSpawn(lightEnt);

	// if not using the grenade2 attachement only!
	// NOTE: other axes are world absolute
	// float vecOrigin[3];
	// vecOrigin[2] += 35.0; // +up -down
	// SetEntPropVector(lightEnt, Prop_Data, "m_vecOrigin", vecOrigin);

	return lightEnt;
}


void MakeParent(int entity, int parent)
{
	char name[10];
	Format(name, sizeof(name), "ntlight");
	DispatchKeyValue(entity, "targetname", name);

	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", parent);

	SetVariantString("!activator");
	if (!AcceptEntityInput(entity, "SetParent", parent, parent, 0))
		LogError("Failed to call SetParent on light_dynamic %d to %d", entity, parent);

	CreateTimer(0.1, timer_SetAttachement, entity);
}


// place light source slightly in front and close to the ground
public Action timer_SetAttachement(Handle timer, int entity)
{
	SetVariantString("lfoot"); // grenade2 or lfeet
	AcceptEntityInput(entity, "SetParentAttachment");

	float vecOrigin[3];
	// for grenade2
	// vecOrigin[0] -= 10.0; // - down + up
	// vecOrigin[1] = 0.0; // - left + right
	// vecOrigin[2] += 15.0; // + forward - backward

	// for none
	// vecOrigin[0] -= 6.0; // - right + left
	// vecOrigin[1] -= 10.0; // forward backward
	// vecOrigin[2] += 13.0; // + up - down

	// for lfoot
	vecOrigin[0] -= 16.0; // - up + down
	vecOrigin[1] += 3.0; // - backwards + forward
	vecOrigin[2] += 14.0; // - left + right

	SetEntPropVector(entity, Prop_Send, "m_vecOrigin", vecOrigin);

	return Plugin_Handled;
}