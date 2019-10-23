#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32

#if !defined DEBUG
#define DEBUG 0
#endif

String:g_sModelName[][] = {
	"materials/sprites/laser.vmt",
	"materials/sprites/halo01.vmt",
	"materials/sprites/laserdot.vmt"
}
int blue_laser_color[3] = {20, 20, 210};
int green_laser_color[3] = {10, 210, 10};
int alphaAmount = 40;
int g_modelLaser, g_modelHalo, g_imodelLaserDot;
Handle CVAR_hurt_trails, CVAR_grenade_trails, CVAR_TrailAlpha = INVALID_HANDLE;
// int m_hThrower, m_hOwnerEntity; // offsets
int g_iBeamClients[NEO_MAX_CLIENTS+1], g_nBeamClients;
Handle g_RefreshArrayTimer = INVALID_HANDLE;


public Plugin:myinfo =
{
	name = "NEOTOKYO highlights",
	author = "glub",
	description = "Highlight bullets and grenades trails for spectators",
	version = "0.1",
	url = "https://github.com/glubsy"
};

// TODO: change thickness of beam depending on damage done
// TODO: make opt-out & cookie pref menu
// TODO: hook cvar change to update alpha amount and colors

public void OnPluginStart()
{
	CVAR_hurt_trails = CreateConVar("sm_hurt_trails", "1", "Enable (1) or disable (0) drawing beams between a hit player and their attacker.", _, true, 0.0, true, 1.0);
	CVAR_grenade_trails = CreateConVar("sm_grenade_trails", "1", "Enable (1) or disable (0) drawing trails on thrown projectiles.", _, true, 0.0, true, 1.0);
	CVAR_TrailAlpha = CreateConVar("sm_highlights_alpha", "40.0", "Transparency amount for highlight trails.", _, true, 0.0, true, 255.0);
	alphaAmount = GetConVarInt(CVAR_TrailAlpha); 

	AutoExecConfig(true, "nt_highlights");

	HookEvent("player_hurt", Event_OnPlayerHurt, EventHookMode_Pre);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("game_round_start", Event_OnRoundStart);
	HookEvent("player_spawn", Event_OnPlayerSpawn);

	// HookEvent("player_shoot", Event_OnPlayerShoot); // doesn't work in NT

	// m_hThrower = FindSendPropInfo("CBaseGrenadeProjectile", "m_hThrower");
	// if (m_hThrower <= 0)
	// 	PrintToServer("[nt_highlights] DEBUG offset m_hThrower was -1");
	// m_hOwnerEntity = FindSendPropInfo("CBaseGrenadeProjectile", "m_hOwnerEntity");
	// if (m_hOwnerEntity <= 0)
	// 	ThrowError("[nt_highlights] DEBUG offset m_hOwnerEntity was -1");
}

public void OnConfigsExecuted()
{
	#if DEBUG > 1
	for (int client = MaxClients; client > 0; client--)
	{
		if (!IsValidClient(client) || !IsClientConnected(client))
			continue;

		SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
		SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	}
	#endif //DEBUG

	UpdateAffectedClientsArray(-1); // force rebuild
}

public OnMapStart()
{
	// laser beam
	// g_modelLaser = PrecacheModel("sprites/laser.vmt");
	g_modelLaser = PrecacheModel(g_sModelName[0]);
	
	// laser halo
	g_modelHalo = PrecacheModel(g_sModelName[1]);
}


public void OnClientPutInServer(int client)
{
	#if DEBUG > 1
	SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
	SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	#endif //DEBUG

	UpdateAffectedClientsArray(client);
}


public Action Event_OnPlayerDeath(Event event, const char[] name, bool dontbroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	// need short delay to read deadflag
	CreateTimer(0.5, timer_RefreshAffectedArray, victim, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


public Action Event_OnPlayerSpawn(Event event, const char[] name, bool dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsValidClient(client))
		return Plugin_Continue;

	#if DEBUG
	PrintToServer("[nt_highlights] Event_OnPlayerSpawn(%d) (%N)", client, client);
	#endif

	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1 || GetEntProp(client, Prop_Send, "deadflag"))
	{
		#if DEBUG
		PrintToServer("[nt_highlights] client %N spawned but is actually dead!", client);
		#endif
		return Plugin_Continue;
	}


	// for players spawning after freeze time has already ended
	if (g_RefreshArrayTimer == INVALID_HANDLE)
		g_RefreshArrayTimer = CreateTimer(5.0, timer_RefreshAffectedArray, -1, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action Event_OnRoundStart(Event event, const char[] name, bool dontbroadcast)
{
	#if DEBUG
	PrintToServer("[nt_highlights] OnRoundStart()")
	#endif

	// 15 seconds should be right when freeze time ends
	g_RefreshArrayTimer = CreateTimer(15.0, timer_RefreshAffectedArray, -1, TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_RefreshAffectedArray(Handle timer, int client)
{
	#if DEBUG
	PrintToServer("[nt_highlights] Timer is now calling UpdateAffectedClientsArray(%d).", client);
	#endif

	UpdateAffectedClientsArray(client); // should be -1 here, forcing refresh for all arrays

	if (g_RefreshArrayTimer != INVALID_HANDLE)
		g_RefreshArrayTimer = INVALID_HANDLE;
	return Plugin_Continue;
}




public void OnEntityCreated(int iEnt, const char[] classname)
{
	if(StrContains(classname, "_projectile", true) != -1)
	{
		//NOTE: we need to delay reading properties values or it will return -1 apparently
		// so perhaps just a timer of 0.1 would do the trick also (untested)
		SDKHook(iEnt, SDKHook_SpawnPost, SpawnPost_Grenade);
	}
}


public void SpawnPost_Grenade(int iEnt)
{
	char sClassname[30];
	GetEntityClassname(iEnt, sClassname, sizeof(sClassname))
	int iOwner, iOwnerEntity;
	switch (sClassname[0])
	{
		case 'g':
		{
			iOwner = GetEntPropEnt(iEnt, Prop_Data, "m_hThrower"); // always -1?
			iOwnerEntity = GetEntPropEnt(iEnt, Prop_Data, "m_hOwnerEntity");
			// iOwner = GetEntDataEnt2(iEnt, m_hThrower);
			// iOwnerEntity = GetEntDataEnt2(iEnt, m_hOwnerEntity);
			iOwner = iOwner == -1 ? 0 : IsClientInGame(iOwner) ? iOwner : 0;
			iOwnerEntity = iOwnerEntity == -1 ? 0 : IsClientInGame(iOwnerEntity) ? iOwnerEntity : 0;
			PrintToServer("[nt_highlights] grenade_projectile created, iOwner %d, iOwnerEntity %d", iOwner, iOwnerEntity);
		}

		case 's':
		{
			iOwner = GetEntPropEnt(iEnt, Prop_Data, "m_hThrower"); // always -1?
			iOwnerEntity = GetEntPropEnt(iEnt, Prop_Data, "m_hOwnerEntity");
			// iOwner = GetEntDataEnt2(iEnt, m_hThrower);
			// iOwnerEntity = GetEntDataEnt2(iEnt, m_hOwnerEntity);
			iOwner = iOwner == -1 ? 0 : IsClientInGame(iOwner) ? iOwner : 0;
			iOwnerEntity = iOwnerEntity == -1 ? 0 : IsClientInGame(iOwnerEntity) ? iOwnerEntity : 0;
			PrintToServer("[nt_highlights] smokegrenade_projectile created, iOwner %d, iOwnerEntity %d", iOwner, iOwnerEntity);
		}
	}
	if (GetClientTeam(iOwnerEntity) == 3) //NSF
		DrawBeamFromProjectile(iEnt, false);
	else
		DrawBeamFromProjectile(iEnt, true);
}

public Action Event_OnPlayerHurt(Event event, const char[] name, bool dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	// int health = GetEventInt(event, "health");

	if (!IsValidClient(client) || !IsValidClient(attacker))
		return Plugin_Continue;

	if (GetClientTeam(attacker) == 3)
		DrawBeamFromClient(client, attacker, false);
	else
		DrawBeamFromClient(client, attacker, true);

	return Plugin_Continue;
}


void DrawBeamFromProjectile(int entity, bool jinrai=true)
{
	TE_Start("BeamFollow");
	TE_WriteEncodedEnt("m_iEntIndex", entity);
	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo);
	TE_WriteNum("m_nStartFrame", 0);
	TE_WriteNum("m_nFrameRate", 0);
	TE_WriteFloat("m_fLife", 9.0);
	TE_WriteFloat("m_fWidth", 2.0);
	TE_WriteFloat("m_fEndWidth", 1.0);
	TE_WriteNum("m_nFadeLength", 1);
	if (jinrai)
	{
		TE_WriteNum("r", green_laser_color[0]);
		TE_WriteNum("g", green_laser_color[1]);
		TE_WriteNum("b", green_laser_color[2]);
	}
	else
	{
		TE_WriteNum("r", blue_laser_color[0]);
		TE_WriteNum("g", blue_laser_color[1]);
		TE_WriteNum("b", blue_laser_color[2]);
	}
	TE_WriteNum("a", alphaAmount);
	TE_Send(g_iBeamClients, g_nBeamClients);
}


void DrawBeamFromClient(int victim, int attacker, bool green_laser=true)
{
	float origin[3], end[3], angle[3];
	GetClientEyePosition(attacker, origin);
	GetClientEyeAngles(attacker, angle);
	GetEndPositionFromClient(attacker, origin, angle, end);
	// GetClientEyePosition(victim, end); // not precise enough for our end point


	#if DEBUG
	PrintToServer("[nt_highlights] Drawing beam from {%f %f %f} to {%f %f %f} laser %d halo %d", 
	origin[0], origin[1], origin[2], end[0], end[1], end[2], g_modelLaser, g_modelHalo);
	#endif

	/*TE_SetupBeamPoints(const Float:start[3], const Float:end[3], ModelIndex, HaloIndex, StartFrame, FrameRate, Float:Life, 
				Float:Width, Float:EndWidth, FadeLength, Float:Amplitude, const Color[4], Speed)*/
	// TE_SetupBeamPoints(origin, end, g_modelLaser, g_modelHalo, 0, 1, 0.1,
	// 				0.2, 0.2, 2, 0.1, (green_laser ? green_laser_color : blue_laser_color), 1);

	TE_Start("BeamPoints");
	TE_WriteVector("m_vecStartPoint", origin);
	TE_WriteVector("m_vecEndPoint", end);
	//TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);
	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo);
	TE_WriteNum("m_nStartFrame", 0);
	TE_WriteNum("m_nFrameRate", 1);
	TE_WriteFloat("m_fLife", 0.1);
	TE_WriteFloat("m_fWidth", 0.2);
	TE_WriteFloat("m_fEndWidth", 0.2);
	TE_WriteFloat("m_fAmplitude", 0.1);
	if (green_laser)
	{
		TE_WriteNum("r", green_laser_color[0]);
		TE_WriteNum("g", green_laser_color[1]);
		TE_WriteNum("b", green_laser_color[2]);
	}
	else
	{
		TE_WriteNum("r", blue_laser_color[0]);
		TE_WriteNum("g", blue_laser_color[1]);
		TE_WriteNum("b", blue_laser_color[2]);
	}
	TE_WriteNum("a", alphaAmount);
	TE_WriteNum("m_nSpeed", 1);
	TE_WriteNum("m_nFadeLength", 2);

	TE_Send(g_iBeamClients, g_nBeamClients);

}



void UpdateAffectedClientsArray(int client)
{
	if (client <= 0) // rebuild entire array
	{
		for(int j = 1; j <= MaxClients; j++)
		{
			if(!IsValidClient(j) || IsFakeClient(j) || !IsClientConnected(j)) // only draw for specs here
				continue;

			if (!GetEntProp(j, Prop_Send, "deadflag") || GetClientTeam(client) <= 1)
				continue;
	
			#if DEBUG
			PrintToServer("[nt_highlights] can send beam TE to %N.", j);
			#endif
			g_iBeamClients[g_nBeamClients++] = j;
		}

		#if DEBUG
		for (int f = 0; f < g_nBeamClients; f++)
		{
			PrintToServer("[nt_highlights] can send beam TE to client: %d", g_iBeamClients[f]);
		}
		#endif
	}
	else if (client > 1) // client most likely just died
	{
		#if DEBUG
		PrintToServer("[nt_highlights] UpdateAffectedClientsArray(%d) %N has deadflag bit %s.", 
		client, client, (GetEntProp(client, Prop_Send, "deadflag") ? "set" : "not set"));
		#endif
		if(GetEntProp(client, Prop_Send, "deadflag") || GetClientTeam(client) <= 1) // only draw for specs here
			g_iBeamClients[g_nBeamClients++] = client;
	}
}


stock bool GetEndPositionFromClient(int client, float[3] start, float[3] angle, float[3] end)
{
	TR_TraceRayFilter(start, angle, (CONTENTS_SOLID|CONTENTS_MOVEABLE|CONTENTS_MONSTER|CONTENTS_DEBRIS|CONTENTS_HITBOX), RayType_Infinite, TraceEntityFilterPlayer, client);
	if (TR_DidHit(INVALID_HANDLE))
	{
		TR_GetEndPosition(end, INVALID_HANDLE);

		int hit_entity = TR_GetEntityIndex(INVALID_HANDLE);
		if (0 < hit_entity <= MaxClients) // we hit a player
		{
			return true;
		}
	}
	// adjusting alignment
	// end[0] += 5.0;
	// end[1] += 5.0;
	// end[2] += 5.0;
	return false;
}


public bool:TraceEntityFilterPlayer(entity, contentsMask, any:data)
{
	// return entity > MaxClients; // this filters all players
	return entity != data; // only avoid collision with ourself (or data)
}



// SDKHooks is not reading values at the right offsets and returns garbage values
public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	PrintToServer("[nt_highlights] OnTraceAttack victim %N attacker %N inflictor %d damage %f damagetype %d ammotype %d hitbox %d hitgroup %d",
	victim, attacker, inflictor, damage, damagetype, ammotype, hitbox, hitgroup);
	return Plugin_Continue;
}

// SDKHooks is not reading values at the right offsets and returns garbage values
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	PrintToServer("[nt_highlights] OnTakeDamage victim %N attacker %N inflictor %d damage %f damagetype %d weapon %d damageForce {%f,%f,%f} damagePosition {%f,%f,%f}",
	victim, attacker, inflictor, damage, damagetype, weapon, damageForce[0], damageForce[1], damageForce[2], damagePosition[0], damagePosition[1], damagePosition[2]);
	return Plugin_Continue;
}

// Of course it doesn't work in NT either, never hooked
public void OnFireBulletsPost(int client, int shots, const char[] weaponname)
{
	PrintToServer("[nt_highlights] Bulletpost() client %d shots %d weaponname %s", client, shots, weaponname);
}