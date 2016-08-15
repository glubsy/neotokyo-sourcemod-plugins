#include <sourcemod>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define DEBUG 0
#define COLLISION_GROUP_WEAPON 11

public Plugin myinfo =
{
	name = "NEOTOKYO: non solid ghost trays",
	author = "glub, soft as HELL",
	description = "Removes collisions for players with ghost trays to avoid being stuck",
	version = "0.2",
	url = "https://github.com/glubsy"
}

char model_list[][] = {
	"models/nt/props_tech/ghostcase.mdl",
	"models/nt/props_tech/monitor_ghostcase.mdl",
	"models/nt/props_tech/ghostcase_hackbar.mdl"
};

public void OnEntityCreated(int entity, const char[] classname)
{
	if(!IsValidEdict(entity))
		return;

	if(StrContains(classname, "prop_physics", false) == -1)
		return;

	// Unable to get model name here so we will just have to hook all props
	SDKHook(entity, SDKHook_SpawnPost, OnPropSpawn);
}

// Called each round after the prop respawns
public void OnPropSpawn(int entity)
{
	if(!IsValidEdict(entity))
		return;

	char classname[32];
	if(!GetEntityClassname(entity, classname, sizeof(classname)))
		return; // Can't get class name

	char modelname[64];
	GetEntPropString(entity, Prop_Data, "m_ModelName", modelname, sizeof(modelname));

	for(int i = 0; i < sizeof(model_list); i++)
	{
		if(!StrEqual(modelname, model_list[i]))
			continue;

		#if DEBUG > 0
		int m_CollisionGroup = GetEntProp(entity, Prop_Send, "m_CollisionGroup");

		PrintToServer("[OnPropSpawn] %s (%d) %s | m_CollisionGroup: %d", classname, entity, modelname, m_CollisionGroup);
		#endif

		// Collision data isn't properly set yet so we will have to do it later
		CreateTimer(5.0, ChangePropCollisionGroup, EntIndexToEntRef(entity));

		return;
	}
}

public Action ChangePropCollisionGroup(Handle timer, int entity)
{
	if(!IsValidEdict(entity))
		return Plugin_Continue;

	#if DEBUG > 0
	int m_CollisionGroup = GetEntProp(entity, Prop_Send, "m_CollisionGroup");

	PrintToServer("[ChangePropCollisionGroup] %d | m_CollisionGroup: %d", EntRefToEntIndex(entity), m_CollisionGroup);
	#endif

	// Attempt to change collision group
	SetEntProp(entity, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_WEAPON);
	SetEntProp(entity, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_WEAPON);

	return Plugin_Continue;
}
