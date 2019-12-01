#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <clientprefs>
#include <adminmenu>
#include <entity_prop_stocks.inc>
#include <nt_entitytools>

#undef REQUIRE_PLUGIN
#include <nt_menu>

#if !defined DEBUG
	#define DEBUG 0
#endif
#pragma semicolon 1
#define NEO_MAX_CLIENTS 32
#define MAX_PROPS_PER_PLAYER 10
#define PLUGIN_VERSION "20191021"

Handle g_cvar_props_enabled, g_cvar_restrict_alive, g_cvar_give_initial_credits, g_cvar_credits_replenish, g_cvar_score_as_credits, g_cvar_opt_in_mode = INVALID_HANDLE;
Handle cvMaxPropsCreds = INVALID_HANDLE; // maximum credits given
Handle cvPropMaxTTL = INVALID_HANDLE; // maximum time to live before prop gets auto removed
Handle g_hPropPrefCookie = INVALID_HANDLE;
Handle g_cvar_props_oncapture, g_cvar_props_onghostpickup, g_cvar_props_oncapture_nodongs, gTimer = INVALID_HANDLE;
bool gb_PausePropSpawning;
int g_AttachmentEnt[NEO_MAX_CLIENTS+1] = {-1, ...}; // strapped on prop
Handle gNoDrawTimer[NEO_MAX_CLIENTS+1] = {INVALID_HANDLE, ...};

// Menu setup
TopMenuObject g_hTopPropsMainMenu_topmenuobj = INVALID_TOPMENUOBJECT;
TopMenu g_hTopMenu; // handle to the nt_menu plugin topmenu
Handle g_hPropsStaticMenu, g_hPropsPhysicsMenu, g_hSpawnDongMenu, g_hStrapDongMenu, g_hPrefsMenu, g_hPropertiesMenu; // our main props menus

// [0] holds virtual credits, [2] current score credits, [3] maximum credits level reached
int g_RemainingCreds[NEO_MAX_CLIENTS+1][3];
#define VIRT_CRED 0
#define SCORE_CRED 1
#define MAX_CRED 2

int g_PropHistory[NEO_MAX_CLIENTS+1][MAX_PROPS_PER_PLAYER]; // history of all props spawned per player
int g_PropCursor[NEO_MAX_CLIENTS+1]; // holds the last spawned entity by client
bool g_bClientWantsProps[NEO_MAX_CLIENTS+1];
int g_GrabbedProp[NEO_MAX_CLIENTS+1];
Handle g_updTimer = INVALID_HANDLE;
bool g_baPropIsBeingGrabbed;

// WARNING: the custom files require the sm_downloader plugin to force clients to download them
// otherwise, have to add all custom files to downloads table ourselves with AddFileToDownloadsTable()
new const String:gs_dongs[][] = {
	"models/d/d_s02.mdl", //small
	"models/d/d_b02.mdl", //big
	"models/d/d_h02.mdl", //huge
	"models/d/d_g02.mdl", //gigantic
	"models/d/d_mh02.mdl" }; //megahuge

new const g_PropPrice[] = { 1, 3, 6, 9, 15 };

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
	"models/nt/props_warehouse/tire.mdl",
};


new const String:gs_allowed_dynamic_models[][] = {
	"models/nt/a_lil_tiger.mdl",
	"models/nt/props_office/rubber_duck.mdl",
	"models/logo/jinrai_logo.mdl",
	"models/logo/nsf_logo.mdl",
	"models/nt/props_nature/koi_fisha.mdl",
	"models/nt/props_vehicles/hachikoma_dynamic.mdl"
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

public Plugin:myinfo =
{
	name = "NEOTOKYO props spawner.",
	author = "glub",
	description = "Allows players to spawn props.",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
};

/*
TODO:
→ rework logic for credits, might be broken
→ spawn props with random coords around a target (player) and velocity, towards their position
→ add sparks to props spawned and maybe a squishy sound for in range with TE_SendToAllInRange
→ save credits in sqlite db for longer term?
→ figure out how to make attached props change their material to cloak (need prop_ornament? flags? DispatchEffect? m_hEffectEntity!? apparently CTEEffectDispatch is unrelated)
→ use ProcessTargetString to target a player by name

KNOWN ISSUES:
-> AFAIK the TE cannot be destroyed by timer, so client preference is very limited, ie. if someone asks for a big scale model that is supposed to be auto-removed
   we can't use a TE because they don't get affected by timers, so regular physics_prop take precedence. Same for dynamic props, cannot have them as TempEnts.
FIXME: debug why player are not spawning TE when opted-out clients are around
TODO: Trigger_multiple
TODO: use tempent Sprite Spray or simply env_spritetrail (for Marterzon)
TODO: move from sm_downloader to downloadtables here
TODO: parse available models from a text file
TODO: make sure props (d too) are not solid to avoid obstructing bullets -> use a refactored create_entity functions
also make sure they don't block line of fire while being grabbed
FIXME: improve static props menu, not enough items!

FIXME: if supports can cloak, we need to cloak attached props too now!
*/

public OnPluginStart()
{
	RegConsoleCmd("sm_props", ConCommand_Props, "Opt-in custom props.");
	RegConsoleCmd("sm_noprops", Command_NoProps, "Opt-out of custom props.");
	RegConsoleCmd("sm_props_spawn", ConCommand_PropSpawn, "Spawns a prop.");
	RegConsoleCmd("sm_dick", Command_Dong_Spawn, "Spawns a dick [scale 1-5] [1 for static prop]");
	RegConsoleCmd("sm_strapdong", Command_Strap_Dong, "Strap a dong onto [me|team|all].");

	RegConsoleCmd("sm_props_rotate_skin", ConCommand_Props_Rotate_Skin, "Change targeted prop's skin");
	RegConsoleCmd("sm_props_rotate_color", ConCommand_Props_Rotate_Color, "Change targeted prop's colors");
	RegConsoleCmd("sm_props_rotate_transparency", ConCommand_Props_Rotate_Transparency, "Change targeted prop's transparency");
	RegConsoleCmd("sm_props_rotate_angles", ConCommand_Props_Rotate_Angles, "Change targeted prop's angles");
	RegConsoleCmd("sm_props_rotate_position", ConCommand_Props_Rotate_Position, "Change targeted prop's position");

	g_hPropPrefCookie = FindClientCookie("wants-props");
	if (g_hPropPrefCookie == INVALID_HANDLE)
		g_hPropPrefCookie = RegClientCookie("wants-props", "player opted to have fun with props", CookieAccess_Protected);

	RegConsoleCmd("sm_props_help", Command_Print_Help, "Prints all props-related commands.");
	RegConsoleCmd("sm_props_pause", Command_Pause_Props_Spawning, "Prevent any further custom prop spawning until end of round.");
	RegConsoleCmd("sm_props_nothx", Command_Hate_Props_Toggle, "Toggle your preference to not see custom props wherever possible.");
	RegConsoleCmd("sm_props_status", Command_Status, "Display who is seeing props or not.");

	// conditions
	g_cvar_props_onghostpickup = CreateConVar("sm_props_onghostpickup", "0", "Picking up the ghost is exciting,", FCVAR_NONE, true, 0.0, true, 1.0 );
	g_cvar_props_oncapture = CreateConVar("sm_props_oncapture", "0", "Fireworks on ghost capture.", FCVAR_NONE, true, 0.0, true, 1.0 );
	g_cvar_props_oncapture_nodongs = CreateConVar("sm_props_oncapture_nodongs", "1", "No dong firework on capture.", FCVAR_NONE, true, 0.0, true, 1.0 );

	// general restrictions
	g_cvar_props_enabled = CreateConVar( "sm_props_enabled", "1",
										"0: disable custom props spawning, 1: enable custom props spawning",
										FCVAR_NONE, true, 0.0, true, 1.0 );

	g_cvar_restrict_alive = CreateConVar( "sm_props_restrict_alive", "0",
										"0: spectators can spawn props too. 1: only living players can spawn props",
										FCVAR_NONE, true, 0.0, true, 1.0 );

	g_cvar_opt_in_mode = CreateConVar( "sm_props_opt_in_mode", "1",
										"0: players have to opt-out to not see custom props. 1: players have to opt-in in order to see custom props",
										FCVAR_NONE, true, 0.0, true, 1.0 );


	// Credit system
	RegConsoleCmd("sm_props_credit_status", Command_Credit_Status, "List all player credits to spawn props.");

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

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	// AddCommandListener(OnSpecCmd, "spec_next"); // probably not needed
	// AddCommandListener(OnSpecCmd, "spec_prev"); // probably not needed
	AddCommandListener(OnSpecCmd, "spec_mode");
	HookEvent("game_round_start", event_RoundStart);

	// Debug commands
	RegAdminCmd("sm_props_givescore", Command_Give_Score, ADMFLAG_SLAY, "DEBUG: add 20 frags to score");
	RegAdminCmd("sm_props_set_credits", Command_Set_Credits_For_Client, ADMFLAG_SLAY, "Gives target player virtual credits in order to spawn props.");
	RegAdminCmd("sm_props_te", Command_Spawn_TE_Prop, ADMFLAG_SLAY, "DEBUG: Spawn TE dong");
	RegAdminCmd("sm_props_fireworks", Command_Spawn_TEST_fireworks, ADMFLAG_SLAY, "DEBUG: test fireworks");

	AutoExecConfig(true, "nt_props");

	// SetCookiePrefabMenu(g_hPropPrefCookie, CookieMenu_OnOff_Int, "Props Preferences", MyCookieMenuHandler);

	// late loading
	for (new i = MaxClients; i > 0; --i)
	{
		if (!IsValidClient(i) || !IsClientConnected(i))
			continue;

		if (!AreClientCookiesCached(i))
			continue;

		OnClientCookiesCached(i);
	}

	// prebuild menus
	g_hPropsPhysicsMenu = BuildMainPropsMenu(1);
	g_hPropsStaticMenu = BuildMainPropsMenu(2);
	g_hSpawnDongMenu = BuildMainPropsMenu(3);
	g_hStrapDongMenu = BuildMainPropsMenu(4);
	g_hPrefsMenu = BuildMainPropsMenu(5);
	g_hPropertiesMenu = BuildMainPropsMenu(6);

	// Is our menu already loaded?
	TopMenu topmenu;
	if (LibraryExists("nt_menu") && ((topmenu = GetNTTopMenu()) != null))
	{
		OnNTMenuReady(topmenu);
	}
	else
	{
		// library missing, we build our own
		g_hTopMenu = CreateTopMenu(TopMenuCategory_Handler);
		BuildTopPropsMenu();
	}

}


public OnNTMenuReady(Handle aTopMenu)
{
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

	// Block us from being called twice
	if (topmenu == g_hTopMenu)
		return;

	// Save the Handle
	g_hTopMenu = topmenu;

	BuildTopPropsMenu();
}

// object ids for our items added to categories
TopMenuObject g_tmo_propsphys, g_tmo_propsdyn, g_tmo_dong, g_tmo_strap, g_tmo_prefs, g_tmo_props_props = INVALID_TOPMENUOBJECT;

void BuildTopPropsMenu()
{
	g_hTopPropsMainMenu_topmenuobj = FindTopMenuCategory(g_hTopMenu, "Props"); // get the category provided by nt_menu plugin

	if (g_hTopPropsMainMenu_topmenuobj != INVALID_TOPMENUOBJECT)
	{
		// AddToTopMenu(g_hTopMenu, "nt_menu", TopMenuObject_Item, TopCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "nt_menu", 0);

		// in our plugin, we have one category for ourselves, so we can add all menus there
		g_tmo_propsphys = g_hTopMenu.AddItem("sm_props_physics", TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_props");
		g_tmo_propsdyn = g_hTopMenu.AddItem("sm_props_dynamic", TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_props");
		g_tmo_dong = g_hTopMenu.AddItem("sm_dick", TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_dick");
		g_tmo_strap = g_hTopMenu.AddItem("sm_strapdong", TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_strapdong");
		g_tmo_prefs = g_hTopMenu.AddItem("sm_props_prefs", TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_props_prefs");
		g_tmo_props_props = g_hTopMenu.AddItem("sm_props_properties", TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_props_properties");
		return;
	}

	// didn't find categories, must be missing nt_menu plugin, so build our own category and attach to it
	g_hTopPropsMainMenu_topmenuobj = g_hTopMenu.AddCategory("Props", TopMenuCategory_Handler);

	g_tmo_propsphys = AddToTopMenu(g_hTopMenu, "sm_props_physics", TopMenuObject_Item, TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_props");
	g_tmo_propsdyn = AddToTopMenu(g_hTopMenu, "sm_props_dynamic", TopMenuObject_Item, TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_props");
	g_tmo_dong = AddToTopMenu(g_hTopMenu, "sm_dick", TopMenuObject_Item, TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_dick");
	g_tmo_strap = AddToTopMenu(g_hTopMenu, "sm_strapdong", TopMenuObject_Item, TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_strapdong");
	g_tmo_prefs = AddToTopMenu(g_hTopMenu, "sm_props_prefs", TopMenuObject_Item, TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_props_prefs");
	g_tmo_props_props = AddToTopMenu(g_hTopMenu, "sm_props_properties", TopMenuObject_Item, TopMenuCategory_Handler, g_hTopPropsMainMenu_topmenuobj, "sm_props_properties");
	SetTopMenuTitleCaching(g_hTopMenu, false); // seems to fix "Preferences" being the de facto title on our "Props" category
}



public TopMenuCategory_Handler (Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if ((action == TopMenuAction_DisplayOption) || (action == TopMenuAction_DisplayTitle))
	{
		// GetTopMenuObjName(topmenu, object_id, buffer, maxlength);

		if (object_id == INVALID_TOPMENUOBJECT)
			Format(buffer, maxlength, "Neotokyo Props Menu", param);
		if (object_id == g_tmo_propsdyn)
			Format(buffer, maxlength, "%s", "Spawn Static Props", param);
		if (object_id == g_tmo_propsphys)
			Format(buffer, maxlength, "%s", "Spawn Physics Props", param);
		if (object_id == g_tmo_dong)
			Format(buffer, maxlength, "%s", "Spawn Dongs", param);
		if (object_id == g_tmo_strap)
			Format(buffer, maxlength, "%s", "Strap Dongs", param);
		if (object_id == g_tmo_prefs)
			Format(buffer, maxlength, "%s", "Preferences", param);
		if (object_id == g_tmo_props_props)
			Format(buffer, maxlength, "%s", "Change props properties", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		if (object_id == g_tmo_propsdyn)
			DisplayMenu(g_hPropsStaticMenu, param, 20);
		if (object_id == g_tmo_propsphys)
			DisplayMenu(g_hPropsPhysicsMenu, param, 20);
		if (object_id == g_tmo_dong)
			DisplayMenu(g_hSpawnDongMenu, param, 20);
		if (object_id == g_tmo_strap)
			DisplayMenu(g_hStrapDongMenu, param, 20);
		if (object_id == g_tmo_prefs)
			DisplayMenu(g_hPrefsMenu, param, 20);
		if (object_id == g_tmo_props_props)
			DisplayMenu(g_hPropertiesMenu, param, 20);
	}
}

public Menu BuildMainPropsMenu(int type)
{
	Menu menu;

	switch (type)
	{
		case 6:
		{
			menu = new Menu(PropsPrefsMenuHandler, MENU_ACTIONS_ALL);
			menu.SetTitle("Prop properties");
			menu.AddItem("b", "Change target prop skin");
			menu.AddItem("c", "Change target prop colors");
			menu.AddItem("d", "Change target prop transparency");
			menu.AddItem("e", "Change target prop rotation");
			menu.AddItem("f", "Change target prop position");
			menu.ExitButton = true;
			menu.ExitBackButton = true;
		}
		case 5:
		{
			menu = new Menu(PropsPrefsMenuHandler, MENU_ACTIONS_ALL);
			menu.SetTitle("Preferences");
			menu.AddItem("a", "Set preference");
			menu.ExitButton = true;
			menu.ExitBackButton = true;
		}
		case 1:
		{
			menu = new Menu(PhysicsPropsSpawningMenuHandler, MENU_ACTIONS_ALL);
			menu.SetTitle("Spawn a physics prop:");
			for (int i = 0; i < sizeof(gs_allowed_physics_models); i++)
			{
				char item_name[PLATFORM_MAX_PATH];
				int index = FindCharInString(gs_allowed_physics_models[i], '/', true);

				do
				{
					++index;
					StrCat(item_name, strlen(gs_allowed_physics_models[i]) - index + 1, gs_allowed_physics_models[i][index]);
				}
				while(index <= strlen(gs_allowed_physics_models[i]));

				SplitString(item_name, ".mdl", item_name, sizeof(item_name));
				ReplaceString(item_name, sizeof(item_name), "_", " ", false);

				#if DEBUG
				PrintToServer("Adding phsysics %s", item_name);
				#endif
				menu.AddItem(gs_allowed_physics_models[i], item_name);
			}
			menu.ExitButton = true;
			menu.ExitBackButton = true;
		}
		case 2:
		{
			menu = new Menu(DynamicPropsSpawningMenuHandler, MENU_ACTIONS_ALL);
			menu.SetTitle("Spawn a static prop:");
			for (int i = 0; i < sizeof(gs_allowed_dynamic_models); i++)
			{
				char item_name[PLATFORM_MAX_PATH];
				int index = FindCharInString(gs_allowed_dynamic_models[i], '/', true);

				do
				{
					index++;
					StrCat(item_name, strlen(gs_allowed_dynamic_models[i]) - index + 1, gs_allowed_dynamic_models[i][index]);
				}
				while(index <= strlen(gs_allowed_dynamic_models[i]));

				SplitString(item_name, ".mdl", item_name, sizeof(item_name));
				ReplaceString(item_name, sizeof(item_name), "_", " ", false);

				#if DEBUG
				PrintToServer("Adding dynamic %s", item_name);
				#endif
				menu.AddItem(gs_allowed_dynamic_models[i], item_name);
			}
			menu.ExitButton = true;
			menu.ExitBackButton = true;
		}
		case 3:
		{
			menu = new Menu(DongSpawningMenuHandler, MENU_ACTIONS_ALL);
			menu.SetTitle("Spawn a dong:");
			menu.AddItem("0", "small dong");
			menu.AddItem("1", "medium dong");
			menu.AddItem("2", "big dong");
			menu.AddItem("3", "huge dong");
			menu.AddItem("4", "mega-huge dong");
			menu.AddItem("5", "small dong (static)");
			menu.AddItem("6", "medium dong (static)");
			menu.AddItem("7", "big dong (static)");
			menu.AddItem("8", "huge dong (static)");
			menu.AddItem("9", "mega-huge dong (static)");
			menu.ExitButton = true;
			menu.ExitBackButton = true;
		}
		case 4:
		{
			menu = new Menu(StrapDongMenuHandler, MENU_ACTIONS_ALL);
			menu.SetTitle("Strap dongs on:");
			menu.AddItem("a", "Strap dong on yourself");
			menu.AddItem("b", "strap dong on your team");
			menu.AddItem("c", "strap dong on everybody");
			menu.ExitButton = true;
			menu.ExitBackButton = true;
		}
		default:
		{
			ThrowError("Wrong BuildMainPropsMenu() type called!");
		}
	}
	return menu;
}


// this is used for two different menus, because why not
public int PropsPrefsMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			// CloseHandle(menu); // breaks toggles?
			//delete menu; (should we here?)
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_Display:
		{
			char title[255];
			Format(title, sizeof(title), "Props spawning preferences:", param1);

			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(title);
		}
		case MenuAction_Select:
		{
			decl String:info[2];
			GetMenuItem(menu, param2, info, sizeof(info));

			switch (info[0])
			{
				case 'a': // in case we add more fine grain control later
				{
					ToggleCookiePreference(param1);
					DisplayMenu(g_hPrefsMenu, param1, 20);
				}
				case 'b': // a different menu is handled here!
				{
					FakeClientCommand(param1, "sm_props_rotate_skin");
					DisplayMenu(g_hPropertiesMenu, param1, 20);
				}
				case 'c':
				{
					FakeClientCommand(param1, "sm_props_rotate_colors");
					DisplayMenu(g_hPropertiesMenu, param1, 20);
				}
				case 'd':
				{
					FakeClientCommand(param1, "sm_props_rotate_transparency");
					DisplayMenu(g_hPropertiesMenu, param1, 20);
				}
				case 'e':
				{
					FakeClientCommand(param1, "sm_props_rotate_angles");
					DisplayMenu(g_hPropertiesMenu, param1, 20);
				}
				case 'f':
				{
					FakeClientCommand(param1, "sm_props_rotate_position");
					DisplayMenu(g_hPropertiesMenu, param1, 0);
				}
				default:
				{
					CloseHandle(g_hTopMenu);
					return 0;
				}
			}
		}

		case MenuAction_DisplayItem:
		{
			char info[32];
			menu.GetItem(param2, info, sizeof(info));

			char display[29];

			if (StrEqual(info, "a")) // toggle item
			{
				Format(display, sizeof(display), "Custom props are: [%s]", (g_bClientWantsProps[param1] ? "enabled" : "disabled" ));
				return RedrawMenuItem(display);
			}
			return 0;
		}
	}
	return 0;
}


public int PhysicsPropsSpawningMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char title[255];
			Format(title, sizeof(title), "Spawn physics props. Credits remaining %d", g_RemainingCreds[param1][VIRT_CRED]);

			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(title);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_Select:
		{
			decl String:info[PLATFORM_MAX_PATH];
			GetMenuItem(menu, param2, info, sizeof(info));
			FakeClientCommand(param1, "sm_props_spawn %s", info);
			DisplayMenu(menu, param1, 20);
		}
	}
	return 0;
}


public int DynamicPropsSpawningMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char title[255];
			Format(title, sizeof(title), "Spawn dynamic props: Credits remaining: %d", g_RemainingCreds[param1][VIRT_CRED]);

			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(title);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_Select:
		{
			decl String:info[PLATFORM_MAX_PATH];
			GetMenuItem(menu, param2, info, sizeof(info));
			FakeClientCommand(param1, "sm_prop_spawn %s", info);
			DisplayMenu(menu, param1, 20);
		}
	}
	return 0;
}


public int DongSpawningMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Spawn dongs. Credits remaining: %d.", g_RemainingCreds[param1][VIRT_CRED]);

			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(buffer);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_Select:
		{
			decl String:info[2];
			GetMenuItem(menu, param2, info, sizeof(info));
			switch(info[0])
			{
				case '0':
				{
					FakeClientCommand(param1, "sm_dick 1");
					DisplayMenu(menu, param1, 20);
				}
				case '1':
				{
					FakeClientCommand(param1, "sm_dick 2");
					DisplayMenu(menu, param1, 20);
				}
				case '2':
					FakeClientCommand(param1, "sm_dick 3");
				case '3':
					FakeClientCommand(param1, "sm_dick 4");
				case '4':
					FakeClientCommand(param1, "sm_dick 5");
				case '5':
				{
					FakeClientCommand(param1, "sm_dick 1 1");
					DisplayMenu(menu, param1, 20);
				}
				case '6':
				{
					FakeClientCommand(param1, "sm_dick 2 1");
					DisplayMenu(menu, param1, 20);
				}
				case '7':
					FakeClientCommand(param1, "sm_dick 3 1");
				case '8':
					FakeClientCommand(param1, "sm_dick 4 1");
				case '9':
					FakeClientCommand(param1, "sm_dick 5 1");
				default:
				{
					// CloseHandle(g_hTopMenu);
					return 0;
				}
			}
		}

		case MenuAction_DrawItem:
		{
			if (IsAdmin(param1)) // bypass credits system
				return 0;

			char info[2];
			menu.GetItem(param2, info, sizeof(info));
			int price = StringToInt(info[0]);

			if (price > 4)
				price -= 5;

			if (!hasEnoughCredits(param1, g_PropPrice[price]))
				return ITEMDRAW_DISABLED;
			return ITEMDRAW_DEFAULT;
		}

		case MenuAction_DisplayItem:
		{
			if (IsAdmin(param1)) // bypass credits system
				return 0;

			char info[2], display[64];
			menu.GetItem(param2, info, sizeof(info), _, display, sizeof(display));
			int price = StringToInt(info[0]) + 1;

			if (price > 4)
				price -= 5;

			Format(display, sizeof(display), "%s (need %d)", display, price);
			return RedrawMenuItem(display);
		}
	}
	return 0;
}


public int StrapDongMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Display:
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "Strap dongs. Credits remaining: %d", g_RemainingCreds[param1][VIRT_CRED]);

			Panel panel = view_as<Panel>(param2);
			panel.SetTitle(buffer);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_Select:
		{
			decl String:info[2];
			GetMenuItem(menu, param2, info, sizeof(info));
			switch(info[0])
			{
				case 'a':
					FakeClientCommand(param1, "sm_strapdong me");
				case 'b':
					FakeClientCommand(param1, "sm_strapdong team");
				case 'c':
					FakeClientCommand(param1, "sm_strapdong all");
				default:
				{
					// CloseHandle(g_hTopMenu);
					return 0;
				}
			}
			return 0;
		}
		case MenuAction_DrawItem:
		{
			if (IsAdmin(param1)) // bypass credits system
				return ITEMDRAW_DEFAULT;

			char info[2];
			menu.GetItem(param2, info, sizeof(info));

			switch(info[0])
			{
				case 'a':
				{
					if (!hasEnoughCredits(param1, 1))
						return ITEMDRAW_DISABLED;

					return ITEMDRAW_DEFAULT;
				}
				case 'b':
				{
					int price;
					int affected[NEO_MAX_CLIENTS+1];
					ComputePriceForProp(param1, 1, price, affected, false); // kind of ugly, we recompute both for DrawItem and DisplayItem...

					if (!hasEnoughCredits(param1, price))
						return ITEMDRAW_DISABLED;

					return ITEMDRAW_DEFAULT;
				}
				case 'c':
				{
					int price;
					int affected[NEO_MAX_CLIENTS+1];
					ComputePriceForProp(param1, 2, price, affected, false);

					if (!hasEnoughCredits(param1, price))
						return ITEMDRAW_DISABLED;

					return ITEMDRAW_DEFAULT;
				}
			}
		}
		case MenuAction_DisplayItem:
		{
			char info[2], display[64];
			menu.GetItem(param2, info, sizeof(info), _, display, sizeof(display));

			switch(info[0])
			{
				case 'b':
				{
					if (IsAdmin(param1)) // bypass credits system
						return 0;

					int price;
					int affected[NEO_MAX_CLIENTS+1];
					ComputePriceForProp(param1, 1, price, affected, false); // called many times here :/

					Format(display, sizeof(display), "%s (need %d)", display, price);

					return RedrawMenuItem(display);
				}
				case 'c':
				{
					if (IsAdmin(param1)) // bypass credits system
						return 0;

					int price;
					int affected[NEO_MAX_CLIENTS+1];
					ComputePriceForProp(param1, 2, price, affected, false); // called many times here :/

					Format(display, sizeof(display), "%s (need %d)", display, price);

					return RedrawMenuItem(display);
				}
			}
		}
	}
	return 0;
}


/*==================================
		Client preferences
==================================*/

stock bool Has_Anyone_Opted_Out()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !g_bClientWantsProps[i]) // at least one person doesn't want to see the props
		{
			#if DEBUG
			PrintToServer("[nt_props] DEBUG: Client %s has opted out of props, let's hide them!", GetClientOfUserId(i));
			#endif
			return true;
		}
	}
	#if DEBUG
	PrintToServer("[nt_props] DEBUG: Nobody opted out of props.");
	#endif
	return false;
}


public Action Command_Status(int client, int args)
{
	char optedin[1000], optedout[1000], name[MAX_NAME_LENGTH];
	int countin, countout;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsClientConnected(i))
			continue;

		if (g_bClientWantsProps[i])
		{
			Format(name, sizeof(name), "%N\n", i);
			StrCat(optedin, sizeof(optedin), name);
			countin++;
		}
		else
		{
			char cookie[2];
			GetClientCookie(i, g_hPropPrefCookie, cookie, sizeof(cookie));
			Format(name, sizeof(name), "%N%s\n", i, ((cookie[0] != '\0' && !StringToInt(cookie)) ? " (explicitly)" : "" ));
			StrCat(optedout, sizeof(optedout), name);
			countout++;
		}
	}
	PrintToConsole(client, "Props are active for:\n%s", (countin ? optedin : "NOBODY! D:"));
	PrintToConsole(client, "Props are inactive for:\n%s", (countout ? optedout : "NOBODY! :D"));


	return Plugin_Handled;
}

// public MyCookieMenuHandler(client, CookieMenuAction:action, any:info, String:buffer[], maxlen)
// {
// 	switch (action)
// 	{
// 		case CookieMenuAction_DisplayOption:
// 		{
// 		}
// 		case CookieMenuAction_SelectOption:
// 		{
// 			OnClientCookiesCached(client);
// 		}
// 	}
// }


public OnClientCookiesCached(int client)
{
	ReadCookies(client);
}


// This might be redundant as OnClientCookiesCached is called on connect anyway?
public OnClientPostAdminCheck(int client)
{
	if(!GetConVarBool(g_cvar_props_enabled))
	{
		//g_bClientWantsProps[client] = false;
		return;
	}

	if (AreClientCookiesCached(client))
	{
		ReadCookies(client);
		if (!GetConVarBool(g_cvar_opt_in_mode))
			CreateTimer(120.0, DisplayNotification, GetClientUserId(client));
		return;
	}
}


public Action timer_AdvertiseHelp(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (!IsValidClient(client) || !IsClientConnected(client))
		return Plugin_Stop;

	PrintToChat(client, "[nt_props] You can print available commands with !props_help or get the menu with !menu");
	return Plugin_Stop;
}


public OnClientDisconnect(int client)
{
	// might not be needed since we check and set on connect
	g_bClientWantsProps[client] = false;
	g_GrabbedProp[client] = 0;
}


// returns true only if previous cookies were found
void ReadCookies(int client)
{
	// if (!IsValidClient(client))
	// 	return;

	char cookie[2];

	GetClientCookie(client, g_hPropPrefCookie, cookie, sizeof(cookie));

	#if DEBUG
	PrintToServer("[nt_props] DEBUG ReadCookies(%N) cookie is: \"%s\"",
	client, ((cookie[0] != '\0' && StringToInt(cookie)) ? cookie : "null" ));
	#endif

	g_bClientWantsProps[client] = (cookie[0] != '\0' && StringToInt(cookie));

	if (!GetConVarBool(g_cvar_opt_in_mode))
		CreateTimer(10.0, DisplayNotification, GetClientUserId(client));
}


// Toggle bool + cookie
void ToggleCookiePreference(int client)
{
	if (!IsValidClient(client))
		return;

	#if DEBUG
	PrintToServer("[nt_props] DEBUG Pref for %N is currently %s, bool toggled.", client, (g_bClientWantsProps[client] ? "true" : "false"));
	#endif

	g_bClientWantsProps[client] = !g_bClientWantsProps[client];

	SetClientCookie(client, FindClientCookie("wants-props"), (g_bClientWantsProps[client] ? "1" : "0"));

	LogAction(-1, -1, "%N %s custom props.", client, (g_bClientWantsProps[client] ? "opted in" : "opted out"));
}


// Obsolete command but kept in case of opt-in mode
public Action DisplayNotification(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if(client > 0 && IsClientConnected(client) && IsClientInGame(client))
	{
		if(!g_bClientWantsProps[client] && !GetConVarBool(g_cvar_opt_in_mode))
		{
			PrintToChat(client, 	"[nt_props] You can toggle seeing custom props completely by typing !props_nothx");
			PrintToConsole(client, 	"\n[nt_props] You can toggle seeing custom props completely by typing sm_props_nothx\n");
			PrintToChat(client, 	"[nt_props] You can prevent people from spawning props until the end of the round by typing !props_pause");
			PrintToConsole(client, 	"\n[nt_props] You can prevent people from spawning props until the end of the round by typing sm_props_pause\n");
			return Plugin_Handled;
		}
		// opt-in mode
		PrintToChat(client, 	"[nt_props] You can use !props to get props features.\n");
		PrintToConsole(client, 	"\n[nt_props] You can use sm_props to get props features.\n");

	}
	return Plugin_Handled;
}


// Obsolete command but kept in case of opt-in mode
public Action Command_Hate_Props_Toggle(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	ToggleCookiePreference(client);

	char buffer[255];
	Format(buffer, sizeof(buffer), "Your preference has been recorded. %s",
	(g_bClientWantsProps[client] ? "You do like props after all." : "You no like props."));

	ReplyToCommand(client, buffer);

	ShowActivity2(client, "[nt_props] ", "%N opted %s nt_props models.",
	client, (g_bClientWantsProps[client] ? "back in" : "out of"));
	LogAction(client, -1, "[nt_props] \"%L\" opted %s nt_props models.",
	client, (g_bClientWantsProps[client] ? "back in" : "out of"));

	return Plugin_Handled;
}


public Action Command_Pause_Props_Spawning(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	char clientname[MAX_NAME_LENGTH];
	GetClientName(client, clientname, sizeof(clientname));

	if (!gb_PausePropSpawning)
	{
		gb_PausePropSpawning = true;
		PrintToChatAll("[nt_props] Prop spawning has been disabled until the end of the round.");
		for (int i=1; i <= MaxClients; i++)
		{
			if (IsValidClient(i))
				PrintToConsole(i, "[nt_props] Prop spawning has been disabled by \"%s\" until the end of the round.", clientname);
		}
	}
	return Plugin_Handled;
}


//==================================
//		Credits management
//==================================

public Action Command_Give_Score (int client, int args)
{
	// if (!client)
	// {
	// 	ReplyToCommand(client, "This command cannot be executed by the server.");
	// 	return Plugin_Stop;
	// }
	if (GetCmdArgs() >= 1)
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
		PrintToConsole(client, "[nt_props] DEBUG: %N gave score of 60 to %N.", client, i_target);

		return Plugin_Handled;
	}

	SetEntProp(client, Prop_Data, "m_iFrags", 60);
	g_RemainingCreds[client][SCORE_CRED] = 60;
	g_RemainingCreds[client][VIRT_CRED] = 60;
	g_RemainingCreds[client][MAX_CRED] = 60;
	Command_Set_Credits_For_Client(client, 60);
	PrintToServer("[nt_props] DEBUG: %N gave score of 60 to himself.", client);
	ReplyToCommand(client, "[nt_props] DEBUG: You gave score of 60 to yourself.");
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
		CreateTimer(60.0, timer_AdvertiseHelp, GetClientUserId(client));

		for (int i = 0; i < sizeof(g_PropHistory[]); i++)
		{
			g_PropHistory[client][i] = -1; // clear history from a previous player just in case
		}
		g_GrabbedProp[client] = 0;

		// if we use score as credit, restore them
		if ( GetConVarBool(g_cvar_score_as_credits) )
			g_RemainingCreds[client][SCORE_CRED] = GetClientFrags(client); //NEEDS TESTING! might need a delay here
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
		PrintToServer("[nt_props] DEBUG: updating score of %d for player %N", score, client);
		#endif
		// if we use score as credit, restore them
		if ( GetConVarBool(g_cvar_score_as_credits) )
			g_RemainingCreds[client][SCORE_CRED] = score;
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

	g_GrabbedProp[client] = 0;

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
		g_GrabbedProp[client] = 0;

		g_baPropIsBeingGrabbed = false;

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
	g_GrabbedProp[victim] = 0;

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
	PrintToServer("[nt_props] DEBUG: DestroyAttachedPropForClient() \
Checking if need to remove strapped entity %d on client %N.", 
	g_AttachmentEnt[client], client);
	#endif

	if (MaxClients < g_AttachmentEnt[client] > 0 && IsValidEntity(g_AttachmentEnt[client]))
	{
		#if DEBUG
		PrintToServer("[nt_props] DEBUG: Yup, killing strapped entity %d of client %d.", g_AttachmentEnt[client], client);
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
			PrintToChat(client, "[nt_props] Your current score doesn't allow you to spawn props.");
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
		PrintToChat(client, "[nt_props] brouzoufs remaining: %d.", g_RemainingCreds[client][VIRT_CRED]);
		PrintToConsole(client, "[nt_props] brouzoufs remaining: %d.", g_RemainingCreds[client][VIRT_CRED]);
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
			PrintToChat(client, "[nt_props] WARNING: Your score has been decreased by 1 point for using that command!");
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
	PrintToChat(client, "[nt_props] You have just used %d brouzouf%s", credits, (credits > 1 ? "s." : "."));
	PrintToConsole(client, "[nt_props] You have just used %d brouzouf%s", credits, (credits > 1 ? "s." : "."));
	Decrease_Credits_For_Client(client, credits, true);
	Decrease_Score_For_Client(client, 1, true);
}


void DisplayActivity(int client, const char[] model)
{
	//ShowActivity2(client, "[nt_props] ", "%s spawned: %s.", client, model);
	LogAction(client, -1, "[nt_props] \"%L\" spawned: %s", client, model);
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

	PrintToChat(i_target, "[nt_props] Your brouzoufs have been set to %d.", g_RemainingCreds[i_target][VIRT_CRED]);
	PrintToConsole(i_target, "[nt_props] Your brouzoufs have been set to %d.", g_RemainingCreds[i_target][VIRT_CRED]);

	if (GetClientName(i_target, s_targetname, sizeof(s_targetname)) && client != i_target)
	{
		ReplyToCommand(client, "[nt_props] The credits for player %s are now set to %d.", s_targetname, g_RemainingCreds[i_target][VIRT_CRED]);
	}
	return Plugin_Handled;
}


//==================================
//		Prop Spawning
//==================================

// Add entity to history array, remove entity being replaced in history.
void AddEntityToHistory(int entity, int client/*, bool remove=true*/)
{
	if (!IsValidEntity(entity))
		return;

	// Cycle around the array. Update cursor first to keep track of last spawned prop.
	g_PropCursor[client]++;
	g_PropCursor[client] %= sizeof(g_PropHistory[]);

	// Remove any previous entity found.
	//if (remove)
	if ((g_PropHistory[client][g_PropCursor[client]] > 0) && (IsValidEntity(g_PropHistory[client][g_PropCursor[client]])))
		AcceptEntityInput(g_PropHistory[client][g_PropCursor[client]], "kill");

	g_PropHistory[client][g_PropCursor[client]] = entity;

	#if DEBUG
	PrintToServer("[nt_props] Added %d. Cursor for client %N is now: %d / %d",
	entity, client, g_PropCursor[client], sizeof(g_PropHistory[]));
	#endif
}


int Prop_Dispatch_By_Model_Path(int client, char[] model_path, bool bdynamic=false)
{

	int entity = (bdynamic ? Create_Basic_DynamicProp(client, model_path, 50) : Create_Basic_PhysicsProp(client, model_path, 50));

	if (bdynamic)
	{
		SetDynamicProperties(entity, model_path);
	}
	else
	{
		SetPhysicsProperties(entity, model_path);
	}

	return entity;
}


// compare model path name and set specific properties here
void SetDynamicProperties(int entity, char[] model_path)
{
	if (StrContains("hachikoma_dynamic", model_path))
	{
		SetVariantString( (GetRandomInt(0,1) ? "idleA" : "idleB") );
		AcceptEntityInput(entity, "SetAnimation");

		char buffer[2];
		IntToString(GetRandomInt(0,4), buffer, sizeof(buffer));
		DispatchKeyValue(entity, "skin", buffer);
	}

	// SetVariantString("!self"); // !self, !activator
	// AcceptEntityInput(entity, "DisableCollision");

	DispatchKeyValue(entity, "solid", "0"); // works for dynamic, bullets don't collide
}



void SetPhysicsProperties(int entity, char[] model_path)
{
	// 0x8 CONTENTS_GRATE, works for physics_props, bullet don't collide,
	// but can't grab anymore because ray tracing doesn't collide either,
	// 0x0 doesn't collide even with world (fall through!)
	// Need more testing on solid type and groups
	DispatchKeyValue(entity, "solid", "8");
	// ChangeEdictState(entity); // probably not needed actually
	return;
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


	int entity = CreatePropPhysicsOverride_AtClientPos(client, model_path, 50);
	AddEntityToHistory(entity, client);

	// FIXME: find a way to make bullets go through physic_props
	if (strcmp(model_path, gs_allowed_physics_models[2]) == 0 || strcmp(model_path, gs_allowed_physics_models[3]) == 0)
	{
		#if DEBUG
		PrintToConsole(client, "Called CreatePhysicsOverride_AtclientPos for admin");
		#endif

		SetEntityRenderFx(entity, RENDERFX_DISTORT); // works, only good for team logos
		AcceptEntityInput(entity, "DisableShadow"); // works
		// SetEntProp(entity, Prop_Send, "m_usSolidFlags", 136);
		// SetEntProp(entity, Prop_Send, "m_CollisionGroup", 13);
		// SetEntProp(entity, Prop_Send, "m_nSolidType", 0);
		DispatchSpawn(entity); 		// without this line, prop will stay in place and not move, but will still block bullets
		ActivateEntity(entity);
	}
	else
	{
		#if DEBUG
		char clsname[255];
		int r,g,b,a, rendm, rendfx;
		float gravity;

		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR > 7
		GetEntityClassname(entity, clsname, sizeof(clsname));
		GetEntityRenderColor(entity, r, g, b, a);
		rendfx = view_as<int>(GetEntityRenderFx(entity);
		rendm = view_as<int>(GetEntityRenderMode(entity);
		gravity = GetEntityGravity(entity);
		PrintToConsole(client, "Rendered before: %s with colors: %d,%d,%d,%d rendermode %d fx %d gravity %f", clsname, r,g,b,a, rendm, rendfx, gravity );
		#endif
		#endif // DEBUG

		// SetEntityRenderMode(entity, RENDER_NORMAL);
		// SetEntityRenderColor(entity, 255, 0, 0, 123); // works only on models supporting that, good for making ghosts (alpha)
		SetEntityRenderFx(entity, RENDERFX_DISTORT); // works, only good for team logos

		// SetEntityMoveType(entity, MOVETYPE_OBSERVER);
		// SetEntityMoveType(entity, MOVETYPE_NOCLIP);
		// SetEntityMoveType(entity, MOVETYPE_PUSH);

		// SetEntityGravity(entity, 0.1); // doesn't seem to work
		// DispatchKeyValue(entity, "Gravity", "0.1"); // doesn't work
		// DispatchKeyValue(entity, "Color", "0 255 0"); // doesn't work

		AcceptEntityInput(entity, "DisableShadow"); // works
		// AcceptEntityInput(entity, "Ignite"); // works

		DispatchSpawn(entity); 		// without this lines, prop will stay in place and not move, but will block bullets
		ActivateEntity(entity);

		#if DEBUG
		rendfx = view_as<int>(GetEntityRenderFx(entity));
		rendm = view_as<int>(GetEntityRenderMode(entity));
		gravity = GetEntityGravity(entity);

		#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR > 7
		GetEntityRenderColor(entity, r, g, b, a);
		#endif
		PrintToConsole(client, "Rendered after: %s with colors: %d,%d,%d,%d rendermode %d, fx %d gravity %f", clsname, r,g,b,a, rendm, rendfx, gravity);
		#endif // DEBUG
	}
}


void Print_Usage_For_Admins(int client)
{
	PrintToChat(client, "[nt_props] Admin, check console for useful commands and convars...");
	PrintToConsole(client, "[nt_props] Admins, some useful commands:");
	PrintToConsole(client, "\nsm_props_set_credits: sets credits for a clientID\nsm_props_credit_status: check credit status for all\nsm_props_restrict_alive: restrict to living players\nsm_props_initial_credits: initial amount given on player connection\nsm_props_max_credits: credits given on initial connection\nsm_props_replenish_credits: whether credits are replenished between rounds\nsm_props_score_as_credits: whether score should be counter as credits.\nsm_props_max_ttl: props get deleted after that time.\nsm_props_enabled: disable the command.");
	PrintToConsole(client, "You may also do sm_props \"model_path\" \"renderfx\" \"movetype\" \"ignite\"");
}


void Print_Usage_For_Client(int client, int type=1)
{
	if (type == 1)
	{
		PrintToConsole(client, "Usage: sm_props_spawn [model path]");
		PrintToChat(client, "Usage: !props_spawn [model path]");
	}
	else //TODO write all commands
	{
		PrintToChat(client, "[nt_props] check console for commands.");
		PrintToConsole(client, "[nt_props] Some \"useful\" commands:");
		PrintToConsole(client, "\nsm_props_nothx: disables props for you and everyone in the server.\n\
sm_strapdong [me|team|all] [specs]: straps a dong on people (including spectators)\n\
sm_props: spawns a model in the game\n\
sm_dick [1-5] [s]: spawns a dong of scale 1 to 5 with optional static properties\n\
sm_props_credit_status: check credits of other players and yourself\n\
sm_props_pause: stops anyone from spawning props until the end of the current round\n");
	}
}


public Action Command_Print_Help(int client, int args)
{
	Print_Usage_For_Client(client, 2);
}


// wall of shame (not a very good idea) OBSOLETE
// void Display_Why_Command_Is_Disabled(int client)
// {
// 	char buffer[255], name[MAX_NAME_LENGTH];
// 	for (int i=1, count=0; i <= MaxClients; i++)
// 	{
// 		if (!g_bClientWantsProps[i])
// 		{
// 			GetClientName(i, name, sizeof(name));
// 			if (count == 0)
// 			{
// 				Format(name, sizeof(name), "%s", name);
// 				count++;
// 			}
// 			else
// 			{
// 				Format(name, sizeof(name), ", %s", name);
// 			}
// 			StrCat(buffer, sizeof(buffer), name);
// 			#if DEBUG
// 			PrintToServer("DEBUG: buffer \"%s\"\nname \"%s\"", buffer, name);
// 			#endif
// 		}
// 	}
// 	PrintToChatAll("Sorry, this command is disabled as these players asked not to be annoyed by props: %s.", buffer);
// }


public Action ConCommand_Props(int client, int args)
{
	// Go straight to our category here
	if (!DisplayTopMenuCategory(g_hTopMenu, FindTopMenuCategory(g_hTopMenu, "Props"), client))
		g_hTopMenu.Display(client, TopMenuPosition_Start); // fall back to the top menu

	// osbolete method
	if (!GetConVarBool(g_cvar_opt_in_mode))
		ConCommand_PropSpawn(client, args);

	return Plugin_Handled;
}


public Action Command_NoProps(int client, int args)
{
	if (g_bClientWantsProps[client])
	{
		ToggleCookiePreference(client);
		PrintToChat(client, "[nt_props] You have opted out of the custom props world. Use !menu to toggle it back on.");
	}
	return Plugin_Handled;
}


bool IsPropCommandAllowed(int client)
{
	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return false;
	}

	if (GetConVarBool(g_cvar_restrict_alive) && GetClientTeam(client) <= 1)
	{
		PrintToChat(client, "Spawning props is currently disabled for spectators.");
		PrintToConsole(client, "Spawning props is currently disabled for spectators.");

		if (IsAdmin(client))
		{
			Print_Usage_For_Admins(client);
		}
		return false;
	}

	if(!GetCmdArgs())
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
			return false;
		}

		return false;
	}

	if (!GetConVarBool(g_cvar_props_enabled))
	{
		PrintToConsole(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		PrintToChat(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		return false;
	}

	return true;
}



public Action ConCommand_PropSpawn(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	// if (HasAnyoneOptedOut())
	// {
	// 	Display_Why_Command_Is_Disabled(client);
	// 	return Plugin_Handled;
	// }

	// opt-in here automatically (if opt-in mode)
	if (GetConVarBool(g_cvar_opt_in_mode) && !g_bClientWantsProps[client])
	{
		ToggleCookiePreference(client);
		PrintToChat(client, "[nt_props] You have opted to see custom props. Use !props to toggle it off.");
	}

	if (!IsPropCommandAllowed(client) && !IsAdmin(client))
		return Plugin_Handled;

	decl String:model_pathname[PLATFORM_MAX_PATH];
	bool dynamic;
	GetCmdArg(1, model_pathname, sizeof(model_pathname));

	if (args > 1)
		dynamic = true;

	#if DEBUG
	PrintToServer("Command props_spawn called with %s, %s", model_pathname, (dynamic ? "dynamic prop" : "physics prop"));
	#endif

	//TODO: check the path, make more secure
	// for (int index=0; index < sizeof(gs_allowed_physics_models); ++index)
	// {
	// 	if (StrContains(gs_allowed_physics_models[index], model_pathname, false) != -1)
	// 	{

	if (hasEnoughCredits(client, g_PropPrice[0])) //FIXME: for now everything costs 1!
	{
		#if DEBUG
		PrintToConsole(client, "Spawned: %s.", model_pathname);
		PrintToChat(client, "Spawning your %s.", model_pathname);
		#endif

		int entity = Prop_Dispatch_By_Model_Path(client, model_pathname, dynamic);
		AddEntityToHistory(entity, client);

		SDKHook(entity, SDKHook_SetTransmit, Hide_SetTransmit);

		Client_Used_Credits(client, g_PropPrice[0]);
		DisplayActivity(client, model_pathname);
	}
	else
	{
		PrintToChat(client, "[nt_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
		g_PropPrice[0], g_RemainingCreds[client][VIRT_CRED]);
		PrintToConsole(client, "[nt_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
		g_PropPrice[0], g_RemainingCreds[client][VIRT_CRED]);
	}

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
				AddEntityToHistory(CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 50), client);
				//Spawn_TE_Dong(client, gs_dongs[scale], gs_PropType[TE_PHYSICS]); // use TempEnts to avoid showing to people who don't like it
			else
				AddEntityToHistory(CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 50), client);
		}
		case 1:
		{
			if (!bstatic)
			{
				AddEntityToHistory(CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 120), client);
				CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, EntIndexToEntRef(g_PropHistory[client][g_PropCursor[client]]));
			}
			else
			{
				AddEntityToHistory(CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 120), client);
				CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, EntIndexToEntRef(g_PropHistory[client][g_PropCursor[client]]));
			}
		}
		case 2:
		{
			if (!bstatic)
				AddEntityToHistory(CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 180), client);
			else
				AddEntityToHistory(CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 180), client);

			// remove the prop when it's touched by a player
			SDKHook(g_PropHistory[client][g_PropCursor[client]], SDKHook_Touch, OnTouchEntityRemove);
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, EntIndexToEntRef(g_PropHistory[client][g_PropCursor[client]]));
		}
		case 3:
		{
			if (!bstatic)
				AddEntityToHistory(CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 200), client);
			else
				AddEntityToHistory(CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 200), client);

			SDKHook(g_PropHistory[client][g_PropCursor[client]], SDKHook_Touch, OnTouchEntityRemove);
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, EntIndexToEntRef(g_PropHistory[client][g_PropCursor[client]]));
		}
		case 4:
		{
			if (!bstatic)
				AddEntityToHistory(CreatePropPhysicsOverride_AtClientPos(client, gs_dongs[scale], 250), client);
			else
				AddEntityToHistory(CreatePropDynamicOverride_AtClientPos(client, gs_dongs[scale], 250), client);

			SDKHook(g_PropHistory[client][g_PropCursor[client]], SDKHook_Touch, OnTouchEntityRemove);
			CreateTimer(GetConVarFloat(cvPropMaxTTL), TimerKillEntity, EntIndexToEntRef(g_PropHistory[client][g_PropCursor[client]]));
		}
	}
	#if DEBUG
	PrintToServer("Hooking SetTransmit for props %d. Cursor is %d", g_PropHistory[client][g_PropCursor[client]], g_PropCursor[client]);
	#endif
// if (Has_Anyone_Opted_Out())
	SDKHook(g_PropHistory[client][g_PropCursor[client]], SDKHook_SetTransmit, Hide_SetTransmit);

}



bool IsCommandAllowed(int client)
{
	if (gb_PausePropSpawning)
	{
		ReplyToCommand(client, "Prop spawning is currently paused.");
		return false;
	}
	else if (!GetConVarBool(g_cvar_props_enabled))
	{
		PrintToConsole(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		PrintToChat(client, "This command is currently disabled. Ask an admin to enable with sm_props_enabled");
		return false;
	}

	if (GetConVarInt( g_cvar_score_as_credits ) > 0)
	{
		if (g_RemainingCreds[client][SCORE_CRED] <= 0)
		{
			PrintToChat(client, "[nt_props] Your current score doesn't allow you to spawn props.");
			PrintToConsole(client, "[nt_props] Your current score doesn't allow you to spawn props.");
			return false;
		}
	}
	if (g_RemainingCreds[client][VIRT_CRED] <= 0)
	{
		PrintToChat(client, "[nt_props] You don't have any remaining brouzoufs to spawn a prop.");
		PrintToConsole(client, "[nt_props] You don't have any remaining brouzoufs to spawn a prop.");
		return false;
	}

	return true;
}


public Action Command_Dong_Spawn(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	if ((GetCmdArgs() > 2) || (GetCmdArgs() == 0))
	{
		PrintToChat(client, "[nt_props] Usage: !dick [scale 1-5] [1 for static]");
		PrintToConsole(client, "[nt_props] Usage: sm_dick [scale 1-5] [1 for static]");
		PrintToChat(client, "[nt_props] Type: !props_credit_status see brouzoufs for everyone.");
		PrintToConsole(client, "[nt_props] Type sm_props_credit_status to see brouzoufs for everyone.");

		DisplayMenu(g_hSpawnDongMenu, client, 20); // display only that submenu
		return Plugin_Handled;
	}

	if (GetConVarBool(g_cvar_opt_in_mode) && !g_bClientWantsProps[client])
	{
		ToggleCookiePreference(client);
		PrintToChat(client, "[nt_props] You have opted to see custom props. Use !props to toggle it off.");
	}

	if (!IsCommandAllowed(client) && !IsAdmin(client))
		return Plugin_Handled;

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

	if (IsAdmin(client))
	{
		DongDispatch(client, iModelScale, iModelProperty);
		DisplayActivity(client, gs_dongs[iModelScale]);
		return Plugin_Handled;
	}

	if (hasEnoughCredits(client, g_PropPrice[iModelScale]))
	{
		DongDispatch(client, iModelScale, iModelProperty);
		Client_Used_Credits(client, g_PropPrice[iModelScale]);
		DisplayActivity(client, gs_dongs[iModelScale]);
		return Plugin_Handled;
	}
	else
	{
		PrintToChat(client, "[nt_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
		g_PropPrice[iModelScale], g_RemainingCreds[client][VIRT_CRED]);
		PrintToConsole(client, "[nt_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
		g_PropPrice[iModelScale], g_RemainingCreds[client][VIRT_CRED]);
		return Plugin_Handled;
	}
}


bool Is_Entity_Owner(int entity, int client)
{
	for (int i; i < sizeof(g_PropHistory[]); i++ )
	{
		if (entity == g_PropHistory[client][i])
			return true;
	}

	return false;
}


public Action ConCommand_Props_Rotate_Skin(int client, int args)
{
	int entity = GetClientAimTarget(client, false);

	if (!IsValidEdict(entity) || !IsValidEntity(entity) || entity <= MaxClients)
		return Plugin_Handled;

	if(!Is_Entity_Owner(entity, client))
	{
		PrintCenterText(client, "This is not your prop!");

		if (!IsAdmin(client))
			return Plugin_Handled;
	}

	//FIXME: property might not be found on just any prop
	// if (GetEntSendPropOffs(entity, "m_nSkin", true) == -1)
	// {
	// 	PrintToChat(client, "Property not found!");
	// 	return Plugin_Handled;
	// }

	int skin = GetEntProp(entity, Prop_Data, "m_nSkin");

	#if DEBUG
	PrintToChatAll("[nt_props] m_nSkin is \"%d\"", skin);
	PrintToServer("[nt_props] m_nSkin is \"%d\"", skin);
	#endif
	skin++;

	if (skin > 6)
		skin = 0;

	char cskin[2];
	IntToString(skin, cskin, sizeof(cskin));
	bool success = DispatchKeyValue(entity, "skin", cskin);

	char classname[255];
	GetEdictClassname(entity, classname, sizeof(classname));
	if (StrContains(classname, "props_physics", false))
	{
		#if DEBUG
		PrintToServer("[nt_props] %s avoiding DispatchSpawn()", classname);
		#endif
		ChangeEdictState(entity);
	}
	else
	{
		// DispatchSpawn(entity);
		ActivateEntity(entity);
	}

	#if DEBUG
	PrintToServer("[nt_props] Dispatched skin value %s", (success ? "was successful" : "failed"));
	#endif

	return Plugin_Handled;
}


public Action ConCommand_Props_Rotate_Color(int client, int args)
{
	int entity = GetClientAimTarget(client, false);

	if (!IsValidEdict(entity) || !IsValidEntity(entity) /*|| entity <= MaxClients*/)
		return Plugin_Handled;

	if(!Is_Entity_Owner(entity, client))
	{
		PrintCenterText(client, "This is not your prop!");

		if (!IsAdmin(client))
			return Plugin_Handled;
	}

	int r = GetRandomInt(0,255);
	int g = GetRandomInt(0,255);
	int b = GetRandomInt(0,255);
	SetEntityRenderColor(entity,r,g,b, 255);

	PrintCenterText(client, "Colors set to [%d %d %d]", r,g,b);

	return Plugin_Handled;
}


public Action ConCommand_Props_Rotate_Transparency(int client, int args)
{
	int entity = GetClientAimTarget(client, false);

	if (!IsValidEdict(entity) || !IsValidEntity(entity) || entity <= MaxClients)
		return Plugin_Handled;

	if(!Is_Entity_Owner(entity, client))
	{
		PrintCenterText(client, "This is not your prop!");

		if (!IsAdmin(client))
			return Plugin_Handled;
	}

	int r,g,b,a;
	RenderMode mode = GetEntityRenderMode(entity);
	GetEntityRenderColorFuture(entity, r, g, b, a);

	a -= 30;
	mode |= RENDER_TRANSCOLOR;

	if (a <= 0)
	{
		// reset to full opacity
		a = 255;
		if ((mode & RENDER_TRANSCOLOR) == RENDER_TRANSCOLOR)
			mode &= ~RENDER_TRANSCOLOR; // should go back to RENDER_NORMAL
	}

	SetEntityRenderMode(entity, mode);
	SetEntityRenderColor(entity, r, g, b, a);

	PrintCenterText(client, "Transparency set to [%f]", a);

	return Plugin_Handled;
}


public Action ConCommand_Props_Rotate_Angles(int client, int args)
{
	int entity = GetClientAimTarget(client, false);

	if (!IsValidEdict(entity) || !IsValidEntity(entity) || entity <= MaxClients)
		return Plugin_Handled;

	if(!Is_Entity_Owner(entity, client))
	{
		PrintCenterText(client, "This is not your prop!");

		if (!IsAdmin(client))
			return Plugin_Handled;
	}

	new Float:Angles[3];
	GetEntPropVector(entity, Prop_Data, "m_angRotation", Angles);

	Angles[0] += 0;
	Angles[1] += GetRandomInt(0,360);
	Angles[2] += 0;

	TeleportEntity(entity, NULL_VECTOR, Angles, NULL_VECTOR);

	PrintCenterText(client, "Angles set to [%f %f %f]", Angles[0], Angles[1], Angles[2]);
	return Plugin_Handled;
}


public Action ConCommand_Props_Rotate_Position(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;

	int entity = GetClientAimTarget(client, false);

	if (!IsValidEdict(entity) || !IsValidEntity(entity) || entity <= MaxClients)
	{
		g_GrabbedProp[client] = 0;

		if (!AnObjectIsBeingGrabbed())
			g_baPropIsBeingGrabbed = false;

		return Plugin_Handled;
	}

	if(!Is_Entity_Owner(entity, client))
	{
		PrintCenterText(client, "This is not your prop!");

		if (!IsAdmin(client))
		{
			g_GrabbedProp[client] = 0;

			if (!AnObjectIsBeingGrabbed())
				g_baPropIsBeingGrabbed = false;

			return Plugin_Handled;
		}
	}

	if (g_GrabbedProp[client] > 0)
	{
		g_GrabbedProp[client] = 0;

		if (!AnObjectIsBeingGrabbed())
			// we were the last one grabbing
			g_baPropIsBeingGrabbed = false;

		return Plugin_Handled;
	}

	#if DEBUG
	PrintToServer("[nt_props] prop %d has been targeted and grabbed.", entity);
	#endif

	g_GrabbedProp[client] = entity;

	if (g_updTimer == INVALID_HANDLE)
	{
		g_baPropIsBeingGrabbed = true;
		g_updTimer = CreateTimer(0.1, UpdateGrabbedObjects, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		#if DEBUG
		PrintToServer("[nt_props] Timer UpdateGrabbedObjects has been started!");
		#endif
	}

	return Plugin_Handled;
}


public Action UpdateGrabbedObjects(Handle timer)
{
	if (!g_baPropIsBeingGrabbed)
	{
		g_updTimer = INVALID_HANDLE; // not sure if really needed
		#if DEBUG
		PrintToServer("[nt_props] Timer UpdateGrabbedObjects has been stopped!");
		#endif
		return Plugin_Stop;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_GrabbedProp[client] <= 0 || !IsValidEntity(g_GrabbedProp[client] ))
			continue;

		float viewAng[3], vecPos[3], vecDir[3], vecVel[3];
		GetClientEyeAngles(client, viewAng);
		GetAngleVectors(viewAng, vecDir, NULL_VECTOR, NULL_VECTOR);

		GetClientAbsOrigin(client, vecPos);

		// update object
		vecPos[0] += vecDir[0] * 120.0;
		vecPos[1] += vecDir[1] * 120.0;
		vecPos[2] += vecDir[2] * 120.0;

		GetEntPropVector(g_GrabbedProp[client], Prop_Send, "m_vecOrigin", vecDir);

		SubtractVectors(vecPos, vecDir, vecVel);

		ScaleVector(vecVel, 10.0);
		vecVel[2] = 20.0;

		new String:classname[20];
		GetEdictClassname(g_GrabbedProp[client], classname, sizeof(classname));
		if(StrContains(classname, "_dynamic", false) > -1)
		{
			DispatchKeyValueVector(g_GrabbedProp[client], "Origin", vecPos);
			DispatchKeyValueVector(g_GrabbedProp[client], "Angles", viewAng);
			//DispatchKeyValueVector(gObj[i], "avelocity", vecVel); // not sure
			ChangeEdictState(g_GrabbedProp[client], GetEntSendPropOffs(g_GrabbedProp[client], "m_vecOrigin", true));
		}
		else
			TeleportEntity(g_GrabbedProp[client], vecPos, NULL_VECTOR, NULL_VECTOR);

		#if DEBUG
		PrintCenterText(client, "Upd: prop %d, %f %f %f", g_GrabbedProp[client], vecPos[0], vecPos[1], vecPos[2]);
		#endif
	}
	return Plugin_Handled;
}


bool AnObjectIsBeingGrabbed()
{
	for (int i = MaxClients; i > 0; i--)
	{
		if (g_GrabbedProp[i] > 0)
			return true;
	}
	return false;
}


// sets the client as the entity's new parent and attach the entity to client
void MakeParent(int client, int entity)
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
	// SetEntPropEnt(entity, Prop_Send, "m_hEffectEntity", client); // doesn't work.

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


void FireWorksOnPlayer(int client, int type)
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


void Setup_Firework (int client, const char[] model_pathname, const FireworksPropType PropEntClass, bool shocking)
{
	if (!IsValidClient(client))
		return;

	int dongclients[NEO_MAX_CLIENTS+1];
	int numClients;
	if (shocking)
		numClients = GetDongClients(dongclients, sizeof(dongclients));

	int i_cached_model_index = PrecacheModel(model_pathname, false);
	if (i_cached_model_index == 0)
	{
		LogError("[nt_props] Couldn't find or precache model \"%s\".", model_pathname);
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
	AddEntityToHistory(SimpleCreatePropPhysicsOverride(model_pathname, 50), client);
	DispatchKeyValueVector(g_PropHistory[client][g_PropCursor[client]], "Origin", origin);
	//TeleportEntity(g_PropCursor[client], origin, NULL_VECTOR, NULL_VECTOR);

	if (StrContains(model_pathname, "logo.mdl") != -1) // it's a logo
	{
		SetEntityRenderFx(g_PropHistory[client][g_PropCursor[client]], RENDERFX_DISTORT); // works, only good for team logos
		AcceptEntityInput(g_PropHistory[client][g_PropCursor[client]], "DisableShadow");
		// DispatchKeyValue(g_PropCursor[client], "Solid", "0");
	}

	DispatchSpawn(g_PropHistory[client][g_PropCursor[client]]);
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

	if (GetConVarBool(g_cvar_opt_in_mode) && !g_bClientWantsProps[client])
	{
		ToggleCookiePreference(client);
		PrintToChat(client, "[nt_props] You have opted to see custom props. Use !menu to toggle it off.");
	}

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
		int price;
		bool affected[NEO_MAX_CLIENTS+1];

		ComputePriceForProp(client, i_case, price, affected, isadmin);

		#if DEBUG
		PrintToServer("[nt_props] DEBUG: affected clients (sizeof(affected) is %d):\n", sizeof(affected));
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
				ReplyToCommand(client, "[nt_props] Attached a dong to your team mates.");
				DisplayActivity(client, "Dong on team.");
			}
			else if (i_case == 2)
			{
				ReplyToCommand(client, "[nt_props] Attached a dong to everyone.");
				DisplayActivity(client, "Dong on everyone.");
			}
			return Plugin_Handled;
		}
		else if (price == 0)
		{
			ReplyToCommand(client, "[nt_props] Nobody would be affected by your request.");
			return Plugin_Handled;
		}
		else
		{
			ReplyToCommand(client, "[nt_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
			price, g_RemainingCreds[client][VIRT_CRED]);
			return Plugin_Handled;
		}
	}
	else //i_case 0, only "me"
	{
		if (g_AttachmentEnt[client] != -1)
		{
			ReplyToCommand(client, "[nt_props] You already have a dong attached to yourself.");
			return Plugin_Handled;
		}

		if (isadmin)
		{
			SpawnAndStrapDongToSelf(client);
			ReplyToCommand(client, "[nt_props] Attached a dong to yourself.");
			DisplayActivity(client, "Dong on themselves.");
			return Plugin_Handled;
		}

		if (hasEnoughCredits(client, g_PropPrice[0]))
		{
			SpawnAndStrapDongToSelf(client);
			Client_Used_Credits(client, g_PropPrice[0]);
			DisplayActivity(client, "Dong on themselves."); //FIXME: format this to add detail about the exact command passed in that string
			return Plugin_Handled;
		}
		else
		{
			ReplyToCommand(client, "[nt_props] You don't have enough brouzoufs to spawn a prop: brouzoufs needed: %d, brouzoufs remaining: %d.",
			g_PropPrice[0], g_RemainingCreds[client][VIRT_CRED]);
			return Plugin_Handled;
		}
	}
}



void ComputePriceForProp(int client, int i_case, int &price, int affected[NEO_MAX_CLIENTS+1], bool isadmin)
{
	int team;
	if (i_case == 1)
		team = GetClientTeam(client);

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
		else if (!IsPlayerReallyAlive(i) && IsPlayerObservingALockedTarget(i)) // already observing someone
			continue;

		// don't add on top of another already attached
		if (g_AttachmentEnt[i] != -1)
			continue;

		if (!isadmin)
			price++;

		affected[i] = true;
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

	#if DEBUG > 1
	PrintToServer("[nt_props] DEBUG: Client %N (%d) has %d health.", client, client, GetEntProp(client, Prop_Send, "m_iHealth"));
	#endif

	// For some reason, 1 health point means dead, but checking deadflag is probably more reliable!
	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1 || GetEntProp(client, Prop_Send, "deadflag"))
	{
		#if DEBUG > 1
		PrintToServer("[nt_props] DEBUG: Determined that %N is not alive right now.", client);
		#endif
		return false;
	}

	return true;
}


public void SpawnAndStrapDongToSelf(int client)
{
	#if DEBUG
	PrintToConsole(client, "[nt_props] DEBUG: SpawnAndStrapDongToSelf() on %L", client);
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
		PrintToServer("[nt_props] DEBUG: Strapped prop index %d to client %L", g_AttachmentEnt[client], client);
		#endif
	}
	else //spectator
	{
		#if DEBUG
		PrintToServer("[nt_props] DEBUG: Client %N is a spectator. Strapping differently.", client);
		#endif

		if (IsPlayerObservingALockedTarget(client)) // don't attach if already spectating someone
			return;

		g_AttachmentEnt[client] = Create_Prop_For_Attachment(client, gs_dongs[0], 5, true);

		#if DEBUG
		PrintToServer("[nt_props] DEBUG: Strapped prop index %d to client %L", g_AttachmentEnt[client], client);
		#endif

		if (gTimer == INVALID_HANDLE)
		{
			gTimer = CreateTimer(0.1, UpdateObjects, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}


// public OnMapEnd()
// {
// 	if (gTimer != INVALID_HANDLE)
// 		KillTimer(gTimer);
// 	if (g_updTimer != INVALID_HANDLE)
// 		KillTimer(g_updTimer);
// }


bool IsPlayerObservingALockedTarget(int client)
{
	int mode = GetEntProp(client, Prop_Send, "m_iObserverMode");

	#if DEBUG
	// note movetype is most likely 10 too
	PrintToServer("[nt_props] %N %s observing: m_iObserverMode %d", client, (mode ? "is" : "is not"), mode);
	#endif

	if(mode == 5) // 5 mean free fly
		return false;
	return true; // 4 means observing a target (locked in)
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

	// SetEntityRenderMode(target, RENDER_TRANSCOLOR);
	// SetEntityRenderColor(target, 255, 255, 255, 100); //only works for some models :(

	SetEntPropEnt(EntIndex, Prop_Send, "m_hEffectEntity", client);

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


void MakeParent_Spec(int client, int entity)
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

	// SetEntProp(entity, Prop_Send, "m_fEffects", 1 << 8); // EF_ITEM_BLINK blink effect, good for highlighting pick-ups

	CreateTimer(0.1, timer_SetParentAttachment, entity);

	// old method below:
	#if DEBUG > 9000
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
	#endif //DEBUG > 9000
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
	for(int i = MaxClients; i > 0; i--)
	{
		if (!IsValidClient(i) || !IsClientConnected(i))
			continue;
		if (!IsPlayerReallyDead(i))
			continue;
		if (g_AttachmentEnt[i] != -1)
		{
			activeprop = true;
			UpdateSpecAttachedCoordinates(i, g_AttachmentEnt[i]);
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


void UpdateSpecAttachedCoordinates(int client, int entity) // FIXME: coordinates are not updated properly on one axis
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

// #if !DEBUG
// public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (client < 1 || (g_AttachmentEnt[client] == -1))
		return Plugin_Continue;

	if((buttons & (1 << 27)) == (1 << 27)) // Cloak button
	{
		if (IsPlayerReallyAlive(client) && (GetEntProp(client, Prop_Send, "m_iClassType") < 3)) // not a Support
		{
			ToggleNoDrawForAttachmentOfClient(client);

			// right now I have no idea how to cloak a parented prop, so we simply kill it :(
			//DestroyAttachedPropForClient(client);

			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}
// #endif // !DEBUG


// workaround since we don't know how to cloak props
void ToggleNoDrawForAttachmentOfClient(int client)
{
	int flags = GetEntProp(g_AttachmentEnt[client], Prop_Send, "m_fEffects");

	if ((flags & (1 << 5)) == (1 << 5))
	{
		#if DEBUG
		PrintToServer("[nt_props] DEBUG: Flags for %N are %d", client, flags);
		return; // we already have the nodraw flag set, skip
		#endif
	}
	#if DEBUG
	// note: this function is called many times during one single key press
	PrintToServer("[nt_props] DEBUG: flags for attached prop to %N are %d will be set to %d", client, flags, (flags |= (1 << 5)));
	#endif

	flags |= (1 << 5); // add EF_NODRAW
	SetEntProp(g_AttachmentEnt[client], Prop_Send, "m_fEffects", flags);

	if (gNoDrawTimer[client] == INVALID_HANDLE)
		// we check if player is still cloaked every second from then on
		gNoDrawTimer[client] = CreateTimer(1.0, timer_CheckIfCloaked, GetClientUserId(client), TIMER_REPEAT);
}


// reset NODRAW flag on attached prop if we are not cloaked anymore
public Action timer_CheckIfCloaked(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (!IsValidClient(client))
	{
		gNoDrawTimer[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}

	if (GetEntProp(client, Prop_Send, "m_iThermoptic"))
		return Plugin_Continue; // we are cloaked, keep nodraw, repeat timer

	if (g_AttachmentEnt[client] == -1)
	{
		// we assume the prop doesn't exist anymore (this might need testing and fixing)
		gNoDrawTimer[client] = INVALID_HANDLE;
		return Plugin_Stop; // kill timer
	}

	int flags = GetEntProp(g_AttachmentEnt[client], Prop_Send, "m_fEffects");

#if DEBUG
	PrintToServer("[nt_props] DEBUG: effects for client %d are %d", client, flags);
#endif

	if ((flags & (1 << 5)) == (1 << 5)) // if we have EF_NODRAW
		flags &= ~(1 << 5); // remove EF_NODRAW
	else
		return Plugin_Continue;

	SetEntProp(g_AttachmentEnt[client], Prop_Send, "m_fEffects", flags);

#if DEBUG
	PrintToServer("[nt_props] DEBUG: reset effects flags to %d.", flags);
#endif

	gNoDrawTimer[client] = INVALID_HANDLE;
	return Plugin_Stop; // kill timer
}


public Action TimerKillEntity(Handle timer, int entref)
{
	int prop = EntRefToEntIndex(entref);
	if(IsValidEdict(prop) && prop > MaxClients)
	{
		LogAction(-1, -1, "Timer killing entity %d", prop);
		AcceptEntityInput(prop, "kill");
	}
	return Plugin_Handled;
}


public Action OnTouchEntityRemove(int propindex, int client)
{
	if(0 < client <= MaxClients && propindex > 0 && !IsFakeClient(client) && IsValidEntity(propindex))
	{
		LogAction(client, -1, "OnTouchEntityRemove entity %d by %N", propindex, client);
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
int GetDongClients(int outClients[NEO_MAX_CLIENTS+1], int arraySize)
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

	int dongclients[NEO_MAX_CLIENTS+1];
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

	int dongclients[NEO_MAX_CLIENTS+1];
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
	if (IsValidClient(client) && g_bClientWantsProps[client])
		return true;
	return false;
}


public Action Hide_SetTransmit(int entity, int client)
{
	if (entity == g_AttachmentEnt[client])
		return Plugin_Handled; // hide client's attached prop from himself
	if (!g_bClientWantsProps[client])
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



stock int Create_Basic_PhysicsProp(int client, const String:modelname[], int health)
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


stock int Create_Basic_DynamicProp(int client, const String:modelname[], int health)
{
	new EntIndex = CreateEntityByName("prop_dynamic_override");

	if(!IsModelPrecached(modelname))
	{
		PrecacheModel(modelname);
	}

	float VecOrigin[3];
	float VecAngles[3];
	float normal[3];

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

	float degree = 180.0;  //rotating properly -glub
	float angles[3];
	GetEntPropVector(EntIndex, Prop_Data, "m_angRotation", angles);
	RotateYaw(angles, degree);

	DispatchKeyValueVector(EntIndex, "Angles", angles );  // rotates 180 degrees! -glub

	return EntIndex;
}


void GetEntityRenderColorFuture(int entity, int &r, int &g, int &b, int &a)
{
	static bool gotconfig = false;
	static char prop[32];

	if (!gotconfig)
	{
		Handle gc = LoadGameConfigFile("core.games");
		bool exists = GameConfGetKeyValue(gc, "m_clrRender", prop, sizeof(prop));
		CloseHandle(gc);

		if (!exists)
		{
			strcopy(prop, sizeof(prop), "m_clrRender");
		}

		gotconfig = true;
	}

	int offset = GetEntSendPropOffs(entity, prop);

	if (offset <= 0)
	{
		ThrowError("GetEntityRenderColor not supported by this mod");
	}

	r = GetEntData(entity, offset, 1);
	g = GetEntData(entity, offset + 1, 1);
	b = GetEntData(entity, offset + 2, 1);
	a = GetEntData(entity, offset + 3, 1);
}


// Use code below to check area before spawning a prop, to avoid spawning on a player?

// #include <sdktools>

// bool IsAreaClearOfPlayers(int MovingEnt, float pos[3])
// {
//     float vecMins[3], vecMaxs[3];

//     GetEntPropVector(MovingEnt, Prop_Send, "m_vecMins", vecMins);
//     GetEntPropVector(MovingEnt, Prop_Send, "m_vecMaxs", vecMaxs);

//     TR_TraceHull(pos, pos, vecMins, vecMaxs, MASK_SOLID);
//     TR_TraceHullFilter(pos, pos, vecMins, vecMaxs, MASK_SOLID, Filter_OnlyPlayers);

//     if(!TR_DidHit())
//         return true;

//     return false;
// }

// public bool Filter_OnlyPlayers(int entity, int contentsMask, any data)
// {
//     return (entity > 0) && (entity <= MaxClients);
// }