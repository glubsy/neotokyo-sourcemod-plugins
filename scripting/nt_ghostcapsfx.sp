#include <sourcemod>
#include <sdktools>
#include <neotokyo>
#pragma semicolon 1
#pragma newdecls required
#define DEBUG 0
#define MAX_SOUND_OCCURENCES 30

#define PLUGIN_VERSION	"0.1"

//requires nt_ghostcap and nt_doublecap plugins!

int ghost;
bool g_bGhostIsCaptured;
bool g_bEndOfRound;
int g_iTickCount = 95;

Handle convar_ghostexplodes = INVALID_HANDLE;
Handle convar_ghostexplosiondamages = INVALID_HANDLE;
Handle convar_roundtimelimit = INVALID_HANDLE;
Handle GhostTimer[MAX_SOUND_OCCURENCES] = INVALID_HANDLE;

char g_sRadioChatterSoundEffect[][] =
{
	"ambient/levels/prison/radio_random1.wav",
	"ambient/levels/prison/radio_random2.wav",
	"ambient/levels/prison/radio_random3.wav",
	"ambient/levels/prison/radio_random4.wav",
	"ambient/levels/prison/radio_random5.wav",
	"ambient/levels/prison/radio_random6.wav",
	"ambient/levels/prison/radio_random7.wav",
	"ambient/levels/prison/radio_random8.wav",
	"ambient/levels/prison/radio_random9.wav",
	"ambient/levels/prison/radio_random10.wav",
	"ambient/levels/prison/radio_random11.wav",
	"ambient/levels/prison/radio_random12.wav",
	"ambient/levels/prison/radio_random13.wav",
	"ambient/levels/prison/radio_random14.wav",
	"ambient/levels/prison/radio_random15.wav"	
};
char g_sSoundEffect[][] = 
{
	"weapons/cguard/charging.wav",
	"weapons/stunstick/alyx_stunner1.wav",
	"weapons/stunstick/alyx_stunner2.wav",
	"weapons/stunstick/spark1.wav",
	"weapons/stunstick/spark2.wav",
	"weapons/stunstick/spark3.wav",
	"weapons/grenade/tick1.wav",
	"weapons/explode3.wav",
	"weapons/explode4.wav",
	"weapons/explode5.wav",
	"buttons/button17.wav"
};


public Plugin myinfo =
{
	name = "NEOTOKYO° Ghost cap special effect",
	author = "soft as HELL",
	description = "SFX on ghost capture event",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
};


//
//	TODO: add sound effect from HL2 radio chatter on capture
//

public void OnPluginStart()
{
	convar_ghostexplodes = CreateConVar("nt_ghostexplodes", "1", "Ghost explodes on removal", FCVAR_SPONLY, true, 0.0, true, 1.0);
	convar_ghostexplosiondamages = CreateConVar("nt_ghostexplosiondamages", "1", "Explosion from ghost damages players", FCVAR_SPONLY, true, 0.0, true, 1.0);
	
	
	HookEvent("game_round_start", OnRoundStart); //needs start in case we foce restart
	
	convar_roundtimelimit = FindConVar("neo_round_timelimit");
}

public void OnConfigsExecuted()
{
	for(int snd = 0; snd < sizeof(g_sRadioChatterSoundEffect); snd++)
	{
		PrecacheSound(g_sRadioChatterSoundEffect[snd], true);
	}
	for(int snd = 0; snd < sizeof(g_sSoundEffect); snd++)
	{
		PrecacheSound(g_sSoundEffect[snd], true);
	}
	
}


public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if(!GetConVarBool(convar_ghostexplodes))
		return; 

	g_bEndOfRound = false;
	g_iTickCount = 95;
	
	for(int i = 0; i < MAX_SOUND_OCCURENCES; i++)
	{
		//killing all remaining timers for sound effects
		if(GhostTimer[i] != INVALID_HANDLE)
		{
			KillTimer(GhostTimer[i]);
			GhostTimer[i] = INVALID_HANDLE;
		}
	}
	
	GhostTimer[0] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 3.8, timer_SoundEffect, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[1] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 33.0, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //30 sec before timeout
	GhostTimer[2] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 26.0, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //sparks
	GhostTimer[3] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 21.0, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[4] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 16.0, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[5] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 12.5, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[6] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 11.0, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[7] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 10.8, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[8] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 10.0, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[9] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 4.8, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //sparks inbetween ticks
	GhostTimer[10] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 5.3, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[11] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 6.5, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[12] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 8.0, timer_SoundEffect, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //beeps countdown
	GhostTimer[13] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 7.0, timer_SoundEffect, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[14] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 6.0, timer_SoundEffect, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[15] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 5.0, timer_SoundEffect, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[16] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 4.0, timer_SoundEffect, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[17] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 3.0, timer_SoundEffect, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[18] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 2.0, timer_SoundEffect, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[19] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 1.0, timer_SoundEffect, 3, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //end beeps countdown
	GhostTimer[20] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) - 0.0, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //crazy sparks
	GhostTimer[21] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 0.3, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[22] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 0.4, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[23] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 0.9, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[24] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 1.7, timer_SoundEffect, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[25] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.0, timer_SoundEffect, 2, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE); //crazy ticks
	GhostTimer[26] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.1, timer_SoundEffect, 2, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[27] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.2, timer_SoundEffect, 2, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[28] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.3, timer_SoundEffect, 2, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	GhostTimer[29] = CreateTimer((GetConVarFloat(convar_roundtimelimit) * 60.0 ) + 2.4, timer_SoundEffect, 2, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_SoundEffect(Handle timer, int soundtype)
{
	if(g_bGhostIsCaptured)
		return Plugin_Handled;
	
	if(!IsValidEntity(ghost))
	{
		return Plugin_Handled;
	}
	
	float vecOrigin[3];
	int carrier = GetEntPropEnt(ghost, Prop_Data, "m_hOwnerEntity");

	if(MaxClients > carrier > 0)
		GetEntPropVector(carrier, Prop_Send, "m_vecOrigin", vecOrigin);
	else
		GetEntPropVector(ghost, Prop_Send, "m_vecOrigin", vecOrigin);
	
	vecOrigin[2] += 10;

	switch(soundtype)
	{
		case 0:
		{	
			g_bEndOfRound = true; //it's ok to hook entity destruction for a bit	
			EmitSoundToAll(g_sSoundEffect[soundtype], SOUND_FROM_WORLD, SNDCHAN_AUTO, 100, SND_NOFLAGS, SNDVOL_NORMAL, 100, -1, vecOrigin); //charging effect
		}
		case 1:
		{
			EmitSoundToAll(g_sSoundEffect[GetRandomInt(3,5)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(90, 110), -1, vecOrigin); //sparks
		}
		case 2:
		{
			EmitSoundToAll(g_sSoundEffect[6], SOUND_FROM_WORLD, SNDCHAN_AUTO, 120, SND_NOFLAGS, SNDVOL_NORMAL, g_iTickCount, -1, vecOrigin); //ticks
			g_iTickCount += 5;
		}
		case 3:
		{
			EmitSoundToAll(g_sSoundEffect[10], SOUND_FROM_WORLD, SNDCHAN_AUTO, 55, SND_NOFLAGS, SNDVOL_NORMAL, g_iTickCount, -1, vecOrigin); //beeps
			g_iTickCount += 5;
		}
	}
	return Plugin_Handled;
}

public void OnGhostSpawn(int entity)
{
	ghost = entity;
	g_bGhostIsCaptured = false;
}

public void OnGhostCapture(int client)
{
	g_bGhostIsCaptured = true;
	
	EmmitCapSound(client);
	
	CreateTimer(1.1, timer_EmitRaidoChatterSound, client);
	CreateTimer(1.4, timer_EmitRaidoChatterSound, client);
	CreateTimer(1.7, timer_EmitRaidoChatterSound, client);
	CreateTimer(1.9, timer_EmitRaidoChatterSound, client);
	CreateTimer(2.3, timer_EmitRaidoChatterSound, client);
	CreateTimer(2.6, timer_EmitRaidoChatterSound, client);
	
	
	CreateTimer(1.0, timer_DoSparks, client);
	CreateTimer(1.5, timer_DoSparks, client);
	CreateTimer(2.0, timer_DoSparks, client);
	CreateTimer(2.2, timer_DoSparks, client);
	CreateTimer(2.5, timer_DoSparks, client);
	CreateTimer(2.9, timer_DoSparks, client);
}

public Action timer_EmitRaidoChatterSound(Handle timer, int client)
{
	float vecOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[2] += 20.0;

	EmitSoundToAll(g_sRadioChatterSoundEffect[GetRandomInt(0, sizeof(g_sRadioChatterSoundEffect) -1)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 130, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, NULL_VECTOR);
}

void EmmitCapSound(int client)
{
	float vecOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[2] += 20.0;

	EmitSoundToAll(g_sSoundEffect[GetRandomInt(1, 2)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 130, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, NULL_VECTOR);
}





public Action timer_DoSparks(Handle timer, int client)
{
	DoSparkleEffect(client);
}

public void DoSparkleEffect(int client)
{
	float vecOrigin[3], vecEyeAngles[3];
	GetClientEyePosition(client, vecOrigin);
	vecOrigin[2] += 10.0;
	vecEyeAngles[2] = 1.0;
	
	//TE_SetupSparks(vecOrigin, vecEyeAngles, 1, 1);
	
	TE_Start("Sparks");
	TE_WriteFloat("m_vecOrigin[0]", vecOrigin[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecOrigin[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecOrigin[2]);
	TE_WriteNum("m_nMagnitude", 50);
	TE_WriteNum("m_nTrailLength", 8);
	TE_WriteVector("m_vecDir", vecEyeAngles);
	TE_SendToAll();
}


public void OnEntityDestroyed(int entity)
{
	if(!GetConVarBool(convar_ghostexplodes))
		return;
	
	if(!g_bEndOfRound)
		return;
	
	char classname[50];
	GetEntityClassname(entity, classname, sizeof(classname));
    
	#if DEBUG > 0
	PrintToServer("entity destroyed %s", classname);
	#endif
	
    if (StrEqual(classname, "weapon_ghost"))
    {
		Explode(entity);
    }
}

void Explode(int entity)
{
	int carrier = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");

	if(MaxClients > carrier > 0)
		entity = carrier;

	float pos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
	
	int explosion;
	
	if(g_bGhostIsCaptured)
		explosion = CreateEntityByName("env_physexplosion");
	if(!g_bGhostIsCaptured && GetConVarBool(convar_ghostexplosiondamages))
		explosion = CreateEntityByName("env_explosion");
	else
		explosion = CreateEntityByName("env_physexplosion");
	
	//DispatchKeyValueFloat(explosion, "magnitude", GetConVarFloat(cv_JarateKnockForce));
	DispatchKeyValue(explosion, "iMagnitude", "400");
	//DispatchKeyValue(explosion, "spawnflags", "18428");
	DispatchKeyValue(explosion, "spawnflags", "0");
	DispatchKeyValue(explosion, "iRadiusOverride", "256");

	if ( DispatchSpawn(explosion) )
	{
		EmitExplosionSound(explosion, pos);
		SetEntPropEnt(explosion, Prop_Data, "m_hOwnerEntity", carrier);
		ActivateEntity(explosion);
		TeleportEntity(explosion, pos, NULL_VECTOR, NULL_VECTOR);
		AcceptEntityInput(explosion, "Explode");
		AcceptEntityInput(explosion, "Kill");
		
		float dir[3] = {0.0, 0.0, 1.0};
		TE_SetupSparks(pos, dir, 50, 8);
		TE_SendToAll();
	}
	
	g_bEndOfRound = false; //don't check for destroyed entities anymore as round is about to restart (lots of them and errors)
}

public void EmitExplosionSound(int entity, float position[3])
{
	EmitSoundToAll(g_sSoundEffect[GetRandomInt(7, 9)], SOUND_FROM_WORLD, SNDCHAN_AUTO, 100, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, position, NULL_VECTOR);
}

public void OnMapEnd()
{
	for(int i = 0; i < MAX_SOUND_OCCURENCES; i++)
	{
		GhostTimer[i] = INVALID_HANDLE;
	}
}