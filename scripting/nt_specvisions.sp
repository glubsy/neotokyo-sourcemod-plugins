#pragma semicolon 1

#include <neotokyo>

bool g_bActiveVision[MAXPLAYERS+1][3];
bool g_bVisionHeld[MAXPLAYERS+1];
bool g_bLeanLHeld[MAXPLAYERS+1];
bool g_bLeanRHeld[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "NEOTOKYO° Vision modes for spectators",
	author = "glub, soft as HELL",
	description = "Thermal vision and night vision for spectators",
	version = "0.11",
	url = "https://github.com/glubsy"
}

public void OnPluginStart()
{
	HookEvent("player_spawn", OnPlayerSpawn);
	
	HookEvent("game_round_start", OnRoundStart);
}

public Action OnPlayerSpawn(Handle event, const char[] name, bool dontbroadcast)
{
	for(int client = 1; client < MaxClients; client++)
	{
		if(!IsClientConnected(client) || !IsClientInGame(client))
			continue;
		
		SetEntProp(client, Prop_Send, "m_iVision", 0);
	}
}


public Action OnPlayerRunCmd(int client, int &buttons)
{	
	if(IsPlayerAlive(client))
		return;

	if((buttons & IN_VISION) == IN_VISION)
	{
		if(g_bVisionHeld[client])
		{
			buttons &= ~IN_VISION; 
		}
		else
		{
			if(g_bActiveVision[client][0])
			{
				SetEntProp(client, Prop_Send, "m_iVision", 0); 
				g_bActiveVision[client][0] = false;
			}
			else if(!g_bActiveVision[client][0])
			{
				SetEntProp(client, Prop_Send, "m_iVision", 3); //thermooptics
				g_bActiveVision[client][0] = true;
			}
			g_bVisionHeld[client] = true;
		}
	}
	else 
	{
		g_bVisionHeld[client] = false;
	}
	
	
	
	
	
	if((buttons & IN_LEANR) == IN_LEANR)
	{
		if(g_bLeanRHeld[client])
		{
			buttons &= ~IN_LEANR;
		}
		else
		{
			if(g_bActiveVision[client][1] == true)
			{
				SetEntProp(client, Prop_Send, "m_iVision", 0);
				g_bActiveVision[client][1] = false;
			}
			else if(g_bActiveVision[client][1] == false)
			{
				SetEntProp(client, Prop_Send, "m_iVision", 4); //motion 4
				g_bActiveVision[client][1] = true;
			}
			g_bLeanRHeld[client] = true;
		}
	}
	else
	{
		g_bLeanRHeld[client] = false;
	}
	
	
	
	
	
	if((buttons & IN_LEANL) == IN_LEANL)
	{
		if(g_bLeanLHeld[client] == true)
		{
			buttons &= ~IN_LEANL;
		}
		else
		{
			if(g_bActiveVision[client][2] == true)
			{
				SetEntProp(client, Prop_Send, "m_iVision", 0);
				g_bActiveVision[client][2] = false;
			}
			else if(g_bActiveVision[client][2] == false)
			{
				SetEntProp(client, Prop_Send, "m_iVision", 2); //night 2
				g_bActiveVision[client][2] = true;
			}
			g_bLeanLHeld[client] = true;
		}
	}
	else
	{
		g_bLeanLHeld[client] = false;
	}
}


public void OnRoundStart(Handle event, const char[] name, bool Broadcast)
{
	for(int client = 1; client < MaxClients; client++)
	{
		if(!IsClientConnected(client) || !IsClientInGame(client))
			continue;
		
		if(GetClientTeam(client) <= 1)
			continue;
		
		SetEntProp(client, Prop_Send, "m_iVision", 0);
	}
}
