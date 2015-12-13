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

public Action:Command_JoinTeam(client, const String:command[], argc) 
{
	new clientTeam = GetClientTeam(client);
	if(!IsPlayerAlive(client))
	{
		CreateTimer(0.0, ClearOverlay, client);
		ClientCommand(client, "r_screenoverlay 0");
		PrintToServer("Hook: Changed team to %d", clientTeam);
	}	
	return Plugin_Continue;
}



public OnClientCookiesCached(client) {
}
public OnClientPostAdminCheck(client) {
    if (AreClientCookiesCached(client))
	{
		ProcessCookies(client);
	}
	
	if(IsClientInGame(client) && client > 0 && !IsFakeClient(client) && IsClientConnected(client))
	{
		ClientCommand(client, "r_screenoverlay off");
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
		CreateTimer(15.0, DisplayNotification, client);
		return;
	}
	if (StrEqual(cookie, "disabled")) {
		g_OverlayDisabled[client] = true;
		CreateTimer(15.0, DisplayNotification, client);
		return;
	}
	else
	{
		CreateTimer(15.0, DisplayNotification, client);
	}
	return;
}

public Action:DisplayNotification(Handle:timer, client)
{
	if(client > 0)
	{
		if(g_OverlayDisabled[client] == false)
			PrintToChat(client, "You can disable Cyborg vision by typing !vision");
			PrintToConsole(client, "You can disable Cyborg vision by typing sm_vision");
		if(g_OverlayDisabled[client] == true)
			PrintToChat(client, "You can re-enable Cyborg vision by typing !vision");
			PrintToConsole(client, "You can re-enable Cyborg vision by typing sm_vision");
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
	} 
	PrintToChat(client, "Cyborg vision re-enabled.");
	SetClientCookie(client, g_cookies[0], "enabled");
}
public Action:DisableVision(client)
{
	ClientCommand(client, "r_screenoverlay off");
	g_OverlayDisabled[client] = true;
	PrintToChat(client, "Cyborg vision now disabled.");
	SetClientCookie(client, g_cookies[0], "disabled");
}

public OnPlayerSpawn(Handle:event,const String:name[],bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new clientTeam = GetClientTeam(client);
	if(!IsPlayerAlive(client) || IsClientObserver(client))
	{
		ClientCommand(client, "r_screenoverlay off");
		return;
	}
	
	
	if(g_OverlayDisabled[client] == true && clientTeam > 1 && IsPlayerAlive(client))
	{
		PrintToServer("overlay is disabled: %d, client: %d", g_OverlayDisabled[client], client); //do nothing
	}
	if (g_OverlayDisabled[client] == false && clientTeam >= 2 && IsPlayerAlive(client) && g_OverlayActive[client] == false && !IsClientObserver(client))
	{
		ClientCommand(client, "r_screenoverlay effects/combine_binocoverlay.vmt");
		PrintToServer("overlay disabled: %d client: %d", g_OverlayDisabled[client], client);
		g_OverlayActive[client] = true;
	}
}

public OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(g_OverlayActive[client] == true)
	{
		CreateTimer(6.0, ClearOverlay, client);
	}

}

public Action:ClearOverlay(Handle:timer, client)
{
	if(IsClientConnected(client) && IsClientInGame(client))
		ClientCommand(client, "r_screenoverlay off");
		g_OverlayActive[client] = false;
}

public OnClientDisconnect(client)
{
	ClientCommand(client, "r_screenoverlay off");
	g_OverlayActive[client] = false;
	g_OverlayDisabled[client] = false;
}
