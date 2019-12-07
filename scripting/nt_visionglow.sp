#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#pragma semicolon 1

#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif

#define USE_LIGHTGLOW 0 // previous method which doesn't work because of a bug :(
// #define SPRITEMDL "sprites/light_glow02.vmt" // bigger
// #define SPRITEMDL "sprites/combineball_glow_red_1.vmt"
// #define SPRITEMDL "sprites/combineball_glow_blue_1.vmt"
// #define SPRITEMDL "sprites/dot.vmt" // small, no glow
// #define SPRITEMDL "sprites/fire_floor.vmt" // faded
// #define SPRITEMDL "sprites/glow1.vmt" //
// #define SPRITEMDL "sprites/glow01.vmt" // small center
// #define SPRITEMDL "sprites/glow02.vmt" // bigger
// #define SPRITEMDL "sprites/glow03.vmt" //
// #define SPRITEMDL "sprites/glow04.vmt" //
// #define SPRITEMDL "sprites/glow06.vmt" // faded
// #define SPRITEMDL "sprites/greenglow1.vmt"
// #define SPRITEMDL "sprites/halo01.vmt"
// #define SPRITEMDL "sprites/physcannon_blueglow.vmt"
// #define SPRITEMDL "sprites/purpleglow1.vmt"
// #define SPRITEMDL "sprites/redglow1.vmt" // needs red color channel
// #define SPRITEMDL "sprites/redglow2.vmt"
// #define SPRITEMDL "sprites/redglow3.vmt"
// #define SPRITEMDL "sprites/redglow4.vmt"
// #define SPRITEMDL "sprites/yellowflare.vmt"
// #define SPRITEMDL "sprites/yellowglow1.vmt"
#define SPRITEMDL "sprites/light_glow01.vmt" // Good one.
#define TARGETMDL "models/editor/ground_node_hint.mdl"


enum modelType {
	MDL_NONE = -1, jrecon1 = 0, jrecon2, jrecon3, nrecon1, nrecon2, nrecon3,
	jassault1, jassault2, jassault3, nassault1, nassault2, nassault3, jsupport1,
	jsupport2, jsupport3, nsupport1, nsupport2, nsupport3 }

new const String:modelStrings[][] = {
	"models/player/jinrai_msf.mdl", // jinrai recon 1
	"models/player/jinrai_msf2.mdl", // jinrai recon 2
	"models/player/jinrai_msf3.mdl", // jinrai recon 3
	"models/player/nsf_gsf.mdl", // nsf recon 1
	"models/player/nsf_gsf2.mdl", // nsf recon 2
	"models/player/nsf_gsf3.mdl", // nsf recon 3
	"models/player/jinrai_mam.mdl", // jinrai assault 1
	"models/player/jinrai_mam2.mdl", // jinrai assault 2
	"models/player/jinrai_mam3.mdl", // jinrai assault 3
	"models/player/nsf_gam.mdl", // nsf assault 1
	"models/player/nsf_gam2.mdl", // nsf assault 2
	"models/player/nsf_gam3.mdl", // nsf assault 3
	"models/player/jinrai_mhm.mdl", // jinrai support 1
	"models/player/jinrai_mhm2.mdl", // jinrai support 2
	"models/player/jinrai_mhm3.mdl", // jinrai support 3
	"models/player/nsf_ghm.mdl", // nsf support 1
	"models/player/nsf_ghm2.mdl", // nsf support 2
	"models/player/nsf_ghm3.mdl" // nsf support 3
};

bool gbIsObserver[NEO_MAX_CLIENTS+1];
bool gbHeldKey[NEO_MAX_CLIENTS+1];
bool gbVisionActive[NEO_MAX_CLIENTS+1];
int giTarget[NEO_MAX_CLIENTS+1];
int giGlow[NEO_MAX_CLIENTS+1];
int giClassType[NEO_MAX_CLIENTS+1];
Handle cvar_SpecOnly = INVALID_HANDLE;
// Handle ghTimerSpawn[NEO_MAX_CLIENTS+1] = {INVALID_HANDLE, ...};
modelType giModelType[NEO_MAX_CLIENTS+1];

public Plugin:myinfo =
{
	name = "NEOTOKYO vision glow",
	author = "glub",
	description = "Glowing halo when using vision mode.",
	version = "0.2",
	url = "https://github.com/glubsy"
};

public void OnPluginStart()
{
	cvar_SpecOnly = CreateConVar("sm_visionglow_speconly", "0",
	"Only show glowing vision halo to spectators", _, true, 0.0, true, 1.0);

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("game_round_end", OnRoundEnd);

	AutoExecConfig(true, "nt_visionglow");

	#if DEBUG
	HookConVarChange(FindConVar("neo_restart_this"), OnNeoRestartThis);
	#endif

	// late loading
	for (int i = MaxClients; i; --i)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		gbIsObserver[i] = true;
	}
}


public void OnNeoRestartThis(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!strncmp(oldValue, "1", 1))
		return;

	#if DEBUG
	PrintToChatAll("[ghostpos] OnNeoRestartThis() %s->%s", oldValue, newValue);
	#endif

	for (int client = MaxClients; client; --client)
	{
		if (!IsValidClient(client))
			continue;

		KillEnts(client);
		giGlow[client] = -1;
		giTarget[client] = -1;
	}
}


public OnMapStart()
{
	PrecacheModel(TARGETMDL, true);
	PrecacheModel(SPRITEMDL, true);
}


// NOTE called on plugin reload
public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	for (int client = MaxClients; client; --client)
	{
		if (!IsValidClient(client))
			continue;

		// KillEnts(client);
	}

	#if DEBUG
	char classname[255];
	for (int entity = MaxClients +1; entity <= GetEntityCount(); ++entity)
	{
		if (!IsValidEntity(entity))
			continue;

		GetEntityClassname(entity, classname, sizeof(classname));

		if (!strcmp(classname, "env_lightglow"))
		{
			PrintToServer("Entity: %s %d", classname, entity);
			continue;
		}

		if (!strcmp(classname, "info_target"))
		{
			PrintToServer("Entity: %s %d", classname, entity);
			char entname[255];
			GetEntPropString(entity, Prop_Data, "m_target", entname, sizeof(entname));
			PrintToServer("info_target name is %s. Killing it anyway", entname);
			AcceptEntityInput(entity, "kill");
		}
	}
	#endif
}

#if DEBUG
public void OnEntityDestroyed(int entity)
{
	char classname[255];
	GetEntityClassname(entity, classname, sizeof(classname));

	if (!strcmp(classname, "env_lightglow") || !strcmp(classname, "info_target"))
	{
		PrintToServer("Deleted: %s %d", classname, entity);
	}
}
#endif

#if DEBUG
public void OnEntityCreated(int entity)
{
	char classname[255];
	GetEntityClassname(entity, classname, sizeof(classname));

	if (!strcmp(classname, "env_lightglow") || !strcmp(classname, "info_target"))
	{
		PrintToServer("Created: %s %d", classname, entity);
	}
}
#endif


public Action OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	for (int client = MaxClients; client; --client)
	{
		if (!IsValidClient(client))
			continue;
		KillEnts(client);
	}
}

void KillEnts(int client)
{
	#if DEBUG
	PrintToServer("[visionglow] KillEnts for %N (%d)", client, client);
	#endif

	// Killed accross rounds by the game
	if (giGlow[client] > MaxClients)
	{
		#if DEBUG
		PrintToServer("[visionglow] removing glow ent for %N (%d)", client, giGlow[client]);
		#endif
		// #if !DEBUG
		if (GetConVarBool(cvar_SpecOnly))
			SDKUnhook(giGlow[client], SDKHook_SetTransmit, Hook_SetTransmitSpecOnly);
		else
			SDKUnhook(giGlow[client], SDKHook_SetTransmit, Hook_SetTransmit);
		// #endif

		// SetGlowColor(giGlow[client], 0);
		HideSprite(giGlow[client]);

		if (!AcceptEntityInput(giGlow[client], "ClearParent"))
		{
			#if DEBUG
			PrintToServer("[visionglow] failed ClearParent on glow for %N", client);
			#endif
		}
		if (!AcceptEntityInput(giGlow[client], "Kill"))
		{
			#if DEBUG
			PrintToServer("[visionglow] failed Kill on glow for %N", client);
			#endif
		}
	}

	// not killed accross rounds by the game!
	if (giTarget[client] > MaxClients)
	{
		#if DEBUG
		PrintToServer("[visionglow] removing target for %N (%d)", client, giTarget[client]);
		#endif
		if (!AcceptEntityInput(giTarget[client], "ClearParent"))
		{
			#if DEBUG
			PrintToServer("[visionglow] failed ClearParent on target for %N", client);
			#endif
		}
		else
		{
			#if DEBUG
			PrintToServer("[visionglow] Success in ClearParent on target for %N", client);
			#endif
		}
		if (!AcceptEntityInput(giTarget[client], "Kill"))
		{
			#if DEBUG
			PrintToServer("[visionglow] failed Kill on target for %N", client);
			#endif
		}
		else
		{
			#if DEBUG
			PrintToServer("[visionglow] success on Kill on target for %N", client);
			#endif
		}
	}
	giGlow[client] = -1;
	giTarget[client] = -1;
}


public Action OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

	gbIsObserver[client] = true;
	gbVisionActive[client] = true;

	CreateTimer(0.3, timer_SpawnPost, userid, TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_SpawnPost(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (!IsValidClient(client) || IsFakeClient(client))
		return Plugin_Handled;

	// avoid hooking first connection "spawn"
	if (GetClientTeam(client) < 2)
	{
		#if DEBUG
		PrintToServer("[visionhalo] OnClientSpawned_Post (%N) team is %d. Ignoring.",
		client, GetClientTeam(client));
		#endif
		gbIsObserver[client] = true;
		gbVisionActive[client] = true;

		return Plugin_Handled;
	}

	// avoid hooking spectator spawns
	if (IsClientObserver(client))
	{
		#if DEBUG
		PrintToServer("[visionhalo] OnClientSpawned ignored because %N (%d) is a spectator.",
		client, client);
		#endif
		gbIsObserver[client] = true;
		gbVisionActive[client] = false;

		return Plugin_Handled;
	}

	#if DEBUG
	PrintToServer("[visionhalo] CLIENT %N (%d) IS SPAWNING!.", client, client);
	#endif

	giClassType[client] = GetEntProp(client, Prop_Send, "m_iClassType");
	giModelType[client] = GetModelType(client);

	giTarget[client] = CreateInfoTarget(client, giModelType[client]);

	#if USE_LIGHTGLOW
	giGlow[client] = CreateGlow(giTarget[client], giClassType[client]);
	#else
	giGlow[client] = CreateSprite(giTarget[client], giClassType[client]);
	#endif

	// #if !DEBUG
	if (GetConVarBool(cvar_SpecOnly))
		SDKHook(giGlow[client], SDKHook_SetTransmit, Hook_SetTransmitSpecOnly);
	else
		SDKHook(giGlow[client], SDKHook_SetTransmit, Hook_SetTransmit);
	// #endif

	gbIsObserver[client] = false;
	gbVisionActive[client] = false;

	#if DEBUG
	PrintToServer("[visionglow] Created glow %d on target %d for %N class %d",
	giGlow[client], giTarget[client], client, giClassType[client]);
	#endif

	return Plugin_Handled;
}

modelType GetModelType(int client)
{
	char modelpath[PLATFORM_MAX_PATH];
	GetEntPropString(client, Prop_Data, "m_ModelName", modelpath, sizeof(modelpath));

	#if DEBUG
	PrintToServer("[visionglow] %N has model %s", client, modelpath);
	#endif

	for (int i = 0; i < sizeof(modelStrings); ++i)
	{
		if (!strcmp(modelpath, modelStrings[i]))
		{
			return view_as<modelType>(i);
		}
	}

	return MDL_NONE;
}

public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	KillEnts(victim);
}

public void OnClientDisconnect(int client)
{
	KillEnts(client);
}


stock void SetGlowColor(int glowEnt, int classType)
{
	int m_clrRenderoffset = FindSendPropOffs("CLightGlow", "m_clrRender");

	#if DEBUG
	float vecPos[3];
	GetEntPropVector(glowEnt, Prop_Send, "m_vecOrigin", vecPos);

	PrintToServer("[visionglow] Setting colortype %d on %d at %f %f %f",
	classType, glowEnt, vecPos[0], vecPos[1], vecPos[2]);
	int r = GetEntData(glowEnt, m_clrRenderoffset, 1);
	int g = GetEntData(glowEnt, m_clrRenderoffset + 1, 1);
	int b = GetEntData(glowEnt, m_clrRenderoffset + 2, 1);
	int a = GetEntData(glowEnt, m_clrRenderoffset + 3, 1);
	int t = GetEntData(glowEnt, m_clrRenderoffset, 4);
	PrintToServer("[visionglow] Colors before %d %d %d %d total %d", r, g, b, a, t);
	#endif

	char rendercolor[20];
	char color[20];

	switch (classType)
	{
		case CLASS_SUPPORT:
		{
			Format(rendercolor, sizeof(rendercolor), "100 100 200");
			Format(color, sizeof(color), "100 100 200");
			r = 100;
			g = 100;
			b = 200;
			a = 255;
		}
		case CLASS_ASSAULT:
		{
			Format(rendercolor, sizeof(rendercolor), "179 60 0");
			Format(color, sizeof(color), "179 60 0");
			r = 179; // 179
			g = 60; // 60
			b = 0; // 0
			a = 255;
		}
		case CLASS_RECON:
		{
			Format(rendercolor, sizeof(rendercolor), "74 199 1");
			Format(color, sizeof(color), "74 199 1");
			r = 74; // 74
			g = 199; // 199
			b = 1; // 1
			a = 255;
		}
		case 0: // turn off
		{
			Format(rendercolor, sizeof(rendercolor), "0 0 0"); // 0 0 0
			Format(color, sizeof(color), "0 0 0");
			r = 0;
			g = 0;
			b = 0;
			a = 255;
		}
		default:
		{
			Format(rendercolor, sizeof(rendercolor), "100 0 255"); // 100 0 255
			Format(color, sizeof(color), "100 255 255");
			r = 100;
			g = 0;
			b = 255;
			a = 255;
		}
	}

	#if DEBUG
	PrintToServer("[visionglow] Changing to rendercolor \"%s\" color \"%s\" rgba: %d %d %d %d",
	rendercolor, color, r, g, b, a);
	#endif

	DispatchKeyValue(glowEnt, "rendercolor", rendercolor);
	SetVariantString(color);
	AcceptEntityInput(glowEnt, "Color");

	// DispatchKeyValue(glowEnt, "MinDist", "3000"); // 6000
	// DispatchKeyValue(glowEnt, "MaxDist", "1");

	// SetEntityRenderColor(glowEnt, 100, 0, 255, 200);
	SetEntData(glowEnt, m_clrRenderoffset, 		r, 1, true);
	SetEntData(glowEnt, m_clrRenderoffset + 1, 	g, 1, true);
	SetEntData(glowEnt, m_clrRenderoffset + 2, 	b, 1, true);
	SetEntData(glowEnt, m_clrRenderoffset + 3, 	a, 1, true);

	// ChangeEdictState(glowEnt);
	// DispatchSpawn(glowEnt);
	// ActivateEntity(glowEnt);
}


// NOTE info_target ens are NOT removed accross rounds!
// https://developer.valvesoftware.com/wiki/S_PreserveEnts
int CreateInfoTarget(int client, modelType model)
{
	// seems to work (in this case) with EF_PARENT_ANIMATES https://developer.valvesoftware.com/wiki/Effect_flags
	// int iEnt = CreateEntityByName("info_target");
	int iEnt = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(iEnt, "model", TARGETMDL); //12 polygons

	// these hacks were used with prop_dynamic_override and to optimize a bit
	DispatchKeyValue(iEnt,"damagetoenablemotion","0");
	DispatchKeyValue(iEnt,"forcetoenablemotion","0");
	DispatchKeyValue(iEnt,"Damagetype","0");
	DispatchKeyValue(iEnt,"disablereceiveshadows","1");
	DispatchKeyValue(iEnt,"massScale","0");
	DispatchKeyValue(iEnt,"nodamageforces","0");
	DispatchKeyValue(iEnt,"shadowcastdist","0");
	DispatchKeyValue(iEnt,"disableshadows","1");
	DispatchKeyValue(iEnt,"spawnflags","1670");
	DispatchKeyValue(iEnt,"PerformanceMode","1");
	DispatchKeyValue(iEnt,"rendermode","10");
	DispatchKeyValue(iEnt,"physdamagescale","0");
	DispatchKeyValue(iEnt,"physicsmode","2");

	#if DEBUG
	char ent_name[20];
	Format(ent_name, sizeof(ent_name), "%s_lightglow", sTag);
	DispatchKeyValue(iEnt, "targetname", ent_name);

	PrintToServer("[visionglow] Created info_target (%d) on client %d :%s",
	iEnt, client, ent_name);
	#endif

	DispatchSpawn(iEnt);

	SetVariantString("!activator");
	AcceptEntityInput(iEnt, "SetParent", client, client, 0);

	DispatchKeyValue(iEnt,"renderfx","256"); // EF_PARENT_ANIMATES (instead of 0)
	SetEntProp(iEnt, Prop_Data, "m_iEFlags", (1<<7)); // EFL_FORCE_CHECK_TRANSMIT

	DataPack dp = CreateDataPack();
	WritePackCell(dp, iEnt);
	WritePackCell(dp, model);
	CreateTimer(0.1, timer_SetAttachmentPosition, dp,
	TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
	return iEnt;
}

// Create glow and attach to target since we can't attach to player directly
// NOTE: env_lightglow ents are removed accross rounds!
// Doesn't totally work. The origin for the fade is stuck at the origin during initial spawn of the entity :(
// which means it doesn't update the fade distance dynamically
stock int CreateGlow(int target, int classType)
{
	int glowEnt = CreateEntityByName("env_lightglow");
	DispatchKeyValue(glowEnt, "rendercolor", "0 0 0");
	// SetVariantString("255 155 255"); // there should be an alpha value according to source code
	// AcceptEntityInput(glowEnt, "Color"); 		// takes precedence over rendercolor?

	if (classType == CLASS_RECON)
		DispatchKeyValue(glowEnt, "MinDist", "3000"); // lower values don't work?
	else
		DispatchKeyValue(glowEnt, "MinDist", "3000"); // 6000

	DispatchKeyValue(glowEnt, "MaxDist", "1");
	// DispatchKeyValue(glowEnt, "OuterMaxDist", "1600");

	// DispatchKeyValue(glowEnt, "origin", );

	DispatchKeyValue(glowEnt, "VerticalGlowSize", "7"); // 16
	DispatchKeyValue(glowEnt, "HorizontalGlowSize", "7"); // 16
	// DispatchKeyValue(glowEnt, "spawnflags", "1");
	DispatchKeyValue(glowEnt, "GlowProxySize", "1.0"); // 2.0
	DispatchKeyValue(glowEnt, "HDRColorScale", "2.0");

	DispatchKeyValue(glowEnt,"renderfx","256"); // EF_PARENT_ANIMATES (instead of 0)

	// SetEntProp(glowEnt, Prop_Data, "m_iEFlags", (1<<7)); //FL_FORCE_CHECK_TRANSMIT should be set already

	// char glow[64];
	// Format(glow, sizeof(glow), "glow%i", glowEnt);
	// DispatchKeyValue(glowEnt, "targetname", glow);

	// Format(glow, sizeof(glow), "%d", client);
	// DispatchKeyValue(glowEnt, "paretname", glow);

	// SetEntProp(glowEnt, Prop_Data, "m_nRenderMode", RENDER_TRANSALPHA, 1);

	DispatchSpawn(glowEnt);
	// ActivateEntity(glowEnt);

	#if DEBUG
	float vecPos[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecPos);
	// vecPos[2] += 30.0;
	// TeleportEntity(glowEnt, vecPos, NULL_VECTOR, NULL_VECTOR);
	#endif

	SetVariantString("!activator");
	AcceptEntityInput(glowEnt, "SetParent", target, glowEnt, 0);

	// this does the same as the above
	// SetEntPropEnt(glowEnt, Prop_Send, "moveparent", target);

	#if DEBUG
	float m_vecAbsOrigin[3];
	GetEntPropVector(glowEnt, Prop_Data, "m_vecAbsOrigin", m_vecAbsOrigin);
	GetEntPropVector(glowEnt, Prop_Send, "m_vecOrigin", vecPos);
	PrintToServer("After parenting, glow is at %f %f %f, m_vecAbsOrigin %f %f %f",
	vecPos[0], vecPos[1], vecPos[2], m_vecAbsOrigin[0], m_vecAbsOrigin[1], m_vecAbsOrigin[2]);
	#endif

	// SetEntPropVector(glowEnt, Prop_Send, "m_vecOrigin", vecPos);
	return glowEnt;
}


// This works, but the sprite is rendered through optic camo! :(
stock int CreateSprite(int target, int classType)
{
	int iEnt = CreateEntityByName("env_glow"); // env_sprite / env_glow same

	DispatchKeyValue(iEnt, "model", SPRITEMDL);

	DispatchKeyValue(iEnt, "rendermode", "3"); // 3 glow keeps size, 9 doesn't
	DispatchKeyValueFloat(iEnt, "GlowProxySize", 0.2);
	DispatchKeyValueFloat(iEnt, "HDRColorScale", 1.0);

	switch (classType)
	{
		case CLASS_RECON:
		{
			DispatchKeyValue(iEnt, "renderamt", "85");
			DispatchKeyValue(iEnt, "disablereceiveshadows", "1");
			DispatchKeyValue(iEnt, "renderfx", "26"); // 22 spotlight effect 26 fade near 23 cull distance
			DispatchKeyValue(iEnt, "rendercolor", "74 199 1"); // there should be an extra value for alpha here
			DispatchKeyValue(iEnt, "alpha", "85");
			DispatchKeyValue(iEnt, "m_bWorldSpaceScale", "1");
		}
		case CLASS_ASSAULT:
		{
			DispatchKeyValue(iEnt, "renderamt", "145");
			DispatchKeyValue(iEnt, "disablereceiveshadows", "1");
			DispatchKeyValue(iEnt, "renderfx", "26"); // 22 spotlight effect 26 fade near 23 cull distance
			DispatchKeyValue(iEnt, "rendercolor", "179 60 0"); // there should be an extra value for alpha here
			DispatchKeyValue(iEnt, "alpha", "145");
			DispatchKeyValue(iEnt, "m_bWorldSpaceScale", "1");
		}
		case CLASS_SUPPORT:
		{
			DispatchKeyValue(iEnt, "renderamt", "145");
			DispatchKeyValue(iEnt, "disablereceiveshadows", "1");
			DispatchKeyValue(iEnt, "renderfx", "26"); // 22 spotlight effect 26 fade near 23 cull distance
			DispatchKeyValue(iEnt, "rendercolor", "100 100 200"); // there should be an extra value for alpha here
			DispatchKeyValue(iEnt, "alpha", "145");
			DispatchKeyValue(iEnt, "m_bWorldSpaceScale", "1");
		}
	}

	DispatchSpawn(iEnt);

	SetVariantString("!activator");
	AcceptEntityInput(iEnt, "SetParent", target, iEnt, 0);

	return iEnt;
}

stock void ShowSprite(int sprite)
{
	if (sprite <= MaxClients)
		return;
	AcceptEntityInput(sprite, "ShowSprite");
}

stock void HideSprite(int sprite)
{
	if (sprite <= MaxClients)
		return;
	AcceptEntityInput(sprite, "HideSprite");
}


public Action timer_SetAttachmentPosition(Handle timer, DataPack dp)
{
	ResetPack(dp);
	int entity = ReadPackCell(dp);
	modelType model = ReadPackCell(dp);

	#if DEBUG
	PrintToServer("[visionglow] setting position for %d model index %d",
	entity, view_as<int>(model));
	#endif

	SetVariantString("eyes");
	AcceptEntityInput(entity, "SetParentAttachment");

	float vecPos[3];
	switch (model)
	{
		case jrecon1: // OK
		{
			vecPos[0] += 4.0600014; // forward 4.0600014
			vecPos[1] += 0.2000016; // +left -right 0.2000016
			vecPos[2] += 0.9300018; // + up - down 0.9300018
		}
		case jrecon2: // OK
		{
			vecPos[0] += 2.3900014; // forward 2.3900014
			vecPos[1] += 1.4000016; // +left -right 1.4000016
			vecPos[2] += 0.3900018; // + up - down 0.3900018
		}
		case jrecon3: // Ok
		{
			vecPos[0] += 4.7100014; // forward 3.9000014
			vecPos[1] += 0.2000016; // +left -right 0.1000016
			vecPos[2] += 0.6900018; // + up - down 0.9300018
		}
		case nrecon1: // OK
		{
			vecPos[0] += 4.1000045; // forward 4.1000045
			vecPos[1] += 1.5000016; // +left -right 1.5000016
			vecPos[2] += 0.1300018; // + up - down 0.1300018
		}
		case nrecon2: // OK
		{
			vecPos[0] += 3.7000515; // forward 3.7000515
			vecPos[1] += 1.4000016; // +left -right 1.4000016
			vecPos[2] -= 0.0006018; // + up - down 0.0006018
		}
		case nrecon3: // OK
		{
			vecPos[0] += 3.7000515; // forward 3.7000515
			vecPos[1] += 1.4000016; // +left -right 1.4000016
			vecPos[2] += 0.0006018; // + up - down 0.0006018
		}
		case jassault1: // OK
		{
			vecPos[0] += 5.5000010; // +forward 5.5000010
			vecPos[1] += 1.6300016; // - right 1.6300016
			vecPos[2] += 0.4540018; // + up - down 0.4540018
		}
		case jassault2: // OK
		{
			vecPos[0] += 4.6; // +forward 4.6
			vecPos[1] += 1.6300016; // - right 1.6300016
			vecPos[2] += 0.4540018; // + up - down 0.4540018
		}
		case jassault3: // OK
		{
			vecPos[0] += 5.010003; // +forward 5.010003
			vecPos[1] += 0.2000016; // - right 0.2000016
			vecPos[2] += 1.4340018; // + up - down 1.4340018
		}
		case nassault1: // OK
		{
			vecPos[0] += 4.6; // +forward 4.6
			vecPos[1] += 1.6300016; // - right 1.6300016
			vecPos[2] += 0.4540018; // + up - down 0.4540018
		}
		case nassault2: // OK
		{
			vecPos[0] += 4.6; // +forward 4.6
			vecPos[1] += 1.5900016; // - right 1.5900016
			vecPos[2] += 0.8540018; // + up - down 0.8540018
		}
		case nassault3: // OK
		{
			vecPos[0] += 5.780000; // +forward 5.780000
			vecPos[1] += 1.6300016; // - right 1.6300016
			vecPos[2] += 0.6540018; // + up - down 0.6540018
		}
		case jsupport1: // OK
		{
			vecPos[0] += 5.711001;
			vecPos[1] += 1.600001;
			vecPos[2] += 0.390001;
		}
		case jsupport2: // OK
		{
			vecPos[0] += 6.811001;
			// vecPos[1] += 1.600001;
			vecPos[2] += 1.990001;
		}
		case jsupport3: // OK
		{
			vecPos[0] += 6.491001;
			// vecPos[1] += 1.600001;
			vecPos[2] += 1.790001;
		}
		case nsupport1: // OK
		{
			vecPos[0] += 5.711001;
			vecPos[1] += 1.600001;
			vecPos[2] += 0.390001;
		}
		case nsupport2: // OK
		{
			vecPos[0] += 5.811001;
			vecPos[1] += 1.600001;
			vecPos[2] += 0.390001;
		}
		case nsupport3: // OK
		{
			vecPos[0] += 6.211001;
			vecPos[1] += 1.600001;
			vecPos[2] += 0.390001;
		}
		default:
		{
			vecPos[0] += 6.3;
		}
	}

	// TeleportEntity(iEnt, vecPos, NULL_VECTOR, NULL_VECTOR);
	SetEntPropVector(entity, Prop_Send, "m_vecOrigin", vecPos);

	// DispatchSpawn(entity);
}


public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (client == 0 || gbIsObserver[client] || IsFakeClient(client))
		return Plugin_Continue;

	#if DEBUG
	for (int i = MaxClients; i; --i)
	{
		if (IsClientInGame(i))
			SetEntPropFloat(i, Prop_Send, "m_fThermopticNRG", 10.0);
	}
	#endif

	if (buttons & IN_VISION)
	{
		if(!gbHeldKey[client])
		{
			gbHeldKey[client] = true;
			if (gbVisionActive[client])
			{
				// gbVisionActive[client] = GetEntProp(client, Prop_Send, "m_iVision") == 2 ? true : false;
				gbVisionActive[client] = false;
				#if USE_LIGHTGLOW
				SetGlowColor(giGlow[client], 0); // turn off
				#else
				HideSprite(giGlow[client]);
				#endif
			}
			else
			{
				gbVisionActive[client] = true; // we assume vision is active client-side
				#if USE_LIGHTGLOW
				SetGlowColor(giGlow[client], giClassType[client]); // turn on
				#else
				ShowSprite(giGlow[client]);
				#endif
			}
		}
	}
	else
	{
		gbHeldKey[client] = false;
	}
	return 	Plugin_Continue;
}


public Action Hook_SetTransmit(int entity, int client)
{
	if (entity == giGlow[client])
		return Plugin_Handled;
	return Plugin_Continue;
}


public Action Hook_SetTransmitSpecOnly(int entity, int client)
{
	if (entity == giGlow[client] || !IsClientObserver(client))
		return Plugin_Handled;
	return Plugin_Continue;
}