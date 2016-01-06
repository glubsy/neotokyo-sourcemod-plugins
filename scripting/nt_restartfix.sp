/**************************************************************
--------------------------------------------------------------
 NEOTOKYO° Restart Fix

 Plugin licensed under the GPLv3
 
 Coded by Agiel.
--------------------------------------------------------------

Changelog

	1.0.0
		* Initial release
	1.0.1
		* Added neo_restart command which initiates a 
		  countdown timer. Looks pretty neat and fixes 
		  the bugged loadout menu by resetting the 
		  scores 1 second before the actual restart.
	1.0.2
		* Round counter is now reset.
	1.0.3
		* neo_restart_this 2 resets current round only and
		  resets players' scores to what they were at the
		  beginning of it.
		* neo_restart 2 works the same way. -glub
**************************************************************/
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION	"1.0.2"

int LastXP[MAXPLAYERS+1], LastDeaths[MAXPLAYERS+1], LastRank[MAXPLAYERS+1];

public Plugin:myinfo =
{
    name = "NEOTOKYO° Restart Fix",
    author = "Agiel",
    description = "Resets deaths on neo_restart_this 1 in NEOTOKYO°",
    version = PLUGIN_VERSION,
    url = ""
};

new Handle:convar_nt_restart_fix_version = INVALID_HANDLE;
new Handle:g_timer;

public OnPluginStart()
{
	convar_nt_restart_fix_version = CreateConVar("sm_nt_restart_fix_version", PLUGIN_VERSION, "NEOTOKYO° Restart Fix.", FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true);
	SetConVarString(convar_nt_restart_fix_version, PLUGIN_VERSION, true, true);

	HookEvent("game_round_start", OnRoundStart);
	RegServerCmd("neo_restart", Restart);
	HookConVarChange(FindConVar("neo_restart_this"), Event_Restart);
}

new count;

public Action:Restart(args)
{
	char cmd[2];
	GetCmdArgString(cmd, sizeof(cmd));
	int resettype = StringToInt(cmd);
	
	count = 0;
	if(resettype == 2)
		PrintToChatAll("Restarting current round in...");
	else
		PrintToChatAll("Restarting in...");
	
	g_timer = CreateTimer(1.0, CountDown, resettype, TIMER_REPEAT);
}

public Action:CountDown(Handle:timer, int resettype)
{
	switch (count)
	{
		case 1:
		{
			PrintToChatAll("3");
		}
		case 2:
		{
			PrintToChatAll("2");
		}
		case 3:
		{
			PrintToChatAll("1");
			if(resettype <= 1)
			{

				for (new i = 1; i <= MaxClients; i++)
				{
					if (IsValidClient(i))
					{
						SetEntProp(i, Prop_Data, "m_iFrags", 0);
						SetEntProp(i, Prop_Data, "m_iDeaths", 0);
						SetEntProp(i, Prop_Send, "m_iRank", 1);
					}
				}
			}
		}
		case 4:
		{
			if(resettype <= 1)
				SetConVarInt(FindConVar("neo_restart_this"), 1);
			else
				SetConVarInt(FindConVar("neo_restart_this"), 2);
		}
		case 9:
		{
			if(resettype <= 1)
				PrintToChatAll("Restarted Match.");
			else
				PrintToChatAll("Restarted Round.");
		}
		case 10:
		{
			PrintToChatAll("LIVE LIVE LIVE!");
			g_timer = INVALID_HANDLE;
			return Plugin_Stop;
		}
	}
	count++;
	return Plugin_Continue;
}

public Event_Restart(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (StringToInt(newVal) == 1)
	{
		GameRules_SetProp("m_iRoundNumber", 0);

		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i))
			{
				//PrintToServer("Resetting deaths for %N.", i);
				SetEntProp(i, Prop_Data, "m_iDeaths", 0);
			}
		}
	}
	else if (StringToInt(newVal) == 2)
	{
		int RoundNum = GameRules_GetProp("m_iRoundNumber");
		GameRules_SetProp("m_iRoundNumber", RoundNum - 1);

		CreateTimer(1.0, RestorePreviousScores);
	}
}

public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	CreateTimer(15.0, SaveCurrentScores); //saving once freeze time ended
}

public Action RestorePreviousScores(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			SetEntProp(i, Prop_Data, "m_iFrags", LastXP[i]);
			SetEntProp(i, Prop_Data, "m_iDeaths", LastDeaths[i]);
			SetEntProp(i, Prop_Send, "m_iRank", LastRank[i]);
		}
	}
}

public Action SaveCurrentScores(Handle timer)
{
	//Storing current client scores and deaths
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			LastXP[i] = GetClientFrags(i);
			LastDeaths[i] = GetEntProp(i, Prop_Data, "m_iDeaths");
			LastRank[i] = GetEntProp(i, Prop_Send, "m_iRank");
		}
	}
	
}

bool:IsValidClient(client)
{
	
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