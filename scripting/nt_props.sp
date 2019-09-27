#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <nt_entitytools>

#pragma semicolon 1
#define PLUGIN_VERSION "20190925"

Handle g_cvar_props_enabled, g_cvar_restrict_alive, g_cvar_give_initial_credits, g_cvar_credits_replenish, g_cvar_score_as_credits= INVALID_HANDLE;
Handle cvMaxPropsCreds = INVALID_HANDLE; // maximum credits given
Handle cvPropMaxTTL = INVALID_HANDLE; // maximum time to live before prop gets auto removed
Handle g_PropPrefCookie = INVALID_HANDLE; // handle to client preferences
Handle g_cvar_props_oncapture, g_cvar_props_onghostpickup, g_cvar_props_oncapture_nodongs = INVALID_HANDLE;
bool gb_PausePropSpawning;
bool gb_hashadhisd[MAXPLAYERS+1];
int AttachmentEnt[MAXPLAYERS+1] = {-1,...};

// WARNING: the custom files require the sm_downloader plugin to force clients to download them
// otherwise, have to add all custom files to downloads table ourselves with AddFileToDownloadsTable()
new const String:gs_dongs[][] = {
	"models/d/d_s02.mdl", //small
	"models/d/d_b02.mdl", //big
	"models/d/d_h02.mdl", //huge
	"models/d/d_g02.mdl", //gigantic
	"models/d/d_mh02.mdl" }; //megahuge
// Prices: scale 1= 1 creds, 2= 3 creds, 3= 6 creds, 4= 8 creds, 5= 10 creds
new const g_DongPropPrice[] = { 1, 3, 6, 8, 10 };

new const String:gs_allowed_physics_models[][] = {
	"models/nt/a_lil_tiger.mdl",
	"models/nt/props_office/rubber_duck.mdl",
	"models/logo/jinrai_logo.mdl",
	"models/logo/nsf_logo.mdl" }; //physics version

new const String:gs_allowed_dynamic_models[][] = {
	"models/nt/a_lil_tiger.mdl",
	"models/nt/props_office/rubber_duck.mdl",
	"models/logo/jinrai_logo.mdl",
	"models/logo/nsf_logo.mdl" };

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

// [0] holds virtual credits, [2] current score credits, [3] maximum credits level reached
new g_RemainingCreds[MAXPLAYERS+1][3];
#define VIRT_CRED 0
#define SCORE_CRED 1
#define MAX_CRED 2

new g_propindex_d[MAXPLAYERS+1]; // holds the last spawned entity by client
new g_precachedModels[10];
new g_prefs_nowantprops[MAXPLAYERS+1];

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
//
// KNOWN ISSUES:
// -> AFAIK the TE cannot be destroyed by timer, so client preference is very limited, ie. if someone asks for a big scale model that is supposed to be auto-removed
//    we can't use a TE because they don't get affected by timers, so regular physics_prop take precedence. Same for dynamic props, cannot have them as TempEnts.
//
// FIXME: restore score credit properly on reconnect after nt_savescore restored it (maybe need a timer)
// FIXME: destroy strapped prop when client dies

public OnPluginStart()
{
	RegAdminCmd("sm_props_set_credits", Command_Set_Credits_For_Client, ADMFLAG_SLAY, "Gives target player virtual credits in order to spawn props.");
	RegConsoleCmd("sm_props_credit_status", Command_Credit_Status, "List all player credits to spawn props.");

	RegConsoleCmd("sm_dick", Command_Dong_Spawn, "Spawns a dick [scale 1-5] [1 for static prop]");
	RegConsoleCmd("sm_props", CommandPropSpawn, "Spawns a prop.");
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


ProcessCookies(int client)
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

public Action Command_Give_Score (int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "This command cannot be executed by the server.");
		return Plugin_Stop;
	}

	SetEntProp(client, Prop_Data, "m_iFrags", 60);
	g_RemainingCreds[client][SCORE_CRED] = 60;
	g_RemainingCreds[client][VIRT_CRED] = 60;
	g_RemainingCreds[client][MAX_CRED] = 60;
	Command_Set_Credits_For_Client(client, 60);
	PrintToConsole(client, "gave score to %d", client);
	return Plugin_Handled;

}


public Action Command_Credit_Status(int client, int args)
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
	// remove entities attached to victim if any
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	if (g_propindex_d[victim] != 0)
	{
		AcceptEntityInput(g_propindex_d[victim], "ClearParent"); // TODO: TEST THIS!
		g_propindex_d[victim] = 0;
	}

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
public Action Command_Set_Credits_For_Client(int client, int args)
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


PropSpawnDispatch(int client, int model_index)
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
	ReplyToCommand(client, "args: modelpath: %s, rest: %s %s %s", model_path, renderfx, movetype, ignite);
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

		GetEntityClassname(g_propindex_d[client], clsname, sizeof(clsname));
		GetEntityRenderColor(g_propindex_d[client], r, g, b, a);
		rendfx = view_as<int>(GetEntityRenderFx(g_propindex_d[client]));
		rendm = view_as<int>(GetEntityRenderMode(g_propindex_d[client]));
		gravity = GetEntityGravity(g_propindex_d[client]);

		PrintToConsole(client, "Rendered before: %s with colors: %d,%d,%d,%d rendermode %d fx %d gravity %f", clsname, r,g,b,a, rendm, rendfx, gravity );
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

		GetEntityRenderColor(g_propindex_d[client], r, g, b, a);
		PrintToConsole(client, "Rendered after: %s with colors: %d,%d,%d,%d rendermode %d, fx %d gravity %f", clsname, r,g,b,a, rendm, rendfx, gravity);
		#endif
	}
}


PrintPluginCommandInfo(int client)
{
	PrintToChat(client, "[sm_props] Admin, check console for useful commands and convars...");
	PrintToConsole(client, "[sm_props] Admins, some useful commands:");
	PrintToConsole(client, "\nsm_props_set_credits: sets credits for a clientID\nsm_props_credit_status: check credit status for all\nsm_props_restrict_alive: restrict to living players\nsm_props_initial_credits: initial amount given on player connection\nsm_props_max_credits: credits given on initial connection\nsm_props_replenish_credits: whether credits are replenished between rounds\nsm_props_score_as_credits: whether score should be counter as credits.\nsm_props_max_ttl: props get deleted after that time.\nsm_props_enabled: disable the command.");
	PrintToConsole(client, "You may also do sm_props \"model_path\" \"renderfx\" \"movetype\" \"ignite\"");
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
			decl String:s_args[PLATFORM_MAX_PATH];
			//bypass credit system
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
				PrintToConsole(client, "Spawned: %s.", gs_allowed_physics_models[index]);
				PrintToChat(client, "Spawning your %s.", model_pathname);
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
			{
				if (Should_Use_TE()) // use TempEnts to avoid showing to people who don't like it
					Spawn_TE_Dong(client, gs_dongs[scale], gs_PropType[TE_PHYSICS]);
				else
				{
					g_propindex_d[client] = CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 50);
				}
			}
			else
				g_propindex_d[client] = CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 50);
		}
		case 1:
		{
			if (!bstatic)
			{
				if (Should_Use_TE()) // use TempEnts to avoid showing to people who don't like it
					Spawn_TE_Dong(client, gs_dongs[scale], gs_PropType[TE_PHYSICS]);
				else
				{
					g_propindex_d[client] = CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 120);
					CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
				}
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
			SDKHook(g_propindex_d[client], SDKHook_Touch, OnTouchEntityRemove);
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
		if (!IsValidClient(client))
			continue;

		if (g_prefs_nowantprops[client]) // at least one person doesn't want to see them
		{
			#if DEBUG
			PrintToServer("Client %s has set pref to opt out of props. We should use TE!", GetClientOfUserId(client));
			#endif
			return true;
		}
	}
	#if DEBUG
	PrintToServer("Nobody opted out of props, we can use physics or dynamics.");
	#endif
	return false;
}


DisplayActivity(int client, const char[] model)
{
	//ShowActivity2(client, "[sm_props] ", "%s spawned: %s.", client, model);
	LogAction(client, -1, "[sm_props] \"%L\" spawned: %s", client, model);

}


// sets the client as the entity's new parent and attach the entity to client
MakeParent(int client, int entity)
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

	float origin[3];
	float angle[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", angle);
	DispatchSpawn(entity);
	origin[0] += 3.0;
	origin[1] += 1.0;
	origin[2] += 2.0;

	angle[0] -= 0.0;
	angle[1] -= 0.0;
	angle[2] += 0.0;
	SetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin); // these might not be working actually
	SetEntPropVector(entity, Prop_Send, "m_angRotation", angle);

	//DispatchKeyValueVector(entity, "Origin", origin);    //FIX testing offset coordinates, remove! -glub
	//DispatchKeyValueVector(entity, "Angles", angle);

	char name[255];
	GetClientName(client, name, sizeof(name));
	PrintToConsole(client, "Made parent: at origin: %f %f %f; angles: %f %f %f for client %s", origin[0], origin[1], origin[2], angle[0], angle[1], angle[2], name);

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

	if (StrContains(model_pathname, "logo.mdl") != -1)
	{
		SetEntityRenderFx(g_propindex_d[client], RENDERFX_DISTORT); // works, only good for team logos
		AcceptEntityInput(g_propindex_d[client], "DisableShadow");
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

	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

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

	if (strcmp(arg, "me") == 0)
	{
		SpawnAndStrapDongToSelf(client);
	}
	else if (strcmp(arg, "team") == 0)
	{
		int team = GetClientTeam(client);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsValidClient(i))
				continue;
			if (GetClientTeam(i) != team)
				continue;

			SpawnAndStrapDongToSelf(i);
		}
	}
	else if (strcmp(arg, "all") == 0)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsValidClient(i))
				continue;
			SpawnAndStrapDongToSelf(i);
		}
	}
	return Plugin_Handled;
}


public void SpawnAndStrapDongToSelf(int client)
{
	#if DEBUG
	char name[255];
	GetClientName(client, name, sizeof(name));
	PrintToConsole(client, "Processing: Strapdongself on client index %d \"%s\"", client, name);
	#endif

	if (!gb_hashadhisd[client]) // limit to once only per round
	{
		g_propindex_d[client] = CreatePropDynamicOverride_AtClientPos(client, gs_dongs[0], 5);
		MakeParent(client, g_propindex_d[client]);
		#if DEBUG < 1
		return; // skip limitation to only one per round
		#endif 
		gb_hashadhisd[client] = true;
	}
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
	decl String:s_model_pathname[PLATFORM_MAX_PATH] = '\0';
	char s_tetype[150];
	GetCmdArg(1, s_model_pathname, sizeof(s_model_pathname));
	//GetCmdArg(2, s_tetype, sizeof(s_tetype));
	strcopy(s_tetype, sizeof(s_tetype), gs_PropType[TE_PHYSICS]); // forcing physicsprop or breakmodel for testing

	int dongclients[MAXPLAYERS+1];
	int numClients = GetDongClients(dongclients, sizeof(dongclients));
	int i_cached_model_index = PrecacheModel(s_model_pathname, false);

	float origin[3];
	GetClientEyePosition(client, origin);

	TE_Start(s_tetype);
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteNum("m_nModelIndex", i_cached_model_index);
	TE_Send(dongclients, numClients, 0.0);
	//PrintToConsole(client, "Spawned at: %f %f %f for model index: %d", origin[0], origin[1], origin[2], i_cached_model_index);
	return Plugin_Handled;
}


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
