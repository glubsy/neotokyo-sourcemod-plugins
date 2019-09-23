#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
//#include <smlib>
#pragma semicolon 1

new Handle:g_cvar_adminonly = INVALID_HANDLE;
new Handle:g_cvar_enabled = INVALID_HANDLE;
new Handle:g_cvar_props_enabled = INVALID_HANDLE;
new Handle:g_cvar_restrict_alive = INVALID_HANDLE;
new Handle:g_cvar_give_initial_credits = INVALID_HANDLE;
new Handle:g_cvar_credits_replenish = INVALID_HANDLE;
new Handle:g_cvar_score_as_credits = INVALID_HANDLE;
new Handle:cvMaxPropsCreds = INVALID_HANDLE; // maximum credits given
new Handle:cvPropMaxTTL = INVALID_HANDLE; // maximum time to live before prop gets auto removed
new Handle:g_PropPrefCookie = INVALID_HANDLE; // handle to client preferences
bool gb_PausePropSpawning;

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

new const String:gs_TE_types[][] = { "physicsprop", "breakmodel" };

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
	name = "nt_entitytools",
	author = "glub",
	description = "Various prop manipulation tools.",
	version = "0.4",
	url = "https://github.com/glubsy"
};

public OnPluginStart()
{
	RegAdminCmd("create_physics_multiplayer", CommandPropCreateMultiplayer, ADMFLAG_SLAY, "create_physics_multiplayer()");
	RegAdminCmd("create_physics_override", CommandPropCreatePhysicsOverride, ADMFLAG_SLAY, "creates physics prop with specified model");
	//RegAdminCmd("create_physics_override_vector", CommandPropCreatePhysicsOverrideVector, ADMFLAG_SLAY, "test");
	RegAdminCmd("create_dynamic_override", CommandCreatePropDynamicOverride, ADMFLAG_SLAY, "creates dynamic prop with specified model");
	RegAdminCmd("getinfo", GetPropInfo, ADMFLAG_SLAY);
	RegAdminCmd("dontcollide", CommandPropNoCollide, ADMFLAG_SLAY, "test");
	RegAdminCmd("collide", CommandPropCollide, ADMFLAG_SLAY);
	RegAdminCmd("makeladder", CommandMakeLadder, ADMFLAG_SLAY);
	RegAdminCmd("spawnghostcapzone", CommandSpawnGhostCapZone, ADMFLAG_SLAY);
	RegAdminCmd("spawnvipentity", CommandSpawnVIPEntity, ADMFLAG_SLAY);

	RegAdminCmd("movetype", ChangeEntityMoveType, ADMFLAG_SLAY);
	RegConsoleCmd("sm_strapon", Command_Strap_Dong, "Strap a dong onto yourself.");
	RegAdminCmd("sm_strapon_target", Command_Strapon_Target, ADMFLAG_SLAY,  "DEBUG: Strapon self/all/target to stick a dick on people");
	//RegAdminCmd("sm_unstrapon_target", Command_UnStrapon_Target, ADMFLAG_SLAY,  "unstrap self/all/target");
	RegAdminCmd("entity_remove", RemoveTargetEntity, ADMFLAG_SLAY, "DEBUG: to remove edict (fixme)");
	RegAdminCmd("setpropinfo", SetPropInfo, ADMFLAG_SLAY, "sets prop property");
	RegAdminCmd("TestSpawnFlags", TestSpawnFlags, ADMFLAG_SLAY, "sets prop property to all by name");
	RegAdminCmd("entity_rotate", Rotate_Entity, ADMFLAG_SLAY, "rotates an entity");
	RegAdminCmd("entity_rotateroll", Rotate_EntityRoll, ADMFLAG_SLAY, "rotates an entity (roll)");
	RegAdminCmd("entity_rotatepitch", Rotate_EntityPitch, ADMFLAG_SLAY, "rotates an entity (pitch)");

	RegAdminCmd("sm_props_set_credits", CommandSetCreditsForClient, ADMFLAG_SLAY, "Gives target player virtual credits in order to spawn props.");
	RegConsoleCmd("sm_props_credit_status", CommandPropCreditStatus, "List all player credits to spawn props.");

	RegConsoleCmd("sm_dick", CommandDongSpawn, "spawns a dick");
	RegConsoleCmd("sm_props", CommandPropSpawn, "spawns a prop");

	g_cvar_enabled = CreateConVar( "entitycreate_enabled", "1",
									"0: disable custom props spawning, 1: enable custom props spawning",
									FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DEMO,
									true, 0.0, true, 1.0 ); //from LeftFortDead plugin
	g_cvar_props_enabled = CreateConVar( "sm_props_enabled", "1",
										"0: disable custom props spawning, 1: enable custom props spawning",
										FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DEMO,
										true, 0.0, true, 1.0 );

	g_cvar_restrict_alive = CreateConVar( "sm_props_restrict_alive", "0",
										"0: spectators can spawn props too. 1: only living players can spawn props",
										FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DEMO,
										true, 0.0, true, 1.0 );
	g_cvar_adminonly = CreateConVar( "entitycreate_adminonly", "0",
									"0: every client can build, 1: only admin can build",
									FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DEMO,
									true, 0.0, true, 1.0 );

	g_cvar_give_initial_credits = CreateConVar( "sm_props_initial_credits", "0",
												"0: players starts with zero credits 1: assign sm_max_props_credits to all players as soon as they connect",
												FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DEMO,
												true, 0.0, true, 1.0 );
	cvMaxPropsCreds = CreateConVar("sm_props_max_credits", "10", "Max number of virtual credits allowed per round/life for spawning props");
	cvPropMaxTTL = CreateConVar("sm_props_max_ttl", "60", "Maximum time to live for spawned props in seconds.");

	g_cvar_credits_replenish = CreateConVar( "sm_props_replenish_credits", "1",
											"0: credits are lost forever after use. 1: credits replenish after each end of round",
											FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DEMO,
											true, 0.0, true, 1.0 );
	g_cvar_score_as_credits = CreateConVar( "sm_props_score_as_credits", "1",
											"0: use virtual props credits only, 1: use score as props credits on top of virtual props credits",
											FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DEMO,
											true, 0.0, true, 1.0 );

	RegConsoleCmd("sm_props_nothx", Command_Hate_Props_Toggle, "Toggle your preference to not see custom props wherever possible.");
	g_PropPrefCookie = RegClientCookie("no-props-plz", "player doesn't like custom props", CookieAccess_Public);

	RegConsoleCmd("sm_props_pause", Command_Pause_Props_Spawning, "Prevent any further custom prop spawning until end of round.");

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", event_RoundStart);

	RegAdminCmd("sm_props_givescore", CommandGiveScore, ADMFLAG_SLAY, "DEBUG: add 20 frags to score");
	RegAdminCmd("sm_props_tedong", Command_TE_dong, ADMFLAG_SLAY, "DEBUG: Spawn TE dong");

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

// Passes client array by ref, and returns num. of clients inserted in the array.
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

public Action Command_TE_dong(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return Plugin_Handled;
	}

	decl String:s_tetype[100];
	//GetCmdArg(1, s_tetype, sizeof(s_tetype));
	s_tetype = gs_TE_types[0]; // or physicsprop or breakmodel

	int dongclients[MAXPLAYERS+1];

	int numClients = GetDongClients(dongclients, sizeof(dongclients));

	int cached_mdl = PrecacheModel(gs_dongs[0], false);

	float origin[3];
	GetClientEyePosition(client, origin);
	TE_Start(s_tetype);
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


public Action CommandGiveScore (int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "This command cannot be executed by the server.");
		return Plugin_Stop;
	}

	SetEntProp(client, Prop_Data, "m_iFrags", 20);
	g_RemainingCreds[client][SCORE_CRED] = 20;
	g_RemainingCreds[client][MAX_CRED] = 20;
	CommandSetCreditsForClient(client, 20);
	PrintToConsole(client, "gave score to %d", client);
	return Plugin_Handled;

}


//==================================
//		Credits management
//==================================


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
		if(!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client))
			continue;

		if ( GetConVarBool(g_cvar_credits_replenish) )
			g_RemainingCreds[client][VIRT_CRED] = GetConVarInt(cvMaxPropsCreds);
		else
			g_RemainingCreds[client][VIRT_CRED] = g_RemainingCreds[client][MAX_CRED];
	}
	gb_PausePropSpawning = false;
	//return Plugin_Continue;  //?
}


public Action OnPlayerDeath(Handle event, const String:name[], bool dontBroadcast)
{
	// keep track of the player score in our credits array
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

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


public Action PropSpawnDispatch(int client, int model)
{
	CreatePropPhysicsOverride(client, gs_allowed_models[model], 50);
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

	decl String:model_name[80];
	GetCmdArg(1, model_name, sizeof(model_name));

	for (int i=0; i < sizeof(gs_allowed_models); ++i)
	{
		//TODO: check the path
		//TODO: make selection menu // Don't stop at first match
		//if (strcmp(model_name, gs_allowed_models[i]) == 0)
		if (StrContains(gs_allowed_models[i], model_name, false) != -1)
		{
			if (hasEnoughCredits(client, 5)) 								//FIXME: for now everything costs 5!
			{
				PrintToConsole(client, "Spawned: %s.", gs_allowed_models[i]);
				PrintToChat(client, "Spawning your %s.", model_name);
				PropSpawnDispatch(client, i);

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



/*=======================================================

					DONG SPAWNING

========================================================*/

// calls the actual model creation
public Action DongDispatch(int client, int scale, int bstatic)
{
	switch(scale)
	{
		case 1:
		{
			if (!bstatic)
				g_propindex_d[client] = CreatePropPhysicsOverride(client, gs_dongs[scale-1], 50);
			else
				g_propindex_d[client] = CreatePropDynamicOverride(client, gs_dongs[scale-1], 50);
		}
		case 2:
		{
			if (!bstatic)
				g_propindex_d[client] = CreatePropPhysicsOverride(client, gs_dongs[scale-1], 120);
			else
				g_propindex_d[client] = CreatePropDynamicOverride(client, gs_dongs[scale-1][0], 120);

			// remove the prop after 40 seconds
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, g_propindex_d[client]);
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


public Action CommandDongSpawn(int client, int args)
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
	new iModelScale = (strlen(model_scale) > 0) ? StringToInt(model_scale) : 1;
	if (iModelScale > 5)
		iModelScale = 5;
	new iModelProperty = (strlen(model_property) > 0) ? StringToInt(model_property) : 0;

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

DisplayActivity(int client, const char[] model)
{
	//ShowActivity2(client, "[sm_props] ", "%s spawned: %s.", client, model);
	LogAction(client, -1, "[sm_props] \"%L\" spawned: %s", client, model);

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
//			Spawning UTILS
//==================================

public Action CommandPropCreatePhysicsOverride(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	if(args >= 3)
	{
		ReplyToCommand(client, "too many arguments");
		return Plugin_Handled;
	}

	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	if(args == 2)
	{
		new String:arg2[10];
		GetCmdArg(2, arg2, sizeof(arg2));

		CreatePropPhysicsOverride(client, arg1, StringToInt(arg2));
		return Plugin_Handled;
	}
	if(args == 1)
	{
		CreatePropPhysicsOverride(client, arg1, 100); // we default to 100 health points if none is entered
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

stock CreatePropPhysicsOverride(int client, const String:modelname[], int health)
{
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_physics_override");

//	if (GetCmdArgs() < 2){
//	health=400;
//	}

	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{
		if(!IsModelPrecached(arg1))
		{
			PrecacheModel(arg1);			// might have to restrict list of models to avoid crash (menu?)
		}

//		SetEntityModel(EntIndex, arg1);   <-- this doesn't work, it spawns at 0 0 0 no matter what!
		//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);   // 4 should be OK, but it's set to 0 instead? <-- 1073741824 now don't collide with players, but ignore collisions altogether
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);   //2, changed to 11 so that they collide bewteen each other! 11 = weapon!
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


//		DispatchKeyValue(EntIndex, "health", "100");    //not working
//		DispatchKeyValue(EntIndex, "rendercolor", "20,50,80,255");  //not working
//		SetEntityRenderColor(EntIndex, 255, 10, 255, 255); //not working

/*		new g_offsCollisionGroup;
		g_offsCollisionGroup = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");
		SetEntData(EntIndex, g_offsCollisionGroup, 2, 4, true);  //new!
*/
//		AcceptEntityInput(EntIndex, "DisableCollision", 0, 0)  // causes absolutely no collision at all?
//		AcceptEntityInput(EntIndex, "kill", 0, 0)

		DispatchKeyValue(EntIndex, "targetname", "test");
		DispatchKeyValue(EntIndex, "model", modelname);     //does the same as SetEntityModel but works better! can teleport!?
		//DispatchKeyValue(EntIndex, "CCollisionProperty", "2");
		//DispatchKeyValueFloat(EntIndex, "solid", 2.0);  //remettre 2.0 !
		//DispatchKeyValue(EntIndex, "Solid", "6");    // might need to disable this one (unnecessary?)
		DispatchKeyValue(EntIndex, "inertiaScale", "1.0");



/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(EntIndex);
		PrintToConsole(client, "Entity: %d, solid: %d", EntIndex, solidtype);
		Entity_SetSolidType(EntIndex, 2);
*/
//		ChangeEdictState(EntIndex, 0);

		new Float:ClientOrigin[3];
		new Float:clientabsangle[3];
		new Float:propangles[3] = {0.0, 0.0, 0.0};
		new Float:ClientEyeAngles[3];
		new Float:clienteyeposition[3];
		new Float:PropStartOrigin[3];
		//new Float:eyes[3];


		GetClientAbsOrigin(client, ClientOrigin);
		GetClientAbsAngles(client, clientabsangle);
		GetClientEyePosition(client, clienteyeposition);
		GetClientEyeAngles(client, ClientEyeAngles);


		propangles[1] = clientabsangle[1];
		//ClientOrigin[2] += 20.0;
		//clienteyeposition[1] += 20.0;
		//ClientEyeAngles[1] += 20.0;

		GetAngleVectors(ClientEyeAngles, propangles, NULL_VECTOR, NULL_VECTOR);
		PropStartOrigin[0] = (ClientOrigin[0] + (100 * Cosine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[1] = (ClientOrigin[1] + (100 * Sine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[2] = (ClientOrigin[2] + 50);

//		GetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", PropStartOrigin);
		SetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", ClientEyeAngles);


		SetEntityMoveType(EntIndex, MOVETYPE_VPHYSICS);   //MOVETYPE_VPHYSICS seems oK, doesn't seem to change anything

/*		PrintToServer("PropStartOrigin: %f %f %f", PropStartOrigin[0], PropStartOrigin[1], PropStartOrigin[2]);
		PrintToServer("client origin: %f %f %f", ClientOrigin[0], ClientOrigin[1], ClientOrigin[2]);
		PrintToServer("GetAngleVectors: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("clientabsangle: %f %f %f", clientabsangle[0], clientabsangle[1], clientabsangle[2]);
		PrintToServer("ClientEyeAngles: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("propangles: %f %f %f", propangles[0], propangles[1], propangles[2]);
*/

/*
		new Float:vAngles[3], Float:vOrigin[3], Float:pos[3];

		GetClientEyePosition(client,vOrigin);
		GetClientEyeAngles(client, vAngles);

		new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

		if(TR_DidHit(trace)){
			TR_GetEndPosition(pos, trace);

			pos[2] += 10.0; // make sure he does not get stuck to the floor, increse Z pos

			TeleportEntity( target, pos, NULL_VECTOR, NULL_VECTOR ); //Teleport target player on hitpos

		}
		CloseHandle(trace);


*/


		DispatchKeyValueVector(EntIndex, "Origin", PropStartOrigin); // works!
		DispatchKeyValueVector(EntIndex, "Angles", ClientEyeAngles); // works!
		//DispatchKeyValueVector(EntIndex, "basevelocity", clienteyeposition);
		DispatchKeyValue(EntIndex, "physdamagescale", "0.1");   // works! positive value = breaks when falling
		DispatchKeyValue(EntIndex, "friction", "1.0");
		DispatchKeyValue(EntIndex, "gravity", "0.8");
		//TeleportEntity(EntIndex, ClientOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(EntIndex);

		//GetPropInfo(client, EntIndex);

	}
	return EntIndex;
}





public Action CommandPropCreatePhysicsOverrideVector(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_physics_override");

	if(!IsModelPrecached(arg1))
	{
		PrecacheModel(arg1);			// might have to restrict list of models to avoid crash (menu?)
	}
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{

//		SetEntityModel(EntIndex, arg1);   <-- this doesn't work, it spawns at 0 0 0 no matter what!
		//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);   // 4 should be OK, but it's set to 0 instead? <-- 1073741824 now don't collide with players but ignore collisions altogether
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);   //2, changed to 11 so that they collide bewteen each other!!
		SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);   // Do I need to change this to 9218?????  <- doesn't work, we need to try with prop_multiplayer
		SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);  //16 is suggested, ghost is 136!??     <- doesn't work, we need to try with prop_multiplayer

		int health=150;
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!


		SetEntPropFloat(EntIndex, Prop_Data, "m_flGravity", 0.2);  // doesn't seem to do anything?

//		DispatchKeyValue(EntIndex, "health", "100");    //not working
//		DispatchKeyValue(EntIndex, "rendercolor", "20,50,80,255");  //not working
//		SetEntityRenderColor(EntIndex, 255, 10, 255, 255); //not working

/*		new g_offsCollisionGroup;
		g_offsCollisionGroup = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");
		SetEntData(EntIndex, g_offsCollisionGroup, 2, 4, true);  //new!
*/
//		AcceptEntityInput(EntIndex, "DisableCollision", 0, 0);  // causes absolutely no collision at all?
//		AcceptEntityInput(EntIndex, "kill", 0, 0);

		DispatchKeyValue(EntIndex, "targetname", "test");
		DispatchKeyValue(EntIndex, "model", arg1);     //does the same as SetEntityModel but works better! can teleport!?
		DispatchKeyValue(EntIndex, "CCollisionProperty", "2");
//		DispatchKeyValueFloat(EntIndex, "solid", 2.0);  //remettre 2.0 !
		DispatchKeyValue(EntIndex, "Solid", "6");    // might need to disable this one (unnecessary?)



/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(EntIndex);
		PrintToConsole(client, "Entity: %d, solid: %d", EntIndex, solidtype);
		Entity_SetSolidType(EntIndex, 2);
*/
//		ChangeEdictState(EntIndex, 0);

		new Float:ClientOrigin[3];
		new Float:clientabsangle[3];
		new Float:propangles[3] = {0.0, 0.0, 0.0};
		new Float:ClientEyeAngles[3];
		new Float:clienteyeposition[3];
		new Float:PropStartOrigin[3];
		//new Float:eyes[3];


		GetClientAbsOrigin(client, ClientOrigin);
		GetClientAbsAngles(client, clientabsangle);
		GetClientEyePosition(client, clienteyeposition);
		GetClientEyeAngles(client, ClientEyeAngles);


		propangles[1] = clientabsangle[1];
		//ClientOrigin[2] += 20.0;
		//clienteyeposition[1] += 20.0;
		//ClientEyeAngles[1] += 20.0;

		GetAngleVectors(ClientEyeAngles, propangles, NULL_VECTOR, NULL_VECTOR);
		PropStartOrigin[0] = (ClientOrigin[0] + (100 * Cosine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[1] = (ClientOrigin[1] + (100 * Sine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[2] = (ClientOrigin[2] + 50);

//		GetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", PropStartOrigin);
		SetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", ClientEyeAngles);


		SetEntityMoveType(EntIndex, MOVETYPE_VPHYSICS);   //MOVETYPE_VPHYSICS seems oK, doesn't seem to change anything

/*		PrintToServer("PropStartOrigin: %f %f %f", PropStartOrigin[0], PropStartOrigin[1], PropStartOrigin[2]);
		PrintToServer("client origin: %f %f %f", ClientOrigin[0], ClientOrigin[1], ClientOrigin[2]);
		PrintToServer("GetAngleVectors: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("clientabsangle: %f %f %f", clientabsangle[0], clientabsangle[1], clientabsangle[2]);
		PrintToServer("ClientEyeAngles: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("propangles: %f %f %f", propangles[0], propangles[1], propangles[2]);
*/

		new Float:vAngles[3], Float:vOrigin[3], Float:pos[3];

		GetClientEyePosition(client,vOrigin);
		GetClientEyeAngles(client, vAngles);

		new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

		if(TR_DidHit(trace)){
			TR_GetEndPosition(pos, trace);

			//pos[2] += 10.0; // make sure he does not get stuck to the floor, increse Z pos
			DispatchKeyValueVector(EntIndex, "Origin", pos);  //spawn at end of raytrace first


		}
		CloseHandle(trace);


		//DispatchKeyValueVector(EntIndex, "Origin", PropStartOrigin); // works!
		DispatchKeyValueVector(EntIndex, "Angles", ClientEyeAngles); // works!
		//DispatchKeyValueVector(EntIndex, "basevelocity", clienteyeposition);
		DispatchKeyValue(EntIndex, "physdamagescale", "0.5");   // works! positive value = breaks when falling
		DispatchKeyValue(EntIndex, "friction", "1.5");
		DispatchKeyValue(EntIndex, "gravity", "0.1");
		TeleportEntity(EntIndex, ClientOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(EntIndex);

		GetPropInfo(client, EntIndex);

	}
	return Plugin_Handled;
}



public Action CommandCreatePropDynamicOverride(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	if(args >= 3)
	{
		ReplyToCommand(client, "too many arguments");
		return Plugin_Handled;
	}

	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	if(args == 2)
	{
		new String:arg2[10];
		GetCmdArg(2, arg2, sizeof(arg2));

		CreatePropDynamicOverride(client, arg1, StringToInt(arg2));
		return Plugin_Handled;
	}
	if(args == 1)
	{
		CreatePropDynamicOverride(client, arg1, 100); // we default to 100 health points if none is entered
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

stock CreatePropDynamicOverride(int client, const String:modelname[], int health)
{
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_dynamic_override");

	if(!IsModelPrecached(arg1))
	{
		PrecacheModel(arg1);
	}

	new String:name[130];
	new Float:VecOrigin[3];
	new Float:VecAngles[3];
	new Float:normal[3];

	DispatchKeyValue(EntIndex, "model", modelname);
	DispatchKeyValue(EntIndex, "Solid", "6");
	//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);
	SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);
	SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);
	SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);

	SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);
	SetEntProp(EntIndex, Prop_Data, "m_iMaxHealth", health, 1);


	GetClientEyePosition(client, VecOrigin);
	GetClientEyeAngles(client, VecAngles);
	TR_TraceRayFilter(VecOrigin, VecAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer, client);
	TR_GetEndPosition(VecOrigin);
	TR_GetPlaneNormal(INVALID_HANDLE, normal);
	GetVectorAngles(normal, normal);
	normal[0] += 90.0;
	DispatchKeyValueVector(EntIndex, "Origin", VecOrigin); // works!
	DispatchKeyValueVector(EntIndex, "Angles", normal); // works!


	TeleportEntity(EntIndex, VecOrigin, normal, NULL_VECTOR);
	DispatchSpawn(EntIndex);

	new Float:degree = 180.0;  //rotating properly -glub
	decl Float:angles[3];
	GetEntPropVector(EntIndex, Prop_Data, "m_angRotation", angles);
	RotateYaw(angles, degree);

	DispatchKeyValueVector(EntIndex, "Angles", angles );  // rotates 180 degrees! -glub
	GetClientName(client, name, sizeof(name));
	//PrintToChatAll("%s spawned something", name);
	return EntIndex;
}



public Action CommandSpawnGhostCapZone(int client, int args)
{
	new aimed  = GetClientAimTarget(client, false);
	if(aimed != -1)
	{
		new String:arg1[5];
		//GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArgString(arg1,sizeof(arg1));

		new EntIndex = CreateEntityByName("neo_ghost_retrieval_point");
		if(EntIndex != -1)
		{
			PrintToChatAll("Aimed at: %i, Created: %i", aimed, EntIndex);
			new Float:VecOrigin[3];
			GetClientEyePosition(aimed, VecOrigin);
			DispatchKeyValueVector(EntIndex, "Origin", VecOrigin); // works!
			DispatchKeyValue(EntIndex, "team", "2");
			SetEntProp(EntIndex, Prop_Data, "m_iTeamNum", 1);



			DispatchKeyValue(EntIndex, "Radius", "128");


			//DispatchKeyValue(EntIndex, "model", "models/nt/a_lil_tiger.mdl");
			//SetEntityMoveType(EntIndex, MOVETYPE_NOCLIP);

			SetVariantString("!activator");
			AcceptEntityInput(EntIndex, "SetParent", aimed);

			//SetEntPropEnt(EntIndex, Prop_Data, "m_iParent", aimed);


			PrintToChatAll("dispatching %i", EntIndex);
			AcceptEntityInput(EntIndex, "start");

			//if(GetEdictFlags(EntIndex) & FL_EDICT_ALWAYS)
			SetEdictFlags(EntIndex, GetEdictFlags(EntIndex) ^ FL_EDICT_ALWAYS);


			SetEntPropEnt(EntIndex, Prop_Data, "m_hEffectEntity", aimed);
			CreateTimer(1.0, TimerSetParent, EntIndex, TIMER_REPEAT);
		}
	}
	return Plugin_Handled;
}


public Action CommandSpawnVIPEntity(int client, int args)
{
	char arg1[30];
	//GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArgString(arg1,sizeof(arg1));

	int newentity = CreateEntityByName(arg1); //use "neo_escape_point" or "neo_vip_entity"

	if(newentity != -1)
	{
		char classname[20];
		GetEdictClassname(newentity, classname, sizeof(classname));
		PrintToChatAll("[ENTITY] create %s, %i", classname, newentity);
		float VecOrigin[3], VecAngles[3], normal[3];

		GetClientEyePosition(client, VecOrigin);
		GetClientEyeAngles(client, VecAngles);

		TR_TraceRayFilter(VecOrigin, VecAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer, client);
		TR_GetEndPosition(VecOrigin);
		TR_GetPlaneNormal(INVALID_HANDLE, normal);
		GetVectorAngles(normal, normal);
		normal[0] += 90.0;

		//DispatchKeyValueVector(EntIndex, "Origin", VecOrigin);
		//DispatchKeyValueVector(EntIndex, "Angles", normal);

		DispatchKeyValue(newentity, "Radius", "140");
		//DispatchKeyValue(newentity, "Model", "models/player/vip.mdl");
		DispatchKeyValue(newentity, "modelindex", "353");

		float position[3];
		GetEntPropVector(newentity, Prop_Send, "m_Position", position);

		int radius;
		GetEntProp(newentity, Prop_Send, "m_Radius", radius);

		PrintToChatAll("Position of %s: %f %f %f", classname, VecOrigin[0], VecOrigin[1], VecOrigin[2]);
		PrintToChatAll("Position getentprop of %s: %f %f %f radius %i", classname, position[0], position[1], position[2], radius);

		TeleportEntity(newentity, VecOrigin, normal, NULL_VECTOR);
		DispatchSpawn(newentity);
	}
	return Plugin_Handled;
}


public Action:TimerSetParent(Handle:timer, entity)
{
	//SetVariantString("grenade2");
	//AcceptEntityInput(entity, "SetParentAttachment");
	//SetVariantString("grenade2");
	//AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset");
	DispatchSpawn(entity);
}


//==================================
//			Make Ladder tests
//==================================

public Action:CommandMakeLadder(int client, int args)
{
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_dynamic");

	if(!IsModelPrecached(arg1))
	{
		PrecacheModel(arg1);
	}

	new String:name[130];
	new Float:VecOrigin[3];
	new Float:VecAngles[3];
	new Float:normal[3];

	DispatchKeyValue(EntIndex, "model", "models/nt/props_construction/ladder2.mdl");
	DispatchKeyValue(EntIndex, "Solid", "7");
	//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);
	//SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 5);
	//SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);
	//SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);


	GetClientEyePosition(client, VecOrigin);
	GetClientEyeAngles(client, VecAngles);
	TR_TraceRayFilter(VecOrigin, VecAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer, client);
	TR_GetEndPosition(VecOrigin);
	TR_GetPlaneNormal(INVALID_HANDLE, normal);
	GetVectorAngles(normal, normal);
	normal[0] += 90.0;
	DispatchKeyValueVector(EntIndex, "Origin", VecOrigin); // works!
	DispatchKeyValueVector(EntIndex, "Angles", normal); // works!

	SetEntityMoveType(EntIndex, MOVETYPE_LADDER);
	TeleportEntity(EntIndex, VecOrigin, normal, NULL_VECTOR);
	DispatchSpawn(EntIndex);

	new Float:degree = 180.0;  //rotating properly -glub
	decl Float:angles[3];
	GetEntPropVector(EntIndex, Prop_Data, "m_angRotation", angles);
	RotateYaw(angles, degree);

	DispatchKeyValueVector(EntIndex, "Angles", angles );
	GetClientName(client, name, sizeof(name));
	PrintToChatAll("%s spawned something", name);
	return Plugin_Handled;
}



public Action:ChangeEntityMoveType(int client, int args)   // doesn't seem to do anything
{
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = GetClientAimTarget(client, false);
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{
		new String:classname[32];
		GetEdictClassname(EntIndex, classname, 32);

		SetEntityMoveType(EntIndex, MOVETYPE_LADDER);
		//DispatchSpawn(EntIndex);  // <- do not use again! it works now.

		ChangeEdictState(EntIndex, 0);
		PrintToChatAll("movetype changed?, %d", GetEntityMoveType(EntIndex));

	}
	return Plugin_Handled;
}


//==================================
//			Client UTILS
//==================================

bool:IsValidClient(client){

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


////////////////////////////////////////////////////////////////////////////////
//
// interior functions
//
////////////////////////////////////////////////////////////////////////////////

//---------------------------------------------------------
// spawn a given entity type and assign it a model
//---------------------------------------------------------
/*
CreateEntity( client, const String:entity_name[], const String:item_name[], const String:model[] = "" )
{
    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot spawn entity over rcon/server console" );
        return -1;
    }

    new index = CreateEntityByName( entity_name );
    if ( index == -1 )
    {
        ReplyToCommand( player, "Failed to create %s !", item_name );
        return -1;
    }

    if ( strlen( model ) != 0 )
    {
        if ( !IsModelPrecached( model ) )
        {
            PrecacheModel( model );
        }
        SetEntityModel( index, model );
    }

    ReplyToCommand( player, "Successfully create %s (index %i)", item_name, index );

    return index;
}
*/




/****************
 *Math (Vectors)*
*****************/

public Float:CreateVectorFromPoints(const Float:vec1[3], const Float:vec2[3], Float:output[3])
{
  output[0]=vec2[0]-vec1[0];
  output[1]=vec2[1]-vec1[1];
  output[2]=vec2[2]-vec1[2];
}

public AddInFrontOf(Float:orig[3], Float:angle[3], Float:distance, Float:output[3])
{
  new Float:viewvector[3];
  ViewVector(angle,viewvector);
  output[0]=viewvector[0]*distance+orig[0];
  output[1]=viewvector[1]*distance+orig[1];
  output[2]=viewvector[2]*distance+orig[2];
}

public ViewVector(Float:angle[3], Float:output[3])
{
  output[0]=Cosine(angle[1]/(180/FLOAT_PI));
  output[1]=Sine(angle[1]/(180/FLOAT_PI));
  output[2]=-Sine(angle[0]/(180/FLOAT_PI));
}

public Float:GetDistanceBetween(Float:startvec[3], Float:endvec[3])
{
  return SquareRoot((startvec[0]-endvec[0])*(startvec[0]-endvec[0])+(startvec[1]-endvec[1])*(startvec[1]-endvec[1])+(startvec[2]-endvec[2])*(startvec[2]-endvec[2]));
}

/*********
 *Helpers*
**********/
new OriginOffset;
new Handle:hEyeAngles;
new Handle:hEyePosition;
new GetVelocityOffset_0;
new GetVelocityOffset_1;
new GetVelocityOffset_2;

public GetEntityOrigin(entity, Float:output[3])
{
  GetEntDataVector(entity,OriginOffset,output);
}

public GetAngles(client, Float:output[3])
{
  SDKCall(hEyeAngles,client,output);
}

public GetEyePosition(client, Float:output[3])
{
  SDKCall(hEyePosition,client,output);
}

public GetVelocity(int client, Float:output[3])
{
  output[0]=GetEntDataFloat(client,GetVelocityOffset_0);
  output[1]=GetEntDataFloat(client,GetVelocityOffset_1);
  output[2]=GetEntDataFloat(client,GetVelocityOffset_2);
}


public Action:CommandPropCreateDynamicOverride(int client, int args)  // not used right now
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_dynamic_override");

	if(!IsModelPrecached(arg1))
	{
		PrecacheModel(arg1);			// might have to restrict list of models to avoid crash (menu?)
	}
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{

//		SetEntityModel(EntIndex, arg1);   <-- this doesn't work, it spawns at 0 0 0 no matter what!
		//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);   // 4 should be OK, but it's set to 0 instead? <-- 1073741824 now don't collide with players but ignore collisions altogether
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);   //2, changed to 11 so that they collide bewteen each other!!
		SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);   // Do I need to change this to 9218?????  <- doesn't work, we need to try with prop_multiplayer
		SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);  //16 is suggested, ghost is 136!??     <- doesn't work, we need to try with prop_multiplayer

		int health=150;
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!


		SetEntPropFloat(EntIndex, Prop_Data, "m_flGravity", 0.5);  // doesn't seem to do anything?

//		DispatchKeyValue(EntIndex, "health", "100");    //not working
//		DispatchKeyValue(EntIndex, "rendercolor", "20,50,80,255");  //not working
//		SetEntityRenderColor(EntIndex, 255, 10, 255, 255); //not working

/*		new g_offsCollisionGroup;
		g_offsCollisionGroup = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");
		SetEntData(EntIndex, g_offsCollisionGroup, 2, 4, true);  //new!
*/
//		AcceptEntityInput(EntIndex, "DisableCollision", 0, 0)  // causes absolutely no collision at all?
//		AcceptEntityInput(EntIndex, "kill", 0, 0)

		DispatchKeyValue(EntIndex, "targetname", "test");
		DispatchKeyValue(EntIndex, "model", arg1);     //does the same as SetEntityModel but works better! can teleport!?
		DispatchKeyValue(EntIndex, "CCollisionProperty", "2");
//		DispatchKeyValueFloat(EntIndex, "solid", 2.0);  //remettre 2.0 !
		DispatchKeyValue(EntIndex, "Solid", "6");    // might need to disable this one (unnecessary?)

/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(EntIndex);
		PrintToConsole(client, "Entity: %d, solid: %d", EntIndex, solidtype);
		Entity_SetSolidType(EntIndex, 2);
*/
//		ChangeEdictState(EntIndex, 0);

		new Float:ClientOrigin[3];
		new Float:clientabsangle[3];
		new Float:propangles[3] = {0.0, 0.0, 0.0};
		new Float:ClientEyeAngles[3];
		new Float:clienteyeposition[3];
		new Float:PropStartOrigin[3];
		//new Float:eyes[3];


		GetClientAbsOrigin(client, ClientOrigin);
		GetClientAbsAngles(client, clientabsangle);
		GetClientEyePosition(client, clienteyeposition);
		GetClientEyeAngles(client, ClientEyeAngles);


		propangles[1] = clientabsangle[1];
		//ClientOrigin[2] += 20.0;
		//clienteyeposition[1] += 20.0;
		//ClientEyeAngles[1] += 20.0;

		GetAngleVectors(ClientEyeAngles, propangles, NULL_VECTOR, NULL_VECTOR);
		PropStartOrigin[0] = (ClientOrigin[0] + (100 * Cosine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[1] = (ClientOrigin[1] + (100 * Sine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[2] = (ClientOrigin[2] + 50);
//		GetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", PropStartOrigin);
		SetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", ClientEyeAngles);


//		SetEntityMoveType(EntIndex, MOVETYPE_NOCLIP);   //MOVETYPE_VPHYSICS seems oK, doesn't seem to change anything

/*		PrintToServer("PropStartOrigin: %f %f %f", PropStartOrigin[0], PropStartOrigin[1], PropStartOrigin[2]);
		PrintToServer("client origin: %f %f %f", ClientOrigin[0], ClientOrigin[1], ClientOrigin[2]);
		PrintToServer("GetAngleVectors: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("clientabsangle: %f %f %f", clientabsangle[0], clientabsangle[1], clientabsangle[2]);
		PrintToServer("ClientEyeAngles: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("propangles: %f %f %f", propangles[0], propangles[1], propangles[2]);
*/



//RAYTRACING
		new Float:vAngles[3], Float:vOrigin[3], Float:pos[3];

		GetClientEyePosition(client,vOrigin);
		GetClientEyeAngles(client, vAngles);

		new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

		if(TR_DidHit(trace)){

			//TR_GetEndPosition(end, INVALID_HANDLE);    //Get position player looking at
			//TR_GetPlaneNormal(INVALID_HANDLE, normal);    //???
			//GetVectorAngles(normal, normal);    //Get angles of vector, which is returned by GetPlaneNormal
			//normal[0] += 90.0;    //Add some angle to existing angles

			TR_GetEndPosition(pos, trace);

			pos[2] += 10.0; // make sure he does not get stuck to the floor, increse Z pos

			DispatchKeyValueVector(EntIndex, "Origin", pos);

		}
		CloseHandle(trace);


		//DispatchKeyValueVector(EntIndex, "Origin", PropStartOrigin); // works!
		DispatchKeyValueVector(EntIndex, "Angles", ClientEyeAngles); // works!
		//DispatchKeyValueVector(EntIndex, "basevelocity", clienteyeposition);
		DispatchKeyValue(EntIndex, "physdamagescale", "0.5");   // works! positive value = breaks when falling
		DispatchKeyValue(EntIndex, "friction", "1.5");
		DispatchKeyValue(EntIndex, "gravity", "0.1");
		TeleportEntity(EntIndex, ClientOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(EntIndex);

		GetPropInfo(client, EntIndex);


	}
	return Plugin_Handled;
}


public bool:TraceEntityFilterPlayer(entity, contentsMask){
	return ((entity > MaxClients) || entity == 0);
}


public Action:GetPropInfo(client, args)
{
	new aimed = GetClientAimTarget(client, false);
	if (aimed != 1 && !IsValidEntity(aimed))
	{
		PrintToConsole(client, "not a valid entity you're aiming at");
	}
	if (aimed != -1 && IsValidEntity(aimed))
	{
		new String:classname[32];
		new String:m_ModelName[130];
		new String:m_nSolidType[130];
//		new String:movetype[130];
		int m_CollisionGroup, m_spawnflags, m_iMaxHealth, m_usSolidFlags;
		new Float:m_flGravity;
//		new Float:m_massScale;

		GetEdictClassname(aimed, classname, 32);
		GetEntPropString(aimed, Prop_Data, "m_ModelName", m_ModelName, 130);   //OK
		GetEntPropString(aimed, Prop_Data, "m_nSolidType", m_nSolidType, 130);  //OK
		m_CollisionGroup = GetEntProp(aimed, Prop_Data, "m_CollisionGroup", m_CollisionGroup);
		m_spawnflags = GetEntProp(aimed, Prop_Data, "m_spawnflags");
		m_iMaxHealth = GetEntProp(aimed, Prop_Data, "m_iMaxHealth", m_iMaxHealth);
		m_flGravity = GetEntPropFloat(aimed, Prop_Data, "m_flGravity");
//		m_massScale = GetEntPropFloat(aimed, Prop_Data, "m_massScale");
		m_usSolidFlags = GetEntProp(aimed, Prop_Data, "m_usSolidFlags");

		PrintToConsole(client, "Entity: %d, classname: %s, m_ModelName: %s, m_usSolidFlags: %d, movetype: %d", aimed, classname, m_ModelName, m_usSolidFlags, GetEntityMoveType(aimed));
		PrintToConsole(client, "m_CollisionGroup: %d, m_spawnflags: %d, m_nSolidType: %d, m_iMaxHealth: %d, m_flGravity: %f", m_CollisionGroup, m_spawnflags, m_nSolidType, m_iMaxHealth, m_flGravity);

/*
		m_iszBasePropData
		m_iInteractions
		m_bIsWalkableSetByPropData
		m_flGroundSpeed
		m_flLastEventCheck
		m_nHitboxSet
		m_flModelWidthScale
		m_iClassname
		m_iGlobalname
		m_iParent
		m_nRenderFX  renderfx
		m_nRenderMode   rendermode
		m_fEffects   effects
		m_clrRender   rendercolor
		m_nModelIndex   modelindex
		touchStamp
		m_aThinkFunctions
		m_ResponseContexts
		m_iszResponseContext  ResponseContext
		m_iEFlags
		m_iName
		Sub-Class Table (1 Deep): m_Collision - CCollisionProperty
		- m_vecMins
		- m_vecMaxs
		- m_nSolidType solid
		- m_usSolidFlags
		- m_nSurroundType
		- m_triggerBloat
		m_MoveType
		m_MoveCollide <-
		m_pPhysicsObject
		m_hGroundEntity
		m_ModelName  model
		m_vecBaseVelocity  basevelocity
		m_vecAbsVelocity
		m_vecAngVelocity   avelocity
		m_pBlocker
		m_flLocalTime
		m_vecAbsOrigin
		m_vecVelocity  - velocity
		m_spawnflags    spawnflags
		m_angAbsRotation (Save)(12 Bytes)
		m_vecOrigin (Save)(12 Bytes)
		m_angRotation
		m_vecViewOffset - view_ofs
		m_fFlags
		InputUse
		CBaseEntitySUB_Remove
		CBaseEntitySUB_Remove (FunctionTable)
		CBaseEntitySUB_DoNothing (FunctionTable)
		CBaseEntitySUB_StartFadeOut (FunctionTable)
		CBaseEntitySUB_StartFadeOutInstant (FunctionTable)
		CBaseEntitySUB_FadeOut (FunctionTable)
		CBaseEntitySUB_Vanish (FunctionTable)
		CBaseEntitySUB_CallUseToggle (FunctionTable)
		CBaseEntityShadowCastDistThink (FunctionTable)
		m_hEffectEntity <-

		MOVETYPE_LADDER (x) that's for player when on a ladder
		!HasSpawnFlags(SF_TRIG_PUSH_AFFECT_PLAYER_ON_LADDER)

		netprops:
		CBaseEntity
		movetype (offset 222) (type integer)
		movecollide (offset 223) (type integer) (bits 3) (Unsigned)

		CFuncLadder
		m_bFakeLadder


		MIGHT BE THIS?!
		SetEntityMoveType(Entindex,MOVETYPE_LADDER);
*/
		new Float:coords[3];
		GetEntPropVector(aimed, Prop_Send, "m_vecOrigin", coords);
		new Float:angles[3];
		GetEntPropVector(aimed, Prop_Data, "m_angRotation", angles);

		PrintToConsole(client, "m_CollisionGroup: %d, m_spawnflags: %d, m_nSolidType: %d, m_iMaxHealth: %d, m_flGravity: %f", m_CollisionGroup, m_spawnflags, m_nSolidType, m_iMaxHealth, m_flGravity);
		PrintToConsole(client, "m_CollisionGroup: %d, m_spawnflags: %d, m_nSolidType: %d, m_iMaxHealth: %d, m_flGravity: %f", m_CollisionGroup, m_spawnflags, m_nSolidType, m_iMaxHealth, m_flGravity);
		PrintToConsole(client, "m_CollisionGroup: %d, m_spawnflags: %d, m_nSolidType: %d, m_iMaxHealth: %d, m_flGravity: %f", m_CollisionGroup, m_spawnflags, m_nSolidType, m_iMaxHealth, m_flGravity);
		PrintToConsole(client, "index %d, coord[0]: %f, coord[1]: %f, coord[2]: %f, angle[0]: %f, angle[1]: %f,angle[2]: %f", aimed, coords[0], coords[1], coords[2], angles[0], angles[1], angles[2]);
	}
	return Plugin_Handled;
}



public Action:TestSpawnFlags(client, args)
{
	new aimed = CreateEntityByName("weapon_mx");
	new Float:vpos[3];
	GetClientEyePosition(client,vpos);
	vpos[0] += 50.0;

	if (IsValidEntity(aimed))
	{
		DispatchKeyValue(aimed, "spawnflags", "1073741824"); //1073741824
		SetEntProp(aimed, Prop_Data, "m_spawnflags", 1073741824);
		DispatchKeyValueVector(aimed, "Origin", vpos);
		DispatchSpawn(aimed);
		PrintToConsole(client, "Spawned  mx: spawnflags: %d", GetEntProp(aimed, Prop_Data, "m_spawnflags"));
	}
	return Plugin_Handled;
}


public Action:SetPropInfo(client, args)
{
	new aimed = GetClientAimTarget(client, false);
	if (aimed != 1 && !IsValidEntity(aimed))
	{
		PrintToConsole(client, "not a valid entity you're aiming at");
	}
	if (aimed != -1 && IsValidEntity(aimed))
	{
		//new String:m_ModelName[130];
		//new Float:m_flGravity;
		new Float:vec[3] = {100.0, 100.0, 100.0};
		DispatchKeyValueVector(aimed, "basevelocity", vec);
		//SetEntityModel(aimed, "models/nt/a_lil_tiger.mdl"); // GONNA CRASH!
		//DispatchSpawn(aimed);
		PrintToConsole(client, "dispatched %d", vec);


		decl String:Buffer[64];
		Format(Buffer, sizeof(Buffer), "Client%d", client);
		DispatchKeyValue(client, "targetname", Buffer);

		SetVariantString("!activator");
		AcceptEntityInput(aimed, "SetParent", client);
        //SetVariantString(Buffer);
        //AcceptEntityInput(aimed, "SetParent");

		SetVariantString("grenade2");
		AcceptEntityInput(aimed, "SetParentAttachment");
		AcceptEntityInput(aimed, "SetParentAttachmentMaintainOffset");
	}
	return Plugin_Handled;
}


// Hopefully someday this will be a hat or something, not a stupi d***
public Action Command_Strap_Dong(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return Plugin_Handled;
	}

	new created = CreatePropDynamicOverride(client, gs_dongs[0], 20);
	decl String:Buffer[64];
	Format(Buffer, sizeof(Buffer), "Client%d", client);
	DispatchKeyValue(client, "targetname", Buffer);

	SetVariantString("!activator");
	AcceptEntityInput(created, "SetParent", client);

	SetVariantString("grenade2");
	AcceptEntityInput(created, "SetParentAttachment");
	SetVariantString("grenade2");
	AcceptEntityInput(created, "SetParentAttachmentMaintainOffset");

	new Float:origin[3];
	new Float:angle[3];
	GetEntPropVector(created, Prop_Send, "m_vecOrigin", origin);
	GetEntPropVector(created, Prop_Send, "m_angRotation", angle);

	origin[0] += 0.0;
	origin[1] += 0.0;
	origin[2] += 0.0;

	angle[0] += 0.0;
	angle[1] += 3.0;
	angle[2] += 0.3;
	//DispatchKeyValueVector(created, "Origin", origin);    //FIX testing offset coordinates, remove! -glub
	//DispatchKeyValueVector(created, "Angles", angle);
	//DispatchSpawn(created);
	ReplyToCommand(client, "origin: %f %f %f; angles: %f %f %f", origin[0], origin[1], origin[2], angle[0], angle[1], angle[2]);

	return Plugin_Handled;
}



public Action Command_Strapon_Target(int client, int args)
{
	if (args < 1)
	{
		new aimed = GetClientAimTarget(client, false);
		if (aimed != -1 && IsValidEntity(aimed))
		{
			new String:classname[32];
			new String:m_ModelName[130];
			new String:m_nSolidType[130];
			int m_CollisionGroup, m_spawnflags;

			GetEdictClassname(aimed, classname, 32);
			if(StrContains(classname, "player"))
			{
				PrintToChat(client, "Can't strapon \"player\" classname");
				return Plugin_Handled;
			}
			GetEntPropString(aimed, Prop_Data, "m_ModelName", m_ModelName, 130);
			GetEntPropString(aimed, Prop_Data, "m_nSolidType", m_nSolidType, 130);
			GetEntProp(aimed, Prop_Data, "m_CollisionGroup", m_CollisionGroup);
			GetEntProp(aimed, Prop_Data, "m_spawnflags", m_spawnflags);

			decl String:Buffer[64];
			Format(Buffer, sizeof(Buffer), "Client%d", client);
			DispatchKeyValue(client, "targetname", Buffer);

			SetVariantString("!activator");
			AcceptEntityInput(aimed, "SetParent", client);
			//SetVariantString(Buffer);
			//AcceptEntityInput(aimed, "SetParent");

			SetVariantString("grenade2");
			AcceptEntityInput(aimed, "SetParentAttachment");
			SetVariantString("grenade2");
			AcceptEntityInput(aimed, "SetParentAttachmentMaintainOffset");
			/*new Float:angle[3];
			coords[0] -= 60.0;
			coords[1] -= 60.0;
			coords[2] += 100.0;
			DispatchKeyValueVector(aimed, "Origin", coords);*/    // Testing offsetting stuffs

			return Plugin_Handled;
		}
	}
	if  (args == 1) // spawns a prop and attach to us
	{
		new String:args1[130];
		GetCmdArg(1, args1, sizeof(args1));

		if (strcmp(args1, "dong") == 0)
		{
			new created = CreatePropDynamicOverride(client, gs_dongs[0], 20);
			decl String:Buffer[64];
			Format(Buffer, sizeof(Buffer), "Client%d", client);
			DispatchKeyValue(client, "targetname", Buffer);

			SetVariantString("!activator");
			AcceptEntityInput(created, "SetParent", client);

			SetVariantString("grenade2");
			AcceptEntityInput(created, "SetParentAttachment");
			SetVariantString("grenade2");
			AcceptEntityInput(created, "SetParentAttachmentMaintainOffset");

			new Float:origin[3];
			new Float:angle[3];
			GetEntPropVector(created, Prop_Send, "m_vecOrigin", origin);
			GetEntPropVector(created, Prop_Send, "m_angRotation", angle);

			origin[0] += 0.0;
			origin[1] += 0.0;
			origin[2] += 0.0;

			angle[0] += 0.0;
			angle[1] += 3.0;
			angle[2] += 0.3;
			//DispatchKeyValueVector(created, "Origin", origin);    //FIX testing offset coordinates, remove! -glub
			//DispatchKeyValueVector(created, "Angles", angle);
			//DispatchSpawn(created);
			PrintToChat(client, "origin: %f %f %f; angles: %f %f %f", origin[0], origin[1], origin[2], angle[0], angle[1], angle[2]);

			return Plugin_Handled;
		}
	}
	return Plugin_Handled;
}


/*
    if (!IsModelPrecached(model))
        PrecacheModel(model);

    g_prop = CreateEntityByName("prop_dynamic_override");
    if (IsValidEntity(g_prop)) {
        SetVariantString("!activator");
        AcceptEntityInput(g_prop, "SetParent", target, g_prop, 0);
        SetVariantString("head");
        AcceptEntityInput(g_prop, "SetParentAttachment", g_prop, g_prop, 0);
        DispatchKeyValue(g_prop, "model", model);
        if (GetClientTeam(target) == 3)
            DispatchKeyValue(g_prop, "skin", "1");
        DispatchKeyValue(g_prop, "solid", "0");
        DispatchKeyValue(g_prop, "targetname", "potw_hat1");
        DispatchSpawn(g_prop);
        AcceptEntityInput(g_prop, "TurnOn", g_prop, g_prop, 0);
    }
*/



public Action CommandPropCreateMultiplayer(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_physics_multiplayer");

	if(!IsModelPrecached(arg1))
	{
		PrecacheModel(arg1);			// might have to restrict list of models to avoid crash (menu?)
	}
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{

//		SetEntityModel(EntIndex, arg1);  // <-- this doesn't work, it spawns at 0 0 0 no matter what?
		SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);   // 4 should be OK, but it's set to 0 instead? <-- now don't collide with players but ignores collisions altogether?
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);   //2, changed to 11 so that they collide bewteen each other!!
		SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);   // Do I need to change this to 9218?????  <- doesn't work, we need to try with prop_multiplayer
		SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);  //16 is suggested, ghost is 136!??     <- doesn't work, we need to try with prop_multiplayer
//		SetEntityMoveType(EntIndex, MOVETYPE_VPHYSICS);   //MOVETYPE_VPHYSICS seems oK, doesn't seem to change anything

		int health=300;
//		health = 300
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!


		SetEntPropFloat(EntIndex, Prop_Send, "m_flGravity", 0.5); // doesn't do anything. FIXME: Changed from Prop_Data

//		DispatchKeyValue(EntIndex, "health", "100");    //not working
//		DispatchKeyValue(EntIndex, "rendercolor", "255,255,80,80");  //no working

/*		new g_offsCollisionGroup;
		g_offsCollisionGroup = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");
		SetEntData(EntIndex, g_offsCollisionGroup, 2, 4, true);  //new!
*/
//		AcceptEntityInput(EntIndex, "DisableCollision", 0, 0)  // causes absolutely no collision at all?
//		AcceptEntityInput(EntIndex, "kill", 0, 0)

		DispatchKeyValue(EntIndex, "targetname", "test");
		DispatchKeyValue(EntIndex, "model", arg1);     //does the same as SetEntityModel but works better! can teleport!?
		DispatchKeyValue(EntIndex, "CCollisionProperty", "2");
//		DispatchKeyValueFloat(EntIndex, "solid", 2.0);  //remettre 2.0 !
		DispatchKeyValue(EntIndex, "StartDisabled", "false");
		DispatchKeyValue(EntIndex, "spawnflags", "1073741824");   // <<- please check! new

		DispatchSpawn(EntIndex);


/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(EntIndex);
		PrintToConsole(client, "Entity: %d, solid: %d", EntIndex, solidtype);
		Entity_SetSolidType(EntIndex, 2);
*/
//		ChangeEdictState(EntIndex, 0);


		new Float:origin[3];
		origin[2] += 150.0;
//		GetClientAbsOrigin(client, origin);
		GetClientEyePosition(client, origin);
		//GetClientEyeAngles(client, angle);

//		GetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", origin);

		TeleportEntity(client, origin, NULL_VECTOR, NULL_VECTOR);

//		SetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", origin);
		PrintToConsole(client, "position: %f %f %f", origin[0], origin[1], origin[2]);
		GetPropInfo(client, EntIndex);

	}
	return Plugin_Handled;
}




public Action CommandPropNoCollide(int client, int args)
{
	new EntIndex = GetClientAimTarget(client, false);
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{
		new String:classname[32];
		GetEdictClassname(EntIndex, classname, 32);

		new String:modelname[130];
		new String:solid[130];
		int collisiongroup, spawnflags;
		GetEntPropString(EntIndex, Prop_Data, "m_ModelName", modelname, 130);
		GetEntProp(EntIndex, Prop_Data, "m_CollisionGroup", collisiongroup);
		GetEntProp(EntIndex, Prop_Data, "m_spawnflags", spawnflags);
		GetEntPropString(EntIndex, Prop_Data, "m_nSolidType", solid, 130);

		int health=150;
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!

		SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 4);    //if 4, props go through each others.
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 2);

		AcceptEntityInput(EntIndex, "DisableCollision", 0, 0);
//		AcceptEntityInput(EntIndex, "kill", 0, 0)

		DispatchKeyValue(EntIndex, "targetname", "test");
//		DispatchKeyValue(EntIndex, "model", "models/d/d_s01.mdl");  // ok it works, no need anymore, just use in another command as changing models for fun :)
		DispatchKeyValue(EntIndex, "CCollisionProperty", "0");
		DispatchKeyValueFloat(EntIndex, "solid", 2.0);
		//DispatchSpawn(EntIndex);   <- do not use again! it works now.

/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(EntIndex);
		PrintToConsole(client, "Entity: %d, solid: %d", EntIndex, solidtype);
		Entity_SetSolidType(EntIndex, 2);
*/

		ChangeEdictState(EntIndex, 0);

		new Float:origin[3];
		GetClientAbsOrigin(client, origin);
		origin[2] += 20.0;
		TeleportEntity(EntIndex, origin, NULL_VECTOR, NULL_VECTOR);


//		ReplyToCommand(client, "Entity: %d, classname: %s, Modelname: %s", EntIndex, classname, modelname);
		PrintToConsole(client, "Entity: %d, classname: %s, Modelname: %s", EntIndex, classname, modelname);
		PrintToConsole(client, "Entity: %d, collision: %d, spawnflags: %d, solid: %d", EntIndex, collisiongroup, spawnflags, solid);

	}
	return Plugin_Handled;
}



public Action CommandPropCollide(int client, int args)
{
	new Ent = GetClientAimTarget(client, false);
	if (Ent != -1 && IsValidEntity(Ent))
	{
		new String:classname[32];
		GetEdictClassname(Ent, classname, 32);

		new String:modelname[130];
		new String:solid[130];
		int collisiongroup, spawnflags;

		GetEntPropString(Ent, Prop_Data, "m_ModelName", modelname, 130);
		GetEntProp(Ent, Prop_Data, "m_CollisionGroup", collisiongroup);
		GetEntProp(Ent, Prop_Data, "m_spawnflags", spawnflags);
		GetEntPropString(Ent, Prop_Data, "m_nSolidType", solid, 130);


		SetEntProp(Ent, Prop_Data, "m_spawnflags", 4);
		SetEntProp(Ent, Prop_Send, "m_CollisionGroup", 6);
//		SetEntProp(Ent, Prop_Send, "m_nSolidType", 9218);   //new


		AcceptEntityInput(Ent, "DisableCollision", 0, 0);
//		AcceptEntityInput(Ent, "kill", 0, 0);

		DispatchKeyValue(Ent, "targetname", "test");
//		DispatchKeyValue(Ent, "model", "models/d/d_s01.mdl");
		DispatchKeyValue(Ent, "CCollisionProperty", "0");
//		DispatchKeyValueFloat(Ent, "solid", 2.0);


/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(Ent);
		PrintToConsole(client, "Entity: %d, solid: %d", Ent, solidtype);
		Entity_SetSolidType(Ent, 2);
*/

		ChangeEdictState(Ent, 0);

		new Float:origin[3];
		GetClientAbsOrigin(client, origin);
		origin[2] += 20.0;
		TeleportEntity(Ent, origin, NULL_VECTOR, NULL_VECTOR);

		PrintToConsole(client, "Entity: %d, classname: %s, Modelname: %s", Ent, classname, modelname);
		PrintToConsole(client, "Entity: %d, collision: %d, spawnflags: %d, solid: %d", Ent, collisiongroup, spawnflags, solid);


		GetPropInfo(client, Ent);
	}
	return Plugin_Handled;
}



bool IsAccessGranted( int client )
{
    new bool:granted = true;

    // client = 0 means server, server always got access
    if ( client != 0 && GetConVarInt( g_cvar_adminonly ) > 0 )
    {
        if ( !GetAdminFlag( GetUserAdmin( client ), Admin_Generic, Access_Effective ) )
        {
            ReplyToCommand( client, "[Left FORT Dead] Server set only admin can use this command" );
            granted = false;
        }
    }

    if ( granted )
    {
        if ( GetConVarInt( g_cvar_enabled ) <= 0 )
        {
            ReplyToCommand( client, "MOD disabled on server side" );
            granted = false;
        }
    }

    return granted;
}



public Action RemoveTargetEntity( int client, int args )
{
    if ( !IsAccessGranted( client ) )
    {
        return Plugin_Handled;
    }

    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot spawn entity over rcon/server console" );
        return Plugin_Handled;
    }

    new index = -1;
    if ( args > 0 )
    {
        new String:param[128];
        GetCmdArg( 1, param, sizeof(param) );
        index = StringToInt( param );
    }
    else
    {
        index = GetClientAimedLocationData( client, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR );
    }

    if ( index > MaxClients )
    {
	new ent;
	ent = EntRefToEntIndex(ent);

	// only grab physics entities
	new String:edictname[128];
	GetEdictClassname(ent, edictname, 128);

	//if(strncmp("prop_", edictname, 5, false)==0 || strncmp("weapon_", edictname, 5, false)==0){  //filtering out prop_ and weapon_! -glub (works!)
	//(StrEqual(edictname, "prop_physics") || StrEqual(edictname, "prop_physics_multiplayer"))


	RemoveEdict( index );

	PrintToConsole( player, "Entity (index %i) removed", index );
	//}
    }
    else if ( index > 0 )
    {
        PrintToConsole( player, "Cannot remove player (index %i)", index );
    }
    else
    {
        PrintToConsole( player, "Nothing picked to remove" );
    }

    return Plugin_Handled;
}




public Action Rotate_Entity( int client, int args )
{
    if ( !IsAccessGranted( client ) )
    {
        return Plugin_Handled;
    }

    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot do over rcon/server console" );
        return Plugin_Handled;
    }

    new index = GetClientAimedLocationData( client, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR );
    if ( index <= 0 )
    {
        ReplyToCommand( player, "Nothing picked to rotate" );
        return Plugin_Handled;
    }

    new String:param[128];

    new Float:degree;
    if ( args > 0 )
    {
        GetCmdArg( 1, param, sizeof(param) );
        degree = StringToFloat( param );
    }

    GetEdictClassname( index, param, 128 );

    decl Float:angles[3];
    GetEntPropVector(index, Prop_Data, "m_angRotation", angles);
    RotateYaw(angles, degree);

    DispatchKeyValueVector(index, "Angles", angles);

    return Plugin_Handled;
}



public Action Rotate_EntityRoll( int client, int args )
{
    if ( !IsAccessGranted( client ) )
    {
        return Plugin_Handled;
    }

    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot do over rcon/server console" );
        return Plugin_Handled;
    }

    new index = GetClientAimedLocationData( client, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR );
    if ( index <= 0 )
    {
        ReplyToCommand( player, "Nothing picked to rotate" );
        return Plugin_Handled;
    }

    new String:param[128];

    new Float:degree;
    if ( args > 0 )
    {
        GetCmdArg( 1, param, sizeof(param) );
        degree = StringToFloat( param );
    }

    GetEdictClassname( index, param, 128 );

    decl Float:angles[3];
    GetEntPropVector(index, Prop_Data, "m_angRotation", angles);
    RotateRoll(angles, degree);

    DispatchKeyValueVector(index, "Angles", angles);

    return Plugin_Handled;
}



public Action Rotate_EntityPitch( int client, int args )
{
    if ( !IsAccessGranted( client ) )
    {
        return Plugin_Handled;
    }

    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot do over rcon/server console" );
        return Plugin_Handled;
    }

    new index = GetClientAimedLocationData( client, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR );
    if ( index <= 0 )
    {
        ReplyToCommand( player, "Nothing picked to rotate" );
        return Plugin_Handled;
    }

    new String:param[128];

    new Float:degree;
    if ( args > 0 )
    {
        GetCmdArg( 1, param, sizeof(param) );
        degree = StringToFloat( param );
    }

    GetEdictClassname( index, param, 128 );

    decl Float:angles[3];
    GetEntPropVector(index, Prop_Data, "m_angRotation", angles);
    RotatePitch(angles, degree);

    DispatchKeyValueVector(index, "Angles", angles);

    return Plugin_Handled;
}

RotateYaw( Float:angles[3], Float:degree )
{
    decl Float:direction[3], Float:normal[3];
    GetAngleVectors( angles, direction, NULL_VECTOR, normal );

    new Float:sin = Sine( degree * 0.01745328 );     // Pi/180
    new Float:cos = Cosine( degree * 0.01745328 );
    new Float:a = normal[0] * sin;
    new Float:b = normal[1] * sin;
    new Float:c = normal[2] * sin;
    new Float:x = direction[2] * b + direction[0] * cos - direction[1] * c;
    new Float:y = direction[0] * c + direction[1] * cos - direction[2] * a;
    new Float:z = direction[1] * a + direction[2] * cos - direction[0] * b;
    direction[0] = x;
    direction[1] = y;
    direction[2] = z;

    GetVectorAngles( direction, angles );

    decl Float:up[3];
    GetVectorVectors( direction, NULL_VECTOR, up );

    new Float:roll = GetAngleBetweenVectors( up, normal, direction );
    angles[2] += roll;
}
RotatePitch( Float:angles[3], Float:degree )  			// !!! TODO !!! unfinished, doesn't work as intended. I suck at maths. -glub
{
	angles[1] += degree;
}

RotateRoll( Float:angles[3], Float:degree )
{
    angles[2] += degree;
}

//---------------------------------------------------------
// get position, angles and normal of aimed location if the parameters are not NULL_VECTOR
// return the index of entity you aimed
//---------------------------------------------------------
GetClientAimedLocationData( client, Float:position[3], Float:angles[3], Float:normal[3] )
{
    new index = -1;

    new player = GetPlayerIndex( client );

    decl Float:_origin[3], Float:_angles[3];
    GetClientEyePosition( player, _origin );
    GetClientEyeAngles( player, _angles );

    new Handle:trace = TR_TraceRayFilterEx( _origin, _angles, MASK_ALL, RayType_Infinite, TraceEntityFilterPlayers );  //was MASK_SOLID_BRUSHONLY -glub
    if( !TR_DidHit( trace ) )
    {
        ReplyToCommand( player, "Failed to pick the aimed location" );
        index = -1;
    }
    else
    {
        TR_GetEndPosition( position, trace );
        TR_GetPlaneNormal( trace, normal );
        angles[0] = _angles[0];
        angles[1] = _angles[1];
        angles[2] = _angles[2];

        index = TR_GetEntityIndex( trace );
    }
    CloseHandle( trace );
    return index;
}

//---------------------------------------------------------
// return 0 if it is a server
//---------------------------------------------------------
GetPlayerIndex( int client )
{
    if ( client == 0 && !IsDedicatedServer() )
    {
        return 1;
    }

    return client;
}

Float:GetAngleBetweenVectors( const Float:vector1[3], const Float:vector2[3], const Float:direction[3] )
{
    decl Float:vector1_n[3], Float:vector2_n[3], Float:direction_n[3], Float:cross[3];
    NormalizeVector( direction, direction_n );
    NormalizeVector( vector1, vector1_n );
    NormalizeVector( vector2, vector2_n );
    new Float:degree = ArcCosine( GetVectorDotProduct( vector1_n, vector2_n ) ) * 57.29577951;   // 180/Pi
    GetVectorCrossProduct( vector1_n, vector2_n, cross );

    if ( GetVectorDotProduct( cross, direction_n ) < 0.0 )
    {
        degree *= -1.0;
    }

    return degree;
}


public bool:TraceEntityFilterPlayers(entity, contentsMask, any:data)
{
    return entity > MaxClients && entity != data;
}


public bool:TraceFilterIgnorePlayers(entity, contentsMask, any:client)
{
    if(entity >= 1 && entity <= MaxClients)
    {
        return false;
    }

    return true;
}


/*
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	for(new i=1; i<=MaxClients; i++)
	{
		iPropNo[i] = 0;
	}
}
*/