#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <neotokyo>
#undef REQUIRE_PLUGIN
#include <nt_menu>

#define NEO_MAX_CLIENTS 32

#if !defined DEBUG
#define DEBUG 0
#endif

Handle g_hCurrentlyPlaying[NEO_MAX_CLIENTS] = {INVALID_HANDLE, ...};
const int MAX_SND_INSTANCES = 5; // maximum concurent sounds allowed to be amitted over CVAR_hurt_sounds_delay period, for security
int g_iSoundInstances = 0;
int g_iAffectedPlayers[NEO_MAX_CLIENTS+1][NEO_MAX_CLIENTS+1]; // arrays of affected players
int g_iAffectedNumPlayers[NEO_MAX_CLIENTS+1] = { 0, ...}; // number of affected players in the array above
Handle g_RefreshArrayTimer = INVALID_HANDLE;
Handle CVAR_hurt_sounds_active, CVAR_team_only, CVAR_spec_only, CVAR_hurt_sounds_delay, CVAR_hurt_sounds_override = INVALID_HANDLE;
char g_sCustomGirlHurtSound[][] = {
	"custom/himitu09065b.mp3",
	"custom/himitu09065.mp3",
	"custom/himitu09066.mp3",
	"custom/himitu09068.mp3",
	"custom/himitu09071.mp3",
	"custom/himitu09080.mp3",
};

// Menu setup
TopMenuObject g_hTopMainMenu_topmenuobj = INVALID_TOPMENUOBJECT;
TopMenuObject g_tmo_prefs = INVALID_TOPMENUOBJECT;
TopMenu g_hTopMenu; // handle to the nt_menu plugin topmenu
Handle g_hPrefsMenu;
bool g_bClientWantsSFX[NEO_MAX_CLIENTS+1];
Handle g_hPrefCookie = INVALID_HANDLE; // handle to cookie in DB

// TODO: assign a specific set of similar sounds for each player?
// TODO: use bitbuffer instead of arrays to keep track of affected players?
// TODO: let users select the type of sounds they want

public Plugin:myinfo =
{
	name = "NEOTOKYO pain sound effects",
	author = "glub",
	description = "Emit sounds when player gets hurt.",
	version = "0.1",
	url = "https://github.com/glubsy"
};

public void OnPluginStart()
{
	CVAR_hurt_sounds_active = CreateConVar("sm_pain_sounds_active", "1",
	"Enable (1) or disable (0) emitting custom sounds when players are hurt.", 0, true, 0.0, true, 1.0);

	CVAR_hurt_sounds_override = CreateConVar("sm_pain_sounds_force_on", "0",
	"(1) force opt-out mode for all players who have not already explicitly opted-out.", 0, true, 0.0, true, 1.0);

	CVAR_hurt_sounds_delay = CreateConVar("sm_pain_sounds_delay", "8.5",
	"Delay until more hurt sounds may be emitted by a player.", 0, true, 0.0, true, 500.0);

	CVAR_team_only = CreateConVar("sm_pain_sounds_team_only", "1",
	"Enable (1) or disable (0) emitting custom sounds from team mates only.", 0, true, 0.0, true, 1.0);

	CVAR_spec_only = CreateConVar("sm_pain_sounds_spec_only", "0",
	"Enable (1) or disable (0) emitting custom sounds for alive players.", 0, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_pain_sounds", ConCommand_Prefs, "Hurt players emit moaning sound effects when active.");
	RegConsoleCmd("sm_pain_sfx_status", ConCommand_Status, "Display who is seeing props or not.");

	#if DEBUG > 1
	AddNormalSoundHook(OnNormalSound);
	#endif

	HookConVarChange(CVAR_hurt_sounds_active, OnConVarChanged);
	HookConVarChange(CVAR_hurt_sounds_override, OnConVarChanged);

	g_hPrefCookie = FindClientCookie("wants-pain-sfx");
	if (g_hPrefCookie == INVALID_HANDLE)
		g_hPrefCookie = RegClientCookie("wants-pain-sfx", "player opted to hear custom sounds when a player is hurt", CookieAccess_Protected);

	// late loading
	for (new i = MaxClients; i > 0; --i)
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


public OnNTMenuReady(Handle aTopMenu)
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
	AutoExecConfig(true, "nt_pain_sfx");

	if (!GetConVarBool(CVAR_hurt_sounds_active))
		return;

	HookEvent("player_hurt", Event_OnPlayerHurt, EventHookMode_Pre);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("game_round_start", Event_OnRoundStart);
	HookEvent("player_spawn", Event_OnPlayerSpawn);

	#if DEBUG
	// tempents probably won't generate errors when sending to disconnected clients
	// so maybe we don't really need to update arrays here
	HookEvent("player_disconnect", Event_OnPlayerDisconnect);
	#endif

	for(int snd = 0; snd < sizeof(g_sCustomGirlHurtSound); snd++)
	{
		PrecacheSound(g_sCustomGirlHurtSound[snd], true);
		decl String:buffer[120];
		Format(buffer, sizeof(buffer), "sound/%s", g_sCustomGirlHurtSound[snd]);
		AddFileToDownloadsTable(buffer);
	}

	// reset arrays for all
	UpdateAffectedArrayForAlivePlayers(-1);
}


public void OnConVarChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (!GetConVarBool(CVAR_hurt_sounds_active))
	{
		UnhookEvent("player_hurt", Event_OnPlayerHurt);
		UnhookEvent("player_death", Event_OnPlayerDeath);
		UnhookEvent("game_round_start", Event_OnRoundStart);
		UnhookEvent("player_spawn", Event_OnPlayerSpawn);

		#if DEBUG
		// tempents probably won't generate errors when sending to disconnected clients
		// so maybe we don't really need to update arrays here
		UnhookEvent("player_disconnect", Event_OnPlayerDisconnect);
		#endif
		return;
	}
	else
	{
		HookEvent("player_hurt", Event_OnPlayerHurt);
		HookEvent("player_death", Event_OnPlayerDeath);
		HookEvent("game_round_start", Event_OnRoundStart);
		HookEvent("player_spawn", Event_OnPlayerSpawn);

		#if DEBUG
		// tempents probably won't generate errors when sending to disconnected clients
		// so maybe we don't really need all this in order to update arrays here
		HookEvent("player_disconnect", Event_OnPlayerDisconnect);
		#endif
	}

	if (convar == CVAR_hurt_sounds_override)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || !IsValidClient(i) || !IsClientConnected(i) | !IsFakeClient(i))
				continue;
			ReadCookies(i); // force checking cookies and setting default pref value of true when possible
		}
		UpdateAffectedArrayForAlivePlayers(-1);
	}
}


void BuildTopMenu()
{
	g_hTopMainMenu_topmenuobj = FindTopMenuCategory(g_hTopMenu, "Various effects"); // get the category provided by nt_menu plugin

	if (g_hTopMainMenu_topmenuobj != INVALID_TOPMENUOBJECT)
	{
		// AddToTopMenu(g_hTopMenu, "nt_menu", TopMenuObject_Item, TopCategory_Handler, g_hTopMainMenu_topmenuobj, "nt_menu", 0);
		g_tmo_prefs = g_hTopMenu.AddItem("sm_pain_sfx_prefs", TopMenuCategory_Handler, g_hTopMainMenu_topmenuobj, "sm_pain_sfx_prefs");
		return;
	}

	// didn't find categories, must be missing nt_menu plugin, so build our own category and attach to it
	g_hTopMainMenu_topmenuobj = g_hTopMenu.AddCategory("Various effects", TopMenuCategory_Handler);

	g_tmo_prefs = AddToTopMenu(g_hTopMenu, "sm_pain_sfx_prefs", TopMenuObject_Item, TopMenuCategory_Handler, g_hTopMainMenu_topmenuobj, "sm_pain_sfx_prefs");
}



public TopMenuCategory_Handler (Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if ((action == TopMenuAction_DisplayOption) || (action == TopMenuAction_DisplayTitle))
	{
		// GetTopMenuObjName(topmenu, object_id, buffer, maxlength);

		if (object_id == INVALID_TOPMENUOBJECT)
			Format(buffer, maxlength, "Neotokyo Menu", param);
		if (object_id == g_tmo_prefs)
			Format(buffer, maxlength, "%s", "Pain sound effects", param);
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
			menu.SetTitle("Pain sound effects preference:");
			menu.AddItem("a", "Set preference");
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
			// CloseHandle(menu); // breaks toggles
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
				case 'a': // in case we add more fine grain control later
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

			char display[30];

			if (StrEqual(info, "a")) // toggle item
			{
				Format(display, sizeof(display), "Pain sounds are: [%s]", (g_bClientWantsSFX[param1] ? "enabled" : "disabled" ));
				return RedrawMenuItem(display);
			}
			return 0;
		}
	}
	return 0;
}


public Action ConCommand_Prefs(int client, int args)
{
	ToggleCookiePreference(client);
	PrintToChat(client, "[nt_pain_sfx] You have %s hear sound effects when players get hurt.", 
	(g_bClientWantsSFX[client] ? "opted to" : "opted not to"));
}


// "Called once a client's saved cookies have been loaded from the database"
public OnClientCookiesCached(int client)
{
	#if DEBUG
	PrintToServer("[nt_pain_sfx] OnClientCookiesCached(%d)", client)
	#endif
	ReadCookies(client);
}


public OnClientPostAdminCheck(int client)
{
	#if DEBUG
	PrintToServer("[nt_pain_sfx] OnClientPostAdminCheck(%d)", client)
	#endif
	if (AreClientCookiesCached(client))
	{
		ReadCookies(client);
	}
}


public Action timer_AdvertiseHelp(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (!IsValidClient(client))
		return Plugin_Stop;
	PrintToChat(client, "[nt_pain_sfx] You can toggle pain sound effects with !pain_sounds");
	return Plugin_Stop;
}


public OnClientDisconnect(int client)
{
	// might not be needed since we check and set on connect
	g_bClientWantsSFX[client] = false;
	UpdateAffectedArrayForAlivePlayers(-1);
}


// returns true only if previous cookies were found
void ReadCookies(int client)
{
	if (!IsValidClient(client))
		return;

	char cookie[2];
	GetClientCookie(client, g_hPrefCookie, cookie, sizeof(cookie));

	#if DEBUG
	PrintToServer("[nt_pain_sfx] DEBUG ReadCookies(%N) cookie is: \"%s\"",
	client, ((cookie[0] != '\0' && StringToInt(cookie)) ? cookie : "null" ));
	#endif

	if (GetConVarBool(CVAR_hurt_sounds_override))
	{
		if (cookie[0] != '\0')
			g_bClientWantsSFX[client] = view_as<bool>(StringToInt(cookie));
		else
			g_bClientWantsSFX[client] = true; //override mode defaults to true unless cookie says otherwise
	}
	else
		g_bClientWantsSFX[client] = (cookie[0] != '\0' && StringToInt(cookie));
}


// Toggle bool + cookie
void ToggleCookiePreference(int client)
{
	if (!IsValidClient(client))
		return;

	#if DEBUG
	PrintToServer("[nt_pain_sfx] DEBUG Pref for %N was %s -> bool toggled.", client, (g_bClientWantsSFX[client] ? "true" : "false"));
	#endif

	g_bClientWantsSFX[client] = !g_bClientWantsSFX[client];

	SetClientCookie(client, g_hPrefCookie, (g_bClientWantsSFX[client] ? "1" : "0"));

	UpdateAffectedArrayForAlivePlayers(client);
}



public Action Event_OnPlayerSpawn(Event event, const char[] name, bool dontbroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);
	// if (!IsValidClient(client))
	// 	return Plugin_Continue;

	#if DEBUG
	PrintToServer("[nt_pain_sfx] Event_OnPlayerSpawn(%d) (%N)", client, client);
	#endif

	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1 
	|| GetEntProp(client, Prop_Send, "deadflag"))
	{
		#if DEBUG
		PrintToServer("[nt_pain_sfx] client %N spawned but is actually dead!", client);
		#endif
		return Plugin_Continue;
	}


	// for players spawning after freeze time has already ended
	if (g_RefreshArrayTimer == INVALID_HANDLE)
		g_RefreshArrayTimer = CreateTimer(10.0, timer_RefreshArraysForAll, -1, 
		TIMER_FLAG_NO_MAPCHANGE);

	#if DEBUG
	CreateTimer(20.0, timer_PrintArray, userid);
	#endif

	return Plugin_Continue;
}


public Action timer_PrintArray(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	for (int i = 0; i < g_iAffectedNumPlayers[client]; i++)
		PrintToServer("[nt_pain_sfx] timer_PrintArray() g_iAffectedPlayers[%N][%i] affected client index %d (%N)",
		client, i, g_iAffectedPlayers[client][i], g_iAffectedPlayers[client][i]);
}

// This might not be needed if we do the same on player spawn
public Action Event_OnRoundStart(Event event, const char[] name, bool dontbroadcast)
{
	#if DEBUG
	PrintToServer("[nt_pain_sfx] OnRoundStart()")
	#endif

	// 15 seconds should be right when freeze time ends
	g_RefreshArrayTimer = CreateTimer(15.0, timer_RefreshArraysForAll, -1, TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_RefreshArraysForAll(Handle timer, int userid)
{
	#if DEBUG
	PrintToServer("[nt_pain_sfx] Timer now calling UpdateAffectedArrayForAlivePlayers(%d).", userid);
	#endif

	if (userid > 0)
		UpdateAffectedArrayForAlivePlayers(GetClientOfUserId(userid));
	else
		UpdateAffectedArrayForAlivePlayers(-1) // should be -1 here, forcing refresh for all arrays

	if (g_RefreshArrayTimer != INVALID_HANDLE)
		g_RefreshArrayTimer = INVALID_HANDLE;
	return Plugin_Stop;
}


public Action Event_OnPlayerHurt(Event event, const char[] name, bool dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int health = GetEventInt(event, "health");

	if (health <= 1) //don't play any sound on death, could even play a different sound too
	{
		#if DEBUG
		PrintToServer("[nt_pain_sfx] health on hurt is <= 1. Skipping.");
		#endif
		return Plugin_Continue;
	}

	if (g_hCurrentlyPlaying[client] == INVALID_HANDLE && 
		g_iSoundInstances <= MAX_SND_INSTANCES)
	{
		EmitHurtSoundFromClientPos(client);
		++g_iSoundInstances;
		// we allow playing one sound clip every range of seconds
		g_hCurrentlyPlaying[client] = CreateTimer(
		GetConVarFloat(CVAR_hurt_sounds_delay), timer_ResetPlayingFlag, client, 
		TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}


public Action Event_OnPlayerDeath(Event event, const char[] name, bool dontbroadcast)
{
	int userid = GetEventInt(event, "userid");

	#if DEBUG
	PrintToServer("[nt_pain_sfx] %N died, asking to update arrays.", 
	GetClientOfUserId(userid));
	#endif

	if (g_RefreshArrayTimer == INVALID_HANDLE)
		g_RefreshArrayTimer = CreateTimer(1.5, timer_RefreshArraysForAll, userid, 
		TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


public void OnClientPutInServer(int client)
{
	g_bClientWantsSFX[client] = false; // by default, we need to opt-in to be affected
	int userid = GetClientUserId(client);

	if (g_RefreshArrayTimer == INVALID_HANDLE)
		g_RefreshArrayTimer = CreateTimer(3.5, timer_RefreshArraysForAll, userid, 
		TIMER_FLAG_NO_MAPCHANGE);

	CreateTimer(160.0, timer_AdvertiseHelp, userid, TIMER_FLAG_NO_MAPCHANGE);
}


public Action Event_OnPlayerDisconnect(Event event, const char[] name, bool dontbroadcast)
{
	int userid = GetEventInt(event, "userid");
	int disconnected = GetClientOfUserId(userid);

	#if DEBUG
	PrintToServer("[nt_pain_sfx] Client %d just disconnected. Asking for array refresh.", disconnected);
	#endif

	if (disconnected < 1)
		disconnected = -1;

	if (g_RefreshArrayTimer == INVALID_HANDLE)
		// delay because when disconnecting, player is respawning and considered still "alive", which is wrong!
		g_RefreshArrayTimer = CreateTimer(0.5, timer_RefreshArraysForAll, disconnected, TIMER_FLAG_NO_MAPCHANGE);
}


// for each alive player, update their array to reflect updated_client being affected
public void UpdateAffectedArrayForAlivePlayers(int updated_client)
{
	// WARNING: updated_client can be -1 here!
	for (int client = 1; client <= MaxClients; ++client)
	{
		if (!IsValidClient(client) || !IsClientConnected(client) || !IsClientInGame(client))
		{
			#if DEBUG > 1
			PrintToServer("[nt_pain_sfx] client %d is either not valid or not connected", client);
			#endif

			continue;
		}

		if (client == updated_client) // don't emit for ourselves
			continue;

		if (!IsPlayerReallyAlive(client)) // dead players wouldn't emit any sound
			continue;

		if (!IsValidClient(updated_client) || (updated_client > 0 && !g_bClientWantsSFX[updated_client]))
		{
			#if DEBUG
			PrintToServer("[nt_pain_sfx] A player has to be removed, rebuilding array for %N.", client);
			#endif

			// CAVEAT: whenever an affected player is to be taken out of the emitting player's array
			// we have no choice but to rebuild the entire array :( There might be a better way?

			g_iAffectedNumPlayers[client] = 0; // reset

			for (int j = 1; j <= MaxClients; j++)
			{
				if (!IsValidClient(j) || !IsClientConnected(j))
					continue;

				if (j == client || !g_bClientWantsSFX[j])
					continue; // we shouldn't emit for ourselves

				if (IsPlayerReallyAlive(j))
				{
					#if DEBUG > 1
					PrintToServer("[nt_pain_sfx] Player \"%N\" is alive.", j)
					#endif

					if (GetConVarBool(CVAR_spec_only))
						continue;
					if (GetConVarBool(CVAR_team_only) && (GetClientTeam(j) != GetClientTeam(client)))
						continue;

					#if DEBUG > 1
					PrintToServer("[nt_pain_sfx] Adding %N to array for %N.", j, client)
					#endif

					g_iAffectedPlayers[client][g_iAffectedNumPlayers[client]++] = j;
					continue;
				}
				#if DEBUG > 1
				PrintToServer("[nt_pain_sfx] Player \"%N\" is not alive. Adding \"%N\" to array for %N.",j, j, client)
				#endif
				g_iAffectedPlayers[client][g_iAffectedNumPlayers[client]++] = j;

			}
			continue;
		}

		// avoid duplicates
		bool found;
		for (int k = 1; k <= MaxClients; k++)
		{
			if (g_iAffectedPlayers[client][k] == updated_client)
			{
				found = true;
				break;
			}
		}

		if (!found) 
		{
			#if DEBUG > 1
			PrintToServer("[nt_pain_sfx] Adding \"%N\" to array for %N.", updated_client, client);
			#endif
			g_iAffectedPlayers[client][g_iAffectedNumPlayers[client]++] = updated_client;
		}
	}
}


void EmitHurtSoundFromClientPos(int client)
{
	int rand = GetRandomInt(0, sizeof(g_sCustomGirlHurtSound) -1);
	float vecEyeAngles[3], vecOrigin[3];
	GetClientEyeAngles(client, vecEyeAngles);
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[0] += 15.0 * Cosine(DegToRad(vecEyeAngles[1]));
	vecOrigin[1] += 15.0 * Sine(DegToRad(vecEyeAngles[1]));
	vecOrigin[2] -= 15;

	#if DEBUG
	PrintToServer("[nt_pain_sfx] Emitting sound %s at %f %f %f.\nFor clients (%d) affected by %N:",
	g_sCustomGirlHurtSound[rand], vecOrigin[0], vecOrigin[1], vecOrigin[2], g_iAffectedNumPlayers[client], client);

	if (g_iAffectedNumPlayers[client] > 0)
	{
		for (int i = 0; i < g_iAffectedNumPlayers[client]; i++)
		{
			PrintToServer("[nt_pain_sfx] %i: %N", i, g_iAffectedPlayers[client][i]);
		}
	}
	else
	{
		PrintToServer("[nt_pain_sfx] NONE!");
	}
	#endif

	EmitSound(g_iAffectedPlayers[client], g_iAffectedNumPlayers[client],
				g_sCustomGirlHurtSound[rand],
				SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL,
				GetRandomInt(95, 110), -1, vecOrigin, vecEyeAngles);
	//StopSoundPerm(client, g_sCustomGirlHurtSound[rand]);
}


public Action timer_ResetPlayingFlag(Handle timer, int client)
{
	g_hCurrentlyPlaying[client] = INVALID_HANDLE;
	--g_iSoundInstances;
	return Plugin_Stop;
}

#if DEBUG > 1
public Action OnNormalSound(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity,
 					 int &channel, float &volume, int &level, int &pitch, int &flags)
{
	PrintToChatAll("[nt_pain_sfx] Sound: %s emitted for %d clients.", sample, numClients);
	PrintToServer("[nt_pain_sfx] Sound: %s emitted for %d clients.", sample, numClients);
	return Plugin_Continue;
}
#endif //DEBUG


void StopSoundPerm(int client, char[] sound)
{
	if(IsClientConnected(client) && IsClientInGame(client))
	{
		StopSound(client, SNDCHAN_AUTO, sound);
		StopSound(client, SNDCHAN_WEAPON, sound);
		StopSound(client, SNDCHAN_VOICE, sound);
		StopSound(client, SNDCHAN_ITEM, sound);
		StopSound(client, SNDCHAN_BODY, sound);
		StopSound(client, SNDCHAN_STREAM, sound);
		StopSound(client, SNDCHAN_VOICE_BASE, sound);
		StopSound(client, SNDCHAN_USER_BASE, sound);
		#if DEBUG > 0
		PrintToChatAll("[nt_pain_sfx] Stopped sound for %N", client);
		#endif
	}
}



public Action ConCommand_Status(int client, int args)
{
	char optedin[1000], optedout[1000], name[MAX_NAME_LENGTH];
	int countin, countout;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsClientConnected(i) || IsFakeClient(i))
			continue;

		if (g_bClientWantsSFX[i])
		{
			Format(name, sizeof(name), "%N\n", i);
			StrCat(optedin, sizeof(optedin), name);
			countin++;
		}
		else
		{
			char cookie[2];
			GetClientCookie(i, g_hPrefCookie, cookie, sizeof(cookie));
			Format(name, sizeof(name), "%N%s\n", i, ((cookie[0] != '\0' && !StringToInt(cookie)) ? " (explicitly)" : "" ));
			StrCat(optedout, sizeof(optedout), name);
			countout++;
		}
	}
	PrintToConsole(client, "Pain sounds are active for:\n%s", (countin ? optedin : "NOBODY! D:"));
	PrintToConsole(client, "Pain sounds are inactive for:\n%s", (countout ? optedout : "NOBODY! :D"));


	return Plugin_Handled;
}


bool IsPlayerReallyAlive(int client)
{
	if ((GetClientTeam(client) < 2)) // not in team, probably spectator
		return false;

	#if DEBUG > 2
	PrintToServer("[nt_pain_sfx] DEBUG: Client %N (%d) has %d health.", client, client, GetEntProp(client, Prop_Send, "m_iHealth"));
	#endif

	// For some reason, 1 health point means dead, but checking deadflag is probably more reliable!
	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1 || GetEntProp(client, Prop_Send, "deadflag"))
	{
		#if DEBUG
		PrintToServer("[nt_pain_sfx] DEBUG: Determined that %N is not alive right now.", client);
		#endif
		return false;
	}

	return true;
}
