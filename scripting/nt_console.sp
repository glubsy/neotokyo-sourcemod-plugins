#pragma semicolon 1
#include <sourcemod>
#define PLUGIN_VERSION "0.3"

public Plugin:myinfo = {
        name	= "Console opening helper",
        description	= "Open client console with !console in chat.",
        version	= PLUGIN_VERSION,
        author	= "Rain, glub",
        url	 	= "github.com/rainyan"
};

new Handle:convar_kill_disabled;

public OnPluginStart()
{
	convar_kill_disabled = CreateConVar("nt_kill_disabled", "1", "Enables or Disables kill (suicide) command.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	RegConsoleCmd("sm_console", Command_ToggleConsole);
	AddCommandListener(Command_kill, "kill");
	AddCommandListener(Command_kill, "hurtme");
}
 
public Action:Command_ToggleConsole(client, args)
{
	ClientCommand(client, "toggleconsole");
	PrintToConsole(client, "\nConsole opened.\nYou can bind this to a key with the following command:\nbind x toggleconsole (replace x with the key you wish to bind)\n");
	return Plugin_Handled;
}

public Action:Command_kill(client, const String:command[], argc)
{
	if (IsAdmin(client))
		return Plugin_Continue;

	if(GetConVarBool(convar_kill_disabled))
	{
		if(IsPlayerAlive(client))
		{
			PrintToConsole(client, "[nt_console] This command is disabled.");
		}
		return Plugin_Handled;
	}
	if(!GetConVarBool(convar_kill_disabled))
		return Plugin_Continue;
	return Plugin_Handled;
}

bool IsValidClient(int client){

	if (client == 0)
		return false;

	if (!IsClientConnected(client))
		return false;

	if (IsFakeClient(client))
		return false;

	if (!IsClientInGame(client))
		return false;

	return true;
}

bool IsAdmin(int client)
{
	if (!IsValidClient(client) || !IsClientAuthorized(client))
	{
		LogError("[nt_console] IsAdmin: Client %i is not valid. This shouldn't happen.", client);
		return false;
	}
	AdminId adminId = GetUserAdmin(client);
	if (adminId == INVALID_ADMIN_ID)
	{
		return false;
	}
	return GetAdminFlag(adminId, Admin_Generic);
}
