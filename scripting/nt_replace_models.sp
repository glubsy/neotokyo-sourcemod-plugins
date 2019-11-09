#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma semicolon 1

new const String:g_GrenadeModel[][] = { 
	"models/nt/a_lil_tiger.mdl",
	"models/nt/props_street/rabbit_doll.mdl",
	"models/nt/props_office/rubber_duck.mdl",
	"models/nt/props_street/bass_guitar.mdl",
	"models/nt/props_nature/crab.mdl",
	"models/nt/props_tech/not_the_ghost.mdl"
};

public Plugin:myinfo = {
	name = "Neotokyo replace models",
	description = "Replace models arbitrarily.",
	author = "glub",
	version = "0.1",
	url = "http://github.com/glubsy"
};

//TODO: replace models in the map

public OnMapStart()
{
	for(new item = 0; item < sizeof(g_GrenadeModel); item++)
	{
		if (!IsModelPrecached(g_GrenadeModel[item]))
			PrecacheModel(g_GrenadeModel[item], true);

		// decl String:buffer[120];
		// AddFileToDownloadsTable(buffer);
	}

}

public OnConfigsExectured()
{

}

public OnEntityCreated(entity, const String:classname[])
{
	if(StrEqual(classname, "grenade_projectile"))
		SDKHook(entity, SDKHook_SpawnPost, SpawnPost_Grenade);

	if(StrEqual(classname, "smokegrenade_projectile"))
		SDKHook(entity, SDKHook_SpawnPost, SpawnPost_Grenade);

	if(StrEqual(classname, "grenade_detapack"))
		SDKHook(entity, SDKHook_SpawnPost, SpawnPost_Grenade);
}


public SpawnPost_Grenade(entity)
{
	int rand = GetRandomInt(0, sizeof(g_GrenadeModel) -1);
	SetEntityModel(entity, g_GrenadeModel[rand]);
}