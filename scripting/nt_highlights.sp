#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32
#define DEBUG 1

int laser_color[4] = {0, 210, 50, 255};
int g_modelLaser, g_modelHalo, g_imodelLaserDot;
Handle CVAR_hurt_trails, CVAR_grenade_trails = INVALID_HANDLE;

public Plugin:myinfo =
{
	name = "NEOTOKYO highlights",
	author = "glub",
	description = "Draws highlight trails for spectators",
	version = "0.1",
	url = "https://github.com/glubsy"
};

// Objective: draw laser beam for every player_hurt event (see Mitchell's API) and show only to spectators
// Draw a beam of color (GREEN/BLUE) when a player gets hit, use CTEBeamFollow
// change thickness of beam depending on damage if possible
// TODO: make opt-out
// TODO: make cookie pref menu

public void OnPluginStart()
{
	CVAR_hurt_trails = CreateConVar("sm_hurt_trails", "1", "Enable (1) or disable (0) drawing laser beam on player hurt events.", _, true, 0.0, true, 1.0);
	CVAR_grenade_trails = CreateConVar("sm_grenade_beams", "1", "Enable (1) or disable (0) drawing trail on grenade throws.", _, true, 0.0, true, 1.0);


	AutoExecConfig(true, "nt_highlights");

	HookEvent("player_hurt", Event_OnPlayerHurt, EventHookMode_Pre);
	// HookEvent("player_shoot", Event_OnPlayerShoot); // doesn't work in NT

}


public void OnConfigsExecuted()
{
	for (int client = MaxClients; client > 0; client--)
	{
		if (!IsValidClient(client) || !IsClientConnected(client))
			continue;
		// SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
		// SDKHook(client, SDKHook_TraceAttack, OnTraceAttackOnTakeDamage);
		// SDKHook(client, SDKHook_OnTakeDamage, OnTraceAttackOnTakeDamage);
	}
}

public void OnClientPutInServer(int client)
{
	// SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
    // SDKHook(client, SDKHook_TraceAttack, OnTraceAttackOnTakeDamage);
    // SDKHook(client, SDKHook_OnTakeDamage, OnTraceAttackOnTakeDamage);
}

public OnMapStart()
{
	// laser beam
	// g_modelLaser = PrecacheModel("sprites/laser.vmt");
	g_modelLaser = PrecacheModel("materials/sprites/laserdot.vmt");
	
	// laser halo
	g_modelHalo = PrecacheModel("materials/sprites/halo01.vmt");

	// laser dot
	g_imodelLaserDot = PrecacheModel("materials/sprites/laser.vmt");
}


public Action Event_OnPlayerHurt(Event event, const char[] name, bool dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	#if DEBUG
	PrintToServer("[nt_highlights] Drawing beam from %N to %N", attacker, client);
	#endif

	if (!IsValidClient(client) || !IsValidClient(attacker))
		return Plugin_Continue;

	DrawBeamFromClient(client, attacker);

	return Plugin_Continue;
}


void DrawBeamFromClient(int client, int attacker)
{
	float origin[3], end[3];
	GetClientEyePosition(attacker, origin);
	GetClientEyePosition(client, end);


	#if DEBUG
	PrintToServer("[nt_highlights] Beam origin %f %f %f, beam end %f %f %f laser %d halo %d", 
	origin[0], origin[1], origin[2], end[0], end[1], end[2], g_modelLaser, g_modelHalo);
	#endif

	/*TE_SetupBeamPoints(const Float:start[3], const Float:end[3], ModelIndex, HaloIndex, StartFrame, FrameRate, Float:Life, 
				Float:Width, Float:EndWidth, FadeLength, Float:Amplitude, const Color[4], Speed)*/
	TE_SetupBeamPoints(origin, end, g_modelLaser, g_modelHalo, 0, 1, 0.0,
					0.9, 0.9, 0, 2.0, laser_color, 1);
	// TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);

	new iBeamClients[MaxClients], nBeamClients;
	for(new j = 1; j <= MaxClients; j++)
	{
		if(!IsValidClient(j) || IsFakeClient(j) || !IsClientConnected(j)) // only draw for specs here
			continue;

		#if DEBUG > 1
		PrintToServer("[nt_highlights] can send TE to %N.", j);
		#endif
		iBeamClients[nBeamClients++] = j;
	}
	#if DEBUG
	for (int f = 0; f < nBeamClients; f++)
	{
		PrintToServer("[nt_highlights] sending TE to %N (item = %d)", iBeamClients[f], iBeamClients[f]);
	}
	#endif
	TE_Send(iBeamClients, nBeamClients);
}



// SDKHooks is not reading values at the right offsets it seems :(
// public Action OnTraceAttackOnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
// {
// 	PrintToServer("OnTraceAttackOnTakeDamage victim: %N attacker %N inflictor %d damage %f damagetype %d ammotype %i hitbox %i hitgroup %i",
// 	victim, attacker, inflictor, damage, damagetype, ammotype, hitbox, hitgroup);
// 	return Plugin_Continue;
// }

// Of course it doesn't work in NT either
// public Action OnFireBulletsPost(int client, int shots, const char[] weaponname)
// {
// 	PrintToChatAll("Bulletpost")
// 	return Plugin_Continue;
// }