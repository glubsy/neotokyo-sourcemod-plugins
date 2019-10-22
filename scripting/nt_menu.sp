#include <sourcemod>
#include <topmenus>
#include "nt_menu.inc"

#define DEBUG 1

// Purpose: centralize access to various plugins' menus

public Plugin:myinfo =
{
	name = "NEOTOKYO easy menu",
	author = "glub, alliedmodders",
	description = "Shows a menu to access various plugins options.",
	version = "0.1",
	url = "https://github.com/glubsy"
};

/* Forwards */
new Handle:hOnNTMenuReady = null;
new Handle:hOnNTMenuCreated = null;

/* Menus */
TopMenu hTopMenu;

/* Top menu objects */
TopMenuObject obj_preferencescmds = INVALID_TOPMENUOBJECT;
TopMenuObject obj_propscmds = INVALID_TOPMENUOBJECT;
TopMenuObject obj_specialeffectscmds = INVALID_TOPMENUOBJECT;

#include "dynamicmenu_nt.sp"

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("GetNTTopMenu", __GetNTTopMenu);
	CreateNative("AddTargetsToNTMenu", __AddTargetsToMenu);
	CreateNative("AddTargetsToNTMenu2", __AddTargetsToMenu2);
	RegPluginLibrary("nt_menu");
	return APLRes_Success;
}

public OnPluginStart()
{
	hOnNTMenuCreated = CreateGlobalForward("OnNTMenuCreated", ET_Ignore, Param_Cell);
	hOnNTMenuReady = CreateGlobalForward("OnNTMenuReady", ET_Ignore, Param_Cell);

	RegConsoleCmd("sm_menu", Command_DisplayMenu, "Neotokyo server main menu.");
}


public OnConfigsExecuted()
{
	decl String:path[PLATFORM_MAX_PATH];
	decl String:error[256];

	BuildPath(Path_SM, path, sizeof(path), "configs/nt_menu_sorting.txt");

	if (!hTopMenu.LoadConfig(path, error, sizeof(error)))
	{
		LogError("Could not load nt menu config (file \"%s\": %s)", path, error);
		return;
	}
}

public OnMapStart()
{
	ParseConfigs();
}


public OnAllPluginsLoaded()
{
	hTopMenu = new TopMenu(DefaultCategoryHandler);

	obj_preferencescmds = 		hTopMenu.AddCategory("Vote commands", DefaultCategoryHandler);
	obj_propscmds = 			hTopMenu.AddCategory("Props", DefaultCategoryHandler);
	obj_specialeffectscmds =	hTopMenu.AddCategory("Various effects", DefaultCategoryHandler);

	BuildDynamicMenu();

	Call_StartForward(hOnNTMenuCreated);
	Call_PushCell(hTopMenu);
	Call_Finish();

	Call_StartForward(hOnNTMenuReady);
	Call_PushCell(hTopMenu);
	Call_Finish();
}


public void OnClientPutInServer(int client)
{
	CreateTimer(120.0, timer_AdvertiseMenu, client, TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_AdvertiseMenu(Handle timer, int client)
{
	if (!client || !IsFakeClient(client) || !IsClientConnected(client))
		return Plugin_Stop;

	PrintToChat(client, "Type !menu to change your preferences and access special features.");
	PrintHintTextToAll("Type !menu to change your preferences.");
	return Plugin_Handled;
}


public DefaultCategoryHandler(Handle:topmenu,
						TopMenuAction:action,
						TopMenuObject:object_id,
						param,
						String:buffer[],
						maxlength)
{
	if (action == TopMenuAction_DisplayTitle)
	{
		if (object_id == INVALID_TOPMENUOBJECT)
		{
			Format(buffer, maxlength, "Neotokyo Menu", param);
		}
		else if (object_id == obj_preferencescmds)
		{
			Format(buffer, maxlength, "Vote commands", param);
		}
		else if (object_id == obj_propscmds)
		{
			Format(buffer, maxlength, "Props", param);
		}
		else if (object_id == obj_specialeffectscmds)
		{
			Format(buffer, maxlength, "Various effects", param);
		}
	}
	else if (action == TopMenuAction_DisplayOption)
	{
		if (object_id == obj_preferencescmds)
		{
			Format(buffer, maxlength, "Vote commands", param);
		}
		else if (object_id == obj_propscmds)
		{
			Format(buffer, maxlength, "Props", param);
		}
		else if (object_id == obj_specialeffectscmds)
		{
			Format(buffer, maxlength, "Various effects", param);
		}
	}
}

public __GetNTTopMenu(Handle:plugin, numParams)
{
	return _:hTopMenu;
}

public __AddTargetsToMenu(Handle:plugin, numParams)
{
	new bool:alive_only = false;

	if (numParams >= 4)
	{
		alive_only = GetNativeCell(4);
	}

	return UTIL_AddTargetsToMenu(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), alive_only);
}

public __AddTargetsToMenu2(Handle:plugin, numParams)
{
	return UTIL_AddTargetsToMenu2(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3));
}

public Action:Command_DisplayMenu(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[SM] Command is in-game only");
		return Plugin_Handled;
	}

	hTopMenu.Display(client, TopMenuPosition_Start);
	return Plugin_Handled;
}

stock int UTIL_AddTargetsToMenu2(Menu menu, source_client, flags)
{
	char user_id[12];
	char name[MAX_NAME_LENGTH];
	char display[MAX_NAME_LENGTH+12];

	new num_clients;

	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i) || IsClientInKickQueue(i))
		{
			continue;
		}

		if (((flags & COMMAND_FILTER_NO_BOTS) == COMMAND_FILTER_NO_BOTS)
			&& IsFakeClient(i))
		{
			continue;
		}

		if (((flags & COMMAND_FILTER_CONNECTED) != COMMAND_FILTER_CONNECTED)
			&& !IsClientInGame(i))
		{
			continue;
		}

		if (((flags & COMMAND_FILTER_ALIVE) == COMMAND_FILTER_ALIVE)
			&& !IsPlayerAlive(i))
		{
			continue;
		}

		if (((flags & COMMAND_FILTER_DEAD) == COMMAND_FILTER_DEAD)
			&& IsPlayerAlive(i))
		{
			continue;
		}

		if ((source_client && ((flags & COMMAND_FILTER_NO_IMMUNITY) != COMMAND_FILTER_NO_IMMUNITY))
			&& !CanUserTarget(source_client, i))
		{
			continue;
		}

		IntToString(GetClientUserId(i), user_id, sizeof(user_id));
		GetClientName(i, name, sizeof(name));
		Format(display, sizeof(display), "%s (%s)", name, user_id);
		menu.AddItem(user_id, display);
		num_clients++;
	}

	return num_clients;
}

stock UTIL_AddTargetsToMenu(Menu menu, source_client, bool:in_game_only, bool:alive_only)
{
	new flags = 0;

	if (!in_game_only)
	{
		flags |= COMMAND_FILTER_CONNECTED;
	}

	if (alive_only)
	{
		flags |= COMMAND_FILTER_ALIVE;
	}

	return UTIL_AddTargetsToMenu2(menu, source_client, flags);
}
