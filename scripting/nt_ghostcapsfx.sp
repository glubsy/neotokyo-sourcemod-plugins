#include <sourcemod>
#include <sdktools>
#include <neotokyo>
#include <clientprefs>
#pragma semicolon 1
#pragma newdecls required
#define DEBUG 0
#define MAX_SOUND_OCCURENCES 30
#define MAX_ANNOUNCER_OCCURENCES 6
#define MAX_FUZZ_OCCURENCES 3

#define PLUGIN_VERSION	"0.24"

int ghost, ghostCarrier, ghostCarrierTeam;
bool g_bGhostIsCaptured;
bool g_bEndOfRound;
int g_iTickCount = 95;
bool g_bGhostIsHeld;
float g_fFuzzRepeatDelay = 0.0;
float g_vecOrigin[3];

Handle convar_ghostexplodes, convar_ghostexplosiondamages, convar_roundtimelimit,
convar_nt_doublecap_version, convar_nt_ghostcap_version, convar_ghost_sounds_enabled = INVALID_HANDLE;
Handle GhostTimer[MAX_SOUND_OCCURENCES] = { INVALID_HANDLE, ...};
Handle AnnouncerTimer[MAX_ANNOUNCER_OCCURENCES] = { INVALID_HANDLE, ...};
Handle FuzzTimer[MAX_FUZZ_OCCURENCES] = { INVALID_HANDLE, ...};
Handle TimerStarter[2] = { INVALID_HANDLE, ... };
Handle g_PropPrefCookie = INVALID_HANDLE; // handle to client preferences
bool g_optedout[MAXPLAYERS+1];
int g_soundsEnabledClient[MAXPLAYERS+1];
int g_numClients;

char g_sRadioChatterSoundEffect[][] =
{
	"ambient/levels/prison/radio_random1.wav",
	"ambient/levels/prison/radio_random2.wav",
	"ambient/levels/prison/radio_random3.wav",
	"ambient/levels/prison/radio_random4.wav",
	"ambient/levels/prison/radio_random5.wav",
	"ambient/levels/prison/radio_random6.wav",
	"ambient/levels/prison/radio_random7.wav",
	"ambient/levels/prison/radio_random8.wav",
	"ambient/levels/prison/radio_random9.wav",
	"ambient/levels/prison/radio_random10.wav",
	"ambient/levels/prison/radio_random11.wav",
	"ambient/levels/prison/radio_random12.wav",
	"ambient/levels/prison/radio_random13.wav",
	"ambient/levels/prison/radio_random14.wav",
	"ambient/levels/prison/radio_random15.wav"
};
char g_sSoundEffect[][] =
{
	"weapons/cguard/charging.wav",
	"weapons/stunstick/alyx_stunner1.wav",
	"weapons/stunstick/alyx_stunner2.wav",
	"weapons/stunstick/spark1.wav",
	"weapons/stunstick/spark2.wav",
	"weapons/stunstick/spark3.wav",
	"weapons/grenade/tick1.wav",
	"weapons/explode3.wav",
	"weapons/explode4.wav",
	"weapons/explode5.wav",
	"buttons/button17.wav",
	"HL1/fvox/fuzz.wav",
	"HL1/fvox/warning.wav",
	"HL1/fvox/targetting_system.wav",
	"HL1/fvox/acquired.wav"
};


public Plugin myinfo =
{
	name = "NEOTOKYO° Ghost cap special effect",
	author = "glub",
	description = "SFX on ghost capture event",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
};

//FIXME: ghost doesn't explode when carried AND not currently primary weapon AND neo_restart_this 1 (probably not really important)
//TODO: make clientpref to disable

public void OnPluginStart()
{
	convar_ghost_sounds_enabled = CreateConVar("nt_ghost_sounds_enabled", "1", "Ghost emits sounds when held and captured.", FCVAR_SPONLY, true, 0.0, true, 1.0);
	convar_ghostexplodes = CreateConVar("nt_ghostexplodes", "1", "Ghost explodes on removal", FCVAR_SPONLY, true, 0.0, true, 1.0);
	convar_ghostexplosiondamages = CreateConVar("nt_ghostexplosiondamages", "1", "Explosion from ghost damages players", FCVAR_SPONLY, true, 0.0, true, 1.0);


	HookEvent("game_round_start", OnRoundStart);

	convar_roundtimelimit = FindConVar("neo_round_timelimit");

	convar_nt_doublecap_version = FindConVar("nt_doublecap_version");
	convar_nt_ghostcap_version = FindConVar("sm_ntghostcap_version");

	RegConsoleCmd("sm_sounds_nothx", Command_Hate_Sounds_Toggle, "Toggle your preference to not hear custom ghost capture sound effect.");
	g_PropPrefCookie = RegClientCookie("no-sounds-plz", "Asked for no ghost capture sound effects.", CookieAccess_Public);

	if(convar_nt_ghostcap_version == INVALID_HANDLE)
		ThrowError("[nt_ghostcapsfx] Couldn't find nt_ghostcap plugin. Wrong version? Aborting.");
	if(GetConVarFloat(convar_nt_ghostcap_version) < 1.70000000)
		ThrowError("[nt_ghostcapsfx] nt_ghostcap plugin is outdated (version is %f and should be at least 1.6)! Aborting.", GetConVarFloat(convar_nt_ghostcap_version));

	// currently we need doublecap to remove the ghost properly and stuff
	if(convar_nt_doublecap_version == INVALID_HANDLE)
		ThrowError("[nt_ghostcapsfx] Couldn't find nt_doublecap plugin. Wrong version? Aborting.");
	// We need the version of nt_doublecap where the ghost is removed with RemoveEdict(), not AcceptEntityInput() otherwise they will crash the server!
	if(GetConVarFloat(convar_nt_doublecap_version) < 0.43)
		ThrowError("[nt_ghostcapsfx] nt_doublecap plugin is outdated (version is %f and should be at least 0.43)! Aborting.", GetConVarFloat(convar_nt_doublecap_version));
}

public void OnConfigsExecuted()
{
	for(int snd = 0; snd < sizeof(g_sRadioChatterSoundEffect); snd++)
	{
		PrecacheSound(g_sRadioChatterSoundEffect[snd], true);
	}
	for(int snd = 0; snd < sizeof(g_sSoundEffect); snd++)
	{
		PrecacheSound(g_sSoundEffect[snd], true);
	}
}


//==================================
//		Client preferences
//==================================


public void OnClientPutInServer(int client)
{
	if(client && !IsFakeClient(client))
	{
		CreateTimer(50.0, timer_AdvertiseHelp, client);
	}
}


public Action timer_AdvertiseHelp(Handle timer, int client)
{
	if (!IsValidClient(client))
		return Plugin_Handled;
	PrintToChat(client, "[nt_ghostcapsfx] You can disable extra ghost warning sounds with !sm_sounds_nothx");
	return Plugin_Handled;
}


public void OnClientCookiesCached(int client)
{
	ProcessCookies(client);
}


public void OnClientPostAdminCheck(int client)
{
	if(!GetConVarBool(convar_ghost_sounds_enabled))
	{
		//g_optedout[client] = false;
		return;
	}

	if (AreClientCookiesCached(client))
	{
		ProcessCookies(client);
		//CreateTimer(120.0, DisplayNotification, client);
		return;
	}
}


public void OnClientDisconnect(int client)
{
	if(GetConVarBool(convar_ghost_sounds_enabled))
	{
		g_optedout[client] = false;
		UpdateSoundEffectOptedOutArray();
	}
}


void ProcessCookies(int client)
{
	if (!IsValidClient(client))
		return;

	if(!FindClientCookie("no-sounds-plz"))
	{
		g_optedout[client] = false;
		UpdateSoundEffectOptedOutArray();

		CreateTimer(60.0, DisplayNotification, client);
		return;
	}

	char cookie[10];
	GetClientCookie(client, g_PropPrefCookie, cookie, sizeof(cookie));

	if (StrEqual(cookie, "senabled"))
	{
		g_optedout[client] = false;
		UpdateSoundEffectOptedOutArray();
		return;
	}
	else if (StrEqual(cookie, "sdisabled"))
	{
		g_optedout[client] = true;
		UpdateSoundEffectOptedOutArray();
		return;
	}
	return;
}


public Action DisplayNotification(Handle timer, int client)
{
	if(client > 0 && IsClientConnected(client) && IsClientInGame(client))
	{
		if(!g_optedout[client])
		{
			PrintToChat(client, 	"[sm_ghostcapsfx] You can toggle hearing ghost sound effects by typing !sounds_nothx");
			PrintToConsole(client, 	"\n[sm_ghostcapsfx] You can toggle hearing ghost sound effects by typing sm_sounds_nothx\n");
		}
	}
	return Plugin_Handled;
}


public Action Command_Hate_Sounds_Toggle(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	// if(!FindClientCookie("no-props-plz")) // this might not be working, REMOVE
	// {
	// 	g_optedout[client] = true;
	// 	SetClientCookie(client, g_PropPrefCookie, "sdisabled");
	// 	ReplyToCommand(client, "Your preference has been recorded. You don't like sounds.");
	// 	UpdateSoundEffectOptedOutArray();
	// 	return Plugin_Handled;
	// }

	char cookie[10];
	GetClientCookie(client, g_PropPrefCookie, cookie, sizeof(cookie));

	if (StrEqual(cookie, "sdisabled"))
	{
		SetClientCookie(client, g_PropPrefCookie, "senabled");
		g_optedout[client] = false;
		ReplyToCommand(client, "Your preference has been recorded. You do like extra sounds after all.");
		ShowActivity2(client, "[sm_ghostcapsfx] ", "%s opted back in.", client);
		LogAction(client, -1, "[sm_ghostcapsfx] \"%L\" opted back in.", client);
		UpdateSoundEffectOptedOutArray();
		return Plugin_Handled;
	}
	else // was enabled, or not yet set
	{
		SetClientCookie(client, g_PropPrefCookie, "sdisabled");
		g_optedout[client] = true;
		ReplyToCommand(client, "You preference has been recorded. You don't like extra sounds.");
		UpdateSoundEffectOptedOutArray();
		ShowActivity2(client, "[sm_ghostcapsfx] ", "%s opted out.", client);
		LogAction(client, -1, "[sm_ghostcapsfx] \"%L\" opted out.", client);
		return Plugin_Handled;
	}
}


bool HasAnyoneOptedOut()
{
	for (int i = 1; i < MaxClients; i++)
	{
		if (IsValidClient(i) && g_optedout[i])
			return true;
	}
	return false;
}


void UpdateSoundEffectOptedOutArray()
{
	int index = 0;
	int arraySize = sizeof(g_soundsEnabledClient);

	for (int thisClient = 1; thisClient <= MaxClients; thisClient++)
	{
		// Reached the max size of array
		if (index == arraySize)
			break;

		if (IsValidClient(thisClient) && !HatesSounds(thisClient))
		{
			g_soundsEnabledClient[index++] = thisClient;
		}
	}

	g_numClients = index;
}


bool HatesSounds(int client)
{
	if (IsValidClient(client) && !g_optedout[client])
		return false;
	return true;
}


public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	g_bGhostIsHeld = false;
	g_fFuzzRepeatDelay = 0.0;

	if(!GetConVarBool(convar_ghostexplodes))
		return;

	g_bEndOfRound = false;
	g_iTickCount = 95;

	for(int i = 0; i < MAX_SOUND_OCCURENCES; i++)
	{
		//killing all remaining timers for sound effects
		if(GhostTimer[i] != INVALID_HANDLE)
		{
			KillTimer(GhostTimer[i]);
			GhostTimer[i] = INVALID_HANDLE;
		}
	}
	#if DEBUG
	char clientname[MAX_NAME_LENGTH];
	for (int i=1; i<MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;
		if (g_optedout[i])
		{
			GetClientName(i, clientname, sizeof(clientname));
			PrintToServer("Client %s has opted out.", clientname);
		}
		else
		{
			GetClientName(i, clientname, sizeof(clientname));
			PrintToServer("Client %s has sound effects active.", clientname);
		}
	}
	#endif

	GhostTimer[0] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 3.8, timer_SoundEffect0, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[1] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 33.0, timer_SoundEffect1, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //30 sec before timeout
	GhostTimer[2] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 26.0, timer_SoundEffect1, 2, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //sparks
	GhostTimer[3] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 21.0, timer_SoundEffect1, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[4] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 16.0, timer_SoundEffect1, 4, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[5] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 12.5, timer_SoundEffect1, 5, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[6] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 11.0, timer_SoundEffect1, 6, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[7] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 10.8, timer_SoundEffect1, 7, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[8] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 10.0, timer_SoundEffect1, 8, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[9] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 4.8, timer_SoundEffect1, 9, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //sparks inbetween ticks
	GhostTimer[10] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 5.3, timer_SoundEffect1, 10, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[11] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 6.5, timer_SoundEffect1, 11, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[12] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 8.0, timer_SoundEffect3, 12, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //beeps countdown
	GhostTimer[13] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 7.0, timer_SoundEffect3, 13, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[14] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 6.0, timer_SoundEffect3, 14, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[15] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 5.0, timer_SoundEffect3, 15, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[16] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 4.0, timer_SoundEffect3, 16, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[17] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 3.0, timer_SoundEffect3, 17, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[18] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 2.0, timer_SoundEffect3, 18, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[19] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 1.0, timer_SoundEffect3, 19, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //end beeps countdown
	GhostTimer[20] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 0.0, timer_SoundEffect1, 20, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //crazy sparks
	GhostTimer[21] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 0.3, timer_SoundEffect1, 21, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[22] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 0.4, timer_SoundEffect1, 22, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[23] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 0.9, timer_SoundEffect1, 23, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[24] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 1.7, timer_SoundEffect1, 24, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[25] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.0, timer_SoundEffect2, 25, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //crazy ticks
	GhostTimer[26] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.1, timer_SoundEffect2, 26, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[27] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.2, timer_SoundEffect2, 27, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[28] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.3, timer_SoundEffect2, 28, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[29] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.4, timer_SoundEffect2, 29, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_SoundEffect0(Handle timer, int timernumber) //charging sound effect
{
	GhostTimer[timernumber] = INVALID_HANDLE;

	g_bEndOfRound = true; //it's ok to hook entity destruction for a bit

	if (!SetupSoundEffect())
		return Plugin_Stop;

	EmitSoundToAll(g_sSoundEffect[0], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.4, 100, -1, g_vecOrigin); //charging effect

	return Plugin_Stop;
}


public Action timer_SoundEffect1(Handle timer, int timernumber)  //sparks sound effect
{
	GhostTimer[timernumber] = INVALID_HANDLE;

	if (!SetupSoundEffect())
		return Plugin_Stop;

	if (HasAnyoneOptedOut())
		EmitSound(g_soundsEnabledClient, g_numClients, g_sSoundEffect[GetRandomInt(3,5)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, GetRandomInt(90, 110), -1, g_vecOrigin); //sparks
	else
		EmitSoundToAll(g_sSoundEffect[GetRandomInt(3,5)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, GetRandomInt(90, 110), -1, g_vecOrigin); //sparks

	return Plugin_Stop;
}


public Action timer_SoundEffect2(Handle timer, int timernumber) //grenade tick sound effect
{
	GhostTimer[timernumber] = INVALID_HANDLE;

	if (!SetupSoundEffect())
		return Plugin_Stop;

	EmitSoundToAll(g_sSoundEffect[6], SOUND_FROM_WORLD, SNDCHAN_AUTO, 90, SND_NOFLAGS, SNDVOL_NORMAL, g_iTickCount, -1, g_vecOrigin); //ticks
	g_iTickCount += 5;

	return Plugin_Stop;
}


public Action timer_SoundEffect3(Handle timer, int timernumber) //beeps countdown
{
	GhostTimer[timernumber] = INVALID_HANDLE;

	if (!SetupSoundEffect())
		return Plugin_Stop;

	EmitSoundToAll(g_sSoundEffect[10], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.5, g_iTickCount, -1, g_vecOrigin); //beeps
	g_iTickCount += 5;

	return Plugin_Stop;
}


bool SetupSoundEffect()
{
	if (g_bGhostIsCaptured)
		return false;

	if (!IsValidEntity(ghost))
	{
		#if DEBUG
		PrintToServer("[sm_ghostcapsfx] ghost entity was not valid! index: %d", ghost);
		#endif
		return false;
	}

	int carrier = GetEntPropEnt(ghost, Prop_Data, "m_hOwnerEntity");

	if (MaxClients > carrier > 0)
	{
		GetEntPropVector(carrier, Prop_Send, "m_vecOrigin", g_vecOrigin);
		#if DEBUG
		PrintToServer("[sm_ghostcapsfx] SetupSoundEffect(), client must be a player at pos: %f %f %f", g_vecOrigin[0], g_vecOrigin[1], g_vecOrigin[2]);
		#endif
	}
	else
	{
		GetEntPropVector(ghost, Prop_Send, "m_vecOrigin", g_vecOrigin);
		#if DEBUG
		PrintToServer("[sm_ghostcapsfx] SetupSoundEffect(), ghost must be on the ground at pos: %f %f %f", g_vecOrigin[0], g_vecOrigin[1], g_vecOrigin[2]);
		#endif
	}

	g_vecOrigin[2] += 10;
	return true;
}


public void OnGhostSpawn(int entity)
{
	ghost = entity;
	g_bGhostIsCaptured = false;
	g_bGhostIsHeld = false;
}


public void OnGhostCapture(int client)
{
	g_bGhostIsCaptured = true;
	g_bGhostIsHeld = false;

	EmmitCapSound(client);

	CreateTimer(6.1, timer_EmitRadioChatterSound, client);
	CreateTimer(6.4, timer_EmitRadioChatterSound, client);
	CreateTimer(6.7, timer_EmitRadioChatterSound, client);
	CreateTimer(6.9, timer_EmitRadioChatterSound, client);
	CreateTimer(7.3, timer_EmitRadioChatterSound, client);
	CreateTimer(7.6, timer_EmitRadioChatterSound, client);


	CreateTimer(1.0, timer_DoSparks, client);
	CreateTimer(1.5, timer_DoSparks, client);
	CreateTimer(2.0, timer_DoSparks, client);
	CreateTimer(2.2, timer_DoSparks, client);
	CreateTimer(2.5, timer_DoSparks, client);
	CreateTimer(2.9, timer_DoSparks, client);
	CreateTimer(6.1, timer_DoSparks, client);
	CreateTimer(7.0, timer_DoSparks, client);
	CreateTimer(8.0, timer_DoSparks, client);
	CreateTimer(9.0, timer_DoSparks, client);
	CreateTimer(10.0, timer_DoSparks, client);
	CreateTimer(11.0, timer_DoSparks, client);
}


public void OnGhostPickUp(int client)
{
	g_bGhostIsHeld = true;

	ghostCarrier = client;

	ghostCarrierTeam = GetClientTeam(ghostCarrier);


	TimerStarter[0] = CreateTimer(0.0, timer_CreateAnnouncerTimers, 0, TIMER_FLAG_NO_MAPCHANGE);
	TimerStarter[1] = CreateTimer(g_fFuzzRepeatDelay + 15.0, timer_CreateFuzzTimers, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	g_fFuzzRepeatDelay = 10.0;

	if(TimerStarter[1] != INVALID_HANDLE)
		TriggerTimer(TimerStarter[1]);
}


public void OnGhostDrop(int client)
{
	g_bGhostIsHeld = false;
	ghostCarrier = -1;
	g_fFuzzRepeatDelay = 0.0;

	for(int i; i < sizeof(AnnouncerTimer); i++)
	{
		if(AnnouncerTimer[i] != INVALID_HANDLE)
		{
			KillTimer(AnnouncerTimer[i]);
			AnnouncerTimer[i] = INVALID_HANDLE;
		}
	}

	for(int i; i < sizeof(TimerStarter); i++)
	{
		if(TimerStarter[i] != INVALID_HANDLE)
		{
			KillTimer(TimerStarter[i]);
			TimerStarter[i] = INVALID_HANDLE;
		}
	}
}


public Action timer_CreateFuzzTimers(Handle timer, int timerindex)
{
	for(int i; i < sizeof(FuzzTimer); i++)
	{
		if(FuzzTimer[i] != INVALID_HANDLE)
		{
			KillTimer(FuzzTimer[i]);
			FuzzTimer[i] = INVALID_HANDLE;
		}
	}

	FuzzTimer[0] = CreateTimer(1.0, timer_EmmitPickupSound1, 0, TIMER_FLAG_NO_MAPCHANGE);
	FuzzTimer[1] = CreateTimer(1.5, timer_EmmitPickupSound1, 1, TIMER_FLAG_NO_MAPCHANGE);
	FuzzTimer[2] = CreateTimer(2.0, timer_EmmitPickupSound1, 2, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


public Action timer_CreateAnnouncerTimers(Handle timer, int timerindex)
{
	TimerStarter[timerindex] = INVALID_HANDLE;

	for(int i; i < sizeof(AnnouncerTimer); i++)
	{
		if(AnnouncerTimer[i] != INVALID_HANDLE)
		{
			KillTimer(AnnouncerTimer[i]);
			AnnouncerTimer[i] = INVALID_HANDLE;
		}
	}

	AnnouncerTimer[0] = CreateTimer(3.5, timer_EmmitPickupSound2, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //2 = warning
	AnnouncerTimer[1] = CreateTimer(4.5, timer_EmmitPickupSound2, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //2 = warning
	AnnouncerTimer[2] = CreateTimer(6.5, timer_EmmitPickupSound3, 2, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //3 = automatic targetting system
	AnnouncerTimer[3] = CreateTimer(10.3, timer_EmmitPickupSound4, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //4 = acquired
	AnnouncerTimer[4] = CreateTimer(12.0, timer_EmmitPickupSound2, 4, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //2 = warning
	AnnouncerTimer[5] = CreateTimer(13.0, timer_EmmitPickupSound2, 5, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //2 = warning
}



public Action timer_EmmitPickupSound1(Handle timer, int timerindex) //fuzz
{
	FuzzTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld)
		return Plugin_Stop;

	for(int client = 1; client < MaxClients; client++)
	{
		if(!IsClientInGame(client))
			continue;

		if(client == ghostCarrier)
			continue;

		if (g_optedout[client]) // no wants soundz
			continue;

		if(!IsPlayerAlive(client))
		{
			EmitSoundToClient(client, g_sSoundEffect[11], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 60, SND_NOFLAGS, 0.2, 100, -1, NULL_VECTOR, NULL_VECTOR);
			continue;
		}

		EmitSoundToClient(client, g_sSoundEffect[11], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.4, 100, -1, NULL_VECTOR, NULL_VECTOR);
	}

	return Plugin_Stop;
}

public Action timer_EmmitPickupSound2(Handle timer, int timerindex) //warning
{
	AnnouncerTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld)
		return Plugin_Stop;

	for(int client = 1; client < MaxClients; client++)
	{
		if(!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;

		if (g_optedout[client]) // no wants soundz
			continue;

		if(client == ghostCarrier)
			continue;

		if(GetClientTeam(client) == ghostCarrierTeam)
			continue;

		EmitSoundToClient(client, g_sSoundEffect[12], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, 100, -1, NULL_VECTOR, NULL_VECTOR);
	}

	return Plugin_Stop;
}


public Action timer_EmmitPickupSound3(Handle timer, int timerindex) //automatic target aquisition system
{
	AnnouncerTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld)
		return Plugin_Stop;

	for(int client = 1; client < MaxClients; client++)
	{
		if(!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;

		if (g_optedout[client]) // no wants soundz
			continue;

		if(client == ghostCarrier)
			continue;

		EmitSoundToClient(client, g_sSoundEffect[13], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, 100, -1, NULL_VECTOR, NULL_VECTOR);
	}


	return Plugin_Stop;
}


public Action timer_EmmitPickupSound4(Handle timer, int timerindex) //acquired
{
	AnnouncerTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld)
		return Plugin_Stop;

	for(int client = 1; client < MaxClients; client++)
	{
		if(!IsClientInGame(client) || !IsPlayerAlive(client))
			continue;

		if (g_optedout[client]) // no wants soundz
			continue;

		if(client == ghostCarrier)
			continue;

		EmitSoundToClient(client, g_sSoundEffect[14], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, 100, -1, NULL_VECTOR, NULL_VECTOR);
	}

	return Plugin_Stop;
}



public Action timer_DoSparks(Handle timer, int client)
{
	DoSparkleEffect(client);
}


public void DoSparkleEffect(int client)
{
	if(!IsClientInGame(client))
		return;

	float vecOrigin[3], vecEyeAngles[3];
	GetClientEyePosition(client, vecOrigin);
	vecOrigin[2] += 10.0;
	vecEyeAngles[2] = 1.0;

	//TE_SetupSparks(vecOrigin, vecEyeAngles, 1, 1);

	TE_Start("Sparks");
	TE_WriteFloat("m_vecOrigin[0]", vecOrigin[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecOrigin[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecOrigin[2]);
	TE_WriteNum("m_nMagnitude", 50);
	TE_WriteNum("m_nTrailLength", 8);
	TE_WriteVector("m_vecDir", vecEyeAngles);
	TE_SendToAll();
}


public void OnEntityDestroyed(int entity)
{
	if(!IsValidEntity(entity) || entity < MaxClients)
		return;

	if(!GetConVarBool(convar_ghostexplodes))
		return;

	if(!g_bEndOfRound)
		return;

	char classname[50];
	GetEntityClassname(entity, classname, sizeof(classname));

	#if DEBUG > 0
	PrintToServer("[sm_ghostcapsfx] entity destroyed %s and id is: %d", classname, entity);
	#endif

    if (StrEqual(classname, "weapon_ghost"))
    {
		#if DEBUG
		int carrier = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
		PrintToServer("[sm_ghostcapsfx] carrier of %s (%d) entity (%d) was: %d.", classname, ghost, entity, carrier);
		#endif
		g_bGhostIsHeld = false;
		Explode(entity);
    }
}


void Explode(int entity)
{
	#if DEBUG
	PrintToServer("[sm_ghostcapsfx] Explode(%d)!", entity);
	#endif

	int carrier = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	if(MaxClients > carrier > 0)
		entity = carrier;

	#if DEBUG
	PrintToServer("[sm_ghostcapsfx] carrier is %d.", carrier);
	#endif

	float pos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	#if DEBUG
	PrintToServer("[sm_ghostcapsfx] pos of %d is %f %f %f.", entity, pos[0], pos[1], pos[2]);
	#endif

	int explosion;

	if(g_bGhostIsCaptured)
		explosion = CreateEntityByName("env_physexplosion");
	if(!g_bGhostIsCaptured && GetConVarBool(convar_ghostexplosiondamages))
		explosion = CreateEntityByName("env_explosion");
	else
		explosion = CreateEntityByName("env_physexplosion");

	//DispatchKeyValueFloat(explosion, "magnitude", GetConVarFloat(cv_JarateKnockForce));
	DispatchKeyValue(explosion, "iMagnitude", "400");
	//DispatchKeyValue(explosion, "spawnflags", "18428");
	DispatchKeyValue(explosion, "spawnflags", "0");
	DispatchKeyValue(explosion, "iRadiusOverride", "256");

	if ( DispatchSpawn(explosion) )
	{
		#if DEBUG
		PrintToServer("[sm_ghostcapsfx] DispatchSpawn(explosion) was true.");
		#endif
		EmitExplosionSound(explosion, pos);

		if (IsValidClient(carrier))
			SetEntPropEnt(explosion, Prop_Data, "m_hOwnerEntity", carrier);
		ActivateEntity(explosion);
		TeleportEntity(explosion, pos, NULL_VECTOR, NULL_VECTOR);
		AcceptEntityInput(explosion, "Explode");
		AcceptEntityInput(explosion, "Kill");

		float dir[3] = {0.0, 0.0, 1.0};
		TE_SetupSparks(pos, dir, 50, 8);
		TE_SendToAll();
	}

	g_bEndOfRound = false; //don't check for destroyed entities anymore as round is about to restart (lots of them and too verbose)
}


public void EmitExplosionSound(int entity, float position[3])
{
	#if DEBUG
	PrintToServer("EmitExplosionSound at %f %f %f,", position[0], position[1], position[2]);
	#endif
	EmitSoundToAll(g_sSoundEffect[GetRandomInt(7, 9)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 85, SND_NOFLAGS, 0.7, GetRandomInt(85, 110), -1, position, NULL_VECTOR);
}




public Action timer_EmitRadioChatterSound(Handle timer, int client)
{
	if(!IsValidEntity(client))
		return;

	float vecOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[2] += 20.0;


	if (!HasAnyoneOptedOut())
		EmitSoundToAll(g_sRadioChatterSoundEffect[GetRandomInt(0, sizeof(g_sRadioChatterSoundEffect) -1)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 130, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, NULL_VECTOR);
	else
		EmitSound(g_soundsEnabledClient, g_numClients, g_sRadioChatterSoundEffect[GetRandomInt(0, sizeof(g_sRadioChatterSoundEffect) -1)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 130, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, NULL_VECTOR);
}


void EmmitCapSound(int client)
{
	if(!IsValidEntity(client))
		return;

	float vecOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[2] += 20.0;

	EmitSoundToAll(g_sSoundEffect[GetRandomInt(1,2)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 100, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, NULL_VECTOR);
}



public void OnMapEnd()
{
	int i;
	for(i = 0; i < MAX_SOUND_OCCURENCES; i++)
	{
		if(GhostTimer[i] != INVALID_HANDLE)
			GhostTimer[i] = INVALID_HANDLE;
	}

	for(i = 0; i < MAX_ANNOUNCER_OCCURENCES; i++)
	{
		if(AnnouncerTimer[i] != INVALID_HANDLE)
			AnnouncerTimer[i] = INVALID_HANDLE;
	}

	for(i = 0; i < sizeof(FuzzTimer); i++)
	{
		if(FuzzTimer[i] != INVALID_HANDLE)
			FuzzTimer[i] = INVALID_HANDLE;
	}

	for(i = 0; i < sizeof(TimerStarter); i++)
	{
		if(TimerStarter[i] != INVALID_HANDLE)
			TimerStarter[i] = INVALID_HANDLE;
	}
}