#include <sourcemod>
#include <sdktools>
#include <neotokyo>
#include <clientprefs>
#include <nt_menu>
#pragma semicolon 1

#if !defined DEBUG
	#define DEBUG 0
#endif

#define SOUND_INSTANCES 31
#define MAX_ANNOUNCER_OCCURENCES 6
#define NEO_MAX_PLAYERS 32
#define CARRYING_TEAM 0 // team holding the ghost
#define OPPOSING_TEAM 1 // team not holding the ghost
#define ALL_ALIVE 2 // all alive players

int g_iGhost, g_iGhostCarrier, g_iGhostCarrierTeam;
bool g_bGhostIsCaptured, g_bGhostIsHeld, g_bEndOfRound;
int g_iTickCount = 95;
float g_vecOrigin[3];
float g_fFuzzRepeatDelay = 0.0;

Handle convar_ghostexplodes, convar_ghostexplosiondamages, convar_roundtimelimit,
convar_nt_doublecap_version, convar_nt_ghostcap_version, convar_ghost_sounds_enabled = INVALID_HANDLE;

Handle GhostTimer[SOUND_INSTANCES] = { INVALID_HANDLE, ...};
Handle AnnouncerTimer[MAX_ANNOUNCER_OCCURENCES] = { INVALID_HANDLE, ...};
Handle g_hFuzzTimers;
Handle FuzzTimer[3] = { INVALID_HANDLE, ...};
Handle KillGhostTimer = INVALID_HANDLE;

Handle g_hPrefCookie = INVALID_HANDLE; // handle to cookie in DB
bool g_bWantsGhostSFX[NEO_MAX_PLAYERS+1];

// menus
TopMenuObject g_hTopMainMenu_topmenuobj = INVALID_TOPMENUOBJECT;
TopMenuObject g_tmo_prefs = INVALID_TOPMENUOBJECT;
TopMenu g_hTopMenu; // handle to the nt_menu plugin topmenu
Handle g_hPrefsMenu;

// caching of affected players
int g_iAffectedAlivePlayers[3][NEO_MAX_PLAYERS+1]; // one array for each team
int g_iNumAffectedAlive[3];

int g_iAffectedDeadPlayers[NEO_MAX_PLAYERS]; // at least one player remains alive, doesn't apply to them + no team distinction
int g_iNumAffectedDead;
int g_iLastCarryingTeam;


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
// NOTE: actually it doesn't explode when neo_restart_this 1 is called, as the ghost entity is not properly reported by OnGhostSpawn()

//FIXME: seems that a remnant timer is activated as soon as the ghost gets picked up, or it's just the game delaying the orignal alarm sound.

// TODO: sound/gameplay/ghost_idle_loop.wav while being carried
// TODO: use sound/player/CPcaptured.wav for ghost capture sound
// TODO: redo all the emitgamesounds to use an array of affected clients instead (for the haters)
// TODO: add menu to toggle cookies


public void OnPluginStart()
{
	convar_ghost_sounds_enabled = CreateConVar("nt_ghost_sounds_enabled", "1", "Ghost emits sounds when held and captured.", FCVAR_SPONLY, true, 0.0, true, 1.0);
	convar_ghostexplodes = CreateConVar("nt_ghostexplodes", "1", "Ghost explodes on capture or timeout.", FCVAR_SPONLY, true, 0.0, true, 1.0);
	convar_ghostexplosiondamages = CreateConVar("nt_ghostexplosiondamages", "1", "Explosion from ghost damages players", FCVAR_SPONLY, true, 0.0, true, 1.0);


	HookEvent("game_round_start", OnRoundStart);
	HookEvent("player_death", OnPlayerDeath);

	convar_roundtimelimit = FindConVar("neo_round_timelimit");

	convar_nt_doublecap_version = FindConVar("nt_doublecap_version");
	convar_nt_ghostcap_version = FindConVar("sm_ntghostcap_version");

	RegConsoleCmd("nt_ghostcapsfx_prefs", Command_Hate_Sounds_Toggle, "Toggle your preference to not hear custom ghost capture sound effect.");

	g_hPrefCookie = FindClientCookie("wants-ghostcapfx");
	if (g_hPrefCookie == INVALID_HANDLE)
		g_hPrefCookie = RegClientCookie("wants-ghostcapfx", "Asked for no ghost capture sound effects.", CookieAccess_Protected);

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


	// late loading read cookies
	for (int i = 0; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsClientConnected(i))
			continue;

		if (!AreClientCookiesCached(i))
			continue;

		OnClientCookiesCached(i);
	}

	// prebuild menus
	g_hPrefsMenu = BuildSubMenu(0);

	// Is our menu already loaded?
	TopMenu topmenu;
	if (LibraryExists("nt_menu") && ((topmenu = GetNTTopMenu()) != null))
	{
		OnNTMenuReady(topmenu);
	}
	else
	{
		// library missing, we build our own
		g_hTopMenu = CreateTopMenu(TopMenuCategory_Handler);
		BuildTopMenu();
	}
}


public void OnNTMenuReady(Handle aTopMenu)
{
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

	// Block us from being called twice
	if (topmenu == g_hTopMenu)
		return;

	// Save the Handle
	g_hTopMenu = topmenu;

	BuildTopMenu();
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

	// Late loading, players should head by default
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsClientConnected(i) | IsFakeClient(i))
			continue;
		ProcessCookies(i);
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


void BuildTopMenu()
{
	g_hTopMainMenu_topmenuobj = FindTopMenuCategory(g_hTopMenu, "Various effects"); // get the category provided by nt_menu plugin

	if (g_hTopMainMenu_topmenuobj != INVALID_TOPMENUOBJECT)
	{
		// AddToTopMenu(g_hTopMenu, "nt_menu", TopMenuObject_Item, TopCategory_Handler, g_hTopMainMenu_topmenuobj, "nt_menu", 0);
		g_tmo_prefs = g_hTopMenu.AddItem("sm_ghostcapsfx_prefs", TopMenuCategory_Handler, g_hTopMainMenu_topmenuobj, "sm_ghostcapsfx_prefs");
		return;
	}

	// didn't find categories, must be missing nt_menu plugin, so build our own category and attach to it
	g_hTopMainMenu_topmenuobj = g_hTopMenu.AddCategory("Various effects", TopMenuCategory_Handler);

	g_tmo_prefs = AddToTopMenu(g_hTopMenu, "sm_ghostcapsfx_prefs", TopMenuObject_Item, TopMenuCategory_Handler, g_hTopMainMenu_topmenuobj, "sm_ghostcapsfx_prefs");
}



public void TopMenuCategory_Handler (Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if ((action == TopMenuAction_DisplayOption) || (action == TopMenuAction_DisplayTitle))
	{
		// GetTopMenuObjName(topmenu, object_id, buffer, maxlength);

		if (object_id == INVALID_TOPMENUOBJECT)
			Format(buffer, maxlength, "Neotokyo Menu", param);
		if (object_id == g_tmo_prefs)
			Format(buffer, maxlength, "%s", "Ghost sound effects", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		if (object_id == g_tmo_prefs)
			DisplayMenu(g_hPrefsMenu, param, 20);
	}
}


public Menu BuildSubMenu(int type)
{
	Menu menu;

	switch (type)
	{
		case 0: // in case we need more later
		{
			menu = new Menu(PropsPrefsMenuHandler, MENU_ACTIONS_ALL);
			menu.SetTitle("Ghost sounds preference:");
			menu.AddItem("a", "Set ghost sounds preference");
			menu.ExitButton = true;
			menu.ExitBackButton = true;
		}
	}
	return menu;
}

public int PropsPrefsMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			// CloseHandle(menu);
			//delete menu; (should we here?)
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
			}
		}
		// case MenuAction_Display:
		// {
		// 	char title[255];
		// 	Format(title, sizeof(title), "Hurt sfx preferences:", param1);

		// 	Panel panel = view_as<Panel>(param2);
		// 	panel.SetTitle(title);
		// }
		case MenuAction_Select:
		{
			decl String:info[2];
			GetMenuItem(menu, param2, info, sizeof(info));

			switch (info[0])
			{
				case 'a':
				{
					ToggleCookiePreference(param1);
					DisplayMenu(g_hPrefsMenu, param1, 20);
				}
				default:
				{
					CloseHandle(g_hTopMenu);
					return 0;
				}
			}
		}

		case MenuAction_DisplayItem:
		{
			char info[2];
			menu.GetItem(param2, info, sizeof(info));

			char display[39];

			if (StrEqual(info, "a")) // toggle item
			{
				Format(display, sizeof(display), "Ghost warning sounds are: [%s]", (g_bWantsGhostSFX[param1] ? "enabled" : "disabled" ));
				return RedrawMenuItem(display);
			}
			return 0;
		}
	}
	return 0;
}



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
		g_bWantsGhostSFX[client] = true;
		//UpdateAffectedArrays(-1); // probably only needed in case it generates errors
	}
}


void ProcessCookies(int client)
{
	if (!IsValidClient(client))
		return;

	char cookie[2];
	GetClientCookie(client, g_hPrefCookie, cookie, sizeof(cookie));

	if (cookie[0] != '\0') // we have a cookie
	{
		g_bWantsGhostSFX[client] = view_as<bool>(StringToInt(cookie));
	}
	else
	{
		//default to opted-out
		g_bWantsGhostSFX[client] = true;
	}

	UpdateAffectedArrays(client, IsPlayerAlive(client));
	CreateTimer(60.0, DisplayNotification, client);
	return;
}


public Action DisplayNotification(Handle timer, int client)
{
	if(client > 0 && IsClientConnected(client) && IsClientInGame(client))
	{
		if(g_bWantsGhostSFX[client])
		{
			PrintToChat(client, 	"[nt_ghostcapsfx] You can toggle hearing ghost sound effects by typing !sounds_nothx");
			PrintToConsole(client, 	"\n[nt_ghostcapsfx] You can toggle hearing ghost sound effects by typing sm_sounds_nothx\n");
		}
	}
	return Plugin_Handled;
}


public Action Command_Hate_Sounds_Toggle(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	g_bWantsGhostSFX[client] = !g_bWantsGhostSFX[client];

	SetClientCookie(client, g_hPrefCookie, (g_bWantsGhostSFX[client] ? "1" : "0"));

	ReplyToCommand(client, "[nt_ghostcapsfx] You have %s sound effects while ghost is held.",
	g_bWantsGhostSFX[client] ? "opted to hear" : "opted out of hearing");

	UpdateAffectedArrays(client, IsPlayerAlive(client));
	ShowActivity2(client, "[nt_ghostcapsfx] ", "%N opted %s.", client, g_bWantsGhostSFX[client] ? "back in" : "out" );
	LogAction(client, -1, "[nt_ghostcapsfx] \"%L\" opted %s.", client, g_bWantsGhostSFX[client] ? "back in" : "out");

	return Plugin_Handled;
}



// Toggle bool + cookie
void ToggleCookiePreference(int client)
{
	if (!IsValidClient(client))
		return;

	#if DEBUG
	PrintToServer("[nt_ghostcapsfx] DEBUG Pref for %N was %s -> bool toggled.", client, (g_bWantsGhostSFX[client] ? "true" : "false"));
	#endif
	g_bWantsGhostSFX[client] = !g_bWantsGhostSFX[client];
	SetClientCookie(client, g_hPrefCookie, (g_bWantsGhostSFX[client] ? "1" : "0"));
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


public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	UpdateAffectedArrays(victim, true);
}


void UpdateAffectedArrays(int client, bool dead=false)
{
	if (dead) // assume player is dead, only upd
	{
		UpdateDeadArray(client);
	}
	if (client == -1) // blank out arrays, start of round
	{
		g_iNumAffectedAlive[CARRYING_TEAM] = 0;
		g_iNumAffectedAlive[OPPOSING_TEAM] = 0;
		g_iNumAffectedDead = 0;
		UpdateDeadArray(-1);
		BuildAffectedTeamArray();
		return;
	}

	// we do need to rebuild everytime
	BuildAffectedTeamArray();

}


void UpdateDeadArray(int client)
{
	// Make sure to only call 15 seconds after round start
	if (client <= 0) // force rebuild for all
	{
		for (int thisClient = 1; thisClient <= MaxClients; thisClient++)
		{
			if (!IsValidClient(thisClient) || !IsClientConnected(thisClient))
				continue;

			// check if observing mode
			if ((IsPlayerObserving(thisClient) || GetClientTeam(thisClient) <= 1) && g_bWantsGhostSFX[thisClient])
				g_iAffectedDeadPlayers[g_iNumAffectedDead++] = thisClient;
		}
		return;
	}

	// checks here
	BuildAffectedTeamArray();

	// remove from alive array -> rebuild alive array!
	g_iAffectedDeadPlayers[g_iNumAffectedDead++] = client;
}


// type is carrying team or not
void BuildAffectedTeamArray()
{
	g_iNumAffectedAlive[CARRYING_TEAM] = 0;
	g_iNumAffectedAlive[OPPOSING_TEAM] = 0;
	g_iNumAffectedAlive[ALL_ALIVE] = 0;
	for (int thisClient = 1; thisClient <= MaxClients; thisClient++)
	{
		if (!IsValidClient(thisClient) || !IsClientConnected(thisClient))
			continue;

		if (!IsPlayerAlive(thisClient) || IsPlayerObserving(thisClient))
			continue;

		if (!g_bWantsGhostSFX[thisClient])
			continue;

		if(thisClient != g_iGhostCarrier)
			g_iAffectedAlivePlayers[ALL_ALIVE][g_iNumAffectedAlive[ALL_ALIVE]++] = thisClient;

		if (g_iGhostCarrier <= 0) // ghost has not been picked up yet
			continue;

		if (thisClient == g_iGhostCarrier) // carrier shouldn't hear warning sound anyway
			continue;

		int iClientTeam = GetClientTeam(thisClient); // FIXME: cache teams by hooking join_team event?

		if (iClientTeam == g_iGhostCarrierTeam)
			g_iAffectedAlivePlayers[CARRYING_TEAM][g_iNumAffectedAlive[CARRYING_TEAM]++] = thisClient;
		else
			g_iAffectedAlivePlayers[OPPOSING_TEAM][g_iNumAffectedAlive[OPPOSING_TEAM]++] = thisClient;
	}

}


public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	g_bGhostIsHeld = false;
	g_iGhostCarrier = -1;
	g_fFuzzRepeatDelay = 0.0;
	g_iLastCarryingTeam = 0;

	UpdateAffectedArrays(-2); // force rebuild all arrays

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
	float fBaseTime = GetConVarFloat(convar_roundtimelimit) * 60.0;
	CreateTimer(fBaseTime, timer_SignalEndOfRound, TIMER_FLAG_NO_MAPCHANGE);

	GhostTimer[index] = CreateTimer(fBaseTime - 33.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE); //30 sec before timeout
	GhostTimer[index] = CreateTimer(fBaseTime - 26.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE); //sparks
	GhostTimer[index] = CreateTimer(fBaseTime - 21.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 16.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 12.5, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 11.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 10.8, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 10.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 4.8, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE); //sparks inbetween ticks
	GhostTimer[index] = CreateTimer(fBaseTime - 5.3, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 6.5, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 12.0, timer_SoundEffect3, index++, TIMER_FLAG_NO_MAPCHANGE); //beeps countdown
	GhostTimer[index] = CreateTimer(fBaseTime - 11.0, timer_SoundEffect3, index++, TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 10.0, timer_SoundEffect3, index++, TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 9.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 8.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 7.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 6.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 5.0, timer_SoundEffect3, index++,  TIMER_FLAG_NO_MAPCHANGE); //end beeps countdow
	GhostTimer[index] = CreateTimer(fBaseTime - 4.0, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE); //crazy sparks
	GhostTimer[index] = CreateTimer(fBaseTime - 3.7, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 3.6, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 3.5, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 3.4, timer_SoundEffect1, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 2.0, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE); //crazy ticks
	GhostTimer[index] = CreateTimer(fBaseTime - 1.9, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 1.8, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 1.7, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 1.6, timer_SoundEffect2, index++,  TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[index] = CreateTimer(fBaseTime - 1.0 , timer_ExplodeGhost, index, TIMER_FLAG_NO_MAPCHANGE); //+sec after round end
}



public Action timer_SignalEndOfRound(Handle timer)
{
	
	g_bEndOfRound = true;

}


public Action timer_ChargingSound(Handle timer) //charging sound effect
{
	g_bEndOfRound = true; //we are allowed to hook entity destructions for a short time during end of round

	if (!UpdateNextSoundOrigin())
		return Plugin_Stop;

	EmitSoundToAll(g_sSoundEffect[0], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.4, 100, -1, g_vecOrigin); //charging effect

	return Plugin_Stop;
}


public Action timer_SoundEffect1(Handle timer, int timernumber)  //sparks sound effect
{
	GhostTimer[timernumber] = INVALID_HANDLE;

	if (!UpdateNextSoundOrigin())
		return Plugin_Stop;

	// if (HasAnyoneOptedOut())
	// 	EmitSound(g_iAffectedAlivePlayers, g_iNumAffectedAlive, g_sSoundEffect[GetRandomInt(3,5)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, GetRandomInt(90, 110), -1, g_vecOrigin); //sparks
	// else
	// 	EmitSoundToAll(g_sSoundEffect[GetRandomInt(3,5)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, GetRandomInt(90, 110), -1, g_vecOrigin); //sparks

	EmitSound(g_iAffectedAlivePlayers[ALL_ALIVE], g_iNumAffectedAlive[ALL_ALIVE], g_sSoundEffect[GetRandomInt(3,5)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, GetRandomInt(90, 110), -1, g_vecOrigin); //sparks
	EmitSound(g_iAffectedDeadPlayers, g_iNumAffectedDead, g_sSoundEffect[GetRandomInt(3,5)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.3, GetRandomInt(90, 110), -1, g_vecOrigin); //sparks


	return Plugin_Stop;
}


public Action timer_SoundEffect2(Handle timer, int timernumber) //grenade tick sound effect
{
	GhostTimer[timernumber] = INVALID_HANDLE;

	if (!UpdateNextSoundOrigin())
		return Plugin_Stop;

	EmitSoundToAll(g_sSoundEffect[6], SOUND_FROM_WORLD, SNDCHAN_AUTO, 90, SND_NOFLAGS, SNDVOL_NORMAL, g_iTickCount, -1, g_vecOrigin); //ticks
	g_iTickCount += 5;

	return Plugin_Stop;
}


public Action timer_SoundEffect3(Handle timer, int timernumber) //beeps countdown
{
	GhostTimer[timernumber] = INVALID_HANDLE;

	if (!UpdateNextSoundOrigin())
		return Plugin_Stop;

	EmitSoundToAll(g_sSoundEffect[10], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, 0.5, g_iTickCount, -1, g_vecOrigin); //beeps
	g_iTickCount += 5;

	return Plugin_Stop;
}


bool UpdateNextSoundOrigin()
{
	// if (g_bGhostIsCaptured)
	// 	return false;

	if (!IsValidEntity(g_iGhost) || g_iGhost == 0)
	{
		#if DEBUG
		PrintToServer("[nt_ghostcapsfx] g_iGhost (%d) entity was not valid! UpdateNextSoundOrigin() returns false!", g_iGhost);
		#endif
		return false;
	}

	int carrier = GetEntPropEnt(g_iGhost, Prop_Data, "m_hOwnerEntity");

	if (MaxClients >= carrier > 0)
	{
		GetEntPropVector(carrier, Prop_Send, "m_vecOrigin", g_vecOrigin);
		#if DEBUG
		PrintToServer("[nt_ghostcapsfx] client must be a player (carrier=%d) at pos: %f %f %f. UpdateNextSoundOrigin()", carrier, g_vecOrigin[0], g_vecOrigin[1], g_vecOrigin[2]);
		#endif
	}
	else
	{
		GetEntPropVector(g_iGhost, Prop_Send, "m_vecOrigin", g_vecOrigin);
		#if DEBUG
		PrintToServer("[nt_ghostcapsfx] ghost (%d) must be on the ground (carrier=%d) at pos: %f %f %f. UpdateNextSoundOrigin()", g_iGhost, carrier, g_vecOrigin[0], g_vecOrigin[1], g_vecOrigin[2]);
		#endif
	}

	g_vecOrigin[2] += 10;
	return true;
}


public void OnGhostSpawn(int entity)
{
	if (IsValidEntity(entity))
	{
		g_iGhost = entity;
	}
	#if DEBUG
	PrintToServer("[nt_ghostcapsfx] OnGhostSpawn() returned entity index: %d.", entity);
	#endif

	g_bGhostIsCaptured = false;
	g_bGhostIsHeld = false;
	g_bEndOfRound = false;
}


public void OnGhostCapture(int client)
{
	#if DEBUG
	PrintToServer("[nt_ghostcapsfx] OnGhostCaptured() marking end of round.");
	#endif
	g_bGhostIsCaptured = true;
	// g_bGhostIsHeld = false;
	g_bEndOfRound = true;

	EmmitCapSound(client);

	for(int i = 0; i < SOUND_INSTANCES; i++)
	{
		//killing all remaining timers for sound effects
		if(GhostTimer[i] != null)
		{
			KillTimer(GhostTimer[i]);
			GhostTimer[i] = null;
		}
	}

	CreateTimer(8.0, timer_ExplodeGhost, -1);

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
	CreateTimer(7.5, timer_DoSparks, client);
	CreateTimer(8.0, timer_DoSparks, client);
	CreateTimer(8.5, timer_DoSparks, client);



}


public void OnGhostPickUp(int client)
{
	g_bGhostIsHeld = true;

	g_iGhostCarrier = client;

	g_iGhostCarrierTeam = GetClientTeam(g_iGhostCarrier);

	if (g_iGhostCarrierTeam != g_iLastCarryingTeam) // first pick up will always be true
	{
		UpdateAffectedArrays(-1); // affects team but not carrier
		CreateAnnouncerTimers(); // avoids recalling this if same team picks it up again, only do announcements once
	}
	g_iLastCarryingTeam = g_iGhostCarrierTeam;

	/* Due to timers being very inaccurate the longer the delay (due to engine ticks not being a constant rate or something)
	we need short delays whenever possible, otherwise these delays become longer than they should be over time. */

	if (g_hFuzzTimers != INVALID_HANDLE)
		KillTimer(g_hFuzzTimers);

	g_hFuzzTimers = CreateTimer(g_fFuzzRepeatDelay + 15.0, timer_CreateFuzzTimers, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	g_fFuzzRepeatDelay = 10.0;

	CreateTimer(0.1, timer_CreateFuzzTimers, _, TIMER_FLAG_NO_MAPCHANGE);
}


public void OnGhostDrop(int client)
{
	g_bGhostIsHeld = false;
	g_iGhostCarrier = -1;
	g_fFuzzRepeatDelay = 0.0;

	for(int i; i < sizeof(AnnouncerTimer); i++)
	{
		if(AnnouncerTimer[i] == INVALID_HANDLE || i == 2 || i == 3) // don't kill announcer in its track
			continue;
		KillTimer(AnnouncerTimer[i]);
		AnnouncerTimer[i] = INVALID_HANDLE;
	}

	for (int i; i < sizeof(FuzzTimer); i++)
	{
		if (FuzzTimer[i] == INVALID_HANDLE)
			continue;
		KillTimer(FuzzTimer[i]);
		FuzzTimer[i] = INVALID_HANDLE;
	}

}


public Action timer_ExplodeGhost(Handle timer, int timernumber) // explode ghost
{
	#if DEBUG
	PrintToServer("[nt_ghostcapsfx] Fired timer_ExplodeGhost.");
	#endif

	if (timernumber != -1)
		GhostTimer[timernumber] = INVALID_HANDLE;

	CreateTimer(0.2, timer_ChargingSound, TIMER_FLAG_NO_MAPCHANGE); // charging sound right before explosion

	if(KillGhostTimer != INVALID_HANDLE)
		KillTimer(KillGhostTimer);

 	KillGhostTimer = CreateTimer(1.3, timer_RemoveGhost, _, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
}



public Action timer_CreateFuzzTimers(Handle timer)
{
	if (!g_bGhostIsHeld || g_bEndOfRound)
	{
		g_hFuzzTimers = INVALID_HANDLE;
		return Plugin_Stop;
	}

	for(int i = 0; i < sizeof(FuzzTimer); i++)
	{
		if(FuzzTimer[i] != null)
		{
			KillTimer(FuzzTimer[i]);
			FuzzTimer[i] = null;
		}
	}

	// three beeps
	FuzzTimer[0] = CreateTimer(1.0, timer_EmmitPickupSound1, 0, TIMER_FLAG_NO_MAPCHANGE);
	FuzzTimer[1] = CreateTimer(1.5, timer_EmmitPickupSound1, 1, TIMER_FLAG_NO_MAPCHANGE);
	FuzzTimer[2] = CreateTimer(2.0, timer_EmmitPickupSound1, 2, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


public Action timer_EmmitPickupSound1(Handle timer, int timernumber) //"fuzz" -> short beeps
{
	FuzzTimer[timernumber] = null;

	if(!g_bGhostIsHeld || g_bEndOfRound)
		return Plugin_Stop;

	EmitSound(g_iAffectedAlivePlayers[ALL_ALIVE], g_iNumAffectedAlive[ALL_ALIVE], g_sSoundEffect[11], SOUND_FROM_PLAYER, SNDCHAN_AUTO,
			60, SND_NOFLAGS, 0.4, 100, -1, NULL_VECTOR, NULL_VECTOR );

	return Plugin_Stop;
}


void CreateAnnouncerTimers()
{
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


// // TODO: use one template function for all sounds?
// 	EmitSound(g_, total, sample, entity, channel,
// 		level, flags, volume, pitch, speakerentity,
// 		origin, dir, updatePos, soundtime);


public Action timer_EmmitPickupSound2(Handle timer, int timerindex) //warning
{
	AnnouncerTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld || g_bEndOfRound)
		return Plugin_Stop;

	EmitSound(g_iAffectedAlivePlayers[OPPOSING_TEAM], g_iNumAffectedAlive[OPPOSING_TEAM], g_sSoundEffect[12], SOUND_FROM_PLAYER, SNDCHAN_AUTO,
			60, SND_NOFLAGS, 0.3, 100, -1, NULL_VECTOR, NULL_VECTOR );

	return Plugin_Stop;
}


public Action timer_EmmitPickupSound3(Handle timer, int timerindex) //automatic target aquisition system
{
	AnnouncerTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld || g_bEndOfRound)
		return Plugin_Stop;

	EmitSound(g_iAffectedAlivePlayers[ALL_ALIVE], g_iNumAffectedAlive[ALL_ALIVE], g_sSoundEffect[13], SOUND_FROM_PLAYER, SNDCHAN_AUTO,
			60, SND_NOFLAGS, 0.3, 100, -1, NULL_VECTOR, NULL_VECTOR);

	return Plugin_Stop;
}


public Action timer_EmmitPickupSound4(Handle timer, int timerindex) //acquired
{
	AnnouncerTimer[timerindex] = INVALID_HANDLE;

	if(!g_bGhostIsHeld || g_bEndOfRound)
		return Plugin_Stop;

	EmitSound(g_iAffectedAlivePlayers[ALL_ALIVE], g_iNumAffectedAlive[ALL_ALIVE], g_sSoundEffect[14], SOUND_FROM_PLAYER, SNDCHAN_AUTO,
			60, SND_NOFLAGS, 0.3, 100, -1, NULL_VECTOR, NULL_VECTOR );

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


// public void OnEntityDestroyed(int entity)
// {
// 	if(!g_bEndOfRound)
// 		return;

// 	if(!IsValidEntity(entity) || entity <= MaxClients)
// 		return;

// 	if(!GetConVarBool(convar_ghostexplodes))
// 		return;

// 	char classname[50];
// 	GetEntityClassname(entity, classname, sizeof(classname));

// 	#if DEBUG > 0
// 	PrintToServer("[nt_ghostcapsfx] \"%s\" destroyed (id: %d)", classname, entity);
// 	#endif

//     if (StrEqual(classname, "weapon_ghost"))
//     {
// 		#if DEBUG
// 		int carrier = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
// 		PrintToServer("[nt_ghostcapsfx] m_hOwnerEntity of \"%s\" (id: %d) entity (%d) was: %d.", classname, g_iGhost, entity, carrier);
// 		#endif
// 		g_bGhostIsHeld = false;
// 		Explode(entity);

// 		// avoid checking for destroyed entities during round restart (lots of them get destroyed, too verbose, slows down server)
// 		g_bEndOfRound = false;
//     }
// }


void Explode(int entity, int carrier)
{
	#if DEBUG
	PrintToServer("[nt_ghostcapsfx] Explode(%d)!", entity);
	#endif

	if(carrier > 0)
		entity = carrier;

	#if DEBUG
	PrintToServer("[nt_ghostcapsfx] carrier is %d.", carrier);
	#endif

	float pos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	#if DEBUG
	PrintToServer("[nt_ghostcapsfx] pos of %d is %f %f %f.", entity, pos[0], pos[1], pos[2]);
	#endif

	int explosion;

	if(g_bGhostIsCaptured)
		explosion = CreateEntityByName("env_physexplosion");

	if(!g_bGhostIsCaptured && GetConVarBool(convar_ghostexplosiondamages))
		explosion = CreateEntityByName("env_explosion"); // explode and damage
	else
		explosion = CreateEntityByName("env_physexplosion"); // FIXME?

	//DispatchKeyValueFloat(explosion, "magnitude", GetConVarFloat(cv_JarateKnockForce));
	DispatchKeyValue(explosion, "iMagnitude", "800");
	//DispatchKeyValue(explosion, "spawnflags", "18428");
	DispatchKeyValue(explosion, "spawnflags", "0");
	DispatchKeyValue(explosion, "iRadiusOverride", "256");

	if ( DispatchSpawn(explosion) )
	{
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
	{
		EmitSound(g_iAffectedAlivePlayers[ALL_ALIVE], g_iNumAffectedAlive[ALL_ALIVE], g_sRadioChatterSoundEffect[GetRandomInt(0, sizeof(g_sRadioChatterSoundEffect) -1)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 130, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, NULL_VECTOR);
	}
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

	if(KillGhostTimer != INVALID_HANDLE)
		KillGhostTimer = INVALID_HANDLE;
}





// Taken from doublecap plugin by Soft as HELL
public Action timer_RemoveGhost(Handle timer)
{
	KillGhostTimer = INVALID_HANDLE;

	if(!IsValidEntity(g_iGhost))
	{
		return Plugin_Handled;
	}

	char classname[50];
	GetEntityClassname(g_iGhost, classname, sizeof(classname));

	if(!StrEqual(classname, "weapon_ghost"))
	{
		#if DEBUG
		PrintToServer("[nt_ghostcapsfx] g_iGhost (%d) was not a weapon_ghost! Skipping.", g_iGhost);
		#endif
		return Plugin_Handled;
	}

	g_iGhostCarrier = GetEntPropEnt(g_iGhost, Prop_Data, "m_hOwnerEntity");

	#if DEBUG > 0
	PrintToServer("Timer: carrier = %i", g_iGhostCarrier);
	#endif

	if((MaxClients >= g_iGhostCarrier > 0) && IsPlayerAlive(g_iGhostCarrier))
	{
		#if DEBUG > 0
		PrintToServer("Timer: removed ghost from carrier %i!", g_iGhostCarrier);
		#endif
		Explode(g_iGhost, g_iGhostCarrier);
		RemoveGhost(g_iGhostCarrier);
	}
	else
	{
		if(IsValidEdict(g_iGhost))
		{
			#if DEBUG > 0
			PrintToServer("Timer: removed ghost %i classname %s!", g_iGhost, classname);
			#endif
			Explode(g_iGhost, -1);
			RemoveEdict(g_iGhost);
			// AcceptEntityInput(ghost, "Kill"); // should be safer
		}
	}

	g_bGhostIsHeld = false;

	// avoid checking for destroyed entities during round restart (lots of them get destroyed, too verbose, slows down server)
	g_bEndOfRound = false;

	return Plugin_Handled;
}


void RemoveGhost(int client)
{
	#if DEBUG > 0
	PrintToServer("Removing current ghost %i", g_iGhost);
	#endif

	// Switch to last weapon if player is still alive and has ghost active
	if(IsValidClient(client) && IsPlayerAlive(client))
	{
		int activeweapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		int ghost_index = EntRefToEntIndex(g_iGhost);

		if(activeweapon == ghost_index)
		{

			//TODO: force TOSS? since viewmodel is not updated correctly due to latency latency

			int lastweapon = GetEntPropEnt(client, Prop_Data, "m_hLastWeapon");

			if(IsValidEdict(lastweapon))
				SetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", lastweapon);
		}
	}

	// Delete ghost
	if(IsValidEdict(g_iGhost))
	{
		RemoveEdict(g_iGhost);
		// 	AcceptEntityInput(ghost, "Kill"); // should be safer
	}

	g_bEndOfRound = false; // stop hooking entity destruction until restart of round
}


bool IsPlayerObserving(int client)
{
	int mode = GetEntProp(client, Prop_Send, "m_iObserverMode");

	#if DEBUG
	// note movetype is most likely 10 too
	PrintToServer("[nt_ghostcapsfx] %N %s observing: m_iObserverMode %d", client, (mode ? "is" : "is not"), mode);
	#endif

	if(mode) // 0 means most likely alive
		return true;
	return false;
}
