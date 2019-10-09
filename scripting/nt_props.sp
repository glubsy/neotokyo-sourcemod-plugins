#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <nt_entitytools>
// #include <smlib> //for entity flags

#pragma semicolon 1
#define PLUGIN_VERSION "20191009"

Handle g_cvar_props_enabled, g_cvar_restrict_alive, g_cvar_give_initial_credits, g_cvar_credits_replenish, g_cvar_score_as_credits= INVALID_HANDLE;
Handle cvMaxPropsCreds = INVALID_HANDLE; // maximum credits given
Handle cvPropMaxTTL = INVALID_HANDLE; // maximum time to live before prop gets auto removed
Handle g_PropPrefCookie = INVALID_HANDLE; // handle to client preferences
Handle g_cvar_props_oncapture, g_cvar_props_onghostpickup, g_cvar_props_oncapture_nodongs, gTimer = INVALID_HANDLE;
bool gb_PausePropSpawning;
int g_AttachmentEnt[MAXPLAYERS+1] = {-1,...}; // strapped on prop

// [0] holds virtual credits, [2] current score credits, [3] maximum credits level reached
new g_RemainingCreds[MAXPLAYERS+1][3];
#define VIRT_CRED 0
#define SCORE_CRED 1
#define MAX_CRED 2

new g_propindex_d[MAXPLAYERS+1]; // holds the last spawned entity by client
new g_optedout[MAXPLAYERS+1];

// WARNING: the custom files require the sm_downloader plugin to force clients to download them
// otherwise, have to add all custom files to downloads table ourselves with AddFileToDownloadsTable()
new const String:gs_dongs[][] = {
	"models/d/d_s02.mdl", //small
	"models/d/d_b02.mdl", //big
	"models/d/d_h02.mdl", //huge
	"models/d/d_g02.mdl", //gigantic
	"models/d/d_mh02.mdl" }; //megahuge

new const g_DongPropPrice[] = { 1, 6, 9, 13, 20 };

new const String:gs_allowed_physics_models[][] = {
	"models/nt/a_lil_tiger.mdl",
	"models/nt/props_office/rubber_duck.mdl",
	"models/logo/jinrai_logo.mdl",
	"models/logo/nsf_logo.mdl", //physics version
	"models/nt/props_street/rabbit_doll.mdl",
	"models/nt/props_street/bass_guitar.mdl",
	"models/nt/props_street/skateboard.mdl",
	"models/nt/props_building/hanging_fish_sign.mdl",
	"models/nt/props_office/spraybottle.mdl",
	"models/nt/props_office/spraycan.mdl",
	"models/nt/props_office/broom.mdl",
	"models/nt/props_nature/crab.mdl",
	"models/nt/props_debris/can01.mdl",
	"models/nt/props_debris/can_crushed01.mdl",
	"models/nt/props_tech/not_the_ghost.mdl",
	"models/nt/props_tech/girlbot_body.mdl",
	"models/nt/props_tech/robobody.mdl",
	"models/nt/props_tech/girlbot_head.mdl",
	"models/nt/props_tech/girlbot_body.mdl",
	"models/nt/props_warehouse/tire.mdl"
};



new const String:gs_allowed_dynamic_models[][] = {
	"models/nt/a_lil_tiger.mdl",
	"models/nt/props_office/rubber_duck.mdl",
	"models/logo/jinrai_logo.mdl",
	"models/logo/nsf_logo.mdl",
	"models/nt/props_nature/koi_fisha.mdl"
};

new const String:gs_PropType[][] = {  // should be an enum?
		"physicsprop", // TempEnt
		"breakmodel",  //TempEnt
		"prop_physics_override",
		"prop_dynamic_override" };

enum FireworksPropType {
	TE_PHYSICS = 0,
	TE_BREAKMODEL,
	REGULAR_PHYSICS,
};

#define DEBUG 1

public Plugin:myinfo =
{
	name = "NEOTOKYO props spawner.",
	author = "glub",
	description = "Allows players to spawn props.",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
};

// TODO:
// → rework logic for credits, might be broken
// → spawn props with random coords around a target (player) and velocity, towards their position
// → make menu to spawn props
// → add sparks to props spawned and maybe a squishy sound for in range with TE_SendToAllInRange
// → save credits in sqlite db for longer term?
// → figure out how to make attached props changed their material to cloak
// → use ProcessTargetString to target a player by name
//
// KNOWN ISSUES:
// -> AFAIK the TE cannot be destroyed by timer, so client preference is very limited, ie. if someone asks for a big scale model that is supposed to be auto-removed
//    we can't use a TE because they don't get affected by timers, so regular physics_prop take precedence. Same for dynamic props, cannot have them as TempEnts.
//
// FIXME: debug why player are not spawning TE when opted-out clients are around
// FIXME: use SDKHook_SetTransmit instead of TE for filtering props

public OnPluginStart()
{
	RegAdminCmd("sm_props_set_credits", Command_Set_Credits_For_Client, ADMFLAG_SLAY, "Gives target player virtual credits in order to spawn props.");
	RegConsoleCmd("sm_props_credit_status", Command_Credit_Status, "List all player credits to spawn props.");

	RegConsoleCmd("sm_dick", Command_Dong_Spawn, "Spawns a dick [scale 1-5] [1 for static prop]");
	RegConsoleCmd("sm_props", CommandPropSpawn, "Spawns a prop.");
	RegConsoleCmd("sm_props_help", Command_Print_Help, "Prints all props-related commands.");
	RegConsoleCmd("sm_strapdong", Command_Strap_Dong, "Strap a dong onto [me|team|all].");

	g_cvar_props_onghostpickup = CreateConVar("sm_props_onghostpickup", "0", "Picking up the ghost is exciting,", FCVAR_NONE, true, 0.0, true, 1.0 );
	g_cvar_props_oncapture = CreateConVar("sm_props_oncapture", "0", "Fireworks on ghost capture.", FCVAR_NONE, true, 0.0, true, 1.0 );
	g_cvar_props_oncapture_nodongs = CreateConVar("sm_props_oncapture_nodongs", "1", "No dong firework on capture.", FCVAR_NONE, true, 0.0, true, 1.0 );


	g_cvar_props_enabled = CreateConVar( "sm_props_enabled", "1",
										"0: disable custom props spawning, 1: enable custom props spawning",
										FCVAR_NONE, true, 0.0, true, 1.0 );

	g_cvar_restrict_alive = CreateConVar( "sm_props_restrict_alive", "0",
										"0: spectators can spawn props too. 1: only living players can spawn props",
										FCVAR_NONE, true, 0.0, true, 1.0 );

	g_cvar_give_initial_credits = CreateConVar( "sm_props_initial_credits", "0",
												"0: players starts with zero credits 1: assign sm_max_props_credits to all players as soon as they connect",
												FCVAR_NONE, true, 0.0, true, 1.0 );
	cvMaxPropsCreds = CreateConVar("sm_props_max_credits", "10",
									"Max number of virtual credits allowed per round/life for spawning props");
	cvPropMaxTTL = CreateConVar("sm_props_max_ttl", "60",
								"Maximum time to live for spawned props in seconds.");

	g_cvar_credits_replenish = CreateConVar( "sm_props_replenish_credits", "1",
											"0: credits are lost forever after use. 1: credits replenish after each end of round",
											FCVAR_NONE, true, 0.0, true, 1.0 );
	g_cvar_score_as_credits = CreateConVar( "sm_props_score_as_credits", "0",
											"0: use virtual props credits only, 1: use score as props credits on top of virtual props credits",
											FCVAR_NONE, true, 0.0, true, 1.0 );

	RegConsoleCmd("sm_props_nothx", Command_Hate_Props_Toggle, "Toggle your preference to not see custom props wherever possible.");
	g_PropPrefCookie = RegClientCookie("no-props-plz", "player doesn't like custom props", CookieAccess_Public);

	RegConsoleCmd("sm_props_pause", Command_Pause_Props_Spawning, "Prevent any further custom prop spawning until end of round.");

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	// AddCommandListener(OnSpecCmd, "spec_next"); // probably not needed
	// AddCommandListener(OnSpecCmd, "spec_prev"); // probably not needed
	AddCommandListener(OnSpecCmd, "spec_mode");
	HookEvent("game_round_start", event_RoundStart);

	RegAdminCmd("sm_props_givescore", Command_Give_Score, ADMFLAG_SLAY, "DEBUG: add 20 frags to score");
	RegAdminCmd("sm_props_te", Command_Spawn_TE_Prop, ADMFLAG_SLAY, "DEBUG: Spawn TE dong");
	RegAdminCmd("sm_props_fireworks", Command_Spawn_TEST_fireworks, ADMFLAG_SLAY, "DEBUG: test fireworks");

	AutoExecConfig(true, "sm_nt_props");
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
		//g_optedout[client] = false;
		return;
	}

	if (AreClientCookiesCached(client))
	{
		ProcessCookies(client);
		//CreateTimer(120.0, DisplayNotification, client);
		return;
	}
}


public Action timer_AdvertiseHelp(Handle timer, int client)
{
	if (!IsValidClient(client))
		return;
	PrintToChat(client, "[sm_props] You can print available commands with !props_help");
}


public OnClientDisconnect(int client)
{
	//if(GetConVarBool(g_cvar_props_enabled)) // not worth checking
		g_optedout[client] = false;
}


public OnMapEnd()
{
	CloseHandle(gTimer);
}


ProcessCookies(int client)
{
	if (!IsValidClient(client))
		return;

	if(!FindClientCookie("no-props-plz"))
	{
		g_optedout[client] = false;
		CreateTimer(10.0, DisplayNotification, client);
		return;
	}

	char cookie[10];
	GetClientCookie(client, g_PropPrefCookie, cookie, sizeof(cookie));

	if (StrEqual(cookie, "penabled"))
	{
		g_optedout[client] = false;
		return;
	}
	else if (StrEqual(cookie, "pdisabled"))
	{
		g_optedout[client] = true;
		return;
	}
	return;
}


public Action DisplayNotification(Handle timer, int client)
{
	if(client > 0 && IsClientConnected(client) && IsClientInGame(client))
	{
		if(!g_optedout[client])
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
		g_optedout[client] = true;
		SetClientCookie(client, g_PropPrefCookie, "pdisabled");
		ReplyToCommand(client, "Your preference has been recorded. You do like props after all.");
		#if DEBUG
		PrintToConsole(client, "Cookie not found?");
		#endif
		return Plugin_Handled;
	}

	new String:cookie[10];
	GetClientCookie(client, g_PropPrefCookie, cookie, sizeof(cookie));

	if (StrEqual(cookie, "pdisabled"))
	{
		SetClientCookie(client, g_PropPrefCookie, "penabled");
		g_optedout[client] = false;
		ReplyToCommand(client, "Your preference has been recorded. You do like props after all.");
		return Plugin_Handled;
	}
	else // was enabled, or not yet set
	{
		SetClientCookie(client, g_PropPrefCookie, "pdisabled");
		g_optedout[client] = true;
		ReplyToCommand(client, "Your preference has been recorded. You no like props.");
		ShowActivity2(client, "[sm_props] ", "%N opted out of sm_props models.", client);
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

public Action Command_Give_Score (int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "This command cannot be executed by the server.");
		return Plugin_Stop;
	}
	if (GetCmdArgs() == 1)
	{
		char arg[10];
		GetCmdArg(1, arg, sizeof(arg));
		int i_target = GetClientOfUserId(StringToInt(arg));
		if (!IsValidClient(i_target))
		{
			ReplyToCommand(client, "Invalid target: %d", i_target);
			return Plugin_Handled;
		}
		SetEntProp(i_target, Prop_Data, "m_iFrags", 60);
		g_RemainingCreds[i_target][SCORE_CRED] = 60;
		g_RemainingCreds[i_target][VIRT_CRED] = 60;
		g_RemainingCreds[i_target][MAX_CRED] = 60;
		Command_Set_Credits_For_Client(i_target, 60);
		PrintToConsole(client, "[sm_props] DEBUG: %N gave score of 60 to %N.", client, i_target);

		return Plugin_Handled;
	}

	SetEntProp(client, Prop_Data, "m_iFrags", 60);
	g_RemainingCreds[client][SCORE_CRED] = 60;
	g_RemainingCreds[client][VIRT_CRED] = 60;
	g_RemainingCreds[client][MAX_CRED] = 60;
	Command_Set_Credits_For_Client(client, 60);
	PrintToServer("[sm_props] DEBUG: %N gave score of 60 to himself.", client);
	ReplyToCommand(client, "[sm_props] DEBUG: You gave score of 60 to yourself.");
	return Plugin_Handled;

}


public Action Command_Credit_Status(int client, int args)
{
	char name[MAX_NAME_LENGTH];
	PrintToConsole(client, "\n--------- Current props spawning brouzoufs status ---------");
	for (int i=1; i <= MaxClients; i++)
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


public OnClientPutInServer(int client)
{
	if(client && !IsFakeClient(client))
	{
		CreateTimer(60.0, timer_AdvertiseHelp, client);

		// if we use score as credit, restore them
		if ( GetConVarBool(g_cvar_score_as_credits) )
			g_RemainingCreds[client][SCORE_CRED] = GetClientFrags(client); //NEEDS TESTING!
		if ( GetConVarBool(g_cvar_give_initial_credits) )
			g_RemainingCreds[client][VIRT_CRED] = g_RemainingCreds[client][MAX_CRED] = GetConVarInt(cvMaxPropsCreds);
		else
			g_RemainingCreds[client][MAX_CRED] = g_RemainingCreds[client][VIRT_CRED] = 0;
	}
}


public OnSavedScoreLoaded(int client, int score)
{
	if(client && !IsFakeClient(client))
	{
		#if DEBUG
		PrintToServer("[sm_props] DEBUG: updating score of %d for player %N", score, client);
		#endif
		// if we use score as credit, restore them
		if ( GetConVarBool(g_cvar_score_as_credits) )
			g_RemainingCreds[client][SCORE_CRED] = score; //NEEDS TESTING!
		if ( GetConVarBool(g_cvar_give_initial_credits) )
			g_RemainingCreds[client][VIRT_CRED] = g_RemainingCreds[client][MAX_CRED] = GetConVarInt(cvMaxPropsCreds);
		else
			g_RemainingCreds[client][MAX_CRED] = g_RemainingCreds[client][VIRT_CRED] = 0;
	}
}


public Action OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	// reinitialize the virtual credits to constant value
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if ( GetConVarBool(g_cvar_credits_replenish) )
		g_RemainingCreds[client][VIRT_CRED] = GetConVarInt(cvMaxPropsCreds);
	else
		g_RemainingCreds[client][VIRT_CRED] = g_RemainingCreds[client][MAX_CRED];
	//return Plugin_Continue;
}


public void event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	for(int client = 1; client <= MaxClients; client++)
	{
		g_AttachmentEnt[client] = -1; // we assume attached prop has been removed by the game

		if(!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client))
			continue;

		if ( GetConVarBool(g_cvar_credits_replenish) )
			g_RemainingCreds[client][VIRT_CRED] = GetConVarInt(cvMaxPropsCreds);
		else
			g_RemainingCreds[client][VIRT_CRED] = g_RemainingCreds[client][MAX_CRED];
	}

	gb_PausePropSpawning = false;
}


public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	// attempt to remove entities that were attached to victim if any
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	DestroyAttachedPropForClient(victim);

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



public Action OnSpecCmd(int client, const char[] command, int args)
{
	if(!IsValidClient(client))
		return Plugin_Continue;

	int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

	if(target <= 0)
		return Plugin_Continue;

	// destroy floating entity, prevents annoying (alive) observed players
	DestroyAttachedPropForClient(client);

	return Plugin_Continue;
}


void DestroyAttachedPropForClient(int client)
{
	#if DEBUG
	PrintToServer("Checking if need to remove strapped entity %d on client %d.", g_AttachmentEnt[client], client);
	#endif
	if (g_AttachmentEnt[client] != -1 && IsValidEntity(g_AttachmentEnt[client]))
	{
		#if DEBUG
		PrintToServer("Killing strapped entity %d of client %d.", g_AttachmentEnt[client], client);
		#endif
		AcceptEntityInput(g_AttachmentEnt[client], "ClearParent");
		AcceptEntityInput(g_AttachmentEnt[client], "kill");
		g_AttachmentEnt[client] = -1;
	}
}

void UpdateAttachedPropArray(int entity)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsValidClient(client))
			continue;

		if (entity == g_AttachmentEnt[client])
		{
			#if DEBUG
			PrintToServer("Strapped entity %d for client %d was destroyed, updated array.", entity, client);
			#endif
			g_AttachmentEnt[client] = -1;
			break;
		}
	}

}


public void OnEntityDestroyed(int entity)
{
	// when strapped entity is destroyed, make sure our array is updated as well
	UpdateAttachedPropArray(entity);
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


void Decrease_Credits_For_Client(int client, int amount, bool relaytoclient)
{
	g_RemainingCreds[client][VIRT_CRED] -= amount;
	if (relaytoclient)
	{
		PrintToChat(client, "[] brouzoufs remaining: %d.", g_RemainingCreds[client][VIRT_CRED]);
		PrintToConsole(client, "[] brouzoufs remaining: %d.", g_RemainingCreds[client][VIRT_CRED]);
	}
}


void Decrease_Score_For_Client(int client, int amount, bool relaytoclient)
{
	if ( GetConVarInt( g_cvar_score_as_credits ) > 0 )
	{
		DecrementScore(client, 1);
		g_RemainingCreds[client][SCORE_CRED] -= amount;

		if (relaytoclient)
		{
			PrintToChat(client, "[] WARNING: Your score has been decreased by 1 point for using that command!");
		}
	}
}


void SetCredits(int client, int amount)
{
	g_RemainingCreds[client][VIRT_CRED] = amount;

	if (g_RemainingCreds[client][VIRT_CRED] > g_RemainingCreds[client][MAX_CRED])
		g_RemainingCreds[client][MAX_CRED] = amount;
}


void DecrementScore(int client, int amount)
{
	new new_xp = GetClientFrags(client) - amount;
	SetEntProp(client, Prop_Data, "m_iFrags", new_xp);
	UpdatePlayerRankXP(client, new_xp);
}


void Client_Used_Credits(int client, int credits)
{
	PrintToChat(client, "[] You have just used %d brouzoufs.", credits);
	PrintToConsole(client, "[] You have just used %d brouzoufs.", credits);
	Decrease_Credits_For_Client(client, credits, true);
	Decrease_Score_For_Client(client, 1, true);
}


void DisplayActivity(int client, const char[] model)
{
	//ShowActivity2(client, "[sm_props] ", "%s spawned: %s.", client, model);
	LogAction(client, -1, "[sm_props] \"%L\" spawned: %s", client, model);
}




// increment (virtual) credits for target client
public Action Command_Set_Credits_For_Client(int client, int args)
{
	if(!client || IsFakeClient(client) || !IsAdmin(client))
		return Plugin_Stop;

	if (GetCmdArgs() != 2)
	{
		PrintToChat(client, "Usage: !props_set_credit #id amount (use \"status\" in console).");
		PrintToConsole(client, "Usage: sm_props_set_credit #id amount (use \"status\" in console).");
		return Plugin_Handled;
	}

	char s_amount[5];
	char s_target[3];
	char s_targetname[MAX_NAME_LENGTH];
	int i_target;
	GetCmdArg(1, s_target, sizeof(s_target));
	GetCmdArg(2, s_amount, sizeof(s_amount));

	//PrintToConsole(client, "[DEBUG] target: %s amount: %s", s_target, s_amount);
	i_target = GetClientOfUserId( StringToInt(s_target) );
	//PrintToConsole(client, "[DEBUG] itarget: %i amount: %d", i_target, StringToInt(s_amount));

	SetCredits(i_target, StringToInt(s_amount));

	PrintToChat(i_target, "[sm_props] Your brouzoufs have been set to %d.", g_RemainingCreds[i_target][VIRT_CRED]);
	PrintToConsole(i_target, "[sm_props] Your brouzoufs have been set to %d.", g_RemainingCreds[i_target][VIRT_CRED]);

	if (GetClientName(i_target, s_targetname, sizeof(s_targetname)) && client != i_target)
	{
		ReplyToCommand(client, "[sm_props] The credits for player %s are now set to %d.", s_targetname, g_RemainingCreds[i_target][VIRT_CRED]);
	}
	return Plugin_Handled;
}


//==================================
//		Prop Spawning
//==================================


Prop_Dispatch_Allowed_Model_Index(int client, int model_index)
{
	g_propindex_d[client] = CreatePropPhysicsOverride_AtClientPos(client, gs_allowed_physics_models[model_index], 50);
}


Prop_Spawn_Dispatch_Admin(int client, const char[] argstring)
{
	// process args
	char buffers[10][255];
	ExplodeString(argstring, " ", buffers, 4, 255);
	char model_path[PLATFORM_MAX_PATH];
	char renderfx[30];
	char movetype[30];
	char ignite[7];
	strcopy(model_path, sizeof(model_path), buffers[0]);
	strcopy(renderfx, sizeof(renderfx), buffers[1]);
	strcopy(movetype, sizeof(movetype), buffers[2]);
	strcopy(ignite, sizeof(ignite), buffers[3]);
	ReplyToCommand(client, "args: modelpath: %s, renderfx: %s, movetype %s, ignite: %s", model_path, renderfx, movetype, ignite);
	//FIXME: unfinished business, check strings, use enums accordingly


	g_propindex_d[client] = CreatePropPhysicsOverride_AtClientPos(client, model_path, 50);

	// FIXME: find a way to make bullets go through physic_props
	if (strcmp(model_path, gs_allowed_physics_models[2]) == 0 || strcmp(model_path, gs_allowed_physics_models[3]) == 0)
	{
		#if DEBUG
		PrintToConsole(client, "Called CreatePhysicsOverride_AtclientPos for admin");
		#endif

		SetEntityRenderFx(g_propindex_d[client], RENDERFX_DISTORT); // works, only good for team logos
		AcceptEntityInput(g_propindex_d[client], "DisableShadow"); // works
		// SetEntProp(g_propindex_d[client], Prop_Send, "m_usSolidFlags", 136);
		// SetEntProp(g_propindex_d[client], Prop_Send, "m_CollisionGroup", 13);
		// SetEntProp(g_propindex_d[client], Prop_Send, "m_nSolidType", 0);
		DispatchSpawn(g_propindex_d[client]); 		// without this line, prop will stay in place and not move, but will still block bullets
		ActivateEntity(g_propindex_d[client]);
	}
	else
	{
		#if DEBUG
		char clsname[255];
		int r,g,b,a, rendm, rendfx;
		float gravity;

		#if SPVER > 17
		GetEntityClassname(g_propindex_d[client], clsname, sizeof(clsname));
		GetEntityRenderColor(g_propindex_d[client], r, g, b, a);
		rendfx = view_as<int>(GetEntityRenderFx(g_propindex_d[client]));
		rendm = view_as<int>(GetEntityRenderMode(g_propindex_d[client]));
		gravity = GetEntityGravity(g_propindex_d[client]);
		PrintToConsole(client, "Rendered before: %s with colors: %d,%d,%d,%d rendermode %d fx %d gravity %f", clsname, r,g,b,a, rendm, rendfx, gravity );
		#endif
		#endif

		// SetEntityRenderMode(g_propindex_d[client], RENDER_NORMAL);
		// SetEntityRenderColor(g_propindex_d[client], 255, 0, 0, 123); // works only on models supporting that, good for making ghosts (alpha)
		SetEntityRenderFx(g_propindex_d[client], RENDERFX_DISTORT); // works, only good for team logos

		// SetEntityMoveType(g_propindex_d[client], MOVETYPE_OBSERVER);
		// SetEntityMoveType(g_propindex_d[client], MOVETYPE_NOCLIP);
		// SetEntityMoveType(g_propindex_d[client], MOVETYPE_PUSH);

		// SetEntityGravity(g_propindex_d[client], 0.1); // doesn't seem to work
		// DispatchKeyValue(g_propindex_d[client], "Gravity", "0.1"); // doesn't work
		// DispatchKeyValue(g_propindex_d[client], "Color", "0 255 0"); // doesn't work

		AcceptEntityInput(g_propindex_d[client], "DisableShadow"); // works
		// AcceptEntityInput(g_propindex_d[client], "Ignite"); // works

		DispatchSpawn(g_propindex_d[client]); 		// without this lines, prop will stay in place and not move, but will block bullets
		ActivateEntity(g_propindex_d[client]);

		#if DEBUG
		rendfx = view_as<int>(GetEntityRenderFx(g_propindex_d[client]));
		rendm = view_as<int>(GetEntityRenderMode(g_propindex_d[client]));
		gravity = GetEntityGravity(g_propindex_d[client]);

		#if SPVER > 17
		GetEntityRenderColor(g_propindex_d[client], r, g, b, a);
		#endif
		PrintToConsole(client, "Rendered after: %s with colors: %d,%d,%d,%d rendermode %d, fx %d gravity %f", clsname, r,g,b,a, rendm, rendfx, gravity);
		#endif
	}
}


Print_Usage_For_Admins(int client)
{
	PrintToChat(client, "[sm_props] Admin, check console for useful commands and convars...");
	PrintToConsole(client, "[sm_props] Admins, some useful commands:");
	PrintToConsole(client, "\nsm_props_set_credits: sets credits for a clientID\nsm_props_credit_status: check credit status for all\nsm_props_restrict_alive: restrict to living players\nsm_props_initial_credits: initial amount given on player connection\nsm_props_max_credits: credits given on initial connection\nsm_props_replenish_credits: whether credits are replenished between rounds\nsm_props_score_as_credits: whether score should be counter as credits.\nsm_props_max_ttl: props get deleted after that time.\nsm_props_enabled: disable the command.");
	PrintToConsole(client, "You may also do sm_props \"model_path\" \"renderfx\" \"movetype\" \"ignite\"");
}


Print_Usage_For_Client(int client, int type=1)
{
	if (type == 1)
	{
		PrintToConsole(client, "Usage: sm_props [model|model path]\nAvailable models currently: duck, tiger");
		PrintToChat(client, "Usage: !props [model | model path]\nAvailable models currently: duck, tiger");
	}
	else //TODO write all commands
	{
		PrintToChat(client, "[sm_props] check console for commands.");
		PrintToConsole(client, "[sm_props] Some \"useful\" commands:");
		PrintToConsole(client, "\nsm_props_nothx: disables props for you and everyone in the server.\n\
sm_strapdong [me|team|all] [specs]: straps a dong on people (including spectators)\n\
sm_props [model|model path]: spawns a model in the game\n\
sm_dick [1-5] [1 for static]: spawns a dong of scale 1 to 5 with optional static properties\n\
sm_props_credit_status: check credits of other players and yourself\n\
sm_props_pause: stops anyone from spawning props until the end of the current round\n");
		ClientCommand(client, "toggleconsole");
	}
}


public Action Command_Print_Help(int client, int args)
{
	Print_Usage_For_Client(client, 2);
}


// wall of shame (not a very good idea)
void Display_Why_Command_Is_Disabled(int client)
{
	ReplyToCommand(client, "Sorry, at least one player requested this command be disabled temporarily.");

	char buffer[255], name[MAX_NAME_LENGTH];

	for (int i=1, count=0; i <= MaxClients; i++)
	{
		if (g_optedout[i])
		{
			GetClientName(i, name, sizeof(name));
			if (count == 0)
			{
				Format(name, sizeof(name), "%s", name);
				count++;
			}
			else
			{
				Format(name, sizeof(name), ", %s", name);
			}
			StrCat(buffer, sizeof(buffer), name);
			#if DEBUG
			PrintToServer("DEBUG: buffer \"%s\"\nname \"%s\"", buffer, name);
			#endif
		}
	}

	PrintToChatAll("Sorry, these players asked not to be annoyed by props: %s.", buffer);
}


public Action CommandPropSpawn(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	// if (HasAnyoneOptedOut())
	// {
	// 	Display_Why_Command_Is_Disabled(client);
	// 	return Plugin_Handled;
	// }

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
			Print_Usage_For_Admins(client);
		}
		return Plugin_Handled;
	}

	if( GetCmdArgs() != 1 )
	{
		Print_Usage_For_Client(client, 1);
		PrintToChat(client, "You currently have %d brouzoufs to spawn props.", g_RemainingCreds[client][VIRT_CRED]);
		PrintToConsole(client, "You currently have %d brouzoufs to spawn props.", g_RemainingCreds[client][VIRT_CRED]);

		if (IsAdmin(client))
		{
			Print_Usage_For_Admins(client);
			decl String:s_args[PLATFORM_MAX_PATH];
			//FIXME: bypass credit system for DEBUGGING ONLY
			GetCmdArgString(s_args, sizeof(s_args));
			Prop_Spawn_Dispatch_Admin(client, s_args);
			return Plugin_Handled;
		}

		return Plugin_Handled;
	}

	if (!GetConVarBool(g_cvar_props_enabled))
	{
		PrintToConsole(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		PrintToChat(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		return Plugin_Handled;
	}

	decl String:model_pathname[PLATFORM_MAX_PATH];
	GetCmdArg(1, model_pathname, sizeof(model_pathname));

	for (int index=0; index < sizeof(gs_allowed_physics_models); ++index)
	{
		//TODO: check the path
		//TODO: make selection menu // Don't stop at first match
		//if (strcmp(model_pathname, gs_allowed_physics_models[i]) == 0)
		if (StrContains(gs_allowed_physics_models[index], model_pathname, false) != -1)
		{
			if (hasEnoughCredits(client, 5)) 								//FIXME: for now everything costs 5!
			{
				#if DEBUG
				PrintToConsole(client, "Spawned: %s.", gs_allowed_physics_models[index]);
				PrintToChat(client, "Spawning your %s.", model_pathname);
				#endif

				Prop_Dispatch_Allowed_Model_Index(client, index);

				Client_Used_Credits(client, 5);
				DisplayActivity(client, gs_allowed_physics_models[index]);
				return Plugin_Handled;
			}
			else
			{
				PrintToChat(client, "[sm_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
				5, g_RemainingCreds[client][VIRT_CRED]);
				PrintToConsole(client, "[sm_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
				5, g_RemainingCreds[client][VIRT_CRED]);
				return Plugin_Handled;
			}
		}
	}
	PrintToConsole(client, "Did not find requested model \"%s\" among allowed models.", model_pathname);
	PrintToChat(client, "Did not find requested model \"%s\" among allowed models.", model_pathname);
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
		case 0:
		{
			if (!bstatic)
				g_propindex_d[client] = CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 50);
				//Spawn_TE_Dong(client, gs_dongs[scale], gs_PropType[TE_PHYSICS]); // use TempEnts to avoid showing to people who don't like it
			else
				g_propindex_d[client] = CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 50);
		}
		case 1:
		{
			if (!bstatic)
			{
				g_propindex_d[client] = CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 120);
				CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
			}
			else
			{
				g_propindex_d[client] = CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 120);
				CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
			}
		}
		case 2:
		{
			if (!bstatic)
				g_propindex_d[client] = CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 180);
			else
				g_propindex_d[client] = CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 180);

			// remove the prop when it's touched by a player
			SDKHook(g_propindex_d[client], SDKHook_Touch, OnTouchEntityRemove); //FIXME
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
		}
		case 3:
		{
			if (!bstatic)
				g_propindex_d[client] = CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 200);
			else
				g_propindex_d[client] = CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 200);

			SDKHook(g_propindex_d[client], SDKHook_Touch, OnTouchEntityRemove);
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
		}
		case 4:
		{
			if (!bstatic)
				g_propindex_d[client] = CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 250);
			else
				g_propindex_d[client] = CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 250);

			SDKHook(g_propindex_d[client], SDKHook_Touch, OnTouchEntityRemove);
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
		}
		default:
		{
			//scale = 0 || scale > 5
		}
	}
	if (Has_Anyone_Opted_Out())
		SDKHook(g_propindex_d[client], SDKHook_SetTransmit, Hide_SetTransmit);
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
	else if (!GetConVarBool(g_cvar_props_enabled))
	{
		PrintToConsole(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		PrintToChat(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		return Plugin_Handled;
	}

	if (GetConVarInt( g_cvar_score_as_credits ) > 0)
	{
		if (g_RemainingCreds[client][SCORE_CRED] <= 0)
		{
			PrintToChat(client, "[sm_props] Your current score doesn't allow you to spawn props.");
			PrintToConsole(client, "[sm_props] Your current score doesn't allow you to spawn props.");
			return Plugin_Handled;
		}
	}
	if (g_RemainingCreds[client][VIRT_CRED] <= 0)
	{
		PrintToChat(client, "[sm_props] You don't have any remaining brouzoufs to spawn a prop.");
		PrintToConsole(client, "[sm_props] You don't have any remaining brouzoufs to spawn a prop.");
		return Plugin_Handled;
	}

	if ((GetCmdArgs() > 2) || (GetCmdArgs() == 0))
	{
		PrintToChat(client, "[sm_props] Usage: !dick [scale 1-5] [1 for static]");
		PrintToConsole(client, "[sm_props] Usage: sm_dick [scale 1-5] [1 for static]");
		PrintToChat(client, "[sm_props] Type: !props_credit_status see brouzoufs for everyone.");
		PrintToConsole(client, "[sm_props] Type sm_props_credit_status to see brouzoufs for everyone.");
		return Plugin_Handled;
	}

	new String:model_scale[2], String:model_property[2]; //FIXME maybe better way?
	GetCmdArg(1, model_scale, sizeof(model_scale));
	GetCmdArg(2, model_property, sizeof(model_property));

	int iModelScale = (strlen(model_scale) > 0) ? StringToInt(model_scale) : 1;
	if (iModelScale > 5)
		iModelScale = 4;
	else if (iModelScale <= 0)
		iModelScale = 0;
	else
		iModelScale--;

	int iModelProperty = (strlen(model_property) > 0) ? StringToInt(model_property) : 0;

	if (hasEnoughCredits(client, g_DongPropPrice[iModelScale]))
	{
		DongDispatch(client, iModelScale, iModelProperty);
		Client_Used_Credits(client, g_DongPropPrice[iModelScale]);
		DisplayActivity(client, gs_dongs[iModelScale]);
		return Plugin_Handled;
	}
	else
	{
		PrintToChat(client, "[sm_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
		g_DongPropPrice[iModelScale], g_RemainingCreds[client][VIRT_CRED]);
		PrintToConsole(client, "[sm_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
		g_DongPropPrice[iModelScale], g_RemainingCreds[client][VIRT_CRED]);
		return Plugin_Handled;
	}
}


bool Has_Anyone_Opted_Out()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && g_optedout[i]) // at least one person doesn't want to see the props
		{
			#if DEBUG
			PrintToServer("[sm_props] DEBUG: Client %s has opted out of props, let's hide them!", GetClientOfUserId(i));
			#endif
			return true;
		}
	}
	#if DEBUG
	PrintToServer("[sm_props] DEBUG: Nobody opted out of props.");
	#endif
	return false;
}


// sets the client as the entity's new parent and attach the entity to client
MakeParent(int client, int entity)
{
	char Buffer[64];
	Format(Buffer, sizeof(Buffer), "Client%d", client);

	DispatchKeyValue(client, "targetname", Buffer);

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", client);

	SetVariantString("grenade2");
	AcceptEntityInput(entity, "SetParentAttachment");
	SetVariantString("grenade2");
	AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset");

	AcceptEntityInput(entity, "DisableShadow");
	// SetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity", client); // warning! do it right

	float origin[3];
	float angle[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", angle);
	DispatchSpawn(entity);
	origin[0] += 6.6; // 6.6 vetical axis
	origin[1] += 1.9; // 1.9 horizontal axis
	origin[2] += 2.5; // 2.5 z axis (+ is forward from origin)

	angle[0] -= 20.0; // 20.0 vertical pitch (+ goes up)
	angle[1] -= 0.0; // 0.0 roll (- goes clockwise)
	angle[2] -= 15.0; // yaw
	SetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin); // these might not be working actually
	SetEntPropVector(entity, Prop_Send, "m_angRotation", angle);

	//DispatchKeyValueVector(entity, "Origin", origin);    //FIX testing offset coordinates, remove! -glub
	//DispatchKeyValueVector(entity, "Angles", angle);

	#if DEBUG
	char name[255];
	GetClientName(client, name, sizeof(name));
	PrintToConsole(client, "Made parent: at origin: %f %f %f; angles: %f %f %f for client %s", origin[0], origin[1], origin[2], angle[0], angle[1], angle[2], name);
	#endif
}


stock SetAlpha (int target, int alpha)
{
	// SetEntityRenderMode(target, RENDER_TRANSCOLOR);
	SetEntityRenderColor(target, 255, 255, 255, alpha); //only works for some models :(
}


public void OnGhostPickUp(int client)
{
	if (GetConVarBool(g_cvar_props_onghostpickup))
	{
		if (!IsValidClient(client))
			return;
		if (g_AttachmentEnt[client] != -1) // limit to one at a time
			return;
		SpawnAndStrapDongToSelf(client);
	}
}


public void OnGhostCapture(int client)
{
	if (GetConVarBool(g_cvar_props_oncapture))
	{
		FireWorksOnPlayer(client, GetConVarBool(g_cvar_props_oncapture_nodongs) ? GetRandomInt(1,3) : GetRandomInt(0,3));
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
			Setup_Firework(client, gs_dongs[0], TE_PHYSICS, true);
		}
		case 1: //ducks
		{
			Setup_Firework(client, gs_allowed_physics_models[0], TE_BREAKMODEL, false);
		}
		case 2: //tigers
		{
			Setup_Firework(client, gs_allowed_physics_models[1], TE_BREAKMODEL, false);
		}
		case 3: //team logo
		{
			if (GetClientTeam(client) == 2)
				Setup_Firework(client, gs_allowed_physics_models[3], REGULAR_PHYSICS, false);
			else // probably NSF
				Setup_Firework(client, gs_allowed_physics_models[2], REGULAR_PHYSICS, false);
		}
	}
}


public Action Command_Spawn_TEST_fireworks(int client, int args)
{
	decl String:s_model_pathname[255], String:s_type[255], String:s_shock[255];
	GetCmdArg(1, s_model_pathname, sizeof(s_model_pathname));
	GetCmdArg(2, s_type, sizeof(s_type));
	GetCmdArg(3, s_shock, sizeof(s_shock));
	bool bshock = (view_as<bool>(StringToInt(s_shock)) ? true : false);
	FireworksPropType itype = view_as<FireworksPropType>(StringToInt(s_type));

	#if DEBUG
	PrintToConsole(client, "[DEBUG] asked for fireworks: model: %s, type: %s shock: %d, itype %d", s_model_pathname, s_type, bshock, itype);
	#endif

	//bind p "sm_props_fireworks models/d/d_s02.mdl breakmodel 1"
	Setup_Firework(client, s_model_pathname, itype, bshock);

	return Plugin_Handled;
}


Setup_Firework (int client, const char[] model_pathname, const FireworksPropType PropEntClass, bool shocking)
{
	if (!IsValidClient(client))
		return;

	int dongclients[MAXPLAYERS+1];
	int numClients;
	if (shocking)
		numClients = GetDongClients(dongclients, sizeof(dongclients));

	int i_cached_model_index = PrecacheModel(model_pathname, false);
	if (i_cached_model_index == 0)
	{
		LogError("[sm_props] Couldn't find or precache model \"%s\".", model_pathname);
		return;
	}

	float pos[3];
	// GetClientEyePosition(client, pos);
	// pos[2] += 90.0;

	GetRandomPosAboveClient(client, pos);

	for (int i=1; i>0; i--)
	{
		switch(PropEntClass)
		{
			case TE_PHYSICS:
			{
				TE_Start(gs_PropType[PropEntClass]); //PropEntClass
				Set_Firework_TE_PhysicsProp(i_cached_model_index, pos);
				if (shocking) 	// only send to clients who have not opted out
					TE_Send(dongclients, numClients, 0.0);
				else
					TE_SendToAll(0.0);
			}
			case TE_BREAKMODEL:
			{
				TE_Start(gs_PropType[PropEntClass]); //PropEntClass
				Set_Firework_TE_BreakModel(i_cached_model_index, pos);
				if (shocking)
					TE_Send(dongclients, numClients, 0.0);
				else
					TE_SendToAll(0.0);
			}
			case REGULAR_PHYSICS:
			{
				Set_Firework_PhysicsProp(client, model_pathname, pos);
			}
		}
		#if DEBUG
		PrintToConsole(client, "Spawned fireworks of %s at: %f %f %f for model %s index %d",
		gs_PropType[PropEntClass], pos[0], pos[1], pos[2], model_pathname, i_cached_model_index);
		#endif
	}
}


void Set_Firework_TE_PhysicsProp(int i_cached_model_index, const float[3] origin)
{
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteNum("m_nModelIndex", i_cached_model_index);
}


void Set_Firework_TE_BreakModel(int i_cached_model_index, const float[3] origin)
{
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteNum("m_nModelIndex", i_cached_model_index);
	TE_WriteNum("m_nCount", 10);
	TE_WriteNum("m_nRandomization", 10);
	TE_WriteFloat("m_fTime", 5.0);
}


void Set_Firework_PhysicsProp(int client, const char[] model_pathname, const float[3] origin)
{
	g_propindex_d[client] = SimpleCreatePropPhysicsOverride(model_pathname, 50);
	DispatchKeyValueVector(g_propindex_d[client], "Origin", origin);
	//TeleportEntity(g_propindex_d[client], origin, NULL_VECTOR, NULL_VECTOR);

	if (StrContains(model_pathname, "logo.mdl") != -1) // it's a logo
	{
		SetEntityRenderFx(g_propindex_d[client], RENDERFX_DISTORT); // works, only good for team logos
		AcceptEntityInput(g_propindex_d[client], "DisableShadow");
		// DispatchKeyValue(g_propindex_d[client], "Solid", "0");
	}

	DispatchSpawn(g_propindex_d[client]);
	return;
}


void GetRandomPosAboveClient(int client, float[3] origin)
{
	float vAngles[3], vOrigin[3], normal[3];
	vAngles[0] -= 90.0 + GetRandomInt(-20,20); // 90 degrees above head of client
	vAngles[1] -= 90.0 + GetRandomInt(-20,20);
	vAngles[2] -= 90.0 + GetRandomInt(-20,20);

	GetClientEyePosition(client, vOrigin);

	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if(TR_DidHit(trace)){

		//TR_GetEndPosition(end, INVALID_HANDLE);    //Get position player looking at
		//TR_GetPlaneNormal(INVALID_HANDLE, normal);    //???
		//GetVectorAngles(normal, normal);    //Get angles of vector, which is returned by GetPlaneNormal
		//normal[0] += 90.0;    //Add some angle to existing angles

		TR_GetEndPosition(origin, trace);
		origin[2] -= 40.0; // avoid spawning in ceiling?


		TR_GetPlaneNormal(INVALID_HANDLE, normal);
		GetVectorAngles(normal, normal);
		normal[0] += 90.0;


		#if DEBUG
		float ClientOrigin[3];
		GetClientEyePosition(client, ClientOrigin);
		PrintToConsole(client, "ClientOrigin: %f %f %f", ClientOrigin[0], ClientOrigin[1], ClientOrigin[2]);
		PrintToConsole(client, "ClientEyeAngles: %f %f %f", vAngles[0], vAngles[1], vAngles[2]);
		PrintToConsole(client, "origin: %f %f %f", origin[0], origin[1], origin[2]);
		#endif
	}
	CloseHandle(trace);
}



// Create dong and strap to target arg1, spectators too if arg2
public Action Command_Strap_Dong(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	// if (HasAnyoneOptedOut() && !IsAdmin(client))
	// {
	// 	Display_Why_Command_Is_Disabled(client);
	// 	return Plugin_Handled;
	// }

	if (gb_PausePropSpawning && !IsAdmin(client))
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return Plugin_Handled;
	}

	bool isadmin = IsAdmin(client);
	char arg[5];
	int i_case;
	GetCmdArg(1, arg, sizeof(arg));

	if (strcmp(arg, "me") == 0)
		i_case = 0;
	else if (strcmp(arg, "team") == 0)
		i_case = 1;
	else if (strcmp(arg, "all") == 0)
		i_case = 2;

	if (i_case >= 1)
	{
		int team;
		if (i_case == 1)
			team = GetClientTeam(client);

		int price;
		bool affected[MAXPLAYERS+1];

		// build the list of affected players
		for (int i=1; i <= MaxClients; i++)
		{
			if (!IsValidClient(i))
				continue;

			if (i_case == 1)
				if (GetClientTeam(i) != team)
					continue;

			// we're dead, we don't add to price; note: IsPlayerAlive() doesn't work in NT
			if (client == i && GetCmdArgs() < 2 && !IsPlayerReallyAlive(client))
				continue;

			// didn't ask for specs to be affected
			if (GetCmdArgs() < 2 && !IsPlayerReallyAlive(i))
				continue;

			// don't add on top of another already attached
			if (g_AttachmentEnt[i] != -1)
				continue;

			if (!isadmin)
				price++;

			affected[i] = true;
		}

		#if DEBUG
		PrintToServer("[sm_props] DEBUG: affected clients (sizeof(affected) is %d):\n", sizeof(affected));
		// this DEBUG has a performance hit on the server!
		for (int i=1; i <= MaxClients; i++)
		{
			PrintToServer("affected[%d] is %d", i, affected[i]);
			if (!IsValidClient(i) || !affected[i])
				continue;
			PrintToServer("affected[%d] (%N?) is %d", i, i, affected[i]);
		}
		#endif

		if (isadmin) //bypass credit system
		{
			for (int i=1; i <= MaxClients; i++)
			{
				if (affected[i] && IsValidClient(i))
					SpawnAndStrapDongToSelf(i);
			}
			if (i_case == 1)
				DisplayActivity(client, "Dong on team.");
			else if (i_case == 2)
				DisplayActivity(client, "Dong on everyone.");
			return Plugin_Handled;
		}

		if (hasEnoughCredits(client, price) && price != 0)
		{
			for (int i=1; i <= MaxClients; i++)
				if (affected[i] && IsValidClient(i))
					SpawnAndStrapDongToSelf(i);

			Client_Used_Credits(client, price);

			if (i_case == 1)
			{
				ReplyToCommand(client, "[sm_props] Attached a dong to your team mates.");
				DisplayActivity(client, "Dong on team.");
			}
			else if (i_case == 2)
			{
				ReplyToCommand(client, "[sm_props] Attached a dong to everyone.");
				DisplayActivity(client, "Dong on everyone.");
			}
			return Plugin_Handled;
		}
		else if (price == 0)
		{
			ReplyToCommand(client, "[sm_props] Nobody would be affected by your request.");
			return Plugin_Handled;
		}
		else
		{
			ReplyToCommand(client, "[sm_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
			price, g_RemainingCreds[client][VIRT_CRED]);
			return Plugin_Handled;
		}
	}
	else //i_case 0, only "me"
	{
		if (g_AttachmentEnt[client] != -1)
		{
			ReplyToCommand(client, "[sm_props] You already have a dong attached to yourself.");
			return Plugin_Handled;
		}

		if (isadmin)
		{
			SpawnAndStrapDongToSelf(client);
			ReplyToCommand(client, "[sm_props] Attached a dong to yourself.");
			DisplayActivity(client, "Dong on themselves.");
			return Plugin_Handled;
		}

		if (hasEnoughCredits(client, g_DongPropPrice[0]))
		{
			SpawnAndStrapDongToSelf(client);
			Client_Used_Credits(client, g_DongPropPrice[0]);
			DisplayActivity(client, "Dong on themselves."); //FIXME: format this to add detail about the exact command passed in that string
			return Plugin_Handled;
		}
		else
		{
			ReplyToCommand(client, "[sm_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
			g_DongPropPrice[0], g_RemainingCreds[client][VIRT_CRED]);
			return Plugin_Handled;
		}
	}
}


bool IsPlayerReallyDead(int client)
{
	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1)
		return true;
	return false;
}


bool IsPlayerReallyAlive(int client)
{
	if ((GetClientTeam(client) < 2)) // not in team, probably spectator
		return false;

	#if DEBUG
	PrintToServer("[sm_props] DEBUG: Client %N (%d) has %d health.", client, client, GetEntProp(client, Prop_Send, "m_iHealth"));
	#endif

	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1) // For some reason, 1 health point means dead.
	{
		#if DEBUG
		PrintToServer("[sm_props] DEBUG: Determined that %N is not alive right now.", client);
		#endif
		return false;
	}

	return true;
}


public void SpawnAndStrapDongToSelf(int client)
{
	#if DEBUG
	PrintToConsole(client, "[sm_props] DEBUG: SpawnAndStrapDongToSelf() on %L", client);
	#endif

	// if (g_AttachmentEnt[client] != -1 || !IsValidClient(client)) // moved up
	// 	return;

	if (IsPlayerReallyAlive(client))
	{
		g_AttachmentEnt[client] = CreatePropDynamicOverride_AtClientPos(client, gs_dongs[0], 5);
		MakeParent(client, g_AttachmentEnt[client]);

		#if !DEBUG
		SDKHook(g_AttachmentEnt[client], SDKHook_SetTransmit, Hide_SetTransmit);
		#endif

		#if DEBUG
		// int prop = SetEntProp(g_AttachmentEnt[client], Prop_Send, "m_iThermoptic");
		PrintToServer("[sm_props] DEBUG: Strapped prop index %d to client %L", g_AttachmentEnt[client], client);
		#endif
	}
	else //spectator
	{
		#if DEBUG
		PrintToServer("[sm_props] DEBUG: Client %N is a spectator. Strapping differently.", client);
		#endif

		g_AttachmentEnt[client] = Create_Prop_For_Attachment(client, gs_dongs[0], 5, true);

		#if DEBUG
		PrintToServer("[sm_props] DEBUG: Strapped prop index %d to client %L", g_AttachmentEnt[client], client);
		#endif

		if (gTimer == INVALID_HANDLE)
		{
			gTimer = CreateTimer(0.1, UpdateObjects, INVALID_HANDLE, TIMER_REPEAT);
		}
	}
}



stock int Create_Prop_For_Attachment(int client, const char[] modelname, int health, bool physics=false)
{
	int EntIndex;
	if (physics)
		EntIndex = CreateEntityByName("prop_physics_override");
	else
		EntIndex = CreateEntityByName("prop_dynamic_override");

	if(!IsModelPrecached(modelname))
		PrecacheModel(modelname);

	DispatchKeyValue(EntIndex, "model", modelname);
	DispatchKeyValue(EntIndex, "Solid", "6"); // 6 should be "use VPhysics", 0 not solid?
	//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);
	SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);
	// SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);
	// SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);
	SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);
	SetEntProp(EntIndex, Prop_Data, "m_iMaxHealth", health, 1);

	float VecOrigin[3];
	GetClientEyePosition(client, VecOrigin);
	//float VecAngles[3];
	// GetClientEyeAngles(client, VecAngles);


	AcceptEntityInput(EntIndex, "DisableShadow");
	SetAlpha(EntIndex, 100);


	// VecAngles[0] += 50.0;
	// DispatchKeyValueVector(EntIndex, "Origin", VecOrigin); // works!
	//DispatchKeyValueVector(EntIndex, "Angles", VecAngles);

	DispatchSpawn(EntIndex);
	TeleportEntity(EntIndex, VecOrigin, NULL_VECTOR, NULL_VECTOR);

	// attach to client
	MakeParent_Spec(client, EntIndex);



	// float degree = 180.0;  //rotating properly -glub
	// float angles[3];
	//GetEntPropVector(EntIndex, Prop_Data, "m_angRotation", angles);
	//RotateYaw(angles, degree);


	//DispatchKeyValueVector(EntIndex, "Angles", angles );  // rotates 180 degrees! -glub

	// #if DEBUG
	// new String:name[130];
	// GetClientName(client, name, sizeof(name));
	// PrintToChatAll("%s spawned a %s.", name, GetEntityClassname(EntIndex));
	// #endif

	return EntIndex;
}


MakeParent_Spec(int client, int entity)
{
	char tName[128];
	Format(tName, sizeof(tName), "target%i", client);
	DispatchKeyValue(client, "targetname", tName);

	// set the position
	float vOrigin[3], vAng[3];
	GetClientEyePosition(client, vOrigin);
	vOrigin[0] -= 20.0;
	// vAng[0] += 0.0;
	// vAng[1] += 0.0;
	// vAng[2] += 120.0;
	TeleportEntity(entity, vOrigin, vAng, NULL_VECTOR);

	// parent to player
	DispatchKeyValue(entity, "parentname", tName);
	SetVariantString(tName);
	AcceptEntityInput(entity, "SetParent", entity, entity, 0);

	CreateTimer(0.1, timer_SetParentAttachment, entity);

	// old method below:
	#if DEBUG > 10
	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", client);

	// SetVariantString("grenade2");
	// Change this entity to attach to a specific attachment point on its parent. The entity will teleport so that the position of its root bone matches that of the attachment. Entities must be parented before being sent this input.
	// AcceptEntityInput(entity, "SetParentAttachment");
	SetVariantString("grenade2");
	//As above, but without teleporting. The entity retains its position relative to the attachment at the time of the input being received.
	AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset");

	float origin[3];
	float angle[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	//GetEntPropVector(entity, Prop_Send, "m_angRotation", angle);

	// origin[0] += 6.6; // 6.6 vetical axis
	// origin[1] += 1.9; // 1.9 horizontal axis
	// origin[2] += 2.5; // 2.5 z axis (+ is forward from origin)

	//angle[0] = 20.0; // 20.0 vertical pitch (+ goes up)
	//angle[1] -= 0.0; // 0.0 roll (- goes clockwise)
	//angle[2] -= 15.0; // yaw
	SetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin); // these might not be working actually
	SetEntPropVector(entity, Prop_Send, "m_angRotation", angle);

	//DispatchKeyValueVector(entity, "Origin", origin);    //FIX testing offset coordinates, remove! -glub
	//DispatchKeyValueVector(entity, "Angles", angle);
	DispatchSpawn(entity);

	#if DEBUG
	PrintToConsole(client, "DEBUG: MakeParent_Spec() origin(%f %f %f) angles(%f %f %f) client(%N)", origin[0], origin[1], origin[2], angle[0], angle[1], angle[2], client);
	#endif
	#endif //DEBUG >10
}


public Action timer_SetParentAttachment(Handle timer, int entity)
{
	SetVariantString("grenade2"); // grenade2, eyes
	// AcceptEntityInput(entity, "SetParentAttachment");
	AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset");

}

public Action UpdateObjects(Handle timer)
{
	bool activeprop; // we still have an active prop to update
	for(int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;
		if (!IsPlayerReallyDead(i))
			continue;
		if (g_AttachmentEnt[i] != -1)
		{
			activeprop = true;
			Update_Coordinates(i, g_AttachmentEnt[i]);
		}

	}
	if (!activeprop)
	{
		if (gTimer != INVALID_HANDLE)
		{
			#if DEBUG
			PrintToServer("DEBUG: no more active attachments, killing timer");
			#endif
			KillTimer(timer);
			gTimer = INVALID_HANDLE;
		}
	}
	return Plugin_Continue;
}


void Update_Coordinates(int client, int entity) // FIXME: coordinates are not updated properly on one axis
{
	if (!IsValidEdict(entity) || !IsValidEntity(entity))
		return;

	float viewAng[3], vAngRot[3];
	// float vPos[3];

	GetClientEyeAngles(client, viewAng);
	// GetClientEyePosition(client, vPos);

	// float vecDir[3];
	// GetClientAbsAngles(client, vecDir);

	// float direction[3], normal[3];
	// GetAngleVectors(viewAng, direction, NULL_VECTOR, NULL_VECTOR);
	// NormalizeVector(direction, direction);

	// float angle[3];
	// GetVectorAngles(viewAng, angle); // "Returns angles from a vec."

	// viewAng[0] = - viewAng[0] - 150.0; // works fine to invert pitch with "angles" by itself

	#if DEBUG
	float v_angRotation[3], v_angRotationClient[3];
	GetEntPropVector(entity, Prop_Send, "m_angRotation", v_angRotation);
	GetEntPropVector(client, Prop_Send, "m_angRotation", v_angRotationClient);
	//PrintToChatAll("Before: m_angRotation: %f %f %f vPos %f %f %f", v_angRotation[0], v_angRotation[1], v_angRotation[2], vPos[0], vPos[1], vPos[2]);
	PrintToChatAll("Client: m_angRotation: %f %f %f", v_angRotationClient[0], v_angRotationClient[1], v_angRotationClient[2]);
	#endif

	// vAngRot[0] -= 100.0;
	// vAngRot[1] += 50.0; // testing
	vAngRot[2] = viewAng[1]; // works for yaw, use to set m_angRotation, don't change

	DispatchKeyValueVector(entity, "angles", viewAng); // seems to work for pitch
	SetEntPropVector(entity, Prop_Send, "m_angRotation", vAngRot); // jerky?

	ChangeEdictState(entity, GetEntSendPropOffs(entity, "m_vecAngles", true)); // ok
	ChangeEdictState(entity, GetEntSendPropOffs(entity, "m_vecRotation", true));
	ChangeEdictState(entity, GetEntSendPropOffs(entity, "m_angRotation", true)); // ok
	// TeleportEntity(entity, vPos, viewAng, NULL_VECTOR);


	#if DEBUG
	PrintToChatAll("viewAng: %f %f %f, vAngRot: %f %f %f", viewAng[0], viewAng[1], viewAng[2], vAngRot[0], vAngRot[1], vAngRot[2]);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", v_angRotation);
	PrintToChatAll("After: m_angRotation: %f %f %f, vAngRot: %f %f %f", v_angRotation[0], v_angRotation[1], v_angRotation[2], vAngRot[0], vAngRot[1], vAngRot[2]);
	#endif
}


//==================================
//		Prop auto-removal
//==================================

public Action OnPlayerRunCmd(int client, int &buttons)
{
	// right now I have no idea how to cloak a parented prop, so we simply kill it :(
	if((buttons & (1 << 27)) == (1 << 27))
	{
		if (IsPlayerReallyAlive(client) && (GetEntProp(client, Prop_Send, "m_iClassType") < 3)) // not a Support
		{
			DestroyAttachedPropForClient(client);
			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}


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
	if(client <= MaxClients && propindex > 0 && !IsFakeClient(client) && IsValidEntity(client) && IsClientInGame(client) /*&& IsPlayerAlive(client)*/ && IsValidEdict(propindex))
	{
		AcceptEntityInput(propindex, "kill");
	}
	return Plugin_Continue;
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


public Action Command_Spawn_TE_Prop(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return Plugin_Handled;
	}

	// char s_tetype[];
	char s_model_pathname[PLATFORM_MAX_PATH];
	char s_tetype[150];
	GetCmdArg(1, s_model_pathname, sizeof(s_model_pathname));
	//GetCmdArg(2, s_tetype, sizeof(s_tetype));
	strcopy(s_tetype, sizeof(s_tetype), gs_PropType[TE_PHYSICS]); // forcing physicsprop or breakmodel for testing

	int dongclients[MAXPLAYERS+1];
	int numClients = GetDongClients(dongclients, sizeof(dongclients));
	int i_cached_model_index = PrecacheModel(s_model_pathname, false);

	if (i_cached_model_index == 0)
	{
		PrintToServer("Error precaching model %s. Return value was: %d", s_model_pathname, i_cached_model_index);
		return Plugin_Handled;
	}

	float origin[3];
	GetClientEyePosition(client, origin);

	TE_Start(s_tetype);
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteNum("m_nModelIndex", i_cached_model_index);
	TE_Send(dongclients, numClients, 0.0);
	//PrintToConsole(client, "Spawned at: %f %f %f for model index: %d", origin[0], origin[1], origin[2], i_cached_model_index);
	return Plugin_Handled;
}


// not used anymore
public Action Spawn_TE_Dong(int client, const char[] model_pathname, const char[] TE_type)
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
	int i_cached_model_index = PrecacheModel(model_pathname, false);

	float origin[3];
	GetClientEyePosition(client, origin);

	TE_Start(TE_type);
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteNum("m_nModelIndex", i_cached_model_index);
	TE_Send(dongclients, numClients, 0.0);
	//PrintToConsole(client, "Spawned at: %f %f %f for model index: %d", origin[0], origin[1], origin[2], i_cached_model_index);
	return Plugin_Handled;
}


bool WantsDong(int client)
{
	if (IsValidClient(client) && !g_optedout[client])
		return true;
	return false;
}


public Action Hide_SetTransmit(int entity, int client)
{
	if(entity == g_AttachmentEnt[client])
		return Plugin_Handled; // hide client's attached prop from himself
	if (g_optedout[client])
		return Plugin_Handled; // hide prop from opted out clients
	return Plugin_Continue;
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



//==================================
//			Props UTILS
//==================================


int SimpleCreatePropPhysicsOverride(const char[] model_pathname, int health)
{

	new EntIndex = CreateEntityByName("prop_physics_override");


	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{
		if(!IsModelPrecached(model_pathname))
		{
			PrecacheModel(model_pathname);
		}

		//SetEntityModel(EntIndex, model_pathname);   <-- this doesn't work, it spawns at 0 0 0 no matter what!
		//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);   // 4 should be OK, but it's set to 0 instead? <-- 1073741824 now don't collide with players, but ignore collisions altogether
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);   //2, changed to 11 so that they collide bewteen each other, 11 = weapon
		SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);   // Do I need to change this to 9218?????  <- doesn't work, we need to try with prop_multiplayer
		SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);  //16 is suggested, ghost is 136!??     <- doesn't work, we need to try with prop_multiplayer

		//int health=150
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!
		SetEntProp(EntIndex, Prop_Data, "m_iMaxHealth", health, 1);

		SetEntPropFloat(EntIndex, Prop_Data, "m_flGravity", 1.0);  // doesn't seem to do anything?
		SetEntityGravity(EntIndex, 0.5); 						// (default = 1.0, half = 0.5, double = 2.0)

		SetEntPropFloat(EntIndex, Prop_Data, "m_massScale", 1.0);  //FIXME!
		DispatchKeyValue(EntIndex, "massScale", "1.0");
		DispatchKeyValue(EntIndex, "physdamagescale", "1.0");  // FIXME! not sure if it works

		DispatchKeyValue(EntIndex, "targetname", "test");
		DispatchKeyValue(EntIndex, "model", model_pathname);     //does the same as SetEntityModel but works better! can teleport!?
		//DispatchKeyValue(EntIndex, "CCollisionProperty", "2");
		//DispatchKeyValueFloat(EntIndex, "solid", 2.0);  //remettre 2.0 !
		//DispatchKeyValue(EntIndex, "Solid", "6");    // might need to disable this one (unnecessary?)
		DispatchKeyValue(EntIndex, "inertiaScale", "1.0");

		SetEntityMoveType(EntIndex, MOVETYPE_VPHYSICS);   //MOVETYPE_VPHYSICS seems oK, doesn't seem to change anything

		//DispatchKeyValueVector(EntIndex, "Origin", PropStartOrigin); // works!
		//DispatchKeyValueVector(EntIndex, "Angles", ClientEyeAngles); // works!
		//DispatchKeyValueVector(EntIndex, "basevelocity", clienteyeposition);
		DispatchKeyValue(EntIndex, "physdamagescale", "0.1");   // works! positive value = breaks when falling
		DispatchKeyValue(EntIndex, "friction", "1.0");
		DispatchKeyValue(EntIndex, "gravity", "0.2");
		//TeleportEntity(EntIndex, ClientOrigin, NULL_VECTOR, NULL_VECTOR);
		//DispatchSpawn(EntIndex);

	}
	return EntIndex;
}
