#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <adminmenu>

#define DEBUG 1
#define PLUGIN_VERSION "1.3"

//TODO: make cookies to save muted players?
//TODO: check last player death and activates alltalk -incompatible with slowmotion plugin!-

bool g_bMutedPlayerFor[MAXPLAYERS+1][MAXPLAYERS+1];
Handle convar_spectator_voice_enabled = INVALID_HANDLE;
Handle convar_alltalk = INVALID_HANDLE;
Handle convar_nt_alltalk = INVALID_HANDLE;
Handle convar_nt_deadtalk = INVALID_HANDLE;
Handle convar_voicefix = INVALID_HANDLE;
Handle convar_endround_alltalk = INVALID_HANDLE;
int g_iClientTeam[MAXPLAYERS+1];


public Plugin myinfo = 
{
	name = "Self-Mute",
	author = "glub, Otokiru",
	description = "Self Mute Player Voice",
	version = PLUGIN_VERSION,
	url = ""
}

//====================================================================================================
//	If voicefix is active, it will set sv_alltalk to 1 by default. 
//	
//
//	 CREDITS: based on Self-Mute plugin by Otokiru (Idea+Source) // TF2MOTDBackpack (PlayerList Menu)
//====================================================================================================

public OnPluginStart() 
{	
	LoadTranslations("common.phrases");
	CreateConVar("sm_selfmute_version", PLUGIN_VERSION, "Version of Self-Mute", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	convar_spectator_voice_enabled = CreateConVar("sm_selfmute_spectator_voice_enabled", "1", "Enable spectators to talk to dead players", FCVAR_PLUGIN|FCVAR_SPONLY);
	convar_voicefix = CreateConVar("nt_voicefix_enabled", "0", "Enables sv_alltalk and uses overrides to control voice broadcasting", FCVAR_PLUGIN|FCVAR_SPONLY);
	convar_endround_alltalk = CreateConVar("nt_endroundalltalk", "1", "Activates alltalk on ghost capture", FCVAR_PLUGIN|FCVAR_SPONLY);
	
	convar_nt_alltalk = CreateConVar("nt_alltalk", "0", "Alltalk for Neotokyo", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED);
	convar_nt_deadtalk = CreateConVar("nt_deadtalk", "1", "Neotokyo controls for how dead communicate. 0 - Off. 1 - Dead players ignore teams. 2 - Dead players talk to living teammates.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY, true, 0.0, true, 2.0);
	convar_alltalk = FindConVar("sv_alltalk");
	
	
	RegAdminCmd("sm_sm", selfMute, 0, "Mute player by typing !selfmute [playername]");
	RegAdminCmd("sm_selfmute", selfMute, 0, "Mute player by typing !sm [playername]");
	RegAdminCmd("sm_su", selfUnmute, 0, "Unmute player by typing !su [playername]");
	RegAdminCmd("sm_selfunmute", selfUnmute, 0, "Unmute player by typing !selfunmute [playername]");
	RegAdminCmd("sm_cm", checkmute, 0, "Check who you have self-muted");
	RegAdminCmd("sm_checkmute", checkmute, 0, "Check who you have self-muted");
	
	//AddCommandListener(OnCommand, "jointeam");
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_team", OnPlayerChangeTeam);
	HookEvent("game_round_start", OnRoundStart);
	
	if(convar_alltalk != INVALID_HANDLE)
		HookConVarChange(convar_alltalk, OnCvarChanged);
	if(convar_nt_alltalk != INVALID_HANDLE)
		HookConVarChange(convar_nt_alltalk, OnCvarChanged);
	
	HookEvent("server_cvar", Event_ServerCvar, EventHookMode_Pre);
}

public void OnConfigsExecuted()
{
	if(GetConVarBool(convar_voicefix))
	{
		if(convar_alltalk != INVALID_HANDLE)
			SetConVarInt(convar_alltalk, 1);
		else
			LogError("Couldn't find sv_alltalk!");
	}
}

public void Event_ServerCvar(Handle event, const char[] name, bool Dontbroadcast)
{
	if(GetConVarBool(convar_voicefix))
	{
		char cvarName[20], cvarValue[2];
		GetEventString(event, "cvarname", cvarName, sizeof(cvarName));
		GetEventString(event, "cvarvalue", cvarValue, sizeof(cvarValue));

		if (StrContains(cvarName, "sv_alltalk") == 0 && StrEqual(cvarValue, "1")) //attempting to change sv_alltalk to 1!
		{
			SetConVarString(convar_nt_alltalk, "1");
			//return Plugin_Handled; //should block notification... otherwise just remove flag and readd as usual
		}
		//return Plugin_Continue;
	}
}

public void OnCvarChanged(Handle convar, char[] oldValue, char[] newValue)
{
	if(GetConVarBool(convar_voicefix))
	{
		char ConVarName[20];
		GetConVarName(convar, ConVarName, sizeof(ConVarName));
		
		
		if(StrEqual(ConVarName, "sv_alltalk") && (StringToInt(newValue) == 0))
		{
			//SetConVarString(convar_alltalk, "1"); //reset sv_alltalk to 1 on change to 0
			SetConVarString(convar_nt_alltalk, "0"); //we change sv_nt_alltalk instead
			
			#if DEBUG > 0
			PrintToServer("Changed cvar back to 1 from 0, and used sv_nt_alltalk instead");
			#endif
		}
		
		
		if(StrEqual(ConVarName, "nt_alltalk") && (StringToInt(newValue) == 1))
		{
			for(int client = 1; client <= MaxClients; client++)
			{
				if(!IsClientInGame(client) || IsFakeClient(client))
					continue;
				
				if(GetClientListeningFlags(client) & VOICE_MUTED)
					continue;
				
				//SetClientListeningFlags(client, VOICE_NORMAL);
				
				for(int id = 1; id <= MaxClients; id++)
				{
					if(!IsClientInGame(id))
						continue; 
					
					if(id == client)
						continue;
					
					if(g_bMutedPlayerFor[client][id])
						continue;
					else
						SetListenOverride(client, id, Listen_Default);
				}
			}
		}
		else if(StrEqual(ConVarName, "nt_alltalk") && (StringToInt(newValue) == 0))
		{
			for(int client = 1; client <= MaxClients; client++)
			{
				if(!IsClientInGame(client) || IsFakeClient(client))
					continue;
				
				if(GetClientListeningFlags(client) & VOICE_MUTED)
					continue;
				
				//SetClientListeningFlags(client, VOICE_NORMAL);
				
				for(int id = 1; id <= MaxClients; id++)
				{
					if(!IsClientInGame(id))
						continue; 
					
					if(id == client)
						continue;
					
					if(g_bMutedPlayerFor[client][id])
						continue;
					else
						SetListenOverride(client, id, Listen_Default);
				}
			}
			RefreshOverrideFlags();
		}
	}
}

public OnGhostCapture(int client)
{
	SetConVarString(convar_alltalk, "1");
}

public Action OnRoundStart(Handle event, const char[] name, bool dontbroadcast)
{
	CreateTimer(15.0, timer_clearAlltalk, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action timer_clearAlltalk(Handle timer)
{
	SetConVarString(convar_alltalk, "0");
}

//Used only when alltalk is changed back to "0"
public void RefreshOverrideFlags()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientInGame(client) || IsFakeClient(client))
		{
			g_iClientTeam[client] = 0;
			continue;
		}
		
		g_iClientTeam[client] = GetClientTeam(client);
	}
	
	
	
	for(int client = 1; client <= MaxClients; client++)
	{	
		if(!IsClientInGame(client) || IsFakeClient(client))
			continue;
		
		//g_iClientTeam[client] = GetClientTeam(client);

		for(int id = 1; id <= MaxClients ; id++)
		{
			if(!IsClientInGame(id) || IsFakeClient(client))
				continue;
			
			if(g_bMutedPlayerFor[id][client]) //unless they muted him before (refreshing mutes, meh)
			{
				SetListenOverride(id, client, Listen_No);
			}
			if(g_bMutedPlayerFor[client][id]) //vice-versa (refreshing mutes, meh)
			{
				SetListenOverride(client, id, Listen_No);
			}
			
			if(g_iClientTeam[client] == g_iClientTeam[id]) //same team, we can hear each other
			{
				if(g_iClientTeam[client] <= 1) //we're both spectators -> we can hear each other
				{
					if(!g_bMutedPlayerFor[id][client]) //unless muted
						SetListenOverride(id, client, Listen_Default);
						
					if(!g_bMutedPlayerFor[client][id])
						SetListenOverride(client, id, Listen_Default);
				}
				else //we're not in spectator team, but the same PLAYING team
				{
					if(IsPlayerAlive(client) && IsPlayerAlive(id)) //both alive
					{
						if(!g_bMutedPlayerFor[id][client])
							SetListenOverride(id, client, Listen_Default);
						
						if(!g_bMutedPlayerFor[client][id])
							SetListenOverride(client, id, Listen_Default);
					}
					else if(IsPlayerAlive(client) && !IsPlayerAlive(id)) //id can hear if deadtalk > 0
					{
						if(GetConVarInt(convar_nt_deadtalk) == 2) //dead team mates can talk to alive but not oppposite team (CSGO-like. STRICT)
						{
							if(!g_bMutedPlayerFor[id][client])
								SetListenOverride(id, client, Listen_Default);
							
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Default);	
						}
						else //regular rules for same team
						{
							if(!g_bMutedPlayerFor[id][client])
								SetListenOverride(id, client, Listen_Default);
							
							SetListenOverride(client, id, Listen_No);
						}
					}
					else if(!IsPlayerAlive(client) && IsPlayerAlive(id))
					{
						if(GetConVarInt(convar_nt_deadtalk) == 2) //dead team mates can talk to alive but not oppposite team (CSGO-like. STRICT)
						{
							if(!g_bMutedPlayerFor[id][client])
								SetListenOverride(id, client, Listen_Default);
							
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Default);	
						}
						else //regular rules for same team
						{
							SetListenOverride(id, client, Listen_No);
						
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Default);
						}
					}
					else //we're both dead
					{
						if(!g_bMutedPlayerFor[id][client])
							SetListenOverride(id, client, Listen_Default);
						
						if(!g_bMutedPlayerFor[client][id])
							SetListenOverride(client, id, Listen_Default);
					}
				}				
			}
			else if(g_iClientTeam[client] != g_iClientTeam[id])  //not the same team
			{
				if(g_iClientTeam[client] <= 1) //spectating, we can hear them, they can't hear us, unless they're dead
				{
					if(!g_bMutedPlayerFor[client][id])
						SetListenOverride(client, id, Listen_Default);
					
					if(IsPlayerAlive(id))
						SetListenOverride(id, client, Listen_No);
					else
						if(!g_bMutedPlayerFor[id][client])
							SetListenOverride(id, client, Listen_Default);
				}
				else //we are in a playing team, we follow deadtalk rules and alive/dead rules
				{
					if(IsPlayerAlive(client))
					{
						SetListenOverride(client, id, Listen_No);
						//no need to set for id, it's in the loop already
					}
					else //we are dead
					{
						if(GetConVarInt(convar_nt_deadtalk) == 2)
						{
							SetListenOverride(client, id, Listen_No);
						}
						else if(GetConVarInt(convar_nt_deadtalk) == 1)
						{
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Default);
						}
						else if(GetConVarInt(convar_nt_deadtalk) == 0)
						{
							SetListenOverride(client, id, Listen_No);
						}		
					}
				}
			}
		}
	}
}


/*
public void RefreshOverrideFlags()
{
	for(int client = 1; client <= MaxClients; client++)
	{	
		if(!IsClientInGame(client) || IsFakeClient(client))
			continue;
		
		g_iClientTeam[client] = GetClientTeam(client);

		if(IsPlayerAlive(client))
		{
			//can't hear spectators anymore
			for(int id = 1; id <= MaxClients ; id++)
			{
				if(id != client && IsClientInGame(id))
				{
					if(g_bMutedPlayerFor[id][client]) //unless they muted him before (refreshing mutes, meh)
					{
						SetListenOverride(id, client, Listen_No);
					}
					if(g_bMutedPlayerFor[client][id]) //vice-versa (refreshing mutes, meh)
					{
						SetListenOverride(client, id, Listen_No);
					}
					
					if(g_iClientTeam[id] == g_iClientTeam[client]) //same team, we can hear each other
					{
						if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
							SetListenOverride(id, client, Listen_Default); //all the others can hear him
						if(!g_bMutedPlayerFor[client][id])
							SetListenOverride(client, id, Listen_Default); //he can hear the others
					}
					else //not same team
					{
						if(g_iClientTeam[id] == 1) //if id is spectating
						{
							if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
								SetListenOverride(id, client, Listen_Default); //all the others can hear him
							
							if(!g_bMutedPlayerFor[client][id] && g_iClientTeam[client] == 1) //client spectating too
								SetListenOverride(client, id, Listen_Default); //all the others can hear him
						}
						
						if(g_iClientTeam[id] == 2)
						{
							if(g_iClientTeam[client] == 2) //same team
							{
								if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
									SetListenOverride(id, client, Listen_Default); //all the others can hear him
								
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Default);
							}
							else //not same team 2
							{
								if(GetConVarInt(convar_nt_alltalk) == 1)
									SetListenOverride(id, client, Listen_Default);
								else
									SetListenOverride(id, client, Listen_No);	//opposite team (3), can't hear unless alltalk
							}
						}
						
						if(g_iClientTeam[id] == 3)
						{
							if(g_iClientTeam[client] == 3) //same team
							{
								if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
									SetListenOverride(id, client, Listen_Default); //all the others can hear him
								
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Default);
							}
							else //not same team 3
							{
								if(GetConVarInt(convar_nt_alltalk) == 1)
									SetListenOverride(id, client, Listen_Default);
								else 
									SetListenOverride(id, client, Listen_No);	//opposite team (2), can't hear unless alltalk
							}
						}					
					}
				}
			}
			return;
		}
		else // player not alive, indeadlounge or spectator team
		{
			for(int id = 1; id <= MaxClients ; id++)
			{
				if(id != client && IsClientInGame(id))
				{
					if(g_bMutedPlayerFor[id][client]) //unless they muted him before (refreshing mutes, meh)
					{
						SetListenOverride(id, client, Listen_No);
					}
					if(g_bMutedPlayerFor[client][id]) //vice-versa (refreshing mutes, meh)
					{
						SetListenOverride(client, id, Listen_No);
					}
					
					if(g_iClientTeam[id] == g_iClientTeam[client]) //SAME TEAM! we can hear each other
					{
						if(g_iClientTeam[client] == 1) // we are both spectating, can hear everyone
						{
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Default);							
						}
						else //we're both in the same PLAYING team (but client is dead)
						{
							if(GetConVarInt(convar_nt_deadtalk) == 2) //dead team mates can talk to alive but not oppposite team (STRICT)
							{
								if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
									SetListenOverride(id, client, Listen_Default); //all the alive can hear him
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Default); //he can hear alive
							}
							else if(GetConVarInt(convar_nt_deadtalk) == 1) //dead players can't talk to alive but talk to all dead (DEFAULT)
							{
								if(IsPlayerAlive(id))
								{
									if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
										SetListenOverride(id, client, Listen_No); //alive players can't hear dead players
									if(!g_bMutedPlayerFor[client][id])
										SetListenOverride(client, id, Listen_Default); //dead player can hear alive though
								}
								else //id is dead too
								{
									if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
										SetListenOverride(id, client, Listen_Default); //id is in dead lounge too
								}
							}
							else if(GetConVarInt(convar_nt_deadtalk) == 0) //dead players can't talk to opposite team at all but can hear TEAM alive (NT STANDARD)
							{
								if(IsPlayerAlive(id))
								{
									if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
										SetListenOverride(id, client, Listen_No); //alive players can't hear dead players
									if(!g_bMutedPlayerFor[client][id])
										SetListenOverride(client, id, Listen_Default); //dead player can hear alive though (same team here, remember?)
								}
								else //id is dead too
								{
									if(!g_bMutedPlayerFor[id][client])
										SetListenOverride(id, client, Listen_Default); //id is in dead lounge too
								}
							}
						}
					}
					else //not same team (but client is dead)
					{
						if(g_iClientTeam[client] == 1) //client is spectating (and dead, same)
						{
							if(GetConVarInt(convar_nt_deadtalk) == 2) //dead TEAM mates can talk to alive TEAM (here, we can't talk to them but we can listen) (STRICT)
							{
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Default);
							}
							else if(GetConVarInt(convar_nt_deadtalk) == 1) //dead players can't talk to alive but talk to all dead (DEFAULT)
							{
								if(IsPlayerAlive(id))
								{
									if(!g_bMutedPlayerFor[id][client])
										SetListenOverride(id, client, Listen_No); //alive players can't hear dead players
									if(!g_bMutedPlayerFor[client][id])
										SetListenOverride(client, id, Listen_Default); //dead player can hear alive though
								}
								else //id is dead too
								{
									if(!g_bMutedPlayerFor[id][client])
										SetListenOverride(id, client, Listen_Default); //id is in dead lounge too
								}
							}
							else if(GetConVarInt(convar_nt_deadtalk) == 0) //dead players can't talk to opposite team at all but can hear TEAM alive, but here we spectate
							{
								if(IsPlayerAlive(id))
								{
									if(!g_bMutedPlayerFor[id][client])
										SetListenOverride(id, client, Listen_No); //alive players can't hear dead players
									if(!g_bMutedPlayerFor[client][id])
										SetListenOverride(client, id, Listen_Default); //dead player can hear alive though
								}
								else //id is dead too
								{
									if(g_iClientTeam[id] == 1) //both spectating, can hear each other
									{
										if(!g_bMutedPlayerFor[id][client])
											SetListenOverride(id, client, Listen_Default); //id is in dead lounge too
										if(!g_bMutedPlayerFor[client][id])
											SetListenOverride(client, id, Listen_Default); //dead player can hear alive though
									}
									else if(g_iClientTeam[client] > 1) //id is in a PLAYING TEAM, he can't listen, but we can
									{
										SetListenOverride(id, client, Listen_No);
										if(!g_bMutedPlayerFor[client][id])
											SetListenOverride(client, id, Listen_Default);
									}
								}
							}
						}
						
						
						if(g_iClientTeam[client] > 1) //client is in PLAYING team and DEAD, and id is in ANOTHER team (team OR spec!)
						{
							if(GetConVarInt(convar_nt_deadtalk) == 2) //dead TEAM mates can talk to alive TEAM (STRICT)
							{
								if(g_iClientTeam[id] == (g_iClientTeam[client])) //same team
								{
									if(!g_bMutedPlayerFor[id][client])
										SetListenOverride(id, client, Listen_Default); 
									if(!g_bMutedPlayerFor[client][id])
										SetListenOverride(client, id, Listen_Default);
								}
								else //not same team
								{
									SetListenOverride(client, id, Listen_No); //can't hear opposite team
									SetListenOverride(id, client, Listen_No); //can't hear opposite team
								}
							}
							else if(GetConVarInt(convar_nt_deadtalk) == 1) //dead players can't talk to alive but talk to all dead (DEFAULT)
							{
								if(IsPlayerAlive(id))
								{
									if(!g_bMutedPlayerFor[id][client])
										SetListenOverride(id, client, Listen_No); //alive players can't hear dead players
									if(!g_bMutedPlayerFor[client][id])
										SetListenOverride(client, id, Listen_Default); //dead player can hear alive though
								}
								else //id is dead too
								{
									if(!g_bMutedPlayerFor[id][client])
										SetListenOverride(id, client, Listen_Default); //id is in dead lounge too
									if(!g_bMutedPlayerFor[client][id])
										SetListenOverride(client, id, Listen_Default); //id is in dead lounge too
								}
							}
							else if(GetConVarInt(convar_nt_deadtalk) == 0) //dead players can't talk to opposite team at all but can hear TEAM alive (BASIC)
							{
								if(IsPlayerAlive(id)) //id is another team! can't talk nor hear
								{
									SetListenOverride(id, client, Listen_No);
									SetListenOverride(client, id, Listen_No);
								}
								else //id is dead too
								{
									if(g_iClientTeam[id] == 1) //id is spectating, can hear client, but client can't
									{
										if(!g_bMutedPlayerFor[id][client])
											SetListenOverride(id, client, Listen_Default); //id is in spec, can hear

										SetListenOverride(client, id, Listen_No); //but we can't (so serious)
									}
									else if(g_iClientTeam[id] > 1) //id is in a PLAYING TEAM, he can't listen, and we can't either (so serious)
									{
										SetListenOverride(id, client, Listen_No);
										SetListenOverride(client, id, Listen_No);
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
*/

//====================================================================================================

public Action OnPlayerChangeTeam(Handle event, const char[] name, bool Dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int oldteam = GetEventInt(event, "oldteam");
	int newteam =  GetEventInt(event, "team");
	int disconnect = GetEventInt(event, "disconnect");
	
	#if DEBUG > 0
	PrintToChatAll("%N changed team: oldteam %i newteam %i", client, oldteam, newteam);
	#endif

	if(disconnect == 1)
	{
		//probably not needed
		/*for(int id = 1; id <= MaxClients; id++)
		{
			if(id != client && IsClientInGame(id))
				SetListenOverride(id, client, Listen_No);		
		}*/
		
		g_iClientTeam[client] = 0; //he disconnected
		return Plugin_Continue;
	}
	
	if(GetConVarBool(convar_voicefix))
	{	
		RefreshOverrideFlags();
		return Plugin_Continue;
	}
	else
	{
		if(newteam == 1) //joined spectator
		{
			g_iClientTeam[client] = 1;
		
			for (int id = 1; id <= MaxClients ; id++)
			{
				if(id != client && IsClientInGame(id) && GetClientTeam(id) > 1)
				{
					if(!IsPlayerAlive(id)) //dead players in teams can hear the new spectator
					{
						if(g_bMutedPlayerFor[id][client]) //unless they muted him before
						{
							SetListenOverride(id, client, Listen_No); //id muted client
						}
						else
						{
							if(g_bMutedPlayerFor[client][id])
							{
								SetListenOverride(client, id, Listen_No); //client muted id
							}
							else
							{
								SetListenOverride(client, id, Listen_Default); //he can hear other
								SetListenOverride(id, client, Listen_Default); //other can hear him
							}
						}
					}
					else //id is alive
					{
						if(g_bMutedPlayerFor[client][id])
						{
							SetListenOverride(client, id, Listen_No); //client muted id
						}
						else
						{
							SetListenOverride(client, id, Listen_Default); //client can hear id
							SetListenOverride(id, client, Listen_No); //alive id in teams ignore the new spectator until they die
						}
					}
				}
				
				if(id != client && IsClientInGame(id) && GetClientTeam(id) == 1) //spectator id can hear the new spectating client
				{
					if(g_bMutedPlayerFor[id][client]) //unless they muted him before
					{
						SetListenOverride(id, client, Listen_No);
					}
					else //id didn't mute
					{
						SetListenOverride(id, client, Listen_Default); 
					}
					
					if(g_bMutedPlayerFor[client][id])
					{
						SetListenOverride(client, id, Listen_No);
					}
					else
					{
						SetListenOverride(client, id, Listen_Default);
					}
				}
			}
			
			return Plugin_Continue;
		}
		
		
		else if(newteam == 2 || newteam == 3) //joined NSF, and is dead (can't join a team if not dead)
		{
			g_iClientTeam[client] = newteam;
			
			if(IsPlayerAlive(client))
				return Plugin_Continue; //client must be in dead lounge to have its flags updated
			
			
			for (int id = 1; id <= MaxClients ; id++)
			{
				if(id != client && IsClientInGame(id) && GetClientTeam(id) > 1) //all the ids in teams can hear
				{
					if(g_bMutedPlayerFor[id][client]) //unless they muted him before
					{
						SetListenOverride(id, client, Listen_No);
					}
					else
					{
						if(g_bMutedPlayerFor[client][id]) //if client muted id
						{
							SetListenOverride(client, id, Listen_No);
						}
						else
						{
							SetListenOverride(client, id, Listen_Default); //client in team can hear all ids
							
							if(IsPlayerAlive(id))
								SetListenOverride(id, client, Listen_No); //id in team can't hear client if id is alive
							else
								SetListenOverride(id, client, Listen_Default);
						}
					}
				}
			}
		}
		
		return Plugin_Continue;
	}
}



// NOT USED ANYMORE

public Action OnCommand(int client, const char[] command, int argc) 
{
	char sArg[3];
	GetCmdArgString(sArg, sizeof(sArg));
	int arg = StringToInt(sArg);

	#if DEBUG > 1
	PrintToServer("[OnCommand] %N [%d]: %s %d {argc = %d}", client, client, command, arg, argc);
	#endif
	
	if(StrEqual(command, "jointeam"))
	{
		if(arg == 1) //we joined spectator, we are muted to all but spectators AND dead players
		{			
			for (int id = 1; id <= MaxClients ; id++)
			{
				if(id != client && IsClientInGame(id) && GetClientTeam(id) > 1)
				{
					if(!IsPlayerAlive(id)) //dead players in teams can hear the new spectator
					{
						if(g_bMutedPlayerFor[id][client]) //unless they muted him before
						{
							SetListenOverride(id, client, Listen_No); //id muted client
						}
						else
						{
							if(g_bMutedPlayerFor[client][id])
							{
								SetListenOverride(client, id, Listen_No); //client muted id
							}
							else
							{
								SetListenOverride(client, id, Listen_Default); //he can hear other
								SetListenOverride(id, client, Listen_Default); //other can hear him
							}
						}
					}
					else //id is alive
					{
						if(g_bMutedPlayerFor[client][id])
						{
							SetListenOverride(client, id, Listen_No); //client muted id
						}
						else
						{
							SetListenOverride(client, id, Listen_Default); //client can hear id
							SetListenOverride(id, client, Listen_No); //alive id in teams ignore the new spectator until they die
						}
					}
				}
				
				if(id != client && IsClientInGame(id) && GetClientTeam(id) == 1) //spectator id can hear the new spectating client
				{
					if(g_bMutedPlayerFor[id][client]) //unless they muted him before
					{
						SetListenOverride(id, client, Listen_No);
					}
					else //id didn't mute
					{
						SetListenOverride(id, client, Listen_Default); 
					}
					
					if(g_bMutedPlayerFor[client][id])
					{
						SetListenOverride(client, id, Listen_No);
					}
					else
					{
						SetListenOverride(client, id, Listen_Default);
					}
				}
			}
			
			return Plugin_Continue;
		}
		else //we joined a team, we are not muted anymore
		{
			//g_iClientTeam[client] = GetClientTeam(client);
			
			#if DEBUG > 0
			PrintToServer("[OnCommand] %N [%d]: client is now in team %i", client, client, g_iClientTeam[client]);
			#endif
			
			RefreshOverrideFlags();
			
			
			/*
			
			if(IsPlayerAlive(client))
				return Plugin_Continue; //client must be in dead lounge to have its flags updated
			
			
			for (int id = 1; id <= MaxClients ; id++)
			{
				if(id != client && IsClientInGame(id) && GetClientTeam(id) > 1) //all the ids in teams can hear
				{
					if(g_bMutedPlayerFor[id][client]) //unless they muted him before
					{
						SetListenOverride(id, client, Listen_No);
					}
					else
					{
						if(g_bMutedPlayerFor[client][id]) //if client muted id
						{
							SetListenOverride(client, id, Listen_No);
						}
						else
						{
							SetListenOverride(client, id, Listen_Default); //client in team can hear all ids
							
							if(IsPlayerAlive(id))
								SetListenOverride(id, client, Listen_No); //id in team can't hear client if id is alive
							else
								SetListenOverride(id, client, Listen_Default);
						}
					}
				}
			}
			*/
			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}

//====================================================================================================

public OnClientPutInServer(int client)
{
	g_iClientTeam[client] = 1;
	
	for (int id = 1; id <= MaxClients ; id++)
	{
		if(IsFakeClient(client))
			continue;
		
		if(id != client && IsClientInGame(id)) //everybody should ignore the new guy
		{
			if(IsFakeClient(id))
				continue;
			
			SetClientListeningFlags(client, VOICE_NORMAL); // probably not needed
			SetListenOverride(id, client, Listen_No); //was Listen_Yes -glub -> Default is ok, but should be no, and then default when joined a team to prevent spec transmitting
			SetListenOverride(client, id, Listen_Default); //new guy can hear everyone
        }
    }
}

public Action OnPlayerDeath(Handle event, const char[] name, bool Dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int team = GetClientTeam(client);
	g_iClientTeam[client] = team;

	if(GetConVarBool(convar_voicefix))
	{
		RefreshOverrideFlags();
	}



	if(team >= 1) 
	{
		for (int id = 1; id <= MaxClients ; id++)
		{
			if(id != client && IsClientInGame(id)) //all connected players can hear
			{
				if(g_bMutedPlayerFor[id][client]) //unless they muted him before
				{
					SetListenOverride(id, client, Listen_No);
				}
				else
				{
					if(g_bMutedPlayerFor[client][id]) //if client muted id
					{
						SetListenOverride(client, id, Listen_No);
					}
					else
					{
						SetListenOverride(client, id, Listen_Default); //client in team can hear all ids
						
						if(IsPlayerAlive(id))
							SetListenOverride(id, client, Listen_No); //id in team can't hear client if id is alive
						else
							SetListenOverride(id, client, Listen_Default);
					}
				}
			}
		}
	}
}



public Action OnPlayerSpawn(Handle event, const char[] name, bool Dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	g_iClientTeam[client] = GetClientTeam(client);
	
	if(GetConVarBool(convar_voicefix))
	{
		RefreshOverrideFlags();
	}
	
	
	if(IsPlayerAlive(client))
	{
		//can't hear spectators anymore
		for(int id = 1; id <= MaxClients ; id++)
		{
			if(id != client && IsClientInGame(id))
			{
				if(g_bMutedPlayerFor[id][client]) //unless they muted him before (refreshing mutes, meh)
				{
					SetListenOverride(id, client, Listen_No);
				}
				if(g_bMutedPlayerFor[client][id]) //vice-versa (refreshing mutes, meh)
				{
					SetListenOverride(client, id, Listen_No);
				}
				
				if(g_iClientTeam[id] == g_iClientTeam[client]) //same team, we can hear each other
				{
					if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
						SetListenOverride(id, client, Listen_Default); //all the others can hear him
					if(!g_bMutedPlayerFor[client][id])
						SetListenOverride(client, id, Listen_Default); //he can hear the others
				}
				else //not same team
				{
					if(g_iClientTeam[id] == 1) //if id is spectating
					{
						if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
							SetListenOverride(id, client, Listen_Default); //all the others can hear him
						
						if(!g_bMutedPlayerFor[client][id] && g_iClientTeam[client] == 1) //client spectating too
							SetListenOverride(client, id, Listen_Default); //all the others can hear him
					}
					
					if(g_iClientTeam[id] == 2)
					{
						if(g_iClientTeam[client] == 2) //same team
						{
							if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
								SetListenOverride(id, client, Listen_Default); //all the others can hear him
							
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Default);
						}
						else //not same team 2
						{
							if(GetConVarInt(convar_nt_alltalk) == 1)
								SetListenOverride(id, client, Listen_Default);
							else
								SetListenOverride(id, client, Listen_No);	//opposite team (3), can't hear unless alltalk
						}
					}
					
					if(g_iClientTeam[id] == 3)
					{
						if(g_iClientTeam[client] == 3) //same team
						{
							if(!g_bMutedPlayerFor[id][client]) //unless muted (see above)
								SetListenOverride(id, client, Listen_Default); //all the others can hear him
							
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Default);
						}
						else //not same team 3
						{
							if(GetConVarInt(convar_nt_alltalk) == 1)
								SetListenOverride(id, client, Listen_Default);
							else 
								SetListenOverride(id, client, Listen_No);	//opposite team (2), can't hear unless alltalk
						}
					}					
				}
			}
		}
		return Plugin_Continue;
	}
	else //client is not yet alive (spawn happens when changing team for example), we don't update flags (FIXME? make sure check is done after spawn for alive state?)
	{
		return Plugin_Continue;
	}
	
}


//====================================================================================================

public Action:selfMute(client, args)
{
    if (client == 0)
	{
		PrintToChat(client, "[SM] Cannot use command from RCON");
		return Plugin_Handled;
	}
    if (args == 0)
	{
		DisplayMuteMenu(client);
		return Plugin_Handled;
	}
	
	//Gets target client
    new target;
    decl String:argstring[128];
    GetCmdArgString(argstring, sizeof(argstring));
    target = FindTarget(client, argstring, true, false);
	
    if (target == -1) 
    {
        DisplayMuteMenu(client);
        return Plugin_Handled;
    }
    muteTargetedPlayer(client, target);
    return Plugin_Handled;
}

stock DisplayMuteMenu(client)
{
	new Handle:menu = CreateMenu(MenuHandler_MuteMenu);
	SetMenuTitle(menu, "Choose a player to mute");
	SetMenuExitBackButton(menu, true);
	
	AddTargetsToMenu2(menu, 0, COMMAND_FILTER_NO_BOTS);
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_MuteMenu(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
		case MenuAction_Select:
		{
			decl String:info[32];
			new target;
			
			GetMenuItem(menu, param2, info, sizeof(info));
			new userid = StringToInt(info);

			if ((target = GetClientOfUserId(userid)) == 0)
			{
				PrintToChat(param1, "[SM] Player no longer available");
			}
			else
			{
				muteTargetedPlayer(param1, target);
			}
		}
	}
}

public muteTargetedPlayer(int client, int target)
{
	SetListenOverride(client, target, Listen_No);
	g_bMutedPlayerFor[client][target] = true;
	decl String:chkNick[256];
	GetClientName(target, chkNick, sizeof(chkNick));
	PrintToChat(client, "[Self-Mute] You have self-muted: %s", chkNick);
}

//====================================================================================================

public Action:selfUnmute(client, args)
{
    if (client == 0)
	{
		PrintToChat(client, "[SM] Cannot use command from RCON");
		return Plugin_Handled;
	}
    if (args == 0)
    {
        DisplayUnMuteMenu(client);
        return Plugin_Handled;
    }
	
	//Gets target client
    new target;
    decl String:argstring[128];
    GetCmdArgString(argstring, sizeof(argstring));
    target = FindTarget(client, argstring, true, false);
	
    if (target == -1) 
    {
        DisplayUnMuteMenu(client);
        return Plugin_Handled;
    }
    unMuteTargetedPlayer(client, target);
    return Plugin_Handled;
}

stock DisplayUnMuteMenu(client)
{
	new Handle:menu = CreateMenu(MenuHandler_UnMuteMenu);
	SetMenuTitle(menu, "Choose a player to unmute");
	SetMenuExitBackButton(menu, true);
	
	AddTargetsToMenu2(menu, 0, COMMAND_FILTER_NO_BOTS);
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_UnMuteMenu(Handle:menu, MenuAction:action, param1, param2)
{
	switch (action)
	{
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
		case MenuAction_Select:
		{
			decl String:info[32];
			new target;
			
			GetMenuItem(menu, param2, info, sizeof(info));
			new userid = StringToInt(info);

			if ((target = GetClientOfUserId(userid)) == 0)
			{
				PrintToChat(param1, "[SM] Player no longer available");
			}
			else
			{
				unMuteTargetedPlayer(param1, target);
			}
		}
	}
}

public unMuteTargetedPlayer(client, target)
{
	SetListenOverride(client, target, Listen_Default);  //was Listen_Yes -glub
	g_bMutedPlayerFor[client][target] = false;
	decl String:chkNick[256];
	GetClientName(target, chkNick, sizeof(chkNick));
	PrintToChat(client, "[Self-Mute] You have self-unmuted: %s", chkNick);
}

//====================================================================================================

public Action:checkmute(client, args)
{
    if (client == 0)
	{
		PrintToChat(client, "[SM] Cannot use command from RCON");
		return Plugin_Handled;
	}

    decl String:nickNames[9216];
    Format(nickNames, sizeof(nickNames), "No players found.");
    new bool:firstNick = true;
    
    for (new id = 1; id <= MaxClients ; id++)
	{
        if (id != client && IsClientInGame(id))
		{
            new ListenOverride:override = GetListenOverride(client, id);

			#if DEBUG > 0
			PrintToChat(client, "Your ListenOverride for %i is: %i", id, GetListenOverride(client, id)); 
			#endif
			
            if(override == Listen_No)
			{
                if(firstNick)
				{
                    firstNick = false;
                    Format(nickNames, sizeof(nickNames), "");
                } 
				else
                    Format(nickNames, sizeof(nickNames), "%s, ", nickNames);
				
                decl String:chkNick[256];
                GetClientName(id, chkNick, sizeof(chkNick));
                Format(nickNames, sizeof(nickNames), "%s%s", nickNames,chkNick);
            }
        }
    }
    
    PrintToChat(client, "[Self-Mute] List of self-muted: %s", nickNames);
    Format(nickNames, sizeof(nickNames), "");

    return Plugin_Handled;
}