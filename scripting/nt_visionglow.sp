#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#pragma semicolon 1
#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif
bool gbIsObserver[NEO_MAX_CLIENTS+1];
bool gbHeldKey[NEO_MAX_CLIENTS+1];
bool gbVisionActive[NEO_MAX_CLIENTS+1];
int giTarget[NEO_MAX_CLIENTS+1];
int giGlow[NEO_MAX_CLIENTS+1];
int giClassType[NEO_MAX_CLIENTS+1];

public Plugin:myinfo =
{
	name = "NEOTOKYO vision glow",
	author = "glub",
	description = "Glowing halo when using vision mode.",
	version = "0.1",
	url = "https://github.com/glubsy"
};

public void OnPluginStart()
{
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("game_round_end", OnRoundEnd);

	#if DEBUG
	HookConVarChange(FindConVar("neo_restart_this"), OnNeoRestartThis);
	#endif
}


public void OnNeoRestartThis(ConVar convar, const char[] oldValue, const char[] newValue)
{
	// #if DEBUG
	// PrintToChatAll("[ghostpos] OnNeoRestartThis() %s->%s", oldValue, newValue);
	// #endif

	if (!strcmp(oldValue, "1"))
		return;

	for (int client = MaxClients; client; --client)
	{
		if (!IsValidClient(client))
			continue;

		KillEnts(client);
		giGlow[client] = -1;
		giTarget[client] = -1;
	}
}


public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	for (int client = MaxClients; client; --client)
	{
		if (!IsValidClient(client))
			continue;

		KillEnts(client);
	}
}


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
	if (giGlow[client] > MaxClients)
	{
		AcceptEntityInput(giGlow[client], "ClearParent");
		AcceptEntityInput(giGlow[client], "Kill");
	}
	if (giTarget[client] > MaxClients)
	{
		AcceptEntityInput(giTarget[client], "ClearParent");
		AcceptEntityInput(giTarget[client], "Kill");
	}
	giGlow[client] = -1;
	giTarget[client] = -1;
}


public Action OnPlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	// avoid hooking first connection "spawn"
	if (GetClientTeam(client) < 2)
	{
		#if DEBUG
		PrintToServer("[visionhalo] OnClientSpawned_Post (%N) team is %d. Ignoring.",
		client, GetClientTeam(client));
		#endif
		gbIsObserver[client] = true;
		gbVisionActive[client] = true;
		return;
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
		return;
	}

	giClassType[client] = GetEntProp(client, Prop_Send, "m_iClassType");

	gbIsObserver[client] = false;
	gbVisionActive[client] = false;

	giTarget[client] = CreateInfoTarget(client, "eyes", giClassType[client]);
	giGlow[client] = CreateGlow(giTarget[client]);

	#if DEBUG
	PrintToServer("[visionglow] Created glow %d on target %d for %N class %d",
	giGlow[client], giTarget[client], client, giClassType[client]);
	#endif
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


void SetGlowColor(int glowEnt, int classType)
{
	// new m_iR = GetEntProp(glowEnt, Prop_Data, "m_clrRender", 1, 0);
	// new m_iG = GetEntProp(glowEnt, Prop_Data, "m_clrRender", 1, 1);
	// new m_iB = GetEntProp(glowEnt, Prop_Data, "m_clrRender", 1, 2);
	// new m_iA = GetEntProp(glowEnt, Prop_Data, "m_clrRender", 1, 3);
	// new m_total = GetEntProp(glowEnt, Prop_Send, "m_clrRender", 1);

	int m_clrRenderoffset = FindSendPropOffs("CLightGlow", "m_clrRender");
	int r = GetEntData(glowEnt, m_clrRenderoffset, 1);
	int g = GetEntData(glowEnt, m_clrRenderoffset + 1, 1);
	int b = GetEntData(glowEnt, m_clrRenderoffset + 2, 1);
	int a = GetEntData(glowEnt, m_clrRenderoffset + 3, 1);
	int t = GetEntData(glowEnt, m_clrRenderoffset, 4);

	#if DEBUG
	PrintToServer("[visionglow] Setting colortype %d on %d", classType, glowEnt);
	PrintToServer("[visionglow] Colors before %d %d %d %d total %d", r, g, b, a, t);
	#endif

	char rendercolor[20];
	char color[20];

	switch (classType)
	{
		case CLASS_SUPPORT:
		{
			Format(rendercolor, sizeof(rendercolor), "255 0 0");
			Format(color, sizeof(color), "255 0 0");
			r = 100;
			g = 100;
			b = 200;
			a = 255;
		}
		case CLASS_ASSAULT:
		{
			Format(rendercolor, sizeof(rendercolor), "255 0 0");
			Format(color, sizeof(color), "255 0 0");
			r = 100;
			g = 100;
			b = 200;
			a = 255;
		}
		case CLASS_RECON:
		{
			Format(rendercolor, sizeof(rendercolor), "255 0 0");
			Format(color, sizeof(color), "255 0 0");
			r = 100;
			g = 100;
			b = 200;
			a = 255;
		}
		case 0: // turn off
		{
			Format(rendercolor, sizeof(rendercolor), "0 0 0");
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
		}
	}

	#if DEBUG
	PrintToServer("[visionglow] Changing to rendercolor \"%s\" color \"%s\" rgba: %d %d %d %d",
	rendercolor, color, r, g, b, a);
	#endif

	DispatchKeyValue(glowEnt, "rendercolor", rendercolor);
	SetVariantString(color);
	AcceptEntityInput(glowEnt, "Color");
	DispatchKeyValue(glowEnt, "MinDist", "2000"); // 6000
	DispatchKeyValue(glowEnt, "MaxDist", "0");
	// DispatchKeyValue(glowEnt, "origin", );

	// SetEntityRenderColor(glowEnt, 100, 0, 255, 200);
	SetEntData(glowEnt, m_clrRenderoffset, 		r, 1, true);
	SetEntData(glowEnt, m_clrRenderoffset + 1, 	g, 1, true);
	SetEntData(glowEnt, m_clrRenderoffset + 2, 	b, 1, true);
	SetEntData(glowEnt, m_clrRenderoffset + 3, 	a, 1, true);

	ChangeEdictState(glowEnt);
	DispatchSpawn(glowEnt);
}


int CreateInfoTarget(int client, char[] sTag, int classType)
{
	// sems to work (in this case) with EF_PARENT_ANIMATES https://developer.valvesoftware.com/wiki/Effect_flags
	int iEnt = CreateEntityByName("info_target");
	// int iEnt = CreateEntityByName("prop_physics");
	// DispatchKeyValue(iEnt, "model", "models/nt/props_debris/can01.mdl");

	// these hacks were used with prop_dynamic_override and to optimize a bit
	DispatchKeyValue(iEnt,"renderfx","256"); // EF_PARENT_ANIMATES (instead of 0)
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
	Format(ent_name, sizeof(ent_name), "%s%d", sTag, client); // in case we need for env_beam end ent
	DispatchKeyValue(iEnt, "targetname", ent_name);

	PrintToServer("[visionglow] Created info_target (%d) on client %d :%s",
	iEnt, client, ent_name);
	#endif

	DispatchSpawn(iEnt);

	SetVariantString("!activator");
	AcceptEntityInput(iEnt, "SetParent", client, client, 0);

	DataPack dp = CreateDataPack();
	WritePackCell(dp, iEnt);
	WritePackCell(dp, classType);
	CreateTimer(0.1, timer_SetAttachmentPosition, dp,
	TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
	return iEnt;
}

// Create glow and attach to target since we can't attach to player directly
int CreateGlow(int target)
{
	int glowEnt = CreateEntityByName("env_lightglow");
	DispatchKeyValue(glowEnt, "rendercolor", "0 0 0");
	// SetVariantString("255 155 255");
	// AcceptEntityInput(glowEnt, "Color"); 		// takes precedence over rendercolor?
	DispatchKeyValue(glowEnt, "MinDist", "3000"); // 6000
	DispatchKeyValue(glowEnt, "MaxDist", "0");
	// DispatchKeyValue(glowEnt, "origin", );

	DispatchKeyValue(glowEnt, "VerticalGlowSize", "5"); // 16
	DispatchKeyValue(glowEnt, "HorizontalGlowSize", "5"); // 16
	// DispatchKeyValue(glowEnt, "spawnflags", "1");
	DispatchKeyValue(glowEnt, "GlowProxySize", "2.0"); // 2.0
	DispatchKeyValue(glowEnt, "HDRColorScale", "1.0");
	// DispatchKeyValue(glowEnt, "OuterMaxDist", "2");
	// char glow[64];
	// Format(glow, sizeof(glow), "glow%i", glowEnt);
	// DispatchKeyValue(glowEnt, "targetname", glow);

	// Format(glow, sizeof(glow), "%d", client);
	// DispatchKeyValue(glowEnt, "paretname", glow);

	// SetEntProp(glowEnt, Prop_Data, "m_nRenderMode", RENDER_TRANSALPHA, 1);
	DispatchKeyValue(glowEnt,"renderfx","256"); // EF_PARENT_ANIMATES (instead of 0)

	DispatchSpawn(glowEnt);

	SetVariantString("!activator");
	AcceptEntityInput(glowEnt, "SetParent", target, target, 0);
	return glowEnt;
}


public Action timer_SetAttachmentPosition(Handle timer, DataPack dp)
{
	ResetPack(dp);
	int entity = ReadPackCell(dp);
	int classType = ReadPackCell(dp);

	#if DEBUG
	PrintToServer("[visionglow] setting position for %d classtype %d", entity, classType);
	#endif

	SetVariantString("eyes");
	AcceptEntityInput(entity, "SetParentAttachment");

	float vecPos[3];
	switch (classType)
	{
		case CLASS_SUPPORT:
		{
			vecPos[0] += 6.6;
		}
		case CLASS_ASSAULT:
		{
			vecPos[0] += 6.6;
		}
		case CLASS_RECON:
		{
			vecPos[0] += 6.6;
		}
		default:
		{
			vecPos[0] += 6.3;
		}
	}

	// TeleportEntity(iEnt, vecPos, NULL_VECTOR, NULL_VECTOR);
	SetEntPropVector(entity, Prop_Send, "m_vecOrigin", vecPos);

	DispatchSpawn(entity);
}


public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (client == 0 || gbIsObserver[client] || IsFakeClient(client))
		return Plugin_Continue;

	#if DEBUG
	for (int i = MaxClients; i; --i)
	{
		if (IsValidClient(i))
			SetEntPropFloat(i, Prop_Send, "m_fThermopticNRG", 10.0);
	}
	#endif

	if (buttons & IN_VISION)
	{
		if(!gbHeldKey[client])
		{
			if (gbVisionActive[client])
			{
				// gbVisionActive[client] = GetEntProp(client, Prop_Send, "m_iVision") == 2 ? true : false;
				gbVisionActive[client] = false;
				SetGlowColor(giGlow[client], 0); // tunrn off
			}
			else
			{
				gbVisionActive[client] = true; // we assume vision is active client-side
				SetGlowColor(giGlow[client], giClassType[client]); // Turn on
			}

		}
		gbHeldKey[client] = true;
	}
	else
	{
		gbHeldKey[client] = false;
	}
	return 	Plugin_Continue;
}