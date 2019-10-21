#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32
#define DEBUG 0
Handle g_hCurrentlyPlaying[NEO_MAX_CLIENTS] = {INVALID_HANDLE, ...};
const int MAX_SND_INSTANCES = 5; // maximum concurent sounds allowed to be amitted over CVAR_hurt_sounds_delay period, for security
int g_iSoundInstances = 0; 
int g_iAffectedPlayers[NEO_MAX_CLIENTS+1][NEO_MAX_CLIENTS+1]; // arrays of affected players
int g_iAffectedNumPlayers[NEO_MAX_CLIENTS+1] = { 0, ...}; // number of affected players in the array above
Handle g_RefreshArrayTimer = INVALID_HANDLE;

Handle CVAR_hurt_sounds, CVAR_team_only, CVAR_spec_only, CVAR_hurt_sounds_delay = INVALID_HANDLE;

char g_sCustomGirlHurtSound[][] = {
	"custom/himitu09065b.mp3",
	"custom/himitu09065.mp3",
	"custom/himitu09066.mp3",
	"custom/himitu09068.mp3",
	"custom/himitu09071.mp3",
	"custom/himitu09080.mp3",
};

// TODO: assign a specific set of similar sounds for each player?
// TODO: make opt-out
// TODO: make cookie pref menu
// TODO: use bitbuffer instead of arrays to keep track of affected players?

public Plugin:myinfo =
{
	name = "NEOTOKYO hurt sound effects",
	author = "glub",
	description = "Emit sounds when player gets hurt.",
	version = "0.1",
	url = "https://github.com/glubsy"
};

public void OnPluginStart()
{
	CVAR_hurt_sounds = CreateConVar("sm_hurt_sounds", "1", 
	"Enable (1) or disable (0) emitting custom sounds when players are hurt.", 0, true, 0.0, true, 1.0);

	CVAR_hurt_sounds_delay = CreateConVar("sm_hurt_sounds_delay", "8.5", 
	"Delay until more hurt sounds may be emitted by a player.", 0, true, 0.0, true, 500.0);

	CVAR_team_only = CreateConVar("sm_hurt_sounds_team_only", "1", 
	"Enable (1) or disable (0) emitting custom sounds from team mates only.", 0, true, 0.0, true, 1.0);

	CVAR_spec_only = CreateConVar("sm_hurt_sounds_spec_only", "0", 
	"Enable (1) or disable (0) emitting custom sounds for alive players.", 0, true, 0.0, true, 1.0);

	#if DEBUG > 1
	AddNormalSoundHook(OnNormalSound);
	#endif

	HookConVarChange(CVAR_hurt_sounds, OnConVarChanged);
}


public void OnConfigsExecuted()
{
	AutoExecConfig(true, "nt_hurt_sfx");

	if (!GetConVarBool(CVAR_hurt_sounds))
		return;

	HookEvent("player_hurt", Event_OnPlayerHurt);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("game_round_start", Event_OnRoundStart);
	HookEvent("player_spawn", Event_OnPlayerSpawn);

	#if DEBUG
	// tempents probably won't generate errors when sending to disconnected clients
	// so maybe we don't really need to update arrays here
	HookEvent("player_disconnect", Event_OnPlayerDisconnect);
	#endif

	for(int snd = 0; snd < sizeof(g_sCustomGirlHurtSound); snd++)
	{
		PrecacheSound(g_sCustomGirlHurtSound[snd], true);
		decl String:buffer[120];
		Format(buffer, sizeof(buffer), "sound/%s", g_sCustomGirlHurtSound[snd]);
		AddFileToDownloadsTable(buffer);
	}

	// reset arrays for all
	UpdateAffectedArrayForAlivePlayers(-1);
}


public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!GetConVarBool(CVAR_hurt_sounds))
	{
		UnhookEvent("player_hurt", Event_OnPlayerHurt);
		UnhookEvent("player_death", Event_OnPlayerDeath);
		UnhookEvent("game_round_start", Event_OnRoundStart);
		UnhookEvent("player_spawn", Event_OnPlayerSpawn);

		#if DEBUG
		// tempents probably won't generate errors when sending to disconnected clients
		// so maybe we don't really need to update arrays here
		UnhookEvent("player_disconnect", Event_OnPlayerDisconnect);
		#endif
	}
	HookEvent("player_hurt", Event_OnPlayerHurt);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("game_round_start", Event_OnRoundStart);
	HookEvent("player_spawn", Event_OnPlayerSpawn);

	#if DEBUG
	// tempents probably won't generate errors when sending to disconnected clients
	// so maybe we don't really need to update arrays here
	HookEvent("player_disconnect", Event_OnPlayerDisconnect);
	#endif
}



public Action Event_OnPlayerSpawn(Event event, const char[] name, bool dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsValidClient(client))
		return Plugin_Continue;

	#if DEBUG
	PrintToServer("[nt_hurt_sfx] Event_OnPlayerSpawn(%d) (%N)", client, client);
	#endif

	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1 || GetEntProp(client, Prop_Send, "deadflag"))
	{
		#if DEBUG
		PrintToServer("[nt_hurt_sfx] client %N spawned but is actually dead!", client);
		#endif
		return Plugin_Continue;
	}


	// for players spawning after freeze time has already ended
	if (g_RefreshArrayTimer == INVALID_HANDLE)
		g_RefreshArrayTimer = CreateTimer(5.0, timer_RefreshArraysForAll, -1, TIMER_FLAG_NO_MAPCHANGE);

	#if DEBUG
	CreateTimer(20.0, timer_PrintArray, client);
	#endif

	return Plugin_Continue;
}


public Action timer_PrintArray(Handle timer, int client)
{
	for (int i = 0; i < g_iAffectedNumPlayers[client]; i++)
		PrintToServer("[nt_hurt_sfx] g_iAffectedPlayers[%i][%i] affected client index %d (%N)", 
		client, i, g_iAffectedPlayers[client][i], g_iAffectedPlayers[client][i]);
}


public Action Event_OnRoundStart(Event event, const char[] name, bool dontbroadcast)
{
	#if DEBUG
	PrintToServer("[nt_hurt_sfx] OnRoundStart()")
	#endif

	// 15 seconds should be right when freeze time ends
	g_RefreshArrayTimer = CreateTimer(15.0, timer_RefreshArraysForAll, -1, TIMER_FLAG_NO_MAPCHANGE);
}


// passing -1 refreshes all arrays
public Action timer_RefreshArraysForAll(Handle timer, int client)
{
	#if DEBUG
	PrintToServer("[nt_hurt_sfx] Timer is now calling UpdateAffectedArrayForAlivePlayers(%d).", client);
	#endif

	// force update for all arrays
	UpdateAffectedArrayForAlivePlayers(client);

	if (g_RefreshArrayTimer != INVALID_HANDLE)
		g_RefreshArrayTimer = INVALID_HANDLE;
	return Plugin_Continue;
}


public Action Event_OnPlayerHurt(Event event, const char[] name, bool dontbroadcast)
{
	if (!GetConVarBool(CVAR_hurt_sounds))
		return Plugin_Continue;

	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (g_hCurrentlyPlaying[client] == INVALID_HANDLE && g_iSoundInstances <= MAX_SND_INSTANCES)
	{
		EmitHurtSoundFromClientPos(client);
		++g_iSoundInstances;
		// we allow playing one sound clip every amount of seconds
		g_hCurrentlyPlaying[client] = CreateTimer(GetConVarFloat(CVAR_hurt_sounds_delay), ResetPlayingFlag, client);
	}
	return Plugin_Continue;
}


public Action Event_OnPlayerDeath(Event event, const char[] name, bool dontbroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	#if DEBUG
	PrintToServer("[nt_hurt_sfx] %N died, updating arrays.", victim);
	#endif

	UpdateAffectedArrayForAlivePlayers(victim);

	return Plugin_Continue;
}


public void OnClientPutInServer(int client)
{
	// delay ?
	UpdateAffectedArrayForAlivePlayers(client);
}


public Action Event_OnPlayerDisconnect(Event event, const char[] name, bool dontbroadcast)
{
	int disconnected = GetClientOfUserId(GetEventInt(event, "userid"));

	#if DEBUG
	PrintToServer("[nt_hurt_sfx] Client %d just disconnected. Asking for array refresh.", disconnected);
	#endif

	if (disconnected < 1)
		disconnected = -1;

	if (g_RefreshArrayTimer == INVALID_HANDLE)
		// delay because when disconnecting, player is respawning and considered still "alive", which is wrong!
		g_RefreshArrayTimer = CreateTimer(1.0, timer_RefreshArraysForAll, disconnected, TIMER_FLAG_NO_MAPCHANGE);
}


// for each alive player, update their array to reflect updated_client being affected
public void UpdateAffectedArrayForAlivePlayers(int updated_client)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsValidClient(client) || !IsClientConnected(client))
		{
			#if DEBUG
			PrintToServer("[nt_hurt_sfx] client %d is either not valid or not connected", client);
			#endif

			continue;
		}

		if (client == updated_client) // don't emit for ourselves
			continue;

		if (!IsPlayerReallyAlive(client)) // dead players wouldn't emit any sound
			continue;
		
		if (!IsValidClient(updated_client) || !IsClientConnected(updated_client))
		{
			#if DEBUG
			PrintToServer("[nt_hurt_sfx] Player %d not valid, rebuilding array for %N.", updated_client, client);
			#endif

			// no choice but to rebuild the entire array :(

			g_iAffectedNumPlayers[client] = 0; // reset counter

			for (int j = 1; j <= MaxClients; j++)
			{
				if (!IsValidClient(j) || !IsClientConnected(j))
					continue;
				
				if (j == client)
					continue; // we shouldn't emit for ourselves

				if (IsPlayerReallyAlive(j))
				{
					#if DEBUG > 1
					PrintToServer("[nt_hurt_sfx] Player \"%N\" is alive.", j)
					#endif
	
					if (GetConVarBool(CVAR_spec_only))
						continue;
					if (GetConVarBool(CVAR_team_only) && GetClientTeam(j) != GetClientTeam(client))
						continue;

					#if DEBUG > 1
					PrintToServer("[nt_hurt_sfx] Adding %N to array for %N.", j, client)
					#endif
	
					g_iAffectedPlayers[client][g_iAffectedNumPlayers[client]++] = j;
					continue;
				}
				#if DEBUG > 1
				PrintToServer("[nt_hurt_sfx] Player \"%N\" is not alive. Adding \"%N\" to array for %N.",j, j, client)
				#endif
				g_iAffectedPlayers[client][g_iAffectedNumPlayers[client]++] = j;

			}
			continue;
		}

		#if DEBUG > 1
		PrintToServer("[nt_hurt_sfx] Adding \"%N\" to array for %N", updated_client, updated_client, client);
		#endif
		g_iAffectedPlayers[client][g_iAffectedNumPlayers[client]++] = updated_client;

	}
}


void EmitHurtSoundFromClientPos(int client)
{
	int rand = GetRandomInt(0, sizeof(g_sCustomGirlHurtSound) -1);
	float vecEyeAngles[3], vecOrigin[3];
	GetClientEyeAngles(client, vecEyeAngles);
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[0] += 15.0 * Cosine(DegToRad(vecEyeAngles[1]));
	vecOrigin[1] += 15.0 * Sine(DegToRad(vecEyeAngles[1]));
	vecOrigin[2] -= 15;

	#if DEBUG
	PrintToServer("[nt_hurt_sfx] Emitting sound %s at %f %f %f.", g_sCustomGirlHurtSound[rand], vecOrigin[0], vecOrigin[1], vecOrigin[2]);
	#endif

	if (GetConVarBool(CVAR_spec_only) || GetConVarBool(CVAR_team_only))
	{
		EmitSound(g_iAffectedPlayers[client], g_iAffectedNumPlayers[client],
				 g_sCustomGirlHurtSound[rand], 
				 SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 
				 GetRandomInt(95, 110), -1, vecOrigin, vecEyeAngles);
	}
	else
	{
		EmitSoundToAll(g_sCustomGirlHurtSound[rand], 
		SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, 
		GetRandomInt(95, 110), -1, vecOrigin, vecEyeAngles);
	}
	//StopSoundPerm(client, g_sCustomGirlHurtSound[rand]);
}


public Action ResetPlayingFlag(Handle timer, int client)
{
	g_hCurrentlyPlaying[client] = INVALID_HANDLE;
	--g_iSoundInstances;
}

#if DEBUG > 1
public Action OnNormalSound(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity,
 					 int &channel, float &volume, int &level, int &pitch, int &flags)
{
	PrintToChatAll("[nt_hurt_sfx] Sound: %s emitted for %d clients.", sample, numClients);
	PrintToServer("[nt_hurt_sfx] Sound: %s emitted for %d clients.", sample, numClients);
	return Plugin_Continue;
}
#endif //DEBUG

 
void StopSoundPerm(int client, char[] sound)
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
		#if DEBUG > 0
		PrintToChatAll("[nt_hurt_sfx] Stopped sound for %N", client);
		#endif
	}
}


bool IsPlayerReallyAlive(int client)
{
	if ((GetClientTeam(client) < 2)) // not in team, probably spectator
		return false;

	#if DEBUG > 2
	PrintToServer("[nt_hurt_sfx] DEBUG: Client %N (%d) has %d health.", client, client, GetEntProp(client, Prop_Send, "m_iHealth"));
	#endif

	// For some reason, 1 health point means dead, but checking deadflag is probably more reliable!
	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1 || GetEntProp(client, Prop_Send, "deadflag"))
	{
		#if DEBUG
		PrintToServer("[nt_hurt_sfx] DEBUG: Determined that %N is not alive right now.", client);
		#endif
		return false;
	}

	return true;
}
