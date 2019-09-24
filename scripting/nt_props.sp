#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <nt_entitytools>

#pragma semicolon 1
#define PLUGIN_VERSION "20190924"

Handle g_cvar_props_enabled, g_cvar_restrict_alive, g_cvar_give_initial_credits, g_cvar_credits_replenish, g_cvar_score_as_credits= INVALID_HANDLE;
Handle cvMaxPropsCreds = INVALID_HANDLE; // maximum credits given
new Handle:cvPropMaxTTL = INVALID_HANDLE; // maximum time to live before prop gets auto removed
new Handle:g_PropPrefCookie = INVALID_HANDLE; // handle to client preferences
Handle g_cvar_props_oncapture, g_cvar_props_onghostpickup = INVALID_HANDLE;
Handle convar_nt_entitytools = INVALID_HANDLE;
bool gb_PausePropSpawning;
bool gb_hashadhisd[MAXPLAYERS+1];

// WARNING: the custom files require the sm_downloader plugin to force clients to download them
// otherwise, have to add all custom files to downloads table ourselves with AddFileToDownloadsTable()
new const String:gs_dongs[][] = {
	"models/d/d_s02.mdl", //small
	"models/d/d_b02.mdl", //big
	"models/d/d_h02.mdl", //huge
	"models/d/d_g02.mdl", //gigantic
	"models/d/d_mh02.mdl" }; //megahuge
// Prices: scale 1= 1 creds, 2= 3 creds, 3= 6 creds, 4= 8 creds, 5= 10 creds
new const g_DongPropPrice[] = { 0, 1, 3, 6, 8, 10 };

new const String:gs_allowed_models[][] = {
	"models/nt/a_lil_tiger.mdl",
	"models/nt/props_office/rubber_duck.mdl",
	"models/logo/jinrai_logo.mdl",
	"models/logo/nsf_logo.mdl" };

new const String:gs_TE_type[][] = { "physicsprop", "breakmodel" };

// [0] holds virtual credits, [2] current score credits, [3] maximum credits level reached
new g_RemainingCreds[MAXPLAYERS+1][3];
#define VIRT_CRED 0
#define SCORE_CRED 1
#define MAX_CRED 2

new g_propindex_d[MAXPLAYERS+1]; // holds a temporary entity index for timer destruction
new g_precachedModels[10];
new g_prefs_nowantprops[MAXPLAYERS+1];


public Plugin:myinfo =
{
	name = "NEOTOKYO props spawner.",
	author = "glub",
	description = "Allows players to spawn props.",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
};

// TODO:
// → split code into sm_props
// → rework logic for credits, might be broken
// → recheck keeping precached model indices in list
// → command to spawn props with random coords around a target (player) and velocity, towards their origin
// → make menu to spawn props
// → add sparks to props spawned and maybe a squishy sound for in range with TE_SendToAllInRange
// → save credits in sqlite db for longer term?
//
// KNOWN ISSUES:
// -> AFAIK the TE cannot be destroyed by timer, so client preference is very limited, ie. if someone asks for a big scale model that is supposed to be auto-removed
//    we can't use a TE because they don't get affected by timers, so regular physics_prop take precedence. Same for dynamic props, cannot have them as TempEnts.


public OnPluginStart()
{
	RegAdminCmd("sm_props_set_credits", CommandSetCreditsForClient, ADMFLAG_SLAY, "Gives target player virtual credits in order to spawn props.");
	RegConsoleCmd("sm_props_credit_status", CommandPropCreditStatus, "List all player credits to spawn props.");

	RegConsoleCmd("sm_dick", Command_Dong_Spawn, "Spawns a dick [scale 1-5] [1 for static prop]");
	RegConsoleCmd("sm_props", CommandPropSpawn, "Spawns a prop.");
	RegConsoleCmd("sm_strapon", Command_Strap_Dong, "Strap a dong onto [me|team|all].");

	g_cvar_props_onghostpickup = CreateConVar("sm_props_onghostpickup", "1", "Picking up the ghost is exciting,", FCVAR_NONE, true, 0.0, true, 1.0 );
	g_cvar_props_oncapture = CreateConVar("sm_props_oncapture", "0", "Fireworks on ghost capture.", FCVAR_NONE, true, 0.0, true, 1.0 );


	g_cvar_props_enabled = CreateConVar( "sm_props_enabled", "1",
										"0: disable custom props spawning, 1: enable custom props spawning",
										FCVAR_NONE, true, 0.0, true, 1.0 );

	g_cvar_restrict_alive = CreateConVar( "sm_props_restrict_alive", "0",
										"0: spectators can spawn props too. 1: only living players can spawn props",
										FCVAR_NONE, true, 0.0, true, 1.0 );

	g_cvar_give_initial_credits = CreateConVar( "sm_props_initial_credits", "0",
												"0: players starts with zero credits 1: assign sm_max_props_credits to all players as soon as they connect",
												FCVAR_NOTIFY, true, 0.0, true, 1.0 );
	cvMaxPropsCreds = CreateConVar("sm_props_max_credits", "10",
									"Max number of virtual credits allowed per round/life for spawning props");
	cvPropMaxTTL = CreateConVar("sm_props_max_ttl", "60",
								"Maximum time to live for spawned props in seconds.");

	g_cvar_credits_replenish = CreateConVar( "sm_props_replenish_credits", "1",
											"0: credits are lost forever after use. 1: credits replenish after each end of round",
											FCVAR_NOTIFY, true, 0.0, true, 1.0 );
	g_cvar_score_as_credits = CreateConVar( "sm_props_score_as_credits", "1",
											"0: use virtual props credits only, 1: use score as props credits on top of virtual props credits",
											FCVAR_NOTIFY, true, 0.0, true, 1.0 );

	RegConsoleCmd("sm_props_nothx", Command_Hate_Props_Toggle, "Toggle your preference to not see custom props wherever possible.");
	g_PropPrefCookie = RegClientCookie("no-props-plz", "player doesn't like custom props", CookieAccess_Public);

	RegConsoleCmd("sm_props_pause", Command_Pause_Props_Spawning, "Prevent any further custom prop spawning until end of round.");

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", event_RoundStart);

	RegAdminCmd("sm_props_givescore", CommandGiveScore, ADMFLAG_SLAY, "DEBUG: add 20 frags to score");
	RegAdminCmd("sm_props_te", Spawn_TE_Prop, ADMFLAG_SLAY, "DEBUG: Spawn TE dong");

	AutoExecConfig(true, "sm_nt_props");

	convar_nt_entitytools = FindConVar("sm_nt_entitytools");

	// Needed for ghost-related events
	// if(convar_nt_entitytools == INVALID_HANDLE)
	// 	ThrowError("[sm_props] Couldn't find nt_entitytools plugin. Wrong version? Aborting.");
}

//==================================
//		Client preferences
//==================================


public OnClientCookiesCached(int client)
{
	ProcessCookies(client);
}


public OnClientPostAdminCheck(int client)
{
	if(!GetConVarBool(g_cvar_props_enabled))
	{
		//g_prefs_nowantprops[client] = false;
		return;
	}

	if (AreClientCookiesCached(client))
	{
		ProcessCookies(client);
		//CreateTimer(120.0, DisplayNotification, client);
		return;
	}
}


public OnClientDisconnect(int client)
{
	if(GetConVarBool(g_cvar_props_enabled))
		g_prefs_nowantprops[client] = false;
}


public ProcessCookies(int client)
{
	if (!IsValidClient(client))
		return;

	if(!FindClientCookie("no-props-plz"))
	{
		g_prefs_nowantprops[client] = false;
		CreateTimer(10.0, DisplayNotification, client);
		return;
	}

	new String:cookie[10] = '\0';
	GetClientCookie(client, g_PropPrefCookie, cookie, sizeof(cookie));

	if (StrEqual(cookie, "penabled"))
	{
		g_prefs_nowantprops[client] = false;
		return;
	}
	else if (StrEqual(cookie, "pdisabled"))
	{
		g_prefs_nowantprops[client] = true;
		return;
	}
	return;
}


public Action DisplayNotification(Handle timer, int client)
{
	if(client > 0 && IsClientConnected(client) && IsClientInGame(client))
	{
		if(!g_prefs_nowantprops[client])
		{
			PrintToChat(client, 	"[sm_props] You can toggle seeing custom props completely by typing !props_nothx");
			PrintToConsole(client, 	"\n[sm_props] You can toggle seeing custom props completely by typing sm_props_nothx\n");
			PrintToChat(client, 	"[sm_props] You can prevent people from spawning props until the end of the round by typing !props_pause");
			PrintToConsole(client, 	"\n[sm_props] You can prevent people from spawning props until the end of the round by typing sm_props_pause\n");
		}
	}
	return Plugin_Handled;
}


public Action Command_Hate_Props_Toggle(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if(!FindClientCookie("no-props-plz")) // this might not be working, REMOVE
	{
		g_prefs_nowantprops[client] = true;
		SetClientCookie(client, g_PropPrefCookie, "pdisabled");
		ReplyToCommand(client, "You preference has been recorded. You do like props after all.");
		PrintToConsole(client, "no found cookiz?");
		return Plugin_Handled;
	}

	new String:cookie[10];
	GetClientCookie(client, g_PropPrefCookie, cookie, sizeof(cookie));

	if (StrEqual(cookie, "pdisabled"))
	{
		SetClientCookie(client, g_PropPrefCookie, "penabled");
		g_prefs_nowantprops[client] = false;
		ReplyToCommand(client, "You preference has been recorded. You do like props after all.");
		return Plugin_Handled;
	}
	else // was enabled, or not yet set
	{
		SetClientCookie(client, g_PropPrefCookie, "pdisabled");
		g_prefs_nowantprops[client] = true;
		ReplyToCommand(client, "You preference has been recorded. You no like props.");
		ShowActivity2(client, "[sm_props] ", "%s opted out of sm_props models.", client);
		LogAction(client, -1, "[sm_props] \"%L\" opted out of sm_props models.", client);
		return Plugin_Handled;
	}
}


public Action Command_Pause_Props_Spawning(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	new String:clientname[MAX_NAME_LENGTH];
	GetClientName(client, clientname, sizeof(clientname));

	if (!gb_PausePropSpawning)
	{
		gb_PausePropSpawning = true;
		PrintToChatAll("[sm_props] Prop spawning has been disabled until the end of the round.");
		for (int i=1; i <= MaxClients; i++)
		{
			if (IsValidClient(i))
				PrintToConsole(i, "[sm_props] Prop spawning has been disabled by \"%s\" until the end of the round.", clientname);
		}
	}
	return Plugin_Handled;
}


//==================================
//		Credits management
//==================================

public Action CommandGiveScore (int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "This command cannot be executed by the server.");
		return Plugin_Stop;
	}

	SetEntProp(client, Prop_Data, "m_iFrags", 20);
	g_RemainingCreds[client][SCORE_CRED] = 20;
	g_RemainingCreds[client][VIRT_CRED] = 20;
	g_RemainingCreds[client][MAX_CRED] = 20;
	CommandSetCreditsForClient(client, 20);
	PrintToConsole(client, "gave score to %d", client);
	return Plugin_Handled;

}


public Action CommandPropCreditStatus(int client, int args)
{
	decl String:name[MAX_NAME_LENGTH] = '\0';
	PrintToConsole(client, "\n--------- Current props ppawning credits status ---------");
	for (int i=1; i < MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;

		if (GetClientName(i, name, sizeof(name)))
		{
			PrintToConsole(client,"Virtual: %d, Score: %d, Maximum: %d for \"%s\"", g_RemainingCreds[i][VIRT_CRED], g_RemainingCreds[i][SCORE_CRED], g_RemainingCreds[i][MAX_CRED], name);
		}
	}
	PrintToConsole(client, "----------------------------------------------------------\n");
	return Plugin_Handled;
}

/*
public OnEventShutdown(){
	UnhookEvent("player_spawn",OnPlayerSpawn);
	UnhookEvent("game_round_start",event_RoundStart);
}*/ //might be responsible for weapon disappearing, don't even remember why I used this in the first place


public OnClientPutInServer(int client){
	if(client && !IsFakeClient(client))
	{
		// if we use score as credit, restore them
		if ( GetConVarBool(g_cvar_score_as_credits) )
			g_RemainingCreds[client][SCORE_CRED] = GetClientFrags(client); //NEEDS TESTING!
		if ( GetConVarBool(g_cvar_give_initial_credits) )
			g_RemainingCreds[client][VIRT_CRED] = g_RemainingCreds[client][MAX_CRED] = GetConVarInt(cvMaxPropsCreds);
		else
			g_RemainingCreds[client][MAX_CRED] = g_RemainingCreds[client][VIRT_CRED] = 0;
	}
}


public Action OnPlayerSpawn(Handle event, const String:name[], bool dontBroadcast)
{
	// reinitialize the virtual credits to constant value
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if ( GetConVarBool(g_cvar_credits_replenish) )
		g_RemainingCreds[client][VIRT_CRED] = GetConVarInt(cvMaxPropsCreds);
	else
		g_RemainingCreds[client][VIRT_CRED] = g_RemainingCreds[client][MAX_CRED];
	//return Plugin_Continue;
}


public void event_RoundStart(Handle event, const String:name[], bool dontBroadcast)
{
	for(int client = 1; client <= MaxClients; client++)
	{
		gb_hashadhisd[client] = false;

		if(!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client))
			continue;

		if ( GetConVarBool(g_cvar_credits_replenish) )
			g_RemainingCreds[client][VIRT_CRED] = GetConVarInt(cvMaxPropsCreds);
		else
			g_RemainingCreds[client][VIRT_CRED] = g_RemainingCreds[client][MAX_CRED];
	}

	gb_PausePropSpawning = false;
}


public Action OnPlayerDeath(Handle event, const String:name[], bool dontBroadcast)
{
	// keep track of the player score in our credits array
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (!IsValidClient(attacker))
		return;

	if (!GetConVarBool(g_cvar_credits_replenish))
		g_RemainingCreds[attacker][VIRT_CRED] += 1;

	g_RemainingCreds[attacker][SCORE_CRED] = GetClientFrags(attacker);

	if (g_RemainingCreds[attacker][SCORE_CRED] > g_RemainingCreds[attacker][MAX_CRED])
		g_RemainingCreds[attacker][MAX_CRED] = g_RemainingCreds[attacker][SCORE_CRED];
	//return Plugin_Continue;
}


bool hasEnoughCredits(int client, int asked)
{
	if ( GetConVarBool( g_cvar_score_as_credits ) )
	{
		if (g_RemainingCreds[client][SCORE_CRED] <= 0)
		{
			PrintToChat(client, "[] Your current score doesn't allow you to spawn props.");
			return false;
		}
	}
	if (asked <= g_RemainingCreds[client][VIRT_CRED])
		return true;
	return false;
}


DecCredits(int client, int amount, bool relaytoclient)
{
	if ( GetConVarInt( g_cvar_score_as_credits ) > 0 )
	{
		DecrementScore(client, 1);
		g_RemainingCreds[client][SCORE_CRED] -= 1;

		if (relaytoclient)
		{
			PrintToChat(client, "[] WARNING: Your score has been decreased by 1 point for using that command!");
		}
	}

	g_RemainingCreds[client][VIRT_CRED] -= amount;
	if (relaytoclient)
	{
		PrintToChat(client, "[] Credits remaining: %d.", g_RemainingCreds[client][VIRT_CRED]);
		PrintToConsole(client, "[] Credits remaining: %d.", g_RemainingCreds[client][VIRT_CRED]);
	}
}


SetCredits(int client, int amount)
{
	g_RemainingCreds[client][VIRT_CRED] = amount;

	if (g_RemainingCreds[client][VIRT_CRED] > g_RemainingCreds[client][MAX_CRED])
		g_RemainingCreds[client][MAX_CRED] = amount;
}


DecrementScore(int client, int amount)
{
	new new_xp = GetClientFrags(client) - amount;
	SetEntProp(client, Prop_Data, "m_iFrags", new_xp);
	UpdatePlayerRankXP(client, new_xp);
}


// increment (virtual) credits for target client
public Action CommandSetCreditsForClient(int client, int args)
{
	if(!client || IsFakeClient(client))
		return Plugin_Stop;

	if (GetCmdArgs() != 2)
	{
		PrintToChat(client, "Usage: !props_set_credit #id amount (use \"status\" in console).");
		PrintToConsole(client, "Usage: sm_props_set_credit #id amount (use \"status\" in console).");
		return Plugin_Handled;
	}

	decl String:s_amount[5];
	decl String:s_target[3];
	decl String:s_targetname[MAX_NAME_LENGTH] = '\0';
	int i_target;
	GetCmdArg(1, s_target, sizeof(s_target));
	GetCmdArg(2, s_amount, sizeof(s_amount));

	//PrintToConsole(client, "[DEBUG] target: %s amount: %s", s_target, s_amount);
	i_target = GetClientOfUserId( StringToInt(s_target) );
	//PrintToConsole(client, "[DEBUG] itarget: %i amount: %d", i_target, StringToInt(s_amount));

	SetCredits(i_target, StringToInt(s_amount));

	PrintToChat(i_target, "[] Your credits have been set to %d.", g_RemainingCreds[i_target][VIRT_CRED]);
	PrintToConsole(i_target, "[] Your credits have been set to %d.", g_RemainingCreds[i_target][VIRT_CRED]);

	if (GetClientName(i_target, s_targetname, sizeof(s_targetname)) && client != i_target)
	{
		ReplyToCommand(client, "[] The credits for player %s are now set to %d.", s_targetname, g_RemainingCreds[i_target][VIRT_CRED]);
	}
	return Plugin_Handled;
}


//==================================
//		Prop Spawning
//==================================


public Action PropSpawnDispatch(int client, int model_index)
{
	CreatePropPhysicsOverride(client, gs_allowed_models[model_index], 50);
	return Plugin_Handled;
}


public Action PrintPluginCommandInfo(int client)
{
	PrintToChat(client, "[sm_props] Admin, check console for useful commands and convars...");
	PrintToConsole(client, "[sm_props] Admins, some useful commands:");
	PrintToConsole(client, "\nsm_props_set_credits: sets credits for a clientID\nsm_props_credit_status: check credit status for all\nsm_props_restrict_alive: restrict to living players\nsm_props_initial_credits: initial amount given on player connection\nsm_props_max_credits: credits given on initial connection\nsm_props_replenish_credits: whether credits are replenished between rounds\nsm_props_score_as_credits: whether score should be counter as credits.\nsm_props_max_ttl: props get deleted after that time.\nsm_props_enabled: disable the command.");

	return Plugin_Handled;
}


public Action CommandPropSpawn(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return Plugin_Handled;
	}

	if (GetConVarBool(g_cvar_restrict_alive) && GetClientTeam(client) <= 1)
	{
		PrintToChat(client, "Spawning props is currently disabled for spectators.");
		PrintToConsole(client, "Spawning props is currently disabled for spectators.");

		if (IsAdmin(client))
		{
			PrintToConsole(client, "Admins, some useful commands:\nsm_props_set_credits: sets credits for a clientID\nsm_props_credit_status: check credit status for all\nsm_props_restrict_alive: restrict to living players\nsm_props_initial_credits: initial amount given on player connection\nsm_props_max_credits: credits given on initial connection\nsm_props_replenish_credits: whether credits are replenished between rounds\nsm_props_score_as_credits: whether score should be counter as credits.\nsm_props_max_ttl: props get deleted after that time.\nsm_props_enabled: disable the command.");
			PrintToChat(client, "Admin, check console for useful commands and convars (more to come later).");
		}
		return Plugin_Handled;
	}

	if( GetCmdArgs() != 1 )
	{
		PrintToConsole(client, "Usage: sm_props [model|model path]\nAvailable models currently: duck, tiger");
		PrintToChat(client, "Usage: !props [model | model path]\nAvailable models currently: duck, tiger");

		PrintToChat(client, "You currently have %d credits to spawn props.", g_RemainingCreds[client][VIRT_CRED]);
		PrintToConsole(client, "You currently have %d credits to spawn props.", g_RemainingCreds[client][VIRT_CRED]);

		if (IsAdmin(client))
		{
			PrintPluginCommandInfo(client);
		}

		return Plugin_Handled;
	}

	if (!GetConVarBool(g_cvar_props_enabled))
	{
		PrintToConsole(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		PrintToChat(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		return Plugin_Handled;
	}

	decl String:model_name[PLATFORM_MAX_PATH];
	GetCmdArg(1, model_name, sizeof(model_name));

	for (int index=0; index < sizeof(gs_allowed_models); ++index)
	{
		//TODO: check the path
		//TODO: make selection menu // Don't stop at first match
		//if (strcmp(model_name, gs_allowed_models[i]) == 0)
		if (StrContains(gs_allowed_models[index], model_name, false) != -1)
		{
			if (hasEnoughCredits(client, 5)) 								//FIXME: for now everything costs 5!
			{
				PrintToConsole(client, "Spawned: %s.", gs_allowed_models[index]);
				PrintToChat(client, "Spawning your %s.", model_name);
				PropSpawnDispatch(client, index);

				PrintToChat(client, "[] You have just used %d credits.", 5);
				PrintToConsole(client, "[] You have just used %d credits.", 5);
				DecCredits(client, 5, true);
				return Plugin_Handled;
			}
			else
			{
				PrintToChat(client, "[] You don't have enough credits to spawn a prop: credits needed: %d, credits remaining: %d.",
				5, g_RemainingCreds[client][VIRT_CRED]);
				PrintToConsole(client, "[] You don't have enough credits to spawn a prop: credits needed: %d, credits remaining: %d.",
				5, g_RemainingCreds[client][VIRT_CRED]);
				return Plugin_Handled;
			}
		}
	}
	PrintToConsole(client, "Did not find requested model \"%s\" among allowed models.", model_name);
	PrintToChat(client, "Did not find requested model \"%s\" among allowed models.", model_name);
	return Plugin_Handled;
}



//==================================
//		Dong Spawning
//==================================

// calls the actual model creation
public DongDispatch(int client, int scale, int bstatic)
{
	switch(scale)
	{
		case 1:
		{
			if (!bstatic)
			{
				if (Should_Use_TE)
					Spawn_TE_Dong(client, gs_dongs[scale-1], gs_TE_type[0]);
				else
					g_propindex_d[client] = CreatePropPhysicsOverride(client, gs_dongs[scale-1], 50);
			}
			else
				g_propindex_d[client] = CreatePropDynamicOverride(client, gs_dongs[scale-1], 50);
		}
		case 2:
		{
			if (!bstatic)
			{
				if (Should_Use_TE)
					Spawn_TE_Dong(client, gs_dongs[scale-1], gs_TE_type[0]);
				else
				{
					g_propindex_d[client] = CreatePropPhysicsOverride(client, gs_dongs[scale-1], 120);
					CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
				}
			}
			else
			{
				g_propindex_d[client] = CreatePropDynamicOverride(client, gs_dongs[scale-1], 120);
				CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
			}
		}
		case 3:
		{
			if (!bstatic)
				g_propindex_d[client] = CreatePropPhysicsOverride(client, gs_dongs[scale-1], 180);
			else
				g_propindex_d[client] = CreatePropDynamicOverride(client, gs_dongs[scale-1], 180);

			// remove the prop when it's touched by a player
			SDKHook(g_propindex_d[client], SDKHook_Touch, OnTouchEntityRemove);
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
		}
		case 4:
		{
			if (!bstatic)
				g_propindex_d[client] = CreatePropPhysicsOverride(client, gs_dongs[scale-1], 200);
			else
				g_propindex_d[client] = CreatePropDynamicOverride(client, gs_dongs[scale-1], 200);

			SDKHook(g_propindex_d[client], SDKHook_Touch, OnTouchEntityRemove);
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
		}
		case 5:
		{
			if (!bstatic)
				g_propindex_d[client] = CreatePropPhysicsOverride(client, gs_dongs[scale-1], 250);
			else
				g_propindex_d[client] = CreatePropDynamicOverride(client, gs_dongs[scale-1], 250);

			SDKHook(g_propindex_d[client], SDKHook_Touch, OnTouchEntityRemove);
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
		}
		default:
		{
			//scale = 0 || scale > 5
		}
	}
}


public Action Command_Dong_Spawn(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return Plugin_Handled;
	}

	if (!GetConVarBool(g_cvar_props_enabled))
	{
		PrintToConsole(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		PrintToChat(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		return Plugin_Handled;
	}

	if (GetConVarInt( g_cvar_score_as_credits ) > 0)
	{
		if (g_RemainingCreds[client][SCORE_CRED] <= 0)
		{
			PrintToChat(client, "[] Your current score doesn't allow you to spawn props.");
			PrintToConsole(client, "[] Your current score doesn't allow you to spawn props.");
			return Plugin_Handled;
		}
	}
	if (g_RemainingCreds[client][VIRT_CRED] <= 0)
	{
		PrintToChat(client, "[] You don't have any remaining credits to spawn a prop.");
		PrintToConsole(client, "[] You don't have any remaining credits to spawn a prop.");
		return Plugin_Handled;
	}

	if ((GetCmdArgs() > 2) || (GetCmdArgs() == 0))
	{
		PrintToChat(client, "Usage: !dick [scale 1-5] [1 for static]");
		PrintToConsole(client, "Usage: sm_dick [scale 1-5] [1 for static]");
		PrintToChat(client, "Type: !props_credit_status see credits for everyone.");
		PrintToConsole(client, "Type sm_props_credit_status to see credits for everyone.");
		return Plugin_Handled;
	}

	new String:model_scale[2], String:model_property[2]; //FIXME maybe better way?
	GetCmdArg(1, model_scale, sizeof(model_scale));
	GetCmdArg(2, model_property, sizeof(model_property));

	//new iModelScale = trim_quotes(model_scale);  returns 0 ?
	int iModelScale = (strlen(model_scale) > 0) ? StringToInt(model_scale) : 1;
	if (iModelScale > 5)
		iModelScale = 5;
	int iModelProperty = (strlen(model_property) > 0) ? StringToInt(model_property) : 0;

	//PrintToConsole(client, "model_scale %s model_property %d iModelScale %d", model_scale, model_propertynum, num);

	if (hasEnoughCredits(client, g_DongPropPrice[iModelScale]))
	{
		DongDispatch(client, iModelScale, iModelProperty);
		PrintToChat(client, "[] You have just used %d credits.", g_DongPropPrice[iModelScale]);
		PrintToConsole(client, "[] You have just used %d credits.", g_DongPropPrice[iModelScale]);
		DecCredits(client, g_DongPropPrice[iModelScale], true);
		DisplayActivity(client, gs_dongs[iModelScale]);
		return Plugin_Handled;
	}
	else
	{
		PrintToChat(client, "[] You don't have enough credits to spawn a prop: credits needed: %d, credits remaining: %d.",
		g_DongPropPrice[iModelScale], g_RemainingCreds[client][VIRT_CRED]);
		PrintToConsole(client, "[] You don't have enough credits to spawn a prop: credits needed: %d, credits remaining: %d.",
		g_DongPropPrice[iModelScale], g_RemainingCreds[client][VIRT_CRED]);
		return Plugin_Handled;
	}
}

bool Should_Use_TE()
{
	for (int client=1; client <= MaxClients; client++)
	{
		if (g_prefs_nowantprops[client]) // at least one person doesn't want to see them
			return true;
	}
	return false;

}


DisplayActivity(int client, const char[] model)
{
	//ShowActivity2(client, "[sm_props] ", "%s spawned: %s.", client, model);
	LogAction(client, -1, "[sm_props] \"%L\" spawned: %s", client, model);

}


// sets the client as the entity's new parent and attach the entity to client
public MakeParent(int client, int entity)
{
	decl String:Buffer[64];
	Format(Buffer, sizeof(Buffer), "Client%d", client);

	DispatchKeyValue(client, "targetname", Buffer);

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", client);

	SetVariantString("grenade2");
	AcceptEntityInput(entity, "SetParentAttachment");
	SetVariantString("grenade2");
	AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset");

	new Float:origin[3];
	new Float:angle[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", angle);

	origin[0] += 0.0;
	origin[1] += 0.0;
	origin[2] += 0.0;

	angle[0] += 0.0;
	angle[1] += 3.0;
	angle[2] += 0.3;
	//DispatchKeyValueVector(entity, "Origin", origin);    //FIX testing offset coordinates, remove! -glub
	//DispatchKeyValueVector(entity, "Angles", angle);
	DispatchSpawn(entity); // might not be needed?
	//PrintToChat(client, "origin: %f %f %f; angles: %f %f %f", origin[0], origin[1], origin[2], angle[0], angle[1], angle[2]);

}


public void OnGhostPickUp(int client)
{
	if (GetConVarBool(g_cvar_props_onghostpickup))
	{
		if (!IsValidClient(client))
			return;

		if (!gb_hashadhisd[client])
		{
			gb_hashadhisd[client] = true;
			SpawnAndStrapDongToSelf(client);
		}
	}
}


public void OnGhostCapture(int client)
{
	if (GetConVarBool(g_cvar_props_oncapture))
	{
		FireWorksOnPlayer(client, GetRandomInt(0,0));
	}
}


FireWorksOnPlayer(int client, int type)
{
	if (!IsValidClient(client))
		return;

	switch(type)
	{
		case 0: //dongs
		{
			PropFireworks(client, gs_dongs[0], gs_TE_type[1], true);
		}
		case 1: //ducks
		{
			PropFireworks(client, gs_allowed_models[0], gs_TE_type[1], false);
		}
		case 2: //tigers
		{
			PropFireworks(client, gs_allowed_models[1], gs_TE_type[1], false);
		}
		case 3: //team logo
		{
			if (GetClientTeam(client) == 2)
				PropFireworks(client, gs_allowed_models[3], gs_TE_type[1], false);
			else // probably NSF
				PropFireworks(client, gs_allowed_models[2], gs_TE_type[1], false);
		}
	}
}



PropFireworks (int client, const char[] modelname, const char[] TE_type, bool shocking)
{
	if (!IsValidClient(client))
		return;

	int dongclients[MAXPLAYERS+1];
	int numClients;
	if (shocking)
		numClients = GetDongClients(dongclients, sizeof(dongclients));

	int cached_mdl = PrecacheModel(modelname, false);

	float origin[3];
	GetClientEyePosition(client, origin);
	// origin[0] += 1500.0;
	// origin[1] += 1500.0;
	// origin[2] += 1500.0;

	new String:TE_type[255] = "physicsprop";
	TE_Start(TE_type); //TE_type
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteNum("m_nModelIndex", cached_mdl);

	Set_TE_Props_By_Type(TE_type);

	if (shocking)
		TE_Send(dongclients, numClients, 0.0);
	else
		TE_SendToAll(0.0);
	PrintToConsole(client, "Spawned fireworks of %s at: %f %f %f for model %s index %d", TE_type, origin[0], origin[1], origin[2], modelname, cached_mdl);
}


void Set_TE_Props_By_Type(const char[] type)
{
	if (strcmp(type, gs_TE_type[0]) == 0) //physicsprops
	{

	}
	else if (strcmp(type, gs_TE_type[1]) == 0) //breakmodel
	{
		TE_WriteNum("m_nCount", 30);
		TE_WriteNum("m_nRandomization", 30);
		TE_WriteFloat("m_fTime", 10.0);
	}

}



// create arg1 and strap to ourself
public Action Command_Strap_Dong(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return Plugin_Handled;
	}

	new String:arg[10];
	GetCmdArg(1, arg, sizeof(arg));
	if (strcmp(arg, "me"))
	{
		SpawnAndStrapDongToSelf(client);
	}
	else if (strcmp(arg, "team"))
	{
		int team = GetClientTeam(client);
		for (client = 1; client <= MaxClients; client++)
		{
			if (!IsValidClient(client))
				continue;
			if (GetClientTeam(client) != team)
				continue;
			SpawnAndStrapDongToSelf(client);
		}
	}
	else if (strcmp(arg, "all"))
	{
		for (client = 1; client <= MaxClients; client++)
		{
			if (!IsValidClient(client))
				continue;
			SpawnAndStrapDongToSelf(client);
		}
	}
	return Plugin_Handled;
}


public void SpawnAndStrapDongToSelf(int client)
{
	new created = CreatePropDynamicOverride(client, gs_dongs[0], 5);
	MakeParent(client, created);
}





//==================================
//		Prop auto-removal
//==================================


public Action TimerKillEntity(Handle:timer, prop)
{
	KillEntity(prop);
	return Plugin_Handled;
}


public Action KillEntity(prop)
{
	if(IsValidEdict(prop))
	{
		AcceptEntityInput(prop, "kill");
	}
	return Plugin_Handled;
}


public Action OnTouchEntityRemove(int propindex, int client)
{
	if(client <= MaxClients && propindex > 0 && !IsFakeClient(client) && IsValidEntity(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsValidEdict(propindex))
	{
		AcceptEntityInput(propindex, "kill");
	}
	//return Plugin_Handled;
}


/*
public trim_quotes(String:text[])
{
	new startidx = 0
	if (text[0] == '"')
	{
		startidx = 1
		//Strip the ending quote, if there is one
		new len = strlen(text);
		if (text[len-1] == '"')
		{
			text[len-1] = '\0'
		}
	}
	return startidx
}
*/


//==================================
//		Temp Ents testing
//==================================

/*	CTEPhysicsProp (type DT_TEPhysicsProp)
		Table: baseclass (offset 0) (type DT_BaseTempEntity)
			Member: m_vecOrigin (offset 12) (type vector) (bits 0) (Coord)
			Member: m_angRotation[0] (offset 24) (type float) (bits 13) (VectorElem)
			Member: m_angRotation[1] (offset 28) (type float) (bits 13) (VectorElem)
			Member: m_angRotation[2] (offset 32) (type float) (bits 13) (VectorElem)
			Member: m_vecVelocity (offset 36) (type vector) (bits 0) (Coord)
			Member: m_nModelIndex (offset 48) (type integer) (bits 11) ()
			Member: m_nSkin (offset 52) (type integer) (bits 10) ()
			Member: m_nFlags (offset 56) (type integer) (bits 2) (Unsigned)
			Member: m_nEffects (offset 60) (type integer) (bits 10) (Unsigned)
 */

// Passes client array by ref, and returns num. of clients inserted in the array.- Rainyan
int GetDongClients(int outClients[MAXPLAYERS+1], int arraySize)
{
	int index = 0;

	for (int thisClient = 1; thisClient <= MaxClients; thisClient++)
	{
		// Reached the max size of array
		if (index == arraySize)
			break;

		if (IsValidClient(thisClient) && WantsDong(thisClient))
		{
			outClients[index++] = thisClient;
		}
	}

	return index;
}


public Action Spawn_TE_Prop(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return Plugin_Handled;
	}

	new String:s_tetype[PLATFORM_MAX_PATH], String:s_modelname[PLATFORM_MAX_PATH];
	s_tetype = gs_TE_type[0]; // or physicsprop or breakmodel
	GetCmdArg(1, s_modelname, sizeof(s_modelname));

	int dongclients[MAXPLAYERS+1];
	int numClients = GetDongClients(dongclients, sizeof(dongclients));
	int cached_mdl = PrecacheModel(s_modelname, false);

	float origin[3];
	GetClientEyePosition(client, origin);

	TE_Start(s_tetype);
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteNum("m_nModelIndex", cached_mdl);
	TE_Send(dongclients, numClients, 0.0);
	//PrintToConsole(client, "Spawned at: %f %f %f for model index: %d", origin[0], origin[1], origin[2], cached_mdl);
	return Plugin_Handled;
}


public Action Spawn_TE_Dong(int client, const char[] modelname, const char[] TE_type)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return Plugin_Handled;
	}

	int dongclients[MAXPLAYERS+1];
	int numClients = GetDongClients(dongclients, sizeof(dongclients));
	int cached_mdl = PrecacheModel(modelname, false);

	float origin[3];
	GetClientEyePosition(client, origin);

	TE_Start(TE_type);
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteNum("m_nModelIndex", cached_mdl);
	TE_Send(dongclients, numClients, 0.0);
	//PrintToConsole(client, "Spawned at: %f %f %f for model index: %d", origin[0], origin[1], origin[2], cached_mdl);
	return Plugin_Handled;
}

bool WantsDong(int client)
{
	if (IsValidClient(client) && !g_prefs_nowantprops[client])
		return true;
	return false;
}


//==================================
//			Client UTILS
//==================================

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

bool IsAdmin(int client) // thanks rain
{
	if (!IsValidClient(client) || !IsClientAuthorized(client))
	{
		LogError("IsAdmin: Client %i is not valid. This shouldn't happen.", client);
		return false;
	}
	AdminId adminId = GetUserAdmin(client);
	if (adminId == INVALID_ADMIN_ID)
	{
		return false;
	}
	return GetAdminFlag(adminId, Admin_Generic);
}


// from neotokyo.inc thanks Soft as Hell
UpdatePlayerRankXP(int client, int xp)
{
	new rank = 0; // Rankless dog

	if(xp >= 0 && xp <= 3)
		rank = 1; // Private
	else if(xp >= 4 && xp <= 9)
		rank = 2; // Corporal
	else if(xp >= 10 && xp <= 19)
		rank = 3; // Sergeant
	else if(xp >= 20)
		rank = 4; // Lieutenant

	SetEntProp(client, Prop_Send, "m_iRank", rank);
}
