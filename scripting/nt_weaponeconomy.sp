//TODO: for saved weapon, if not using full economy, use Client_HasWeapon(classname) and add ammo to it
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#include <smlib>

#pragma semicolon 1
#pragma newdecls required

#define DEBUG 1
#define PLUGIN_VERSION "0.4"

char
	g_iPlayersHeldPrimaryWeapon[MAXPLAYERS+1][32],
	g_iPlayersHeldSecondaryWeapon[MAXPLAYERS+1][32],
	g_iPlayersHeldGrenades[MAXPLAYERS+1][32];

int
	g_iPlayersHeldPrimaryWeaponAmmo[MAXPLAYERS+1],
	g_iPlayersHeldSecondaryWeaponAmmo[MAXPLAYERS+1],
	g_iPlayersHeldGrenadesAmmo[MAXPLAYERS+1],
	g_iPlayerSelectedClass[MAXPLAYERS+1],
	g_bPlayerSurvivedLastRound[MAXPLAYERS+1];

bool
	g_F3Bound[MAXPLAYERS+1],
	g_bJumpHeld[MAXPLAYERS+1],
	g_bClassSelected[MAXPLAYERS+1],
	g_bVariantSelected[MAXPLAYERS+1],
	g_bBlockWeapons[MAXPLAYERS+1],
	g_bBuytime;

Handle
	convar_weaponeconomy_enabled = INVALID_HANDLE,
	convar_weaponsaving_enabled = INVALID_HANDLE;

public Plugin myinfo =
{
	name = "NEOTOKYO° weapon economy system",
	author = "soft as HELL, glub",
	description = "Saves and restores weapon throughout rounds, and more",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
}

public void OnPluginStart()
{
	CreateConVar("sm_ntweaponeconomy_version", PLUGIN_VERSION, "NEOTOKYO° weapon economy version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	convar_weaponeconomy_enabled = CreateConVar("sm_ntweaponeconomy_enabled", "1", "Enable NEOTOKYO weapon economy", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	convar_weaponsaving_enabled = CreateConVar("sm_ntweaponsaving_enabled", "1", "Enable NEOTOKYO weapon saving through rounds", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);

	HookEvent("game_round_start", OnRoundStart);
	HookEvent("game_round_end", OnRoundEnd);
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_disconnect", OnPlayerDisconnected);

	HookUserMessage(GetUserMessageId("VGUIMenu"), OnVGUIMenu, true);

	AddCommandListener(OnCommand, "loadout");
	AddCommandListener(OnCommand, "loadoutmenu");
	AddCommandListener(OnCommand, "setclass");
	AddCommandListener(OnCommand, "setvariant");
	AddCommandListener(OnCommand, "playerready");

	g_bBuytime = false;

	// Hook again if plugin is restarted
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsValidClient(client))
		{
			OnClientPostAdminCheck(client);
		}
	}
}

public void OnClientPostAdminCheck(int client)
{
	if(!GetConVarBool(convar_weaponeconomy_enabled))
		return;

	SDKHook(client, SDKHook_WeaponEquip, OnWeaponEquip);
	SDKHook(client, SDKHook_WeaponCanSwitchTo, OnWeaponCanSwitchTo);

	if(!IsFakeClient(client))
	{
		ClientCommand(client, "bind F3 loadoutmenu");

		g_F3Bound[client] = true;
	}
}

public void OnPlayerDisconnected(Handle event, const char[] name, bool dontBroadcast)
{
	if(!GetConVarBool(convar_weaponeconomy_enabled) || !GetConVarBool(convar_weaponsaving_enabled))
		return;

	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	SDKUnhook(client, SDKHook_WeaponEquip, OnWeaponEquip);
	SDKUnhook(client, SDKHook_WeaponCanSwitchTo, OnWeaponCanSwitchTo);

	g_bClassSelected[client] = false;
	g_bVariantSelected[client] = false;
	g_bBlockWeapons[client] = false;
	g_bPlayerSurvivedLastRound[client] = false;

	g_iPlayersHeldPrimaryWeapon[client] = "";
	g_iPlayersHeldSecondaryWeapon[client] = "";
	g_iPlayersHeldGrenades[client] = "";

	g_iPlayersHeldPrimaryWeaponAmmo[client] = 0;
	g_iPlayersHeldSecondaryWeaponAmmo[client] = 0;
	g_iPlayersHeldGrenadesAmmo[client] = 0;

	g_iPlayerSelectedClass[client] = 0;
}

public void OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)  // could use "playerready" command listen instead if dosen't work
{
	if(!GetConVarBool(convar_weaponeconomy_enabled) || !GetConVarBool(convar_weaponsaving_enabled))
		return;

	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	CreateTimer(0.5, OnPlayerSpawn_Post, client);
}

public Action OnPlayerSpawn_Post(Handle timer, int client)
{
	if(!IsValidClient(client) && !IsPlayerAlive(client))
		return;

	if(GetPlayerClass(client) == CLASS_SUPPORT && !IsValidEdict(GetPlayerWeaponSlot(client, SLOT_MELEE)))
	{
		// Give knife to supports if they don't have one already
		GiveWeaponToPlayer(client, "weapon_knife");
	}

	g_bBlockWeapons[client] = false;

	if(g_bPlayerSurvivedLastRound[client])
	{
		GivePlayerLastPrimaryWeapon(client);
		GivePlayerLastSecondaryWeapon(client);
	}
}

public void OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if(!GetConVarBool(convar_weaponsaving_enabled))
		return;

	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	#if DEBUG > 0
	PrintToServer("[OnPlayerDeath] %N (%d) didn't survive this round!", victim, victim);
	#endif

	g_bPlayerSurvivedLastRound[victim] = false;
	g_bVariantSelected[victim] = false;
}

public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if(!GetConVarBool(convar_weaponeconomy_enabled))
		return;

	g_bBuytime = true;

	PrintToChatAll("[WE] Buytime active!");
	CreateTimer(30.0, timer_ClearBuyTime); //FIXME: 30 seconds is a lot of time, round can end before bytime is over

	for(int client = 1; client <= MaxClients; client++)
	{
		g_bClassSelected[client] = false;
		g_bVariantSelected[client] = false;

		CreateTimer(1.0, OnRoundStart_Post, client);
	}
}

public Action OnRoundStart_Post(Handle timer, int client)
{
	if(IsValidClient(client) && GetClientTeam(client) >= 2)
	{
		#if DEBUG > 0
		PrintToServer("[LOADOUT OnRoundStart_Post] %N [%d] showing classmenu on round start; m_iClassType = %d", client, client, GetEntProp(client, Prop_Send, "m_iClassType"));
		#endif

		ClientCommand(client, "classmenu");
	}
}

public void OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	//storing weapons if still alive
	if(!GetConVarBool(convar_weaponsaving_enabled))
		return;

	for(int client = 1; client <= MaxClients; client++)
	{
		g_bVariantSelected[client] = false;
		g_bBlockWeapons[client] = true;

		if(!IsClientInGame(client) || !IsClientConnected(client) || IsFakeClient(client))
			continue;

		if(!IsPlayerAlive(client))
			continue;

		#if DEBUG > 0
		PrintToServer("[OnRoundEnd] %N (%d) survived this round!", client, client);
		#endif

		g_bPlayerSurvivedLastRound[client] = true;

		int primaryweapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
		int secondaryweapon = GetPlayerWeaponSlot(client, SLOT_SECONDARY);
		int grenade = GetPlayerWeaponSlot(client, SLOT_SECONDARY);

		StoreWeapon(client, primaryweapon, SLOT_PRIMARY);
		StoreWeapon(client, secondaryweapon, SLOT_SECONDARY);
		StoreWeapon(client, grenade, SLOT_SECONDARY);

		#if DEBUG > 0
		PrintToServer("[WE] EndofRound: Client: %i, primary wpn held: %i, secondary wpn held: %i", client, primaryweapon, secondaryweapon);
		#endif
	}
}

public Action OnCommand(int client, const char[] command, int args)
{
	if(!GetConVarBool(convar_weaponeconomy_enabled))
		return Plugin_Continue;

	char sArg[3];
	GetCmdArgString(sArg, sizeof(sArg));
	int arg = StringToInt(sArg);

	PrintToServer("[OnCommand] %N [%d]: %s %d {argc = %d}", client, client, command, arg, args);

	if(StrEqual(command, "playerready") && !g_bClassSelected[client])
	{
		#if DEBUG > 0
		PrintToServer("[LOADOUT] OnCommand. %N %i fired playerready while class selected. Checking if variant=false then forcing.", client, client);
		#endif

		if(!g_bVariantSelected[client])
		{
			#if DEBUG > 0
			PrintToServer("[LOADOUT] OnCommand. %N %i FORCING class menu!", client, client);
			#endif

			ClientCommand(client, "classmenu");
		}

		return Plugin_Handled;
	}
	else if(StrEqual(command, "setvariant"))
	{
		#if DEBUG > 0
		PrintToServer("[LOADOUT] OnCommand. %N %i set variant used.", client, client);
		#endif

		g_bClassSelected[client] = true;
		g_bVariantSelected[client] = true;
	}
	else if(StrEqual(command, "setclass"))
	{
		#if DEBUG > 0
		PrintToServer("[LOADOUT] OnCommand. %N %i setclass used.", client, client);
		#endif

		g_bClassSelected[client] = true;
	}
	else if(StrEqual(command, "loadoutmenu")) // It doesn't get called with valid client id, always 0
	{
		#if DEBUG > 0
		PrintToServer("[LOADOUT] OnCommand. %N [%d] called loadoutmenu manually", client, client);
		#endif
	}
	else if(StrEqual(command, "loadout"))
	{
		// Fired manually with -1 loadout, probably not needed but it was easier to debug this way
		if(arg == -1)
		{
			#if DEBUG > 0
			PrintToServer("[LOADOUT] OnCommand. %N [%d] selected loadout on spawn, probably doesn't have class and variant selected yet", client, client);
			#endif

			return Plugin_Handled;
		}

		#if DEBUG > 0
		PrintToServer("[LOADOUT] OnCommand. %N [%d] selected loadout, probably has class and variant selected by now", client, client);
		#endif

		// Fixes the classmenu being shown after firing playerready after this
		g_bClassSelected[client] = true;
		g_bVariantSelected[client] = true;
	}

	return Plugin_Continue;
}

public Action OnVGUIMenu(UserMsg msg_id, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!GetConVarBool(convar_weaponeconomy_enabled))
		return Plugin_Continue;

	if(!reliable || playersNum != 1)
		return Plugin_Continue;

	char name[12];
	BfReadString(bf, name, sizeof(name));

	// Only gets called on spawn, doesn't get triggered by other commands
	if(!StrEqual(name, "loadout"))
		return Plugin_Continue;

	// Is sent to only one player
	int client = players[0];

	if(!IsValidClient(client) || IsFakeClient(client))
		return Plugin_Continue;

	int type = BfReadShort(bf); // 0 for model, 1 for weapons?

	switch(type)
	{
		case 0: // Class menu, also gets called without showing it if you survive the round
		{
			g_bClassSelected[client] = false;

			return Plugin_Continue; // You can't block it
		}
		case 1:  // Loadout menu
		{
			#if DEBUG > 0
			PrintToServer("[LOADOUT] OnVGUIMenu. %N Hiding loadout menu and forcing spawn with mpn!", client);
			#endif

			// Make player spawn with mpn
			ClientCommand(client, "loadout -1"); // Is this even needed? I think only the playerready is important, left it there for now to debug loadout menu
			ClientCommand(client, "playerready");

			// Block loadout menu
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	if(g_bBuytime && GetConVarBool(convar_weaponeconomy_enabled))
	{
		if(buttons & IN_JUMP)
		{
			if(g_bJumpHeld[client])
			{
				buttons &= ~IN_JUMP; //releasing
			}
			else
			{
				// FIXME: Is this even needed?
				if(IsPlayerAlive(client))
				{
					GivePlayerLastPrimaryWeapon(client);
					GivePlayerLastSecondaryWeapon(client);
				}

				g_bJumpHeld[client] = true;
			}
		}
		else
		{
			g_bJumpHeld[client] = false;
		}
	}
}

public Action OnWeaponEquip(int client, int weapon)
{
	if(!g_bBlockWeapons[client])
		return Plugin_Continue;

	int slot = GetWeaponSlot(weapon);

	if(g_bPlayerSurvivedLastRound[client]) // Survived the round
	{
		// Block primary and secondary weapons
		if(slot == SLOT_PRIMARY || slot == SLOT_SECONDARY)
		{
			#if DEBUG > 1
			char classname[15];
			GetEdictClassname(weapon, classname, sizeof(classname));

			PrintToServer("[WE] Blocking equiping %s for %N (%i)", classname, client, client);
			#endif

			return Plugin_Handled;
		}
	}
	else // Died
	{
		// Only block primary weapon
		if(slot == SLOT_PRIMARY)
		{
			#if DEBUG > 1
			char classname[15];
			GetEdictClassname(weapon, classname, sizeof(classname));

			PrintToServer("[WE] Blocking equiping %s for %N (%i)", classname, client, client);
			#endif

			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action OnWeaponCanSwitchTo(int client, int weapon)
{
	if(!g_bBlockWeapons[client])
		return Plugin_Continue;

	int slot = GetWeaponSlot(weapon);

	if(g_bPlayerSurvivedLastRound[client]) // Survived last round
	{
		if(slot != SLOT_MELEE)
		{
			#if DEBUG > 1
			char classname[15];
			GetEdictClassname(weapon, classname, sizeof(classname));

			PrintToServer("[WE] WeaponCanSwitch %N blocking switching to weapon %s (%i)", client, classname, weapon);
			#endif

			// Block everything but knife
			return Plugin_Stop;
		}

	}
	else // Died last round
	{
		if(slot != SLOT_SECONDARY)
		{
			#if DEBUG > 1
			char classname[15];
			GetEdictClassname(weapon, classname, sizeof(classname));

			PrintToServer("[WE] WeaponCanSwitch %N blocking switching to weapon %s (%i)", client, classname, weapon);
			#endif

			// Block everything but pistols
			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

public Action timer_ClearBuyTime(Handle timer)
{
	if(!GetConVarBool(convar_weaponeconomy_enabled))
		return;

	g_bBuytime = false;

	PrintToChatAll("Buytime ended!");
}

void StripPlayerWeapon(int client, int weaponslot)
{
	int weapon = GetPlayerWeaponSlot(client, weaponslot);

	if(!IsValidEntity(weapon))
		return;

	char classname[13];
	if(!GetEdictClassname(weapon, classname, 13))
	{
		LogError("[WE] couldn't get weapon classname");
		return;
	}

	RemoveEdict(weapon);

	switch(weaponslot)
	{
		case SLOT_PRIMARY:
		{
			PrintToServer("[WE] Removed primary weapon %s from %N", classname, client);
		}
		case SLOT_SECONDARY:
		{
			PrintToServer("[WE] Removed secondary weapon %s from %N", classname, client);
		}
	}
}

bool GivePlayerLastPrimaryWeapon(int client)
{
	if(!g_iPlayersHeldPrimaryWeapon[client][0])
		return false;

	#if DEBUG > 0
	PrintToServer("[WE] GivePlayerLastPrimaryWeapon: Giving %N (%i) %s", client, client, g_iPlayersHeldPrimaryWeapon[client]);
	#endif

	return GiveWeaponToPlayer(client, g_iPlayersHeldPrimaryWeapon[client]);
}

bool GivePlayerLastSecondaryWeapon(int client)
{
	if(!g_iPlayersHeldSecondaryWeapon[client][0])
		return false;

	#if DEBUG > 0
	PrintToServer("[WE] GivePlayerLastSecondaryWeapon: Giving %N (%i) %s", client, client, g_iPlayersHeldSecondaryWeapon[client]);
	#endif

	// Get current secondary weapon if any
	int currentwpn = GetPlayerWeaponSlot(client, SLOT_SECONDARY);

	if(IsValidEdict(currentwpn))
	{
		char classname[20];
		GetEdictClassname(currentwpn, classname, 20);

		if(!StrEqual(classname, g_iPlayersHeldSecondaryWeapon[client]))
		{
			// Stored different weapon than what we spawned with, remove it
			StripPlayerWeapon(client, SLOT_SECONDARY);
		}
		else
		{
			// Already spawned with that weapon
			return true;
		}
	}

	return GiveWeaponToPlayer(client, g_iPlayersHeldSecondaryWeapon[client]);
}

bool GiveWeaponToPlayer(int client, const char[] weaponclassname)
{
	int ent = GivePlayerItem(client, weaponclassname);

	if(ent == -1)
	{
		PrintToServer("[DEBUG] Invalid Weapon Item: %s", weaponclassname);
		return false;
	}
	else
	{
		return true;
	}
}

void StoreWeapon(int client, int weapon, int slottype)
{
	if(weapon == -1 || !IsValidEdict(weapon))
		return;

	char classname[20];
	if(!GetEdictClassname(weapon, classname, 20))
		return;

	#if DEBUG > 0
	PrintToServer("[WE] Storing Weapon %s (%i) for client %N", classname, weapon, client);
	#endif

	switch(slottype)
	{
		case SLOT_PRIMARY:
		{
			g_iPlayersHeldPrimaryWeapon[client] = classname;
		}
		case SLOT_SECONDARY:
		{
			g_iPlayersHeldSecondaryWeapon[client] = classname;
		}
		case SLOT_GRENADE:
		{
			if(StrEqual(classname, "weapon_grenade"))
				g_iPlayersHeldGrenades[client] = classname;
		}
	}
}
