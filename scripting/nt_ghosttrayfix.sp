#include <sourcemod>
#include <sdkhooks>
#define PLUGIN_VERSION "0.1"
#pragma semicolon 1

public Plugin:myinfo = 
{
	name = "NEOTOKYO: non solid ghost trays",
	author = "glub",
	description = "Removes collisions for players with ghost trays to avoid being stuck",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
}

public OnPluginStart()
{
	HookEvent("game_round_start", OnRoundStart);
}

/*
public void OnMapStart()
{
	CreateTimer(16.0, timer_ChangeCollisionForGhostCase);
}*/


public Action OnRoundStart(Handle event, const char[] eventname, bool dontbroadcast)
{
	//for some reason, the collision group is reset after freeze time...
	CreateTimer(16.0, timer_ChangeCollisionForGhostCase);
}

public Action timer_ChangeCollisionForGhostCase(Handle timer)
{
	for(int prop = MaxClients + 1; prop <= 2048; prop++)
	{
		if(!IsValidEntity(prop))
			continue;
		
		char classbuffer[30];
		GetEntityClassname(prop, classbuffer, sizeof(classbuffer));
		
		if(!StrEqual(classbuffer, "prop_physics_multiplayer", false))
			continue; 
		
		char modelname[45];
		GetEntPropString(prop, Prop_Data, "m_ModelName", modelname, sizeof(modelname));
		if(StrEqual(modelname, "models/nt/props_tech/ghostcase.mdl", false) || StrEqual(modelname, "models/nt/props_tech/monitor_ghostcase.mdl", false) || StrEqual(modelname, "models/nt/props_tech/ghostcase_hackbar.mdl", false))
		{
			SDKHook(prop, SDKHook_Touch, Touch_Hook);
			SetEntProp(prop, Prop_Send, "m_CollisionGroup", 11); // 2 is fine, but not collisions with weapons, except ghost. :(
			SetEntProp(prop, Prop_Data, "m_CollisionGroup", 11);
			SetEntProp(prop, Prop_Data, "m_nSolidType", 6);
			//SetEntProp(prop, Prop_Data, "m_usSolidFlags", 136); 

			//LogError("[TEST] OnRoundStart changed: %s, collisiongroup prop_send %i, prop_data %i", modelname, GetEntProp(prop, Prop_Send, "m_CollisionGroup"),  GetEntProp(prop, Prop_Data, "m_CollisionGroup"));
		}
		
		
	}
}

public Action Touch_Hook(int prop, int client)
{
	if(client <= MaxClients && prop > 0 && !IsFakeClient(client) && IsValidEntity(client) && IsClientInGame(client) && IsPlayerAlive(client) && IsValidEdict(prop))
	{
		SetEntProp(prop, Prop_Send, "m_CollisionGroup", 11);
		SetEntProp(prop, Prop_Data, "m_CollisionGroup", 11);
		SetEntProp(prop, Prop_Data, "m_nSolidType", 6);
		//PrintToChatAll("%N touched %i", client, prop);
	}
}
