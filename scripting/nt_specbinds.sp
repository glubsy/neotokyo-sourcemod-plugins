#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>
#include <neotokyo>
#include <clientprefs>
#define DEBUG 1
#define PLUGIN_VERSION "0.3"

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
	RegConsoleCmd("sm_specbinds", CastBindCallback, "Binds key nums to spectator modes");
	
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_disconnect", OnPlayerDisconnect, EventHookMode_Pre);

	RegConsoleCmd("sm_spec_client", SpecClientCommand, "Spectate a specific client 1 to 10");
	
	g_cookies[0] = RegClientCookie("config-backed-up","backed-up default client config file", CookieAccess_Public);
	
	RegConsoleCmd("testobs", Test, "test");
}

public Action Test(client, args)
{
	char arg1[3];
	GetCmdArgString(arg1,sizeof(arg1));
	argtest = StringToInt(arg1);
	
	//ObservedPlayer = GetEntProp(client, Prop_Send, "m_hObserverTarget");
	ObservedPlayer[0] = argtest;
	Observers[0] = client;
	PrintToChatAll("Observed: %N %i", ObservedPlayer[0], ObservedPlayer[0]);

	
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
			if(g_iNSFPlayer[0] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[0]])
			{
				PrintCenterText(client, "%N is dead.", g_iNSFPlayer[0]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[0]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[0]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[0], g_iNSFPlayer[0]);
			#endif
		}
		case 2:
		{
			if(g_iNSFPlayer[1] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[1]])
			{
				PrintCenterText(client, "%N is dead.", g_iNSFPlayer[1]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[1]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[1]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[1], g_iNSFPlayer[1]);
			#endif
		}
		case 3:
		{
			if(g_iNSFPlayer[2] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[2]])
			{
				PrintCenterText(client, "%N is dead.", g_iNSFPlayer[2]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[2]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[2]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[2], g_iNSFPlayer[2]);
			#endif
		}
		case 4:
		{
			if(g_iNSFPlayer[3] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[3]])
			{
				PrintCenterText(client, "%N is dead.", g_iNSFPlayer[3]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[3]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[3]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[3], g_iNSFPlayer[3]);
			#endif
		}
		case 5:
		{
			if(g_iNSFPlayer[4] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iNSFPlayer[4]])
			{
				PrintCenterText(client, "%N is dead.", g_iNSFPlayer[4]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iNSFPlayer[4]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iNSFPlayer[4]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iNSFPlayer[4], g_iNSFPlayer[4]);
			#endif
		}
		case 6:
		{
			if(g_iJINRAIPlayer[0] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[0]])
			{
				PrintCenterText(client, "%N is dead.", g_iJINRAIPlayer[0]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[0]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[0]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[0], g_iJINRAIPlayer[0]);
			#endif
		}
		case 7:
		{
			if(g_iJINRAIPlayer[1] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[1]])
			{
				PrintCenterText(client, "%N is dead.", g_iJINRAIPlayer[1]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[1]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[1]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[1], g_iJINRAIPlayer[1]);
			#endif
		}
		case 8:
		{
			if(g_iJINRAIPlayer[2] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[2]])
			{
				PrintCenterText(client, "%N is dead.", g_iJINRAIPlayer[2]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[2]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[2]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[2], g_iJINRAIPlayer[2]);
			#endif
		}
		case 9:
		{
			if(g_iJINRAIPlayer[3] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[3]])
			{
				PrintCenterText(client, "%N is dead.", g_iJINRAIPlayer[3]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[3]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[3]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[3], g_iJINRAIPlayer[3]);
			#endif
		}
		case 10:
		{
			if(g_iJINRAIPlayer[4] < 1)
				return Plugin_Handled;
			
			if(g_bIsDead[g_iJINRAIPlayer[4]])
			{
				PrintCenterText(client, "%N is dead.", g_iJINRAIPlayer[4]);
				
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
				TeleportEntity(client, g_fDeathOrigin[g_iJINRAIPlayer[4]], NULL_VECTOR, NULL_VECTOR);
				return Plugin_Handled;
			}
			
			SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_iJINRAIPlayer[4]);
			#if DEBUG >0
			PrintToChatAll("%N is observing %i %N", client, g_iJINRAIPlayer[4], g_iJINRAIPlayer[4]);
			#endif
		}
	}
	return Plugin_Handled;
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
		ExecCFG(client, 3); //restoring backup
		return;
	}
	else 
	{
		WriteCFG(client, 3); //backing up if not backedup
	}
	return;
}


public Action CastBindCallback(int client, args)
{
	if(!IsClientObserver(client))
		return;
	
	g_bWantsBinds[client] = true;
	
	CreateTimer(0.0, UpdateAlivePlayersArrays);
	
	if(!g_bDefaultCFGSaved)
	{
		WriteCFG(client, 1);
	}
	
	SetBindsInit(client);
	WriteCFG(client, 2);
}

public Action WriteCFG(int client, int type)
{
	if(type == 1)
	{
		g_bDefaultCFGSaved[client] = true;
		ClientCommand(client, "host_writeconfig config.cfg");
	}
	if(type == 2)
	{
		ClientCommand(client, "host_writeconfig casters.cfg");
	}
	if(type == 3)
	{
		SetClientCookie(client, g_cookies[0], "backedup");
		ClientCommand(client, "host_writeconfig config_backup.cfg");
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







public Action SetBindsInit(int client)
{
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


//reverting to default NT bindings
public void RebindKeyDefault(int client, int key)
{
	
	ClientCommand(client, "bind %i '\"'slot%i;", g_iNumber[1]);
}


public Action UpdateAlivePlayersArrays(Handle timer)
{
	int countNSF = 0;
	int countJinrai = 0;
	int totalcount = 0;
	
	for(int i = 1; i < 32; i++)
	{
		if(!IsClientConnected(i) || !IsClientInGame(i)) //|| !IsFakeClient(i) 
			continue;
		
		if(GetClientTeam(i) <= 1)
			continue;		
		
		if(totalcount > 10)
			break; 


		if(GetClientTeam(i) == 3)
		{
			g_iNSFPlayer[countNSF] = i;
			
			countNSF++;
			totalcount++;
		}
		else if(GetClientTeam(i) == 2)
		{
			g_iJINRAIPlayer[countJinrai] = i;

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
	CreateTimer(5.0, UpdateAlivePlayersArrays);
	
	for(int client = 1; client < MaxClients; client++)
	{
		if(!g_bWantsBinds[client] || GetClientTeam(client) > 1)
			return;

		SetBindsInit(client);
	}
}


public void OnPlayerDeath(Handle event, const char[] name, bool Broadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	GetClientAbsOrigin(victim, g_fDeathOrigin[victim]);
	g_fDeathOrigin[victim][2] += 70.0;
	
	g_bIsDead[victim] = true;
	
	
	
	CreateTimer(2.0, UpdateAlivePlayersArrays);
	
	for(int i = 1; i < MaxClients; i++)
	{
		if(!g_bWantsBinds[i])
			continue;
	}	
}


public void OnPlayerDisconnect(Handle event, const char[] name, bool Broadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	g_bDefaultCFGSaved[client] = false; //for the next guy
	
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
