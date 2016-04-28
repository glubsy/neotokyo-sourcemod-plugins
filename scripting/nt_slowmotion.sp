#include <sourcemod>
#include <sdktools>
#include <neotokyo>
#define PLUGIN_VERSION "0.4"
#define MESSAGE_LASTMAN "You are the last man standing! Time to !seppuku"
#define MESSAGE_DUEL 	"You are dueling against enemy last player, don't drag this out!"
#define DEBUG 1

bool g_MessageShownLast[MAXPLAYERS+1];
Handle hPlayerCounter;

int lastJin, lastNsf;
bool g_bSoundFilesExist[2], g_bLastManStanding[MAXPLAYERS+1];
Handle convar_slowmotion_enabled = INVALID_HANDLE;
Handle convar_slowmotion_clientside = INVALID_HANDLE;
Handle g_TimerSlowMotion = INVALID_HANDLE;
Handle hGravity, hPhysTimeScale;
Handle hCheatCvar = INVALID_HANDLE;
Handle hHostTimeScale = INVALID_HANDLE;
Handle convar_nt_deathmatch = INVALID_HANDLE;
Handle g_hForwardLastManDeath = INVALID_HANDLE;
bool g_bStartedSlowmo, g_bDeathMatchActive;

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
	convar_slowmotion_enabled = CreateConVar("sm_slowmotion_enabled", "1", "Enable Slow-Motion on last man standing death", FCVAR_PLUGIN|FCVAR_SPONLY);
	convar_slowmotion_clientside = CreateConVar("sm_slowmotion_clientsideonly", "0", "cl_phys_timescale is changed clientside (not recommended)", FCVAR_PLUGIN|FCVAR_SPONLY);
	HookEvent("game_round_start", Event_RoundStart, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
	
	g_hForwardLastManDeath = CreateGlobalForward("OnLastManDeath", ET_Event, Param_Cell);

	hGravity = FindConVar("sv_gravity");
	hPhysTimeScale = FindConVar("phys_timescale");
	hCheatCvar = FindConVar("sv_cheats");
	hHostTimeScale = FindConVar("host_timescale");
	
	//OnConfigsExecuted();
}

public void OnConfigsExecuted()
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

public Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if(hPlayerCounter != INVALID_HANDLE)
	{
		KillTimer(hPlayerCounter);
		hPlayerCounter = INVALID_HANDLE;
	}

	convar_nt_deathmatch = FindConVar("nt_tdm_enabled");
	if(convar_nt_deathmatch != INVALID_HANDLE)
	{
		if(GetConVarFloat(convar_nt_deathmatch) > 0.0)
			g_bDeathMatchActive = true;		//we don't want to fire slomo in deathmatch mode
		else
			g_bDeathMatchActive = false;
	}

	g_bStartedSlowmo = false;

	lastJin = 0;
	lastNsf = 0;
	
	if(GetConVarBool(convar_slowmotion_enabled))
	{
		#if DEBUG > 0
		PrintToChatAll("Slowmo: Resetting cvars");
		#endif 
		
		if(GetConVarBool(hCheatCvar))
		{			
			if(GetConVarBool(convar_slowmotion_clientside))
			{
				for(int i = 1; i < MaxClients; i++)
				{
					if(!IsClientConnected(i) || !IsClientInGame(i) || !IsValidEntity(i))
						continue;
					ClientCommand(i, "cl_phys_timescale 1.0");
				}
				
				SetConVarFloat(hPhysTimeScale, 1.0);
				
				SetConVarInt(hGravity, 800);
			}
			else
			{
				//SetConVarFloat(hHostTimeScale, 1.0);
				ChangeHostTimeScale(1.0);
			}
			ActivateCheats(0);
		}
		

		
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
	
	if(g_bDeathMatchActive)
		return;

	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(client == lastJin && g_bLastManStanding[client] || client == lastNsf && g_bLastManStanding[client])
	{
		PushOnLastManDeath(client); 				//calling forward for the last man standing who died
	
		if(GetConVarBool(convar_slowmotion_enabled))
		{
			if(g_bStartedSlowmo)
				return;

			g_bStartedSlowmo = true; 				//we don't want to fire twice in case of a duel ending with 2 deaths

			#if DEBUG > 0
			PrintToChatAll("Starting slowmotion");
			#endif 
			
			ActivateCheats(1);
			
			if(GetConVarBool(hCheatCvar))
			{
				if(GetConVarBool(convar_slowmotion_clientside))
				{
					for(int i = 1; i < MaxClients; i++)
					{
						if(!IsClientConnected(i) || !IsClientInGame(i) || !IsValidEntity(i))
							continue;
						ClientCommand(i, "cl_phys_timescale 0.2"); //FIXME: might need a very short timer for this to work?
					}
					
					SetConVarFloat(hPhysTimeScale, 0.2);
					
					SetConVarInt(hGravity, 220);
				}
				else
				{
					//SetConVarFloat(hHostTimeScale, 0.6);
					ChangeHostTimeScale(0.2);
				}
			}
			
			if(g_bSoundFilesExist[0])
			{
				EmitSoundToAll(g_SloMoSound[0], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 160, SND_NOFLAGS, 0.6);
			}
			if(GetConVarBool(convar_slowmotion_clientside))
				g_TimerSlowMotion = CreateTimer(4.0, timer_DefaultTimeScale);
			else
				g_TimerSlowMotion = CreateTimer(1.0, timer_DefaultTimeScale);
		}
	}
}

public Action timer_DefaultTimeScale(Handle timer)
{
	g_TimerSlowMotion = INVALID_HANDLE;
	
	if(g_bSoundFilesExist[1])
	{
		EmitSoundToAll(g_SloMoSound[1], SOUND_FROM_PLAYER, SNDCHAN_AUTO, 160, SND_NOFLAGS, 0.6);
	}
	
	if(GetConVarBool(hCheatCvar))
	{
		if(GetConVarBool(convar_slowmotion_clientside))
		{
			for(int i = 1; i < MaxClients; i++)
			{
				if(!IsClientConnected(i) || !IsClientInGame(i) || !IsValidEntity(i))
					continue;
				ClientCommand(i, "cl_phys_timescale 1.0");
			}
			
			SetConVarFloat(hPhysTimeScale, 1.0);
			
			SetConVarInt(hGravity, 800);
		}
		else
		{
			//SetConVarFloat(hHostTimeScale, 1.0);
			ChangeHostTimeScale(1.0);
		}
	}
	
	CreateTimer(1.0, timer_DeactivateCheats);	
}

public Action timer_DeactivateCheats(Handle timer)
{
	ActivateCheats(0);
	return Plugin_Handled;
}

stock ChangeHostTimeScale(float value)
{
	if( hHostTimeScale == INVALID_HANDLE )
		return;
	
	char val[10];
	FloatToString(value, val, 10);
	new flags = GetConVarFlags(hHostTimeScale);
	SetConVarFlags(hHostTimeScale, flags & ~FCVAR_NOTIFY);
	SetConVarFloat(hHostTimeScale, value);
	SetConVarFlags(hHostTimeScale, flags);
	
	for(int i = 1; i < MaxClients; i++)
	{
		if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i))
			continue;
		SendConVarValue(i, hHostTimeScale, val);
	}
	#if DEBUG > 0
	PrintToChatAll("timescale %f", GetConVarFloat(hHostTimeScale));
	PrintToServer("timescale %f", GetConVarFloat(hHostTimeScale));
	#endif
}


stock ActivateCheats(int value)
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
	if(!IsClientInGame(client))
		return;
	
	if(!IsPlayerAlive(client) || g_MessageShownLast[client])
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

void PushOnLastManDeath(int client)
{
	Call_StartForward(g_hForwardLastManDeath);
	Call_PushCell(client);
	Call_Finish();
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