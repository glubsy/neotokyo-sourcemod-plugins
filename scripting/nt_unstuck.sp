#include <sourcemod>
#include <sdktools>


public Plugin:myinfo = 
{
	name = "Unstuck Me!",
	author = "glub",
	description = "Nudges a player in a given direction.",
	version = "1.0",
	url = "https://github.com/glubsy"
}

new Handle:unstuck_cvar_amount = INVALID_HANDLE;
new g_cvar_amount[MAXPLAYERS+1];

public OnPluginStart()
{
	RegConsoleCmd("sm_stuck", Command_UnStuckMe, "Nudges a player in the direction [n-s-e-w]")
	RegConsoleCmd("sm_unstuck", Command_UnStuckMe, "Nudges a player in the direction [n-s-e-w]")
	unstuck_cvar_amount = CreateConVar("nt_unstuck_amount", "40", "Amount of unstuck commands allowed per round/life", FCVAR_REPLICATED | FCVAR_DEMO )

	HookConVarChange(unstuck_cvar_amount, Command_OnChangedCvar);
	
	HookEvent("player_spawn", PlayerSpawn);
	HookEvent("game_round_start", event_RoundStart);
}

public Command_OnChangedCvar(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	for(new i; i <= MAXPLAYERS+1 ; i++)
	{
		g_cvar_amount[i] = GetConVarInt(unstuck_cvar_amount);
		PrintToServer("g_cvar_amount[i]: i = %d amout = %d", i, g_cvar_amount[i]);
	}
}

public Action:Command_UnStuckMe_Up(Handle:timer, client)
{
	new Float:vec[3];

	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	vec[2]=vec[2]+30.0;
	SetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	PrintToChat(client,"You have been given a nudge up.");
}
public Action:Command_UnStuckMe_Down(Handle:timer, client)
{
	new Float:vec[3];

	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	vec[2]=vec[2]-30.0;
	SetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	PrintToChat(client,"You have been given a nudge down.");
}
public Action:Command_UnStuckMe_North(Handle:timer, client)
{
	new Float:vec[3];

	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	vec[0]=vec[0]-30.0;
	SetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	PrintToChat(client,"You have been given a nudge north.");
}
public Action:Command_UnStuckMe_South(Handle:timer, client)
{
	new Float:vec[3];

	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	vec[0]=vec[0]+30.0;
	SetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	PrintToChat(client,"You have been given a nudge south.");
}
public Action:Command_UnStuckMe_East(Handle:timer, client)
{
	new Float:vec[3];

	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	vec[1]=vec[1]+30.0;
	SetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	PrintToChat(client,"You have been given a nudge east.");
}
public Action:Command_UnStuckMe_West(Handle:timer, client)
{
	new Float:vec[3];

	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	vec[1]=vec[1]-30.0;
	SetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);

	PrintToChat(client,"You have been given a nudge west.");
}


public Action:Command_UnStuckMe(client, args)
{
	new String:arg1[5];
	GetCmdArg(1, arg1, sizeof(arg1));
	PrintToConsole(client, "sm_stuck or !stuck usage: sm_stuck [e-w-n-s] for cardinal directions, or [u-d] for up or down.");
	
	if(g_cvar_amount[client] > 0)
	{
		if(GetCmdArgs() == 1)
		{
			if(StrEqual(arg1, "n"))
			{
				CreateTimer(0.3, Command_UnStuckMe_North, client);
				g_cvar_amount[client]-=1;
				return Plugin_Handled;
			}
			if(StrEqual(arg1, "s"))
			{
				CreateTimer(0.3, Command_UnStuckMe_South, client);
				g_cvar_amount[client]-=1;
				return Plugin_Handled;
			}	
			if(StrEqual(arg1, "e"))
			{
				CreateTimer(0.3, Command_UnStuckMe_East, client);
				g_cvar_amount[client]-=1;
				return Plugin_Handled;
			}	
			if(StrEqual(arg1, "w"))
			{
				CreateTimer(0.3, Command_UnStuckMe_West, client);
				g_cvar_amount[client]-=1;
				return Plugin_Handled;
			}
			if(StrEqual(arg1, "u"))
			{
				CreateTimer(0.3, Command_UnStuckMe_Up, client);
				g_cvar_amount[client]-=1;
				return Plugin_Handled;
			}
			if(StrEqual(arg1, "d"))
			{
				CreateTimer(0.3, Command_UnStuckMe_Down, client);
				//penalty for nudge down is higher as it can be hazardous, or even be an exploit
				g_cvar_amount[client]-=20;  
				return Plugin_Handled;
			}
		}
		else
		{
			CreateTimer(0.3, Command_UnStuckMe_Up, client);
			g_cvar_amount[client]-=1;
			return Plugin_Handled;
		}
	}
	else
	{
		PrintToChat(client, "You have used this command too often this round. Sorry.");
	}
	return Plugin_Handled;
}

public OnClientPutInServer(client)
{
  if(client && !IsFakeClient(client)) g_cvar_amount[client] = 15;
}

public Action:PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client;
	client = GetClientOfUserId(GetEventInt(event, "userid"));
	g_cvar_amount[client] = GetConVarInt(unstuck_cvar_amount);
	return Plugin_Continue;
}

public Action:event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client;
	client = GetClientOfUserId(GetEventInt(event, "userid"));
	g_cvar_amount[client] = GetConVarInt(unstuck_cvar_amount);
}	


public OnEventShutdown()
{
	UnhookEvent("player_spawn", PlayerSpawn);
	UnhookEvent("game_round_start",event_RoundStart);
}
