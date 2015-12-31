#include <sourcemod>
#include <sdktools>
#include <smlib>
#include <neotokyo>
#define DEBUG 0

new bool:IsClientSupport[MAXPLAYERS+1]

public Plugin:myinfo = 
{
	name = "NEOTOKYO: give knife to supports",
	author = "glub",
	description = "Automatically gives a knife to supports and switch to it",
	version = "0.2",
	url = "https://github.com/glubsy"
}

public OnPluginStart()
{
	#if DEBUG > 0
	AddCommandListener(SwapToWeaponSlottest, "slottest");
	#endif 
	
	AddCommandListener(cmd_handler, "setclass");
	HookEvent("player_spawn", event_PlayerSpawn);
}

#if DEBUG > 0
public Action SwapToWeaponSlottest(client, const String:command[], args) //slottest 0, 1, 2, 3 to test each slot
{
	decl String:cmd[3];
	GetCmdArgString(cmd, sizeof(cmd));
	new arg = StringToInt(cmd);
	
	SwapToWeaponSlot(client, arg);
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
			PrintToServer("%N is support. IsClientSupport is %b", client, IsClientSupport[client]);
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
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsClientInGame(client) && !IsPlayerAlive(client))
		return;
	if(IsPlayerSupport(client) == true)
		IsClientSupport[client] = true;
	
	if(IsClientSupport[client])  //FIXME: this is dumb, still needs a rewrite
	{
		//GivePlayerItem(client, "weapon_knife");
		Client_GiveWeapon(client, "weapon_knife", false); //SMLIB, false = do not equip
		
		//ClientCommand(client, "slot1"); //too hackish, forces votes in some cases. Do not use. See below instead.
		CreateTimer(0.1, timer_SwapToWeaponSlot, client)
	}
}

public bool IsPlayerSupport(client)
{
	int classtype = GetEntProp(client, Prop_Send, "m_iClassType");
	if(classtype == 3)
	{
		#if DEBUG > 0
		PrintToServer("classtype: %i for client: %N", classtype, client);
		#endif
		return true;
	}
	else
		return false;
}


public Action timer_SwapToWeaponSlot(Handle timer, client)
{
	//switching to pistol
	SwapToWeaponSlot(client, 0);	
	SwapToWeaponSlot(client, 3);	//note: for supports we have to spam slots in this order
	SwapToWeaponSlot(client, 1);	//otherwise we get viewmodel nodraw glitch
}

public Action SwapToWeaponSlot(int client, int slot)
{
	int currentweapon = GetWeaponFromSlot(client, slot);
	
	if((currentweapon != -1) && IsValidEdict(currentweapon) && IsValidEntity(currentweapon))
	{
		//  Set active weapon
		EquipPlayerWeapon(client, currentweapon); 
		SetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", currentweapon);
		ChangeEdictState(client, FindDataMapOffs(client, "m_hActiveWeapon"));
		
		//Client_SetActiveWeapon(client, currentweapon);	//smlib testing
		//Client_EquipWeapon(client, currentweapon, true);	//smlib testing
		//Client_ChangeToLastWeapon(client);				//smlib testing
		
		
		new String:classname[13];
		GetEdictClassname(currentweapon, classname, 13)
		#if DEBUG > 0
		PrintToChatAll("[]client %N switching to: slot %i, weapon: %s, wpnindex: %i", client, slot, classname, currentweapon);
		#endif
	}
}


public OnEntityCreated(entity, const String:classname[])
{
	if(StrEqual(classname, "smokegrenade_projectile")) // when client throws a smoke grenade
	{
		new client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(client > 0 && IsValidEntity(client) && IsPlayerAlive(client))
		{
			//ClientCommand(client, "slot1");	//not a recommnended method
			SwapToWeaponSlot(client, 2);
			SwapToWeaponSlot(client, 1);
			SwapToWeaponSlot(client, 0);	//switching progressively to primary slot
		}
	}
}
