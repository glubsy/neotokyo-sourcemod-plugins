#include <sourcemod>
#include <sdktools>
#include <neotokyo>
#define PLUGIN_VERSION "0.3"
#define MESSAGE_LASTMAN "You are the last man standing! Time to !seppuku"
#define MESSAGE_DUEL 	"You are dueling against enemy last player, don't drag this out!"

bool g_MessageShownLast[MAXPLAYERS+1];
Handle hPlayerCounter;

int lastJin, lastNsf;
bool g_bSoundFilesExist[2], g_bLastManStanding[MAXPLAYERS+1];
Handle convar_slowmotion_enabled = INVALID_HANDLE;
Handle g_TimerSlowMotion = INVALID_HANDLE;
Handle hGravity, hPhysTimeScale;
Handle hCheatCvar = INVALID_HANDLE;

new const String:g_SloMoSound[][] = { 
	"custom/slowmoin.mp3",
	"custom/slowmoout.mp3" };


public Plugin myinfo = 
{
	name = "NEOTOKYO° slow-motion",
	author = "glub, soft as HELL",
	description = "Slow-motion on last man killed",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
}


public OnPluginStart()
{
	convar_slowmotion_enabled = CreateConVar("sm_slowmotion_enabled", "1", "Enable Slow-Motion on last man standing death", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	HookEvent("game_round_start", Event_RoundStart, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
	
	hGravity = FindConVar("sv_gravity");
	hPhysTimeScale = FindConVar("phys_timescale");
	hCheatCvar = FindConVar("sv_cheats");
}

public OnConfigsExecuted()
{
	if(GetConVarBool(convar_slowmotion_enabled))
	{
		static char file[PLATFORM_MAX_PATH];
		for(int i; i < sizeof(g_SloMoSound); i++)
		{
			Format(file, sizeof(file), "sound/%s", g_SloMoSound[i]);
			if(FileExists(file))
			{
				PrecacheSound(g_SloMoSound[i], true);
				AddFileToDownloadsTable(file);
				g_bSoundFilesExist[i] = true;
			}
			else
				LogError("[SLOMO] File %s not found!", file);
		}
	}
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(hPlayerCounter != INVALID_HANDLE)
		KillTimer(hPlayerCounter);

	hPlayerCounter = INVALID_HANDLE;
	
	lastJin = 0;
	lastNsf = 0;
	
	if(GetConVarBool(convar_slowmotion_enabled))
	{
		//just in case something went wrong
		//ServerCommand("host_timescale 1.0");
		SetConVarFloat(hPhysTimeScale, 1.0);
		
		if(GetConVarBool(hCheatCvar))
		{
			for(int i = 1; i < MaxClients; i++)
			{
				if(!IsClientConnected(i) || !IsClientInGame(i) || !IsValidEntity(i))
					continue;
				ClientCommand(i, "cl_phys_timescale 1.0");
			}
			ActivateCheats(0);
		}
		
		SetConVarInt(hGravity, 800);	
		
		for (int i; i <= MaxClients; i++)
		{
			g_bLastManStanding[i] = false;
		}
	}
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(hPlayerCounter == INVALID_HANDLE)
		hPlayerCounter = CreateTimer(0.1, CountPlayers);
	
	if(GetConVarBool(convar_slowmotion_enabled))
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		
		if(client == lastJin && g_bLastManStanding[client] || client == lastNsf && g_bLastManStanding[client])
		{
			ActivateCheats(1);
			
			//ServerCommand("host_timescale 0.6");
			SetConVarFloat(hPhysTimeScale, 0.2);
			
			if(GetConVarBool(hCheatCvar))
			{
				for(int i = 1; i < MaxClients; i++)
				{
					if(!IsClientConnected(i) || !IsClientInGame(i) || !IsValidEntity(i))
						continue;
					ClientCommand(i, "cl_phys_timescale 0.2"); //FIXME: might need a very short timer for this to work?
				}
			}
			
			SetConVarInt(hGravity, 220);
			
			if(g_bSoundFilesExist[0])
			{
				EmitSoundToAll(g_SloMoSound[0], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 160, SND_NOFLAGS, 0.6);
			}
			g_TimerSlowMotion = CreateTimer(4.0, timer_DefaultTimeScale, _, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public Action timer_SlowMoScalePost(Handle timer)
{
	//ServerCommand("host_timescale 0.2");
	ServerCommand("phys_timescale 0.2");
	ServerCommand("sm_exec @all cl_phys_timescale 0.2");
	g_TimerSlowMotion = CreateTimer(0.6, timer_StopSlowMo, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action timer_StopSlowMo(Handle timer)
{
	//progressively scaling back up
	//ServerCommand("host_timescale 0.6");
	ServerCommand("phys_timescale 0.2");
	ServerCommand("sm_exec @all cl_phys_timescale 0.2");
	g_TimerSlowMotion = CreateTimer(0.3, timer_DefaultTimeScale, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action timer_DefaultTimeScale(Handle timer)
{
	if(g_bSoundFilesExist[1])
	{
		EmitSoundToAll(g_SloMoSound[1], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 160, SND_NOFLAGS, 0.6);
	}
	
	//ServerCommand("host_timescale 1.0");
	SetConVarFloat(hPhysTimeScale, 1.0);
	if(GetConVarBool(hCheatCvar))
	{
		for(int i = 1; i < MaxClients; i++)
		{
			if(!IsClientConnected(i) || !IsClientInGame(i) || !IsValidEntity(i))
				continue;
			ClientCommand(i, "cl_phys_timescale 1.0");
		}
	}
	
	CreateTimer(1.5, timer_DeactivateCheats);
	
	SetConVarInt(hGravity, 800);
	
}

public Action timer_DeactivateCheats(Handle timer)
{
	ActivateCheats(0);
}


public ActivateCheats(int value)
{
	if( hCheatCvar == INVALID_HANDLE )
		return;
	
	char val[2];
	IntToString(value, val, 2);
	new flags = GetConVarFlags(hCheatCvar);
	SetConVarFlags(hCheatCvar, flags & ~FCVAR_NOTIFY);
	SetConVarString(hCheatCvar, val);
	SetConVarFlags(hCheatCvar, flags);
	
	for(int i = 1; i < MaxClients; i++)
	{
		if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i))
			continue;
		SendConVarValue(i, hCheatCvar, val);
	}
}




public Action CountPlayers(Handle timer)
{
	int countTotal, countJin, countNsf;

	hPlayerCounter = INVALID_HANDLE;

	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsValidClient(client))
			continue;

		if(!IsPlayerAlive(client))
		{
			countTotal++;
			continue;
		}

		switch(GetClientTeam(client))
		{
			case TEAM_JINRAI:
			{
				countTotal++;
				countJin++;

				lastJin = client;
			}
			case TEAM_NSF:
			{
				countTotal++;
				countNsf++;

				lastNsf = client;
			}
		}
	}

	if(countJin == 1 && countNsf == 1)
	{
		if(countTotal <= 2)
		{
			if(GetConVarBool(convar_slowmotion_enabled))
			{
				g_bLastManStanding[lastNsf] = true;
				g_bLastManStanding[lastJin] = true;
			}
			return;
		}
		
		if(GetConVarBool(convar_slowmotion_enabled))
		{
			g_bLastManStanding[lastNsf] = true;
			g_bLastManStanding[lastJin] = true;
		}
		CreateTimer(3.0, LastManStanding, lastNsf);
		CreateTimer(3.0, LastManStanding, lastJin);
		return;
		//Duel(lastJin);
		//Duel(lastNsf);
	}
	if(countJin >= 2)
	{
		if(countNsf == 1)
		{
			CreateTimer(3.0, LastManStanding, lastNsf);
			if(GetConVarBool(convar_slowmotion_enabled))
				g_bLastManStanding[lastNsf] = true;
		}
	}
	if(countNsf >= 2)
	{
		if(countJin == 1)
		{
			CreateTimer(3.0, LastManStanding, lastJin);
			if(GetConVarBool(convar_slowmotion_enabled))
				g_bLastManStanding[lastJin] = true;
		}
	}
}

public Action LastManStanding(Handle timer, int client)
{
	if(!IsClientConnected(client) || !IsPlayerAlive(client) || g_MessageShownLast[client])
		return;

	PrintToChat(client, MESSAGE_LASTMAN);

	g_MessageShownLast[client] = true;
}

stock Duel(client)
{
	PrintToChat(client, MESSAGE_DUEL);
}

public Action Event_PlayerDisconnect(Handle event, const char[] name, bool dontBroadcast)
{
	if(hPlayerCounter == INVALID_HANDLE)
		hPlayerCounter = CreateTimer(0.1, CountPlayers);
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	g_MessageShownLast[client] = false;
}

public OnMapEnd()
{
	//clearing handles for timers with flag TIMER_FLAG_NO_MAPCHANGE
	if(g_TimerSlowMotion != INVALID_HANDLE)
		g_TimerSlowMotion = INVALID_HANDLE;	
}

/*
stock void StopSoundPerm(char[] sound)
{
	for(int client = 1; client < MaxClients; client++)
	{
		if(IsClientConnected(client) && IsClientInGame(client))
		{			
			StopSound(client, SNDCHAN_AUTO, sound);
			StopSound(client, SNDCHAN_WEAPON, sound);
			StopSound(client, SNDCHAN_VOICE, sound);
			StopSound(client, SNDCHAN_ITEM, sound);
			StopSound(client, SNDCHAN_BODY, sound);
			StopSound(client, SNDCHAN_STREAM, sound);
			StopSound(client, SNDCHAN_VOICE_BASE, sound);
			StopSound(client, SNDCHAN_USER_BASE, sound);
		}
	}
}
*/