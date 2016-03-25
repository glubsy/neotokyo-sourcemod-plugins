//TODO: bind !cameraman to have casters use the same point of view
//

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>
#include <neotokyo>
#include <clientprefs>
#define DEBUG 0
#define PLUGIN_VERSION "0.41"

//Players
int g_iNSFPlayer[5];
int g_iJINRAIPlayer[5];
bool g_bIsDead[MAXPLAYERS+1];
float g_fDeathOrigin[MAXPLAYERS+1][3];

//Casters
bool g_bWantsBinds[MAXPLAYERS+1];
bool g_bDefaultCFGSaved[MAXPLAYERS+1];
int Observers[MAXPLAYERS+1];
int ObservedPlayer[MAXPLAYERS+1];
int argtest;
Handle g_cookies[1];
bool g_bEnteredFPPOV[MAXPLAYERS+1][10];

public Plugin:myinfo = 
{
	name = "NEOTOKYO: casting binds",
	author = "glub",
	description = "Binds number keys to spectate players",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
}


public void OnPluginStart()
{
	RegConsoleCmd("sm_specbinds", SpecBindsCommand, "Binds key nums to spectator modes");
	RegConsoleCmd("sm_specunbind", SpecUnbindCommand, "Restores config_backup.cfg for the client");
	RegConsoleCmd("sm_resetbinds", ResetbindsCommand, "Restores config_backup.cfg for the client");
	//RegConsoleCmd("sm_camerabind", CamerabindCommand "");
	
	
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_disconnect", OnPlayerDisconnect, EventHookMode_Pre);

	RegConsoleCmd("sm_spec_client", SpecClientCommand, "Spectate a specific client 1 to 10");
	
	g_cookies[0] = RegClientCookie("config-backed-up","backed-up default client config file", CookieAccess_Public);
	
	RegConsoleCmd("testobs", Test, "test");
	
	for(int client = 1; client < MaxClients; client++)
	{
		if(!IsValidEntity(client) || !IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client))
			continue;
		ProcessCookies(client);
	}
}

public Action Test(client, args)
{
	char arg1[3];
	GetCmdArgString(arg1,sizeof(arg1));
	argtest = StringToInt(arg1);
	
	//ObservedPlayer = GetEntProp(client, Prop_Send, "m_hObserverTarget");
	ObservedPlayer[0] = argtest;
	Observers[0] = client;
	
	#if DEBUG >0
	PrintToChatAll("Observed: %N %i", ObservedPlayer[0], ObservedPlayer[0]);
	#endif
	
	//CreateTimer(5.0, timer_setobs, client);
	SetEntProp(client, Prop_Send, "m_hObserverTarget", ObservedPlayer[0]);
	Client_SetObserverMode(client, 6, false); 


	Client_SetThirdPersonMode(client, false); 
	
	//SetClientViewEntity(client, ObservedPlayer[0]);
}
public Action timer_setobs(Handle timer, int client)
{
	SetEntProp(client, Prop_Send, "m_hObserverTarget", ObservedPlayer[0]);
}






public Action OnPlayerSpawn(Handle event, char[] name, bool Broadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(!IsPlayerAlive(client))
		return;
	
	g_bIsDead[client] = false;
	
	CreateTimer(0.2, UpdateAlivePlayersArrays);
}


public Action SpecClientCommand(int client, int args)
{
	if(GetClientTeam(client) > 1)
		return Plugin_Handled;
	
	char arg1[3];
	GetCmdArgString(arg1,sizeof(arg1));
	int iNum = StringToInt(arg1);

	
	//Client_SetObserverMode(client, 4, false); //need chase mode

	switch(iNum)
	{
		case 1:
		{
			if(g_iJINRAIPlayer[0] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[0]])
			{
				//PrintCenterText(client, "%N is dead.", g_iNSFPlayer[0]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[0]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}

			/*
			if(g_bEnteredFPPOV[client][0])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][0] = false;
			}		
			else if(!g_bEnteredFPPOV[client][0])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][0] = true;
			}*/

			if(!IsValidEntity(client))
				return Plugin_Handled;
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[0]);
			
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[0], g_iJINRAIPlayer[0]);
			#endif
			
		}
		case 2:
		{
			if(g_iJINRAIPlayer[1] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[1]])
			{
				//PrintCenterText(client, "%N is dead.", g_iJINRAIPlayer[1]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[1]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			/*
			if(g_bEnteredFPPOV[client][1])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][1] = false;
			}		
			else if(!g_bEnteredFPPOV[client][1])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][1] = true;
			}*/
			
			if(!IsValidEntity(client))
				return Plugin_Handled; 
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[1]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[1], g_iJINRAIPlayer[1]);
			#endif
		}
		case 3:
		{
			if(g_iJINRAIPlayer[2] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[2]])
			{
				//PrintCenterText(client, "%N is dead.", g_iJINRAIPlayer[2]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[2]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			/*
			if(g_bEnteredFPPOV[client][2])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][2] = false;
			}		
			else if(!g_bEnteredFPPOV[client][2])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][2] = true;
			}
			*/
			
			if(!IsValidEntity(client))
				return Plugin_Handled;
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[2]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[2], g_iJINRAIPlayer[2]);
			#endif
		}
		case 4:
		{
			if(g_iJINRAIPlayer[3] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[3]])
			{
				//PrintCenterText(client, "%N is dead.", g_iJINRAIPlayer[3]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[3]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			/*
			if(g_bEnteredFPPOV[client][3])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][3] = false;
			}		
			else if(!g_bEnteredFPPOV[client][3])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][3] = true;
			}*/
			
			if(!IsValidEntity(client))
				return Plugin_Handled; 
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[3]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[3], g_iJINRAIPlayer[3]);
			#endif
		}
		case 5:
		{
			if(g_iJINRAIPlayer[4] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[4]])
			{
				//PrintCenterText(client, "%N is dead.", g_iJINRAIPlayer[4]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[4]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			/*
			if(g_bEnteredFPPOV[client][4])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][4] = false;
			}		
			else if(!g_bEnteredFPPOV[client][4])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][4] = true;
			}*/
			
			if(!IsValidEntity(client))
				return Plugin_Handled;
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[4]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[4], g_iJINRAIPlayer[4]);
			#endif
		}
		case 6:
		{
			if(g_iNSFPlayer[0] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[0]])
			{
				//PrintCenterText(client, "%N is dead.", g_iNSFPlayer[0]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[0]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			/*
			if(g_bEnteredFPPOV[client][5])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][5] = false;
			}		
			else if(!g_bEnteredFPPOV[client][5])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][5] = true;
			}*/
			
			if(!IsValidEntity(client))
				return Plugin_Handled;
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[0]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[0], g_iNSFPlayer[0]);
			#endif
		}
		case 7:
		{
			if(g_iNSFPlayer[1] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[1]])
			{
				//PrintCenterText(client, "%N is dead.", g_iNSFPlayer[1]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[1]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			/*
			if(g_bEnteredFPPOV[client][6])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][6] = false;
			}		
			else if(!g_bEnteredFPPOV[client][6])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][6] = true;
			}*/
			
			if(!IsValidEntity(client))
				return Plugin_Handled;
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[1]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[1], g_iNSFPlayer[1]);
			#endif
		}
		case 8:
		{
			if(g_iNSFPlayer[2] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[2]])
			{
				//PrintCenterText(client, "%N is dead.", g_iNSFPlayer[2]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[2]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			/*
			if(g_bEnteredFPPOV[client][7])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][7] = false;
			}		
			else if(!g_bEnteredFPPOV[client][7])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][7] = true;
			}*/
			
			if(!IsValidEntity(client))
				return Plugin_Handled;
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[2]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[2], g_iNSFPlayer[2]);
			#endif
		}
		case 9:
		{
			if(g_iNSFPlayer[3] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[3]])
			{
				//PrintCenterText(client, "%N is dead.", g_iNSFPlayer[3]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[3]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			/*
			if(g_bEnteredFPPOV[client][8])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][8] = false;
			}		
			else if(!g_bEnteredFPPOV[client][8])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][8] = true;
			}*/
			
			if(!IsValidEntity(client))
				return Plugin_Handled;
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[3]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[3], g_iNSFPlayer[3]);
			#endif
		}
		case 10:
		{
			if(g_iNSFPlayer[4] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[4]])
			{
				//PrintCenterText(client, "%N is dead.", g_iNSFPlayer[4]);
				
				//SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				//TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[4]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			/*
			if(g_bEnteredFPPOV[client][9])
			{
				EnterFPPOV(client, false);
				g_bEnteredFPPOV[client][9] = false;
			}		
			else if(!g_bEnteredFPPOV[client][9])
			{
				EnterFPPOV(client, true);
				g_bEnteredFPPOV[client][9] = true;
			}*/
			
			if(!IsValidEntity(client))
				return Plugin_Handled;
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[4]);
			#if DEBUG > 0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[4], g_iNSFPlayer[4]);
			#endif
		}
	}
	return Plugin_Handled;
}


public void EnterFPPOV(int client, bool state)
{
	if(state)
	{
		ClientCommand(client, "sm_spec_pov 1");	
	}
	else if(!state)
	{
		ClientCommand(client, "sm_spec_pov 0");	
		SetEntProp(client, Prop_Send, "m_iVision", 0);
		ClientCommand(client, "spec_mode");	
		
		//SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
		//Client_SetObserverMode(client, view_as<Obs_Mode>(4));
		
	}
}



public OnClientPostAdminCheck(int client)
{
	if (AreClientCookiesCached(client))
	{
		ProcessCookies(client);
	}
}

public ProcessCookies(int client)
{
	decl String:cookie[10];
	GetClientCookie(client, g_cookies[0], cookie, sizeof(cookie));

	if (StrEqual(cookie, "backedup")) 
	{
		ResetbindsCommand(client, 1);
		//ExecCFG(client, 3); //restoring backup
		return;
	}
	else 
	{
		WriteCFG(client, 3); //backing up if not backedup
	}
	return;
}


public Action SpecBindsCommand(int client, int args)
{
	if(!IsClientObserver(client))
	{
		PrintToChat(client, "You cannot use this command while not being in spectator team");
		return;
	}
	WriteCFG(client, 3);
	
	g_bWantsBinds[client] = true;
	
	CreateTimer(0.1, UpdateAlivePlayersArrays);
	
	if(g_bDefaultCFGSaved[client])
	{
		PrintToChat(client, "Your current config was saved to config_backup.cfg");
		PrintToChat(client, "Type !specunbind to restore it when needed.");
		CreateTimer(0.5, timer_SetBindsInit, client);
	}
}


public Action SpecUnbindCommand(int client, int args)
{
	ExecCFG(client, 3);
	PrintToChat(client, "Your previous config was restored.");
}

public Action ResetbindsCommand(int client, int args)
{
	ClientCommand(client, "bind 1 \"slot1\" ");
	ClientCommand(client, "bind 2 \"slot2\" ");
	ClientCommand(client, "bind 3 \"slot3\" ");
	ClientCommand(client, "bind 4 \"slot4\" ");
	ClientCommand(client, "bind 5 \"slot5\" ");
	
	ClientCommand(client, "bind 6 \"slot6\" ");
	ClientCommand(client, "bind 7 \"slot7\" ");
	ClientCommand(client, "bind 8 \"slot8\" ");
	ClientCommand(client, "bind 9 \"slot9\" ");
	ClientCommand(client, "bind 0 \"slot10\" ");
	
	PrintToConsole(client, "Reset your binds to default NT ones\n");
}


public Action WriteCFG(int client, int type)
{
	if(type == 1)
	{		
		ClientCommand(client, "host_writeconfig config.cfg");
	}
	if(type == 2)
	{
		ClientCommand(client, "host_writeconfig casters.cfg");
	}
	if(type == 3)
	{
		ClientCommand(client, "host_writeconfig config_backup.cfg");
		g_bDefaultCFGSaved[client] = true;
		SetClientCookie(client, g_cookies[0], "backedup");
	}
}


public Action ExecCFG(int client, int type)
{
	if(type == 1)
		ClientCommand(client, "exec casters.cfg");
	if(type == 2)
		ClientCommand(client, "exec config.cfg");
	if(type == 3)
		ClientCommand(client, "exec config_backup.cfg");
}




public Action timer_SetBindsInit(Handle timer, int client)
{
	if(!g_bWantsBinds[client])
		return;
	
	ClientCommand(client, "bind 1 \"slot1; sm_spec_client 1\" ");
	ClientCommand(client, "bind 2 \"slot2; sm_spec_client 2\" ");
	ClientCommand(client, "bind 3 \"slot3; sm_spec_client 3\" ");
	ClientCommand(client, "bind 4 \"slot4; sm_spec_client 4\" ");
	ClientCommand(client, "bind 5 \"slot5; sm_spec_client 5\" ");
	
	ClientCommand(client, "bind 6 \"slot6; sm_spec_client 6\" ");
	ClientCommand(client, "bind 7 \"slot7; sm_spec_client 7\" ");
	ClientCommand(client, "bind 8 \"slot8; sm_spec_client 8\" ");
	ClientCommand(client, "bind 9 \"slot9; sm_spec_client 9\" ");
	ClientCommand(client, "bind 0 \"slot10; sm_spec_client 10\" ");
}


public Action UpdateAlivePlayersArrays(Handle timer)
{
	int countNSF = 0;
	int countJinrai = 0;
	int totalcount = 0;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidEntity(i))
			continue; 
		
		if(!IsValidClient(i)) //|| !IsFakeClient(i) 
			continue;
		
		if(GetClientTeam(i) <= 1)
			continue;
		
		if(totalcount >= 10)
			break;

		if(GetClientTeam(i) == 3)
		{
			g_iNSFPlayer[countNSF] = i;
			
			if(countNSF < 4)
				countNSF++;
			
			totalcount++;
		}
		else if(GetClientTeam(i) == 2)
		{
			g_iJINRAIPlayer[countJinrai] = i;

			if(countJinrai < 4)
				countJinrai++;
			
			totalcount++;
		}
	}
	#if DEBUG > 0
	PrintToServer("NSF: %i %N, %i %N, %i %N, %i %N, %i %N", g_iNSFPlayer[0], g_iNSFPlayer[0], g_iNSFPlayer[1], g_iNSFPlayer[1], g_iNSFPlayer[2], g_iNSFPlayer[2], g_iNSFPlayer[3], g_iNSFPlayer[3], g_iNSFPlayer[4], g_iNSFPlayer[4]);
	PrintToServer("JINRAI: %i %N, %i %N, %i %N, %i %N, %i %N, totalcount %i, countjinrai %i", g_iJINRAIPlayer[0], g_iJINRAIPlayer[0], g_iJINRAIPlayer[1], g_iJINRAIPlayer[1], g_iJINRAIPlayer[2], g_iJINRAIPlayer[2], g_iJINRAIPlayer[3], g_iJINRAIPlayer[3], g_iJINRAIPlayer[4], g_iJINRAIPlayer[4], totalcount, countJinrai);
	PrintToServer("Deads: JINRAI: %b %b %b %b %b, NSF: %b %b %b %b %b", g_bIsDead[g_iJINRAIPlayer[0]], g_bIsDead[g_iJINRAIPlayer[1]], g_bIsDead[g_iJINRAIPlayer[2]], g_bIsDead[g_iJINRAIPlayer[3]], g_bIsDead[g_iJINRAIPlayer[4]], g_bIsDead[g_iNSFPlayer[0]], g_bIsDead[g_iNSFPlayer[1]], g_bIsDead[g_iNSFPlayer[2]], g_bIsDead[g_iNSFPlayer[3]], g_bIsDead[g_iNSFPlayer[4]]);
	#endif
}




public void OnRoundStart(Handle event, const char[] name, bool Broadcast)
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsClientInGame(client) || !IsValidEntity(client) || IsFakeClient(client))
			continue;

		if(GetClientTeam(client) > 1)
			continue;

		CreateTimer(0.3, timer_ChangeSpecMode, client);	
	}
	
	CreateTimer(14.0, UpdateAlivePlayersArrays); // just in case
}

public Action timer_ChangeSpecMode(Handle timer, int client)
{
	if(!IsClientInGame(client) || IsPlayerAlive(client) || IsFakeClient(client))
		return;

	//ClientCommand(client, "spec_mode");
	//ClientCommand(client, "spec_mode");
	SetEntProp(client, Prop_Send, "m_iObserverMode", 4);  //causes problems if player is alive and spawning?
}



public void OnPlayerDeath(Handle event, const char[] name, bool Broadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	GetClientAbsOrigin(victim, g_fDeathOrigin[victim]);
	g_fDeathOrigin[victim][2] += 40.0;
	
	g_bIsDead[victim] = true;
	
	CreateTimer(2.0, UpdateAlivePlayersArrays);
}


public void OnPlayerDisconnect(Handle event, const char[] name, bool Broadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	g_bDefaultCFGSaved[client] = false;
	
	CreateTimer(1.0, UpdateAlivePlayersArrays);
}	
	
	
	

stock SendDialogToOne(int client, const char[] text, any:...)
{
	char message[100];
	VFormat(message, sizeof(message), text, 3);	
	
	KeyValues kv = new KeyValues("Stuff", "title", message);
	kv.SetColor("color", 0, 255, 0, 255);
	kv.SetNum("level", 1); //0 is highest priority
	kv.SetNum("time", 10); //minimum 10 sec? fuck this, Valve!
	
	CreateDialog(client, kv, DialogType_Msg);

	delete kv;
}

