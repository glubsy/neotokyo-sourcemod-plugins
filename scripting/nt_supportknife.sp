#include <sourcemod>
#include <sdktools>
#include <neotokyo>

new bool:IsClientSupport[MAXPLAYERS+1]

public Plugin:myinfo = 
{
	name = "Neotokyo: give knife to supports",
	author = "glub",
	description = "Automatically give a knife to support class on spawn",
	version = "0.1",
	url = "https://github.com/glubsy"
}

public OnPluginStart()
{
	AddCommandListener(cmd_handler, "setclass");
	HookEvent("player_spawn", event_PlayerSpawn);
}

public Action:cmd_handler(client, const String:command[], args)
{
	decl String:cmd[3];
	GetCmdArgString(cmd, sizeof(cmd));

	new arg = StringToInt(cmd);

	if(StrEqual(command, "setclass"))
	{
		if (arg == 3)
		{
			//PrintToChat(client, "You're support!");
			IsClientSupport[client] = true;
			return Plugin_Continue;
		}
		else
		{
			IsClientSupport[client] = false;
		}
	}
	return Plugin_Continue;
}

public event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsClientInGame(client))
		return;
	if(IsClientSupport[client])
	{
		GivePlayerItem(client, "weapon_knife");
		ClientCommand(client, "slot1");
	}
}
