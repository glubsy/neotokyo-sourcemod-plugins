#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <adminmenu>

#define DEBUG 0
#define PLUGIN_VERSION "1.61"

bool g_bMutedPlayerFor[MAXPLAYERS+1][MAXPLAYERS+1];
Handle convar_spectator_voice_enabled = INVALID_HANDLE;
Handle convar_alltalk = INVALID_HANDLE;
Handle convar_nt_alltalk = INVALID_HANDLE;
Handle convar_nt_deadtalk = INVALID_HANDLE;
Handle convar_voicefix = INVALID_HANDLE;
Handle convar_endround_alltalk = INVALID_HANDLE;
Handle convar_roundtimelimit = INVALID_HANDLE;
Handle TieTimer = INVALID_HANDLE;
int g_iClientTeam[MAXPLAYERS+1];
bool g_bAllTalkVotedOn;
bool g_bEndOfRoundAllTalk;


public Plugin myinfo = 
{
	name = "Self-Mute",
	author = "glub, Otokiru",
	description = "Self Mute Player Voice",
	version = PLUGIN_VERSION,
	url = ""
}


// TODO: prevent freshly spawned people from being heard by opposite team

//====================================================================================================
//	If voicefix is active, it will set sv_alltalk to 1 by default. 
//	NOTICE: you need to change sv_alltalk to nt_alltalk in funvotes.sp for !votealltalk to redirect to the new convar. Not recommended currently.
//	DEPENDENCIES: funvotes-NT, nt_slowmotion, nt_ghostcap 1.6
//	TODO: make cookies to save muted players?
//	CREDITS: based on Self-Mute plugin by Otokiru (Idea+Source) // TF2MOTDBackpack (PlayerList Menu)
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
	convar_roundtimelimit = FindConVar("neo_round_timelimit");
	
	
	RegAdminCmd("sm_sm", selfMute, 0, "Mute player by typing !selfmute [playername]");
	RegAdminCmd("sm_selfmute", selfMute, 0, "Mute player by typing !sm [playername]");
	RegAdminCmd("sm_su", selfUnmute, 0, "Unmute player by typing !su [playername]");
	RegAdminCmd("sm_selfunmute", selfUnmute, 0, "Unmute player by typing !selfunmute [playername]");
	RegAdminCmd("sm_cm", checkmute, 0, "Check who you have self-muted");
	RegAdminCmd("sm_checkmute", checkmute, 0, "Check who you have self-muted");
	
	//AddCommandListener(OnCommand, "jointeam");
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_spawn", OnPlayerSpawn);
	//HookEvent("player_spawn", OnPlayerSpawn2);
	HookEvent("player_team", OnPlayerChangeTeam);
	HookEvent("game_round_start", OnRoundStart);
	
	if(convar_alltalk != INVALID_HANDLE)
		HookConVarChange(convar_alltalk, OnCvarChanged);
	if(convar_nt_alltalk != INVALID_HANDLE)
		HookConVarChange(convar_nt_alltalk, OnCvarChanged);
	if(convar_voicefix != INVALID_HANDLE)
		HookConVarChange(convar_voicefix, OnCvarChanged);

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

		if(StrContains(cvarName, "sv_alltalk") == 0 && StrEqual(cvarValue, "1")) //attempting to change sv_alltalk to 1!
		{
			SetConVarString(convar_nt_alltalk, "1");
			//return Plugin_Handled; //should block notification... otherwise just remove flag and read as usual
		}
		//return Plugin_Continue;
	}
}


public void OnCvarChanged(Handle convar, char[] oldValue, char[] newValue)
{
	char cvarName[20];
	GetConVarName(convar, cvarName, sizeof(cvarName));

	//attempting to change nt_voicefix_enabled
	if(StrContains(cvarName, "nt_voicefix_enabled") == 0 && StrEqual(newValue, "1"))
	{
		SetConVarString(convar_alltalk, "1");
		//return Plugin_Handled;
	}
	if(StrContains(cvarName, "nt_voicefix_enabled") == 1 && StrEqual(newValue, "0"))
	{
		SetConVarString(convar_alltalk, "0");
		//return Plugin_Handled;
	}


	if(GetConVarBool(convar_voicefix))
	{
		char ConVarName[20];
		GetConVarName(convar, ConVarName, sizeof(ConVarName));
		
		
		if(StrEqual(ConVarName, "sv_alltalk") && (StringToInt(newValue) == 0))
		{
			SetConVarString(convar_alltalk, "1"); //reset sv_alltalk to 1 on change to 0
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
						SetListenOverride(client, id, Listen_Yes);
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

			CreateTimer(3.0, timer_ResetFlags);
		}
	}
}

public OnVotedAllTalk(int cvarvalue)
{
	if(cvarvalue >= 1) //sv_alltalk has been voted 1
	{
		g_bAllTalkVotedOn = true;
		RefreshOverrideFlags();
	}
	if(cvarvalue == 0)
	{
		g_bAllTalkVotedOn = false;
		RefreshOverrideFlags();
	}
}


public OnGhostCapture(int client)
{
	if(g_bEndOfRoundAllTalk) //already activated once
		return;

	ActivateEndRoundAllTalk();
}

public OnLastManDeath(int client)
{
	if(g_bEndOfRoundAllTalk) //already activated once
		return;

	#if DEBUG > 0
	PrintToChatAll("selfmute: activating alltalk on last man death");
	#endif

	ActivateEndRoundAllTalk();
}

public Action timer_TieTimer(Handle timer)
{
	TieTimer = INVALID_HANDLE; 

	if(g_bEndOfRoundAllTalk) //already activated once
		return;

	#if DEBUG > 0
	PrintToChatAll("selfmute: activating alltalk on TIE");
	#endif

	ActivateEndRoundAllTalk();
}

public void ActivateEndRoundAllTalk()
{
	if(GetConVarBool(convar_endround_alltalk))
	{
		if(!GetConVarBool(convar_voicefix))
		{
			if(g_bAllTalkVotedOn)			//we assume sv_alltalk 1 right now
			{
				return;
			}
			else
			{
				#if DEBUG > 1
				PrintToChatAll("Alltalk is on, temporarily");
				#endif

				g_bEndOfRoundAllTalk = true;
				SetConVarString(convar_alltalk, "1");
				SetConVarInt(convar_alltalk, 1);
				//SetConVarString(convar_nt_alltalk, "1");
				RefreshOverrideFlags();
			}
		}
		else // we assume sv_alltalk is always 1 with voicefix active, we don't touch it
		{
			SetConVarString(convar_nt_alltalk, "1");
		}
	}
}

public void StartTieCountDown()
{
	//killing all remaining timers
	if(TieTimer != INVALID_HANDLE)
	{
		KillTimer(TieTimer);
		TieTimer = INVALID_HANDLE; 
	}
	
	TieTimer = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ), timer_TieTimer, 0, TIMER_FLAG_NO_MAPCHANGE);
}



public Action OnRoundStart(Handle event, const char[] name, bool dontbroadcast)
{
	if(GetConVarBool(convar_endround_alltalk))
		CreateTimer(15.0, timer_clearAlltalk, _, TIMER_FLAG_NO_MAPCHANGE);

	CreateTimer(16.0, timer_ResetFlags, _, TIMER_FLAG_NO_MAPCHANGE);

	StartTieCountDown();
}



public Action timer_clearAlltalk(Handle timer)
{
	g_bEndOfRoundAllTalk = false;

	if(GetConVarBool(convar_endround_alltalk))
	{
		if(!GetConVarBool(convar_voicefix))
		{
			if(g_bAllTalkVotedOn)
			{
				
				return;	//we don't reset sv_alltalk because we voted to keep it on
			}
			else
			{
				SetConVarString(convar_alltalk, "0");
				//SetConVarString(convar_nt_alltalk, "0");
			}
		}
		else 									//we assume sv_alltalk is always 1 with voicefix active, we don't touch it
		{
			SetConVarString(convar_nt_alltalk, "0");
		}
	}
}


public Action timer_ResetFlags(Handle timer)
{
	#if DEBUG > 1
	PrintToChatAll("Timer: refreshing override flags");
	#endif
	RefreshOverrideFlags();
}



//Should use only for when sv_alltalk is changed
public void RefreshOverrideFlags()
{
	if(GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix))
	{
		for(int client = 1; client <= MaxClients; client++)
		{	
			if(!IsClientInGame(client) || IsFakeClient(client))
				continue;

			for(int id = 1; id <= MaxClients; id++)
			{
				if(!IsClientInGame(id) || IsFakeClient(client) || id == client)
					continue;

				if(g_bMutedPlayerFor[id][client]) //unless they muted him before (refreshing mutes, meh)
				{
					SetListenOverride(id, client, Listen_No);
				}
				else
					SetListenOverride(id, client, Listen_Yes);

				if(g_bMutedPlayerFor[client][id]) //vice-versa (refreshing mutes, meh)
				{
					SetListenOverride(client, id, Listen_No);
				}
				else
					SetListenOverride(client, id, Listen_Yes);
			}
		}
		return;
	}

	for(int client = 1; client <= MaxClients; client++)
	{	
		if(!IsClientInGame(client) || IsFakeClient(client))
			continue;

		for(int id = 1; id <= MaxClients; id++)
		{
			if(!IsClientInGame(id) || IsFakeClient(client) || id == client)
				continue;
			
			if(g_bMutedPlayerFor[id][client]) //unless they muted him before (refreshing mutes, meh)
			{
				SetListenOverride(id, client, Listen_No);
			}
			if(g_bMutedPlayerFor[client][id]) //vice-versa (refreshing mutes, meh)
			{
				SetListenOverride(client, id, Listen_No);
			}
			


			if(g_iClientTeam[client] != g_iClientTeam[id])  //not the same team
			{
				if(g_iClientTeam[client] <= 1) //spectating, we can hear them, they can't hear us, unless they're dead
				{
					if(!g_bMutedPlayerFor[client][id])
						SetListenOverride(client, id, Listen_Yes);
					
					if(IsPlayerAlive(id))
						SetListenOverride(id, client, Listen_No);
					else
						if(!g_bMutedPlayerFor[id][client] && GetConVarBool(convar_spectator_voice_enabled) && g_bEndOfRoundAllTalk)
							SetListenOverride(id, client, Listen_Yes);
				}
				else //we are in different playing teams
				{
					if(IsPlayerAlive(client))
					{
						SetListenOverride(client, id, Listen_No);
						//no need to set for id, it's in the loop already
					}
					else //client is dead
					{
						if(GetConVarInt(convar_nt_deadtalk) == 2)
						{
							SetListenOverride(client, id, Listen_No);
						}
						if(GetConVarInt(convar_nt_deadtalk) == 1)
						{
							if(!g_bMutedPlayerFor[client][id])
							{
								SetListenOverride(client, id, Listen_Yes);
							}
						}
						if(GetConVarInt(convar_nt_deadtalk) == 0)
						{
							SetListenOverride(client, id, Listen_No);
						}
					}
				}
			}




			if(g_iClientTeam[client] == g_iClientTeam[id]) //same team, we can hear each other
			{
				if(g_iClientTeam[client] <= 1) //we're both spectators -> we can hear each other
				{
					if(!g_bMutedPlayerFor[id][client]) //unless muted
						SetListenOverride(id, client, Listen_Yes);
						
					if(!g_bMutedPlayerFor[client][id])
						SetListenOverride(client, id, Listen_Yes);
				}
				else //we're not in spectator team, but the same PLAYING team
				{
					if(IsPlayerAlive(client) && IsPlayerAlive(id)) //both alive
					{
						if(!g_bMutedPlayerFor[id][client])
							SetListenOverride(id, client, Listen_Yes);
						
						if(!g_bMutedPlayerFor[client][id])
							SetListenOverride(client, id, Listen_Yes);
					}
					else if(IsPlayerAlive(client) && !IsPlayerAlive(id)) //id can hear if deadtalk > 0
					{
						if(GetConVarInt(convar_nt_deadtalk) == 2) //dead team mates can talk to alive but not oppposite team (CSGO-like. STRICT)
						{
							if(!g_bMutedPlayerFor[id][client])
								SetListenOverride(id, client, Listen_Yes);
							
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Yes);	
						}
						else //regular rules for same team
						{
							if(!g_bMutedPlayerFor[id][client])
								SetListenOverride(id, client, Listen_Yes);
							
							SetListenOverride(client, id, Listen_No);
						}
					}
					else if(!IsPlayerAlive(client) && IsPlayerAlive(id))
					{
						if(GetConVarInt(convar_nt_deadtalk) == 2) //dead team mates can talk to alive but not oppposite team (CSGO-like. STRICT)
						{
							if(!g_bMutedPlayerFor[id][client])
								SetListenOverride(id, client, Listen_Yes);
							
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Yes);	
						}
						else //regular rules for same team
						{
							SetListenOverride(id, client, Listen_No);
						
							if(!g_bMutedPlayerFor[client][id])
								SetListenOverride(client, id, Listen_Yes);
						}
					}
					else if(!IsPlayerAlive(client) && !IsPlayerAlive(id))  //we're both dead
					{
						if(!g_bMutedPlayerFor[id][client])
							SetListenOverride(id, client, Listen_Yes);
						
						if(!g_bMutedPlayerFor[client][id])
							SetListenOverride(client, id, Listen_Yes);
					}
				}
			}
		}
	}
}

//====================================================================================================

public Action OnPlayerChangeTeam(Handle event, const char[] name, bool Dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int oldteam = GetEventInt(event, "oldteam");
	int newteam =  GetEventInt(event, "team");
	int disconnect = GetEventInt(event, "disconnect");
	
	if(oldteam != newteam)
		g_iClientTeam[client] = newteam;

	#if DEBUG > 1
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
	
	if(newteam == 1) 													//joined spectator
	{		
		for (int id = 1; id <= MaxClients; id++)
		{
			if(id != client && IsClientInGame(id) && GetClientTeam(id) > 1)
			{
				if(!IsPlayerAlive(id)) 									//dead players in teams can hear the new spectator
				{
					if(g_bMutedPlayerFor[id][client])
					{
						SetListenOverride(id, client, Listen_No);
					}
					else
					{
						if(GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix)) //we use regular sv_alltalk 
						{
							SetListenOverride(id, client, Listen_Yes);
						}

						if(GetConVarBool(convar_spectator_voice_enabled) && g_bEndOfRoundAllTalk)
						{
							if(!GetConVarBool(convar_voicefix))
								SetListenOverride(id, client, Listen_Yes); //other can hear him
							else
								SetListenOverride(id, client, Listen_Yes);
						}
					}


					if(g_bMutedPlayerFor[client][id])
					{
						SetListenOverride(client, id, Listen_No);
					}
					else
					{
						if(GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix)) //we use regular sv_alltalk 
						{
							SetListenOverride(client, id, Listen_Yes); //FIXME: might be redundant and glitch
						}

						if(!GetConVarBool(convar_nt_alltalk) && !GetConVarBool(convar_voicefix))
							SetListenOverride(client, id, Listen_Yes);

						if(!GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix))
							SetListenOverride(client, id, Listen_Yes);  //FIXME: should be Listen_Default but game breaks

						if(GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix))
							SetListenOverride(client, id, Listen_Yes);  //FIXME: should be Listen_Default
					}
				}
				else 			//ID IS ALIVE!  id cannot hear client, but client can hear id
				{
					if(g_bMutedPlayerFor[id][client])
					{
						SetListenOverride(id, client, Listen_No);
					}
					else
					{
						if(GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix)) //we use regular sv_alltalk 
						{
							SetListenOverride(id, client, Listen_Yes);
						}

						if(GetConVarBool(convar_spectator_voice_enabled) && g_bEndOfRoundAllTalk)
						{
							if(!GetConVarBool(convar_voicefix))
								SetListenOverride(id, client, Listen_Yes); //other can hear him
							else
								SetListenOverride(id, client, Listen_Yes);
						}
					}



					if(g_bMutedPlayerFor[client][id])
					{
						SetListenOverride(client, id, Listen_No); //client muted id
					}
					else //client has not muted id
					{
						if(GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix)) //we use regular sv_alltalk 
						{
							SetListenOverride(client, id, Listen_Yes); //FIXME: should be Listen_Default
						}

						if(!GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix))
							SetListenOverride(client, id, Listen_Yes);
						else
							SetListenOverride(client, id, Listen_Yes); //client can hear id
					}

					/*
					if(GetConVarBool(convar_voicefix)) //we assume sv_alltalk 1 and nt_alltalk 1, so voicefix_enabled 1 too
					{
						if(GetConVarBool(convar_nt_alltalk))
							SetListenOverride(id, client, Listen_Yes);
					}

					if(!GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix))
						SetListenOverride(id, client, Listen_No); //alive id in teams ignore the new spectator until they die

					if(GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix))
						SetListenOverride(id, client, Listen_Yes);  //FIXME: should be Listen_Default
					*/ //commented out because we don't care about ID here, only client
				}
			}
			


			if(id != client && IsClientInGame(id) && GetClientTeam(id) == 1) //id and client same team SPECTATORS
			{
				if(g_bMutedPlayerFor[id][client]) //unless they muted him before
					SetListenOverride(id, client, Listen_No);
				else
				{
					if(!GetConVarBool(convar_voicefix))
						SetListenOverride(id, client, Listen_Yes);
					else
						SetListenOverride(id, client, Listen_Yes); 
				}
				
				if(g_bMutedPlayerFor[client][id])
					SetListenOverride(client, id, Listen_No);
				else
				{
					if(!GetConVarBool(convar_voicefix))
						SetListenOverride(client, id, Listen_Yes);
					else
						SetListenOverride(client, id, Listen_Yes);
				}
			}
		}
		return Plugin_Continue;
	}







	if(newteam == 2 || newteam == 3) //joined team and is dead (can't join a team if not dead, so we assume client is dead)
	{
		if(IsPlayerAlive(client))
		{
			#if DEBUG > 1
			PrintToChatAll("Changing team while alive!? What!?");
			#endif

			return Plugin_Continue; //client must be in dead lounge to have its flags updated
		}
		
		for(int id = 1; id <= MaxClients; id++)
		{
			if(id != client && IsClientInGame(id) && GetClientTeam(id) >= 1) //all the ids in teams can hear client
			{
				if(g_bMutedPlayerFor[id][client])
					SetListenOverride(id, client, Listen_No);
				else
				{
					if((IsPlayerAlive(id) && !GetConVarBool(convar_nt_alltalk) && GetConVarBool(convar_voicefix)))
						SetListenOverride(id, client, Listen_No); 			//id in team can't hear client if id is alive
					
					if(IsPlayerAlive(id) && !GetConVarBool(convar_alltalk))
						SetListenOverride(id, client, Listen_No);

					if(GetConVarBool(convar_alltalk))
					{
						if(!GetConVarBool(convar_voicefix))
							SetListenOverride(id, client, Listen_Yes);
						else
							SetListenOverride(id, client, Listen_Yes);
					}
				}

				if(g_bMutedPlayerFor[client][id])
					SetListenOverride(client, id, Listen_No); 
				else 													//client can hear id if id is dead only
				{
					if(!GetConVarBool(convar_voicefix))
					{
						if(GetConVarBool(convar_alltalk))	 			//we use regular sv_alltalk 
						{
							SetListenOverride(client, id, Listen_Yes);
						}
						if(!GetConVarBool(convar_alltalk))
						{
							SetListenOverride(client, id, Listen_Yes); //FIXME: should be Listen_Default but game breaks!
						}
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action OnPlayerSpawn2(Handle event, const char[] name, bool Dontbroadcast)
{
	if(!GetConVarBool(convar_voicefix))
	{
		RefreshOverrideFlags();
	}
}
	


public Action OnPlayerSpawn(Handle event, const char[] name, bool Dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	g_iClientTeam[client] = GetClientTeam(client);
	
	if(!IsPlayerAlive(client)) //client is not yet alive (spawn happens when changing team for example), we don't update flags (FIXME? make sure check is done after spawn for alive state?)
	{
		RefreshOverrideFlags();
		#if DEBUG > 1 
		PrintToChatAll("Spawning NOT alive. %N", client);
		#endif
		return Plugin_Continue;
	}
	else //client IS alive
	{
		#if DEBUG > 1 
		PrintToChatAll("Spawning alive! %N", client); //NOTE: players changing to a team are considered alive by the game (100hp). DAMNIT!
		#endif

		for(int id = 1; id <= MaxClients ; id++)
		{
			if(id == client || !IsClientInGame(id))
				continue;



			if(g_bMutedPlayerFor[id][client])
			{
				SetListenOverride(id, client, Listen_No);
			}
			if(g_bMutedPlayerFor[client][id])
			{
				SetListenOverride(client, id, Listen_No);
			}



			if(g_iClientTeam[client] == g_iClientTeam[id]) 		//NEW fix
			{
				if(!GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix) && !g_bAllTalkVotedOn)
				{
					SetListenOverride(client, id, Listen_Yes);
				}
				if(GetConVarBool(convar_alltalk) && !GetConVarBool(convar_voicefix))
				{
					SetListenOverride(client, id, Listen_Yes);
				}
			}



			if(g_iClientTeam[client] != g_iClientTeam[id]) 				//not same team
			{


				if(g_iClientTeam[id] == 1) 								//spectating
				{
					if(!g_bMutedPlayerFor[id][client])
						SetListenOverride(id, client, Listen_Yes); 
					
					if(!g_bMutedPlayerFor[client][id] && GetConVarBool(convar_spectator_voice_enabled) && g_bEndOfRoundAllTalk)
						SetListenOverride(client, id, Listen_Yes); 

					if(!GetConVarBool(convar_alltalk))
					{
						SetListenOverride(id, client, Listen_Yes); 		//dead players can listen to alive
						SetListenOverride(client, id, Listen_No); 		//alive player can't listen to spectators
					}
					if(GetConVarBool(convar_alltalk))
					{
						SetListenOverride(id, client, Listen_Yes);
						SetListenOverride(client, id, Listen_Yes);
					}
				}
				




				if(g_iClientTeam[id] == 2)									 //but client is NOT 2 (could be 1 or 3)
				{

					if(GetConVarBool(convar_voicefix))
					{
						if(GetConVarInt(convar_nt_alltalk) == 1) 			//custom alltalk is on
							if(!g_bMutedPlayerFor[id][client])
								SetListenOverride(id, client, Listen_Yes);

						if(GetConVarBool(convar_alltalk))					 //voicefix standard situation
						{
							if(g_iClientTeam[client] == 1) //client can listen to id
							{
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Yes);

								if(!g_bMutedPlayerFor[id][client])
									SetListenOverride(id, client, Listen_No);
							}
							else //client and id are opposite teams!
							{
								SetListenOverride(id, client, Listen_No);	 //opposite team (3), can't hear if alltalk is on
								SetListenOverride(client, id, Listen_No);
							}
						}
					}


					if(!GetConVarBool(convar_voicefix))
					{
						if(GetConVarBool(convar_alltalk))
						{
							if(g_iClientTeam[client] == 1)					//only client is spectating
							{
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Yes);

								if(!g_bMutedPlayerFor[id][client])
									SetListenOverride(id, client, Listen_Yes);
							}
							else 											//opposite teams! We can hear each other with sv_alltalk
							{
								SetListenOverride(client, id, Listen_Yes);  //FIXME: should be Listen_Default
								SetListenOverride(id, client, Listen_Yes);  //FIXME: should be Listen_Default
							}
						}
						
						if(!GetConVarBool(convar_alltalk))
						{
							if(g_iClientTeam[client] == 1)					//only client is spectating
							{
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Yes);

								if(!g_bMutedPlayerFor[id][client])
									SetListenOverride(id, client, Listen_No);
							}
							else
							{
								SetListenOverride(id, client, Listen_No);  		//they both shouldn't hear each other
								SetListenOverride(client, id, Listen_No);
							}
						}
					}
				}
				





				if(g_iClientTeam[id] == 3)
				{

					if(GetConVarBool(convar_voicefix))
					{
						if(GetConVarInt(convar_nt_alltalk) == 1) 			//custom alltalk is on
							if(!g_bMutedPlayerFor[id][client])
								SetListenOverride(id, client, Listen_Yes);

						if(GetConVarBool(convar_alltalk))					 //voicefix standard situation
						{
							if(g_iClientTeam[client] == 1) //client can listen to id
							{
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Yes);

								if(!g_bMutedPlayerFor[id][client])
									SetListenOverride(id, client, Listen_No);
							}
							else //client and id are opposite teams!
							{
								SetListenOverride(id, client, Listen_No);	 //opposite team (3), can't hear if alltalk is on
								SetListenOverride(client, id, Listen_No);
							}
						}
					}


					if(!GetConVarBool(convar_voicefix))
					{
						if(GetConVarBool(convar_alltalk))
						{
							if(g_iClientTeam[client] == 1)					//only client is spectating
							{
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Yes);

								if(!g_bMutedPlayerFor[id][client])
									SetListenOverride(id, client, Listen_Yes);
							}
							else 											//opposite teams! We can hear each other with sv_alltalk
							{
								SetListenOverride(client, id, Listen_Yes);  //FIXME: should be Listen_Default
								SetListenOverride(id, client, Listen_Yes);  //FIXME: should be Listen_Default
							}
						}
						
						if(!GetConVarBool(convar_alltalk))
						{
							if(g_iClientTeam[client] == 1)					//only client is spectating
							{
								if(!g_bMutedPlayerFor[client][id])
									SetListenOverride(client, id, Listen_Yes);

								if(!g_bMutedPlayerFor[id][client])
									SetListenOverride(id, client, Listen_No);
							}
							else
							{
								SetListenOverride(id, client, Listen_No);  		//they both shouldn't hear each other
								SetListenOverride(client, id, Listen_No);
							}
						}
					}
				}			
			}
		}
		return Plugin_Continue;
	}
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
			SetListenOverride(client, id, Listen_Yes); //new guy can hear everyone
        }
    }
}

public Action OnPlayerDeath(Handle event, const char[] name, bool Dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int team = GetClientTeam(client);
	g_iClientTeam[client] = team;

	if(!GetConVarBool(convar_voicefix))
	{
		if(team >= 1) //just to make sure
		{
			for (int id = 1; id <= MaxClients ; id++)
			{
				if(id != client && IsClientInGame(id)) //all connected players can hear
				{
					if(g_bMutedPlayerFor[id][client]) //unless they muted him before
					{
						SetListenOverride(id, client, Listen_No);
					}
					else //id has not muted client who just died
					{
						if(g_bMutedPlayerFor[client][id])
						{
							SetListenOverride(client, id, Listen_No);
						}
						else
						{
							SetListenOverride(client, id, Listen_Default); //client in team can hear all ids
							
							if(IsPlayerAlive(id))
							{
								if(GetConVarBool(convar_alltalk))
									SetListenOverride(id, client, Listen_Yes); //id in team can't hear client if id is alive
								else
									SetListenOverride(id, client, Listen_No); //id in team can't hear client if id is alive
							}
							else // id is dead too
								SetListenOverride(id, client, Listen_Yes);
						}
					}
				}
			}
		}
	}
	else //same method, but Listen_Yes instead of Listen_Default
	{
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
							SetListenOverride(client, id, Listen_Yes); //client in team can hear all ids
							
							if(IsPlayerAlive(id))
							{
								if(GetConVarBool(convar_nt_alltalk))
								{
									SetListenOverride(id, client, Listen_Yes);
								}
								else
									SetListenOverride(id, client, Listen_No); //id in team can't hear client if id is alive
							}
							else
								SetListenOverride(id, client, Listen_Yes);
						}
					}
				}
			}
		}
	}
}

public void OnMapEnd()
{
	if(TieTimer != INVALID_HANDLE)
		TieTimer = INVALID_HANDLE;
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