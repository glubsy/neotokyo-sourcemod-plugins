#include <sourcemod>
#include <clientprefs>

public Plugin:myinfo = 
{
	name = "Neotokyo Cyborg Vision",
	author = "glub",
	description = "Places an overlay on players' field of view",
	version = "0.3",
	url = "https://github.com/glubsy"
};


//new const String:overlayfile[] = "effects/combine_binocoverlay.vmt";
bool g_OverlayDisabled[MAXPLAYERS+1];
bool g_OverlayActive[MAXPLAYERS+1];
bool g_bPluginEnabled;
Handle convar_cyborgvision_enabled = INVALID_HANDLE;
Handle ghcookie = INVALID_HANDLE;

//NOTE: this plugin is outdated, terribly done and would need to be redone if it wasn't so superflous and useless

public OnPluginStart(){
	RegConsoleCmd("sm_vision", Command_ToggleVision, "Toggles cyborg vision on/off.")
	convar_cyborgvision_enabled = CreateConVar("nt_cyorgvision_enabled", "0", "Enables automatic cyborg vision on connect.")

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);

	if(!AddCommandListener(Command_JoinTeam, "jointeam"))
		PrintToServer("jointeam listening not available in this mod!")
	

	ghcookie = FindClientCookie("overlay-disabled");
	if (ghcookie == INVALID_HANDLE)
		ghcookie = RegClientCookie("overlay-disabled", "cyborg vision disable status", CookieAccess_Protected);
}

public OnConfigsExecuted()
{
	if(GetConVarBool(convar_cyborgvision_enabled))
		g_bPluginEnabled = true;
}

public OnClientCookiesCached(int client)
{
}

public OnClientPostAdminCheck(int client)
{
	if(!g_bPluginEnabled)
	{
		g_OverlayDisabled[client] = true;
		return;
	}

	if (AreClientCookiesCached(client))
	{
		ProcessCookies(client);
	}
	if(client > 0 && IsClientInGame(client) && !IsFakeClient(client))
	{
		// Active by default!
		ClientCommand(client, "r_screenoverlay off");
		g_OverlayActive[client] = false;
	}
}

public void ProcessCookies(int client)
{
	char cookie[2];
	GetClientCookie(client, ghcookie, cookie, sizeof(cookie));

	if (cookie[0] != '\0') // we have a cookie
	{
		g_OverlayDisabled[client] = view_as<bool>(StringToInt(cookie));
		CreateTimer(22.0, DisplayNotification, GetClientUserId(client));
	}
	else
	{
		CreateTimer(22.0, DisplayNotification, GetClientUserId(client));
	}
}

public Action DisplayNotification(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (client <= 0 || !IsClientInGame(client))
		return Plugin_Stop;

	if(g_OverlayDisabled[client] == true)
	{
		PrintToChat(client, "[SM] You can re-enable Cyborg vision by typing !vision");
		PrintToConsole(client, "\n[SM] You can re-enable Cyborg vision by typing sm_vision\n");
	}
	else
	{
		PrintToChat(client, "[SM] You can disable Cyborg vision by typing !vision");
		PrintToConsole(client, "\n[SM] You can disable Cyborg vision by typing sm_vision\n");
	}

	return Plugin_Handled;
}

public Action Command_ToggleVision(int client, args)
{
	if(g_OverlayDisabled[client])
	{
		EnableVision(client);	
		return Plugin_Handled;
	}
	else 
	{ 
		DisableVision(client);
		return Plugin_Handled;
	}
}

public Action EnableVision(int client)
{
	g_OverlayDisabled[client] = false;
	if(IsPlayerAlive(client))
	{
		ClientCommand(client, "r_screenoverlay effects/combine_binocoverlay.vmt");
		g_OverlayActive[client] = true;
	} 
	PrintToChat(client, "[SM] Cyborg vision re-enabled.");
	SetClientCookie(client, ghcookie, "0");
}

public Action DisableVision(int client)
{
	ClientCommand(client, "r_screenoverlay off");
	g_OverlayActive[client] = false;
	g_OverlayDisabled[client] = true;
	PrintToChat(client, "[SM] Cyborg vision now disabled.");
	SetClientCookie(client, ghcookie, "1");
}

public OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new clientTeam = GetClientTeam(client);
	
	if(g_OverlayActive[client] == true)
	{
		return;
	}
	
	if(!IsPlayerAlive(client) || IsClientObserver(client) && !IsFakeClient(client))
	{
		ClientCommand(client, "r_screenoverlay off");
		g_OverlayActive[client] = false;
		return;
	}
	
	if(g_OverlayDisabled[client] && IsPlayerAlive(client) && !IsFakeClient(client))
	{
		//do nothing
		return;
	}
	if (!g_OverlayDisabled[client] && clientTeam >= 2 
	&& IsPlayerAlive(client) && g_OverlayActive[client] == false 
	&& !IsClientObserver(client) && !IsFakeClient(client))
	{
		ClientCommand(client, "r_screenoverlay effects/combine_binocoverlay.vmt");
		g_OverlayActive[client] = true;
	}
}

public OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(g_OverlayActive[client] == true)
	{
		CreateTimer(7.0, ClearOverlay, client);
	}
}



public Action Command_JoinTeam(int client, const char[] command, argc) 
{
	if(client > 0 && !g_OverlayDisabled[client])
	{
		if(!IsPlayerAlive(client))
		{
			CreateTimer(0.0, ClearOverlay, client);
			//ClientCommand(client, "r_screenoverlay off");  //doesn't fire for some reason, need a timer of 0.0
			//g_OverlayActive[client] = false;
			//PrintToServer("Hook: Changed team to %d", clientTeam); 
		}	
		return Plugin_Continue;
	}
	return Plugin_Continue;
}

public Action ClearOverlay(Handle timer, int client)
{
	if(IsClientConnected(client) && IsClientInGame(client))
	{
		ClientCommand(client, "r_screenoverlay off");
		g_OverlayActive[client] = false;
	}
}

public OnMapEnd()
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if((IsClientInGame(i) && IsPlayerAlive(i)) && g_OverlayActive[i])
		{
			ClientCommand(i, "r_screenoverlay off");
			g_OverlayActive[i] = false;
		}
	}
}

public OnClientDisconnect(int client)
{
	//ClientCommand(client, "r_screenoverlay off");
	g_OverlayActive[client] = false;
	if(g_bPluginEnabled)
		g_OverlayDisabled[client] = false;
}