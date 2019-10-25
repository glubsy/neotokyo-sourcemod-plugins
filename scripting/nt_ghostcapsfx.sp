#include <sourcemod>
#include <sdktools>
#include <neotokyo>
#include <clientprefs>
#pragma semicolon 1
#pragma newdecls required

#if !defined DEBUG
	#define DEBUG 0
#endif

#define SOUND_INSTANCES 31
#define MAX_ANNOUNCER_OCCURENCES 6
#define MAX_FUZZ_OCCURENCES 3
#define NEO_MAX_PLAYERS 32

int ghost, g_ghostCarrier, g_ghostCarrierTeam;
bool g_bGhostIsCaptured, g_bGhostIsHeld, g_bEndOfRound;
int g_iTickCount = 95;
float g_fFuzzRepeatDelay = 0.0;
float g_vecOrigin[3];

Handle convar_ghostexplodes, convar_ghostexplosiondamages, convar_roundtimelimit,
convar_nt_doublecap_version, convar_nt_ghostcap_version, convar_ghost_sounds_enabled = INVALID_HANDLE;

Handle GhostTimer[SOUND_INSTANCES] = { INVALID_HANDLE, ...};
Handle AnnouncerTimer[MAX_ANNOUNCER_OCCURENCES] = { INVALID_HANDLE, ...};
Handle FuzzTimer[MAX_FUZZ_OCCURENCES] = { INVALID_HANDLE, ...};
Handle g_hAnnouncerTimerStarter[2] = { INVALID_HANDLE, ... };

Handle g_PropPrefCookie = INVALID_HANDLE; // handle to cookie in DB
bool g_bWantsGhostSFX[NEO_MAX_PLAYERS+1];
int g_soundsEnabledClient[NEO_MAX_PLAYERS+1];
int g_numClients;
Handle KillGhostTimer = INVALID_HANDLE;

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
	version = "0.3",
	url = "https://github.com/glubsy"
};

//FIXME: ghost doesn't explode when carried AND not currently primary weapon AND neo_disable_tie is 1 (probably not really important)
// TODO: explode ghost on clock expiration, not 5 seconds after
//FIXME: seems that a remnant timer is activated as soon as the ghost gets picked up, or it's just the game delaying the orignal alarm sound.
// TODO: sound/gameplay/ghost_idle_loop.wav while being carried
// TODO: use sound/player/CPcaptured.wav for ghost capture sound
// TODO: redo all the emitgamesounds to use an array of affected clients instead (for the haters)
// TODO: add menu to toggle cookies


public void OnPluginStart()
{
	convar_ghost_sounds_enabled = CreateConVar("nt_ghost_sounds_enabled", "1", "Ghost emits sounds when held and captured.", FCVAR_SPONLY, true, 0.0, true, 1.0);
	convar_ghostexplodes = CreateConVar("nt_ghostexplodes", "1", "Ghost explodes on removal", FCVAR_SPONLY, true, 0.0, true, 1.0);
	convar_ghostexplosiondamages = CreateConVar("nt_ghostexplosiondamages", "1", "Explosion from ghost damages players", FCVAR_SPONLY, true, 0.0, true, 1.0);


	HookEvent("game_round_start", OnRoundStart);

	convar_roundtimelimit = FindConVar("neo_round_timelimit");

	convar_nt_doublecap_version = FindConVar("nt_doublecap_version");
	convar_nt_ghostcap_version = FindConVar("sm_ntghostcap_version");

	RegConsoleCmd("sm_ghostcapsfx_prefs", Command_Hate_Sounds_Toggle, "Toggle your preference to not hear custom ghost capture sound effect.");

	g_PropPrefCookie = FindClientCookie("wants-ghostcapfx");
	if (g_PropPrefCookie == INVALID_HANDLE)
		g_PropPrefCookie = RegClientCookie("wants-ghostcapfx", "Asked for no ghost capture sound effects.", CookieAccess_Public);

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


public void OnAllPluginsLoaded()
{
	// we need to remove doublecap plugin because we essentially do the same here with extra sparks
	Handle iterator = GetPluginIterator();
	if (iterator == INVALID_HANDLE)
		ThrowError("Couldn't get the plugin iterator!");

	Handle plugin;
	char buffer[35];
	char filename[PLATFORM_MAX_PATH];

	while(MorePlugins(iterator))
	{
		plugin = ReadPlugin(iterator);

		PluginStatus status = GetPluginStatus(plugin);
		if (status != Plugin_Running)
			continue;

		GetPluginInfo(plugin, PlInfo_Name, buffer, sizeof(buffer));
		if (StrContains(buffer, "Double cap prevention", false) != -1) // found doublecap plugin most likely
		{
			GetPluginFilename(plugin, filename, sizeof(filename));
			ServerCommand("sm plugins unload %s", filename);
			PrintToServer("[nt_ghostcapsfx] Unloaded %s because it is in conflict and does the same thing.", filename);
			break;
		}
	}
	CloseHandle(iterator);
}


//==================================
//		Client preferences
//==================================


public void OnClientPutInServer(int client)
{
	CreateTimer(50.0, timer_AdvertiseHelp, client);
}


public Action timer_AdvertiseHelp(Handle timer, int client)
{
	if (!IsValidClient(client) || !IsClientConnected(client))
		return Plugin_Stop;

	PrintToChat(client, "[nt_ghostcapsfx] You can disable extra ghost warning sounds with !ghostcapsfx_prefs");
	return Plugin_Stop;
}


public void OnClientCookiesCached(int client)
{
	ProcessCookies(client);
}


public void OnClientPostAdminCheck(int client)
{
	if(!GetConVarBool(convar_ghost_sounds_enabled))
	{
		//g_bWantsGhostSFX[client] = false;
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
		g_bWantsGhostSFX[client] = false;
		UpdateSoundEffectOptedOutArray();
	}
}


void ProcessCookies(int client)
{
	if (!IsValidClient(client))
		return;

	char cookie[2];
	GetClientCookie(client, g_PropPrefCookie, cookie, sizeof(cookie));

	if (cookie[0] != '\0') // we have a cookie
	{
		g_bWantsGhostSFX[client] = view_as<bool>(StringToInt(cookie));
	}
	else
	{
		//default to opted-out
		g_bWantsGhostSFX[client] = true;
	}

	UpdateSoundEffectOptedOutArray();
	CreateTimer(60.0, DisplayNotification, client);
	return;
}


public Action DisplayNotification(Handle timer, int client)
{
	if(client > 0 && IsClientConnected(client) && IsClientInGame(client))
	{
		if(g_bWantsGhostSFX[client])
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

	g_bWantsGhostSFX[client] = !g_bWantsGhostSFX[client];

	SetClientCookie(client, g_PropPrefCookie, (g_bWantsGhostSFX[client] ? "1" : "0"));

	ReplyToCommand(client, "[nt_ghostcapsfx] You have %s sound effects while ghost is held.",
	g_bWantsGhostSFX[client] ? "opted to hear" : "opted out of hearing");

	UpdateSoundEffectOptedOutArray();
	ShowActivity2(client, "[sm_ghostcapsfx] ", "%s opted %s.", client, g_bWantsGhostSFX[client] ? "back in" : "out" );
	LogAction(client, -1, "[sm_ghostcapsfx] \"%L\" opted %s.", client, g_bWantsGhostSFX[client] ? "back in" : "out");

	return Plugin_Handled;
}


bool HasAnyoneOptedOut()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !g_bWantsGhostSFX[i])
			return true;
	}
	return false;
}


void UpdateSoundEffectOptedOutArray()
{
	g_numClients = 0;
	int arraySize = sizeof(g_soundsEnabledClient);

	for (int thisClient = 1; thisClient <= MaxClients; thisClient++)
	{
		// Reached the max size of array
		if (g_numClients == arraySize)
			break;

		if (IsValidClient(thisClient) && IsClientConnected(thisClient) && g_bWantsGhostSFX[thisClient])
		{
			g_soundsEnabledClient[g_numClients++] = thisClient;
		}
	}
}


public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	g_bGhostIsHeld = false;
	g_fFuzzRepeatDelay = 0.0;

	if(!GetConVarBool(convar_ghostexplodes))
		return;

	g_bEndOfRound = false;
	g_iTickCount = 95;

	for(int i = 0; i < SOUND_INSTANCES; i++)
	{
		//killing all remaining timers for sound effects
		if(GhostTimer[i] != INVALID_HANDLE)
		{
			KillTimer(GhostTimer[i]);
			GhostTimer[i] = INVALID_HANDLE;
		}
	}
	#if DEBUG
	for (int i=1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;
		PrintToServer("[nt_ghostcapsfx] Client %N has %s.", i, (g_bWantsGhostSFX[i] ? "opted in" : "opted out"));
	}
	#endif

	int index;

	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 33.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE); //30 sec before timeout
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 26.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE); //sparks
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 21.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 16.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 12.5, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 11.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 10.8, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 10.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 4.8, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE); //sparks inbetween ticks
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 5.3, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 6.5, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 12.0, timer_SoundEffect3, index++, TIMER_FLAG_NO_MAPCHANGE); //beeps countdown
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 11.0, timer_SoundEffect3, index++, TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 10.0, timer_SoundEffect3, index++, TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 9.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 8.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 7.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 6.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 5.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE); //end beeps countdow
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 4.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE); //crazy sparks
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 3.7, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 3.6, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 3.5, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 3.4, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 2.0, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE); //crazy ticks
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 1.9, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 1.8, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 1.7, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 1.6, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 1.0 , timer_ExplodeGhost, index, TIMER_FLAG_NO_MAPCHANGE); //+sec after round end
}




public Action timer_ChargingSound(Handle timer) //charging sound effect
{
	g_bEndOfRound = true; //we are allowed to hook entity destructions for a short time during end of round

	if (!SetupSoundEffect())
		return Plugin_Stop;

	EmitSoundToAll(g_sSoundEffect[0], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.4, 100, -1, g_vecOrigin); //charging effect

	return Plugin_Stop;
}


public Action timer_SoundEffect1(Handle timer, int timernumber)  //sparks sound effect
{


	if (!SetupSoundEffect())
		return Plugin_Stop;

	if (HasAnyoneOptedOut())
		EmitSound(g_soundsEnabledClient, g_numClients, g_sSoundEffect[GetRandomInt(3,5)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, GetRandomInt(90, 110), -1, g_vecOrigin); //sparks
	else
		EmitSoundToAll(g_sSoundEffect[GetRandomInt(3,5)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, GetRandomInt(90, 110), -1, g_vecOrigin); //sparks

	GhostTimer[timernumber] = INVALID_HANDLE;
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

	if (MaxClients >= carrier > 0)
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
	g_bEndOfRound = true;

	EmmitCapSound(client);

	for(int i = 0; i < SOUND_INSTANCES; i++)
	{
		//killing all remaining timers for sound effects
		if(GhostTimer[i] != INVALID_HANDLE)
		{
			KillTimer(GhostTimer[i]);
			GhostTimer[i] = INVALID_HANDLE;
		}
	}

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

	CreateTimer(11.0, timer_ExplodeGhost, -1);

}


public void OnGhostPickUp(int client)
{
	g_bGhostIsHeld = true;

	g_ghostCarrier = client;

	g_ghostCarrierTeam = GetClientTeam(g_ghostCarrier);


	g_hAnnouncerTimerStarter[0] = CreateTimer(0.0, timer_CreateAnnouncerTimers, 0, TIMER_FLAG_NO_MAPCHANGE);
	g_hAnnouncerTimerStarter[1] = CreateTimer(g_fFuzzRepeatDelay + 15.0, timer_CreateFuzzTimers, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	g_fFuzzRepeatDelay = 10.0;

	if(g_hAnnouncerTimerStarter[1] != INVALID_HANDLE)
		TriggerTimer(g_hAnnouncerTimerStarter[1]);
}


public void OnGhostDrop(int client)
{
	g_bGhostIsHeld = false;
	g_ghostCarrier = -1;
	g_fFuzzRepeatDelay = 0.0;

	for(int i; i < sizeof(AnnouncerTimer); i++)
	{
		if(AnnouncerTimer[i] != INVALID_HANDLE)
		{
			KillTimer(AnnouncerTimer[i]);
			AnnouncerTimer[i] = INVALID_HANDLE;
		}
	}

	for(int i; i < sizeof(g_hAnnouncerTimerStarter); i++)
	{
		if(g_hAnnouncerTimerStarter[i] != INVALID_HANDLE)
		{
			KillTimer(g_hAnnouncerTimerStarter[i]);
			g_hAnnouncerTimerStarter[i] = INVALID_HANDLE;
		}
	}
}



public Action timer_ExplodeGhost(Handle timer, int timernumber) // explode ghost
{
	if (timernumber != -1)
		GhostTimer[timernumber] = INVALID_HANDLE;

	CreateTimer(0.0, timer_ChargingSound, TIMER_FLAG_NO_MAPCHANGE); // charging sound right before explosion

	if(KillGhostTimer != INVALID_HANDLE)
		KillTimer(KillGhostTimer);

 	KillGhostTimer = CreateTimer(1.3, timer_RemoveGhost, _, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
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

	// three beeps
	FuzzTimer[0] = CreateTimer(1.0, timer_EmmitPickupSound1, 0, TIMER_FLAG_NO_MAPCHANGE);
	FuzzTimer[1] = CreateTimer(1.5, timer_EmmitPickupSound1, 1, TIMER_FLAG_NO_MAPCHANGE);
	FuzzTimer[2] = CreateTimer(2.0, timer_EmmitPickupSound1, 2, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


public Action timer_CreateAnnouncerTimers(Handle timer, int timerindex)
{
	g_hAnnouncerTimerStarter[timerindex] = INVALID_HANDLE;

	for(int i; i < sizeof(AnnouncerTimer); i++)
	{
		if(AnnouncerTimer[i] != INVALID_HANDLE)
		{
			KillTimer(AnnouncerTimer[i]);
			AnnouncerTimer[i] = INVALID_HANDLE;
		}
	}

	AnnouncerTimer[0] = CreateTimer(3.5, timer_EmmitPickupSound2, 0, TIMER_FLAG_NO_MAPCHANGE); //2 = warning
	AnnouncerTimer[1] = CreateTimer(4.5, timer_EmmitPickupSound2, 1, TIMER_FLAG_NO_MAPCHANGE); //2 = warning
	AnnouncerTimer[2] = CreateTimer(6.5, timer_EmmitPickupSound3, 2, TIMER_FLAG_NO_MAPCHANGE); //3 = automatic targetting system
	AnnouncerTimer[3] = CreateTimer(10.3, timer_EmmitPickupSound4, 3, TIMER_FLAG_NO_MAPCHANGE); //4 = acquired
	AnnouncerTimer[4] = CreateTimer(12.0, timer_EmmitPickupSound2, 4, TIMER_FLAG_NO_MAPCHANGE); //2 = warning
	AnnouncerTimer[5] = CreateTimer(13.0, timer_EmmitPickupSound2, 5, TIMER_FLAG_NO_MAPCHANGE); //2 = warning
}



public Action timer_EmmitPickupSound1(Handle timer, int timerindex) //fuzz
{
	FuzzTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld || g_bEndOfRound)
		return Plugin_Stop;

	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientInGame(client) || !IsClientConnected(client))
			continue;

		if(client == g_ghostCarrier)
			continue;

		if (!g_bWantsGhostSFX[client]) // no wants soundz
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

	if(!g_bGhostIsHeld || g_bEndOfRound)
		return Plugin_Stop;

	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientConnected(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
			continue;

		if (!g_bWantsGhostSFX[client]) // no wants soundz
			continue;

		if(client == g_ghostCarrier)
			continue;

		if(GetClientTeam(client) == g_ghostCarrierTeam)
			continue;

		EmitSoundToClient(client, g_sSoundEffect[12], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, 100, -1, NULL_VECTOR, NULL_VECTOR);
	}

	return Plugin_Stop;
}


public Action timer_EmmitPickupSound3(Handle timer, int timerindex) //automatic target aquisition system
{
	AnnouncerTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld || g_bEndOfRound)
		return Plugin_Stop;

	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientInGame(client) || !IsClientConnected(client) || !IsPlayerAlive(client))
			continue;

		if (!g_bWantsGhostSFX[client]) // no wants soundz
			continue;

		if(client == g_ghostCarrier)
			continue;

		EmitSoundToClient(client, g_sSoundEffect[13], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, 100, -1, NULL_VECTOR, NULL_VECTOR);
	}


	return Plugin_Stop;
}


public Action timer_EmmitPickupSound4(Handle timer, int timerindex) //acquired
{
	AnnouncerTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld || g_bEndOfRound)
		return Plugin_Stop;

	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientInGame(client) || !IsClientConnected(client) || !IsPlayerAlive(client))
			continue;

		if (g_bWantsGhostSFX[client]) // no wants soundz
			continue;

		if(client == g_ghostCarrier)
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
	if(!IsClientInGame(client) || !IsClientConnected(client))
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
	if(!g_bEndOfRound)
		return;

	if(!IsValidEntity(entity) || entity <= MaxClients)
		return;

	if(!GetConVarBool(convar_ghostexplodes))
		return;

	char classname[50];
	GetEntityClassname(entity, classname, sizeof(classname));

	#if DEBUG > 0
	PrintToServer("[sm_ghostcapsfx] \"%s\" destroyed (id: %d)", classname, entity);
	#endif

    if (StrEqual(classname, "weapon_ghost"))
    {
		#if DEBUG
		int carrier = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
		PrintToServer("[sm_ghostcapsfx] m_hOwnerEntity of \"%s\" (id: %d) entity (%d) was: %d.", classname, ghost, entity, carrier);
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
	if(MaxClients >= carrier > 0)
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

	// avoid checking for destroyed entities during round restart (lots of them get destroyed, too verbose, slows down server)
	g_bEndOfRound = false;
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
	if(!IsValidEntity(client) || !IsClientConnected(client))
		return Plugin_Stop;

	float vecOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[2] += 20.0;


	if (!HasAnyoneOptedOut())
		EmitSoundToAll(g_sRadioChatterSoundEffect[GetRandomInt(0, sizeof(g_sRadioChatterSoundEffect) -1)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 130, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, NULL_VECTOR);
	else
		EmitSound(g_soundsEnabledClient, g_numClients, g_sRadioChatterSoundEffect[GetRandomInt(0, sizeof(g_sRadioChatterSoundEffect) -1)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 130, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, NULL_VECTOR);

	return Plugin_Stop;
}


void EmmitCapSound(int client)
{
	if(!IsValidEntity(client) || !IsClientConnected(client))
		return;

	float vecOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[2] += 20.0;

	EmitSoundToAll(g_sSoundEffect[GetRandomInt(1,2)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 100, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, NULL_VECTOR);
}



public void OnMapEnd()
{
	int i;
	for(i = 0; i < SOUND_INSTANCES; i++)
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

	for(i = 0; i < sizeof(g_hAnnouncerTimerStarter); i++)
	{
		if(g_hAnnouncerTimerStarter[i] != INVALID_HANDLE)
			g_hAnnouncerTimerStarter[i] = INVALID_HANDLE;
	}

	if(KillGhostTimer != INVALID_HANDLE)
		KillGhostTimer = INVALID_HANDLE;
}





// Taken from doublecap plugin by Soft as HELL
public Action timer_RemoveGhost(Handle timer)
{
	KillGhostTimer = INVALID_HANDLE;

	if(!IsValidEntity(ghost))
	{
		return Plugin_Handled;
	}

	char classname[50];
	GetEntityClassname(ghost, classname, sizeof(classname));

	if(!StrEqual(classname, "weapon_ghost"))
	{
		return Plugin_Handled;
	}

	g_ghostCarrier = GetEntPropEnt(ghost, Prop_Data, "m_hOwnerEntity");

	#if DEBUG > 0
	PrintToServer("Timer: carrier = %i", g_ghostCarrier);
	#endif

	if((MaxClients >= g_ghostCarrier > 0) && IsPlayerAlive(g_ghostCarrier))
	{
		#if DEBUG > 0
		PrintToServer("Timer: removed ghost from carrier %i!", g_ghostCarrier);
		#endif

		RemoveGhost(g_ghostCarrier);
	}
	else
	{
		if(IsValidEdict(ghost))
		{
			#if DEBUG > 0
			PrintToServer("Timer: removed ghost %i classname %s!", ghost, classname);
			#endif

			RemoveEdict(ghost);
			// AcceptEntityInput(ghost, "Kill"); // should be safer
		}
	}

	return Plugin_Handled;
}


void RemoveGhost(int client)
{
	#if DEBUG > 0
	PrintToServer("Removing current ghost %i", ghost);
	#endif

	// Switch to last weapon if player is still alive and has ghost active
	if(IsValidClient(client) && IsPlayerAlive(client))
	{
		int activeweapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		int ghost_index = EntRefToEntIndex(ghost);

		if(activeweapon == ghost_index)
		{

			//TODO: force TOSS? since viewmodel is not updated correctly due to latency latency

			int lastweapon = GetEntPropEnt(client, Prop_Data, "m_hLastWeapon");

			if(IsValidEdict(lastweapon))
				SetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", lastweapon);
		}
	}

	// Delete ghost
	if(IsValidEdict(ghost))
	{
		RemoveEdict(ghost);
		// 	AcceptEntityInput(ghost, "Kill"); // should be safer
	}
}
