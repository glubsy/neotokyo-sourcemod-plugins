#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>
#include <neotokyo>
#define DEBUG 0

bool IsClientSupport[MAXPLAYERS+1]
Handle g_CvarWeaponEconomyCheck = INVALID_HANDLE;
Handle g_CvarVIPModeCheck = INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "NEOTOKYO: give knife to supports",
	author = "glub",
	description = "Automatically gives a knife to supports and switch to it",
	version = "0.3",
	url = "https://github.com/glubsy"
}

public OnPluginStart()
{
	#if DEBUG > 0
	AddCommandListener(SwapToWeaponSlottest, "slottest");
	#endif 
	
	AddCommandListener(cmd_handler, "setclass");
	HookEvent("player_spawn", event_PlayerSpawn);
	//HookEvent("player_death", event_PlayerDeath);
	
	g_CvarWeaponEconomyCheck = FindConVar("sm_ntweaponeconomy_version");
	g_CvarVIPModeCheck = FindConVar("sm_nt_vip_enabled");
	
}

#if DEBUG > 0
public Action SwapToWeaponSlottest(client, const String:command[], args) //slottest 0, 1, 2, 3 to test each slot
{
	decl String:cmd[3];
	GetCmdArgString(cmd, sizeof(cmd));
	new arg = StringToInt(cmd);
	
	SwitchToWeaponSlot(client, arg);
	return Plugin_Handled;
}
#endif

public Action:cmd_handler(client, const String:command[], args)
{
	decl String:cmd[3];
	GetCmdArgString(cmd, sizeof(cmd));

	new arg = StringToInt(cmd);

	if(StrEqual(command, "setclass"))
	{
		if (arg == 3)
		{
			IsClientSupport[client] = true;
			#if DEBUG > 0
			PrintToServer("[SUPPORTKNIFE] %N is support. IsClientSupport is %b", client, IsClientSupport[client]);
			#endif
			
			return Plugin_Continue;
		}
		else
		{
			IsClientSupport[client] = false;
		}
	}
	return Plugin_Continue;
}

public event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsClientInGame(client) && !IsPlayerAlive(client))
		return;
	if(IsPlayerSupport(client) == true)
		IsClientSupport[client] = true;
	
	if(IsClientSupport[client])  //FIXME: this is dumb, still needs a rewrite
	{
		#if DEBUG > 0
		PrintToServer("[SUPPORTKNIFE] %N is support. Giving knife", client);
		#endif
		
		CreateTimer(0.1, timer_DelayGiveKnife, client); //delaying giving knife otherwise can't switch to last active weapon

		
		
		
		//this crashes the server once the player is killed! (why!?) we must kill the give knife right before death
		//Client_GiveWeapon(client, "weapon_knife", false); //SMLIB, false = do not equip -> doesn't work
	
		//CreateKnifeForPlayer(client);  //our safe weapon creation function
	}
}


public Action timer_DelayGiveKnife(Handle timer, int client)
{
	if(GivePlayerItem(client, "weapon_knife") != -1)
		CreateTimer(0.0, timer_SwitchToWeaponSlot, client)
}



stock void CreateKnifeForPlayer(int client)
{
	#if DEBUG > 0
	PrintToChatAll("[SUPPORTKNIFE] Making knife for %N", client);
	#endif
	
	decl knife;
	if((knife = CreateEntityByName("weapon_knife")) != -1)
	{
		float clientorigin[3];
		GetClientAbsOrigin(client, clientorigin);
		clientorigin[2] += 30.0;
		TeleportEntity(knife, clientorigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(knife);
		//DispatchKeyValueVector(knife, "origin", clientorigin);
		
		#if DEBUG > 0
		PrintToServer("[SUPPORTKNIFE] made knife at %f %f %f", clientorigin[0], clientorigin[1], clientorigin[2]);
		LogError("[SUPPORTKNIFE] made knife at %f %f %f. Index: %i", clientorigin[0], clientorigin[1], clientorigin[2], knife);
		#endif
	}
}

public bool IsPlayerSupport(client)
{
	int classtype = GetEntProp(client, Prop_Send, "m_iClassType");
	if(classtype == 3)
	{
		#if DEBUG > 0
		PrintToServer("[SUPPORTKNIFE] classtype: %i for client: %N", classtype, client);
		#endif
		return true;
	}
	else
		return false;
}


public Action timer_SwitchToWeaponSlot(Handle timer, client)
{
	if(g_CvarWeaponEconomyCheck != INVALID_HANDLE)
		return; //we run nt_weaponeconomy which switches to secondary already, do not do anything
	
	if(g_CvarVIPModeCheck != INVALID_HANDLE && GetConVarBool(g_CvarVIPModeCheck))
		return; //VIP mode active, VIPs have no primary on spawn and aready switch to secondary
	
	
	//we didn't find nt_weaponeconomy NOR nt_vip which conflict here, so we switch to primary safely
	if(g_CvarWeaponEconomyCheck == INVALID_HANDLE && g_CvarVIPModeCheck == INVALID_HANDLE) 
	{
		//switching to primary safely 0, 3, 0 (old methods to counter viewmodel glitch)
		//SwitchToWeaponSlot(client, 0);
		//SwitchToWeaponSlot(client, 3);
		//SwitchToWeaponSlot(client, 0);
		
		SwitchToLastWeapon(client);

		#if DEBUG > 0
		PrintToChatAll("[SUPPORTKNIFE] client %N attempted switch back weapon", client);
		#endif
	}
	
	/*
	//if VIP mode is loaded, but not active, switch to secondary in case we don't have primary
	if(g_CvarVIPModeCheck != INVALID_HANDLE)
	{
		//switching to pistol! As conflicting plugins remove primary which then causes viewmodel glitches
		//0 = primary, 1 = pistol
		//note: for supports we have to spam slots in this order (0, 3, 1 for pistol last) /otherwise we get viewmodel nodraw glitch
		SwitchToWeaponSlot(client, 0);
		SwitchToWeaponSlot(client, 3);
		SwitchToWeaponSlot(client, 1);
		
		//SwitchToLastWeapon(client);
		#if DEBUG > 0
		PrintToChatAll("[SUPPORTKNIFE] client %N attempted switch to secondary", client);
		#endif
	}
	*/
}

public SwitchToLastWeapon(int client)
{	
	return Client_ChangeToLastWeapon(client);
}


public int SwitchToWeaponSlot(int client, int slot)
{
	int currentweapon = GetPlayerWeaponSlot(client, slot);
	
	if((currentweapon != -1) && IsValidEdict(currentweapon) && IsValidEntity(currentweapon))
	{
		char classname[20];
		GetEdictClassname(currentweapon, classname, sizeof(classname));
		
		if((StrContains(classname, "weapon_")) != -1)
		{
			//  Set active weapon
			//EquipPlayerWeapon(client, currentweapon);	 THIS CRASHES THE SERVER on player death!
			
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", currentweapon);  //Works well enough, but no animation.
			ChangeEdictState(client, FindDataMapOffs(client, "m_hActiveWeapon"));
			
			//Client_SetActiveWeapon(client, currentweapon);	//smlib testing: works the same as above.
			//Client_EquipWeapon(client, currentweapon, true);	//smlib testing: CRASHES as it uses EquipPlayerWeapon, also if the primary wpn was dropped on floor, it's given back to owner! (always same wpn index)
			
			#if DEBUG > 0
			PrintToChatAll("[SUPPORTKNIFE] client %N forced switching to: slot %i, currentweapon: %s %i", client, slot, classname, currentweapon);
			PrintToServer("[SUPPORTKNIFE] client %N forced switching to: slot %i, currentweapon: %s %i", client, slot, classname, currentweapon);
			#endif
			return currentweapon;
		}
		#if DEBUG > 0
		PrintToServer("[SUPPORTKNIFE]  couldn't find weapon_ in string: %s", classname);
		#endif
		return 0;
	}
	return currentweapon;
}


//Killing dropped knife on death. Not necessary anymore (was for debugging EquipPlayerWeapon)
/*
public Action event_PlayerDeath (Handle:event, const String:name[], bool:dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	int classtype = GetEntProp(client, Prop_Send, "m_iClassType");
	if(classtype == 0)
	{
		int knife = GetPlayerWeaponSlot(client, 2);
		char classname[13];
		GetEdictClassname(knife, classname, 13);
		
		#if DEBUG > 0
		PrintToServer("[SUPPORTKNIFE] weapon detected in slot2: %s %i", classname, knife);
		LogError("[SUPPORTKNIFE] weapon detected in slot2: %s %i", classname, knife);
		#endif
		
		if(StrEqual(classname, "weapon_knife"))
		{		
			KillEntityKnife(knife);
		}
	}
}

public Action KillEntityKnife(int entity)
{
	#if DEBUG > 0
	PrintToServer("[SUPPORTKNIFE] Killing knife %i", entity);
	LogError("[SUPPORTKNIFE] Killing knife %i", entity);
	#endif
	
	//AcceptEntityInput(entity, "kill");
	RemoveEdict(entity);
}
*/

public OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "smokegrenade_projectile") || StrEqual(classname, "grenade_projectile"))
    {
        SDKHook(entity, SDKHook_SpawnPost, Grenade_SpawnPost);
    }
}

public Grenade_SpawnPost(int entity)
{
	new client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	
	if(client > 0 && IsValidEntity(client) && IsPlayerAlive(client))
	{
		/*
		//switching back towards primary slot
		if(IsWeaponPresentInSlot(client, 0))
		{
			ClientCommand(client, "slot1");	//not recommnended as it forces votes!
		}
		else if(IsWeaponPresentInSlot(client, 1))
		{
			ClientCommand(client, "slot2");
		}
		*/
		
		//if(SwitchToWeaponSlot(client, 0) <= 0) //if there is no primary(0) we switch to secondary(1)
		//{
		//	SwitchToWeaponSlot(client, 1); // not pretty as switching animation is not played. :(
		//}
		//SwitchToLastWeapon(client); //or use this simply
		
		
		//Latest and best method: prevent switching to knife, then allow again
		SDKHook(client, SDKHook_WeaponCanSwitchTo, Hook_WeaponCanSwitchTo);
		CreateTimer(0.1, timer_AllowSwitchingToKnife, client);
	}
}

public Action Hook_WeaponCanSwitchTo(int client, int weapon) 
{
	char classname[15];
	GetEdictClassname(weapon, classname, sizeof(classname));
	if(StrEqual(classname, "weapon_knife"))
	{
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action timer_AllowSwitchingToKnife(Handle timer, int client)
{
	SDKUnhook(client, SDKHook_WeaponCanSwitchTo, Hook_WeaponCanSwitchTo);
}

public bool IsWeaponPresentInSlot(int client, int slot)
{
	int currentweapon = GetPlayerWeaponSlot(client, slot);
	
	if((currentweapon != -1) && IsValidEdict(currentweapon) && IsValidEntity(currentweapon))
	{
		char classname[20];
		GetEdictClassname(currentweapon, classname, sizeof(classname));
		
		if((StrContains(classname, "weapon_")) != -1)
		{
			return true;
		}
		return false;
	}
	return false;
}