#include <sourcemod>
#include <clientprefs>

public Plugin:myinfo = 
{
	name = "Neotokyo Cyborg Vision",
	author = "glub",
	description = "Places an overlay on players' vision",
	version = "0.1",
	url = "https://github.com/glubsy"
};


//new const String:overlayfile[] = "effects/combine_binocoverlay.vmt";
bool:g_OverlayDisabled[MAXPLAYERS+1];
bool:g_OverlayActive[MAXPLAYERS+1];
new Handle:g_cookies[1];

public OnPluginStart(){
	RegConsoleCmd("sm_vision", Command_ToggleVision, "Toggles cyborg vision on/off.")
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	if(!AddCommandListener(Command_JoinTeam, "jointeam"))
		PrintToServer("jointeam listening not available in this mod!")
	
	g_cookies[0] = RegClientCookie("overlay-disabled","cyborg vision disable status", CookieAccess_Public);	
}

public OnClientCookiesCached(client) {
}
public OnClientPostAdminCheck(client)
{
	if (AreClientCookiesCached(client))
	{
		ProcessCookies(client);
	}
	if(IsClientInGame(client) && client > 0 && !IsFakeClient(client) && IsClientConnected(client))
	{
		ClientCommand(client, "r_screenoverlay off");
		g_OverlayActive[client] = false;
	}
}

public ProcessCookies(client)
{
	//if(FindClientCookie("overlay-disabled"))
	//{
	decl String:cookie[10];
	GetClientCookie(client, g_cookies[0], cookie, sizeof(cookie));

	
	if (StrEqual(cookie, "enabled")) {
		g_OverlayDisabled[client] = false;
		CreateTimer(22.0, DisplayNotification, client);
		return;
	}
	if (StrEqual(cookie, "disabled")) {
		g_OverlayDisabled[client] = true;
		CreateTimer(22.0, DisplayNotification, client);
		return;
	}
	else
	{
		CreateTimer(22.0, DisplayNotification, client);
	}
	return;
}

public Action:DisplayNotification(Handle:timer, client)
{
	if(client > 0 && IsClientConnected(client) && IsClientInGame(client))
	{
		if(g_OverlayDisabled[client] == false)
		{
			PrintToChat(client, "[SM] You can disable Cyborg vision by typing !vision");
			PrintToConsole(client, "\n[SM] You can disable Cyborg vision by typing sm_vision\n");
		}
		if(g_OverlayDisabled[client] == true)
		{
			PrintToChat(client, "[SM] You can re-enable Cyborg vision by typing !vision");
			PrintToConsole(client, "\n[SM] You can re-enable Cyborg vision by typing sm_vision\n");
		}
	}
}

public Action:Command_ToggleVision(client, args)
{
	if(g_OverlayDisabled[client]) {
		EnableVision(client);	
		return Plugin_Handled;
	}
	else { 
		DisableVision(client);
		return Plugin_Handled;
	}
}
public Action:EnableVision(client)
{
	g_OverlayDisabled[client] = false;
	if(IsPlayerAlive(client))
	{
		ClientCommand(client, "r_screenoverlay effects/combine_binocoverlay.vmt");
		g_OverlayActive[client] = true;
	} 
	PrintToChat(client, "[SM] Cyborg vision re-enabled.");
	SetClientCookie(client, g_cookies[0], "enabled");
}
public Action:DisableVision(client)
{
	ClientCommand(client, "r_screenoverlay off");
	g_OverlayActive[client] = false;
	g_OverlayDisabled[client] = true;
	PrintToChat(client, "[SM] Cyborg vision now disabled.");
	SetClientCookie(client, g_cookies[0], "disabled");
}

public OnPlayerSpawn(Handle:event,const String:name[],bool:dontBroadcast)
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
	
	if(g_OverlayDisabled[client] == true && IsPlayerAlive(client) && !IsFakeClient(client))
	{
		//PrintToServer("overlay is disabled: %d, client: %d", g_OverlayDisabled[client], client); 
		//do nothing
		return;
	}
	if (g_OverlayDisabled[client] == false && clientTeam >= 2 && IsPlayerAlive(client) && g_OverlayActive[client] == false && !IsClientObserver(client) && !IsFakeClient(client) && IsClientInGame(client))
	{
		ClientCommand(client, "r_screenoverlay effects/combine_binocoverlay.vmt");
		g_OverlayActive[client] = true;
	}
}

public OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(g_OverlayActive[client] == true)
	{
		CreateTimer(7.0, ClearOverlay, client);
	}
}



public Action:Command_JoinTeam(client, const String:command[], argc) 
{
	if(client > 0)
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

public Action:ClearOverlay(Handle:timer, client)
{
	if(IsClientConnected(client) && IsClientInGame(client))
	{
		ClientCommand(client, "r_screenoverlay off");
		g_OverlayActive[client] = false;
	}
}

public OnMapEnd()
{
	for(new i = 1; i < GetMaxClients(); i++)
	{
		if((IsClientInGame(i) && IsPlayerAlive(i)) && g_OverlayActive[i] == true)
		{
			ClientCommand(i, "r_screenoverlay off");
			g_OverlayActive[i] = false;
		}
	}
}

public OnClientDisconnect(client)
{
	//ClientCommand(client, "r_screenoverlay off");
	g_OverlayActive[client] = false;
	g_OverlayDisabled[client] = false;
}