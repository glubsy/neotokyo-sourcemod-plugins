#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#define PLUGIN_VERSION "0.3"
#pragma semicolon 1
#define DEBUG 0
#define SPAM_TIME 2.0

bool g_bAttackHeld[MAXPLAYERS+1];
bool g_AntiSwitchBool[MAXPLAYERS+1];
float g_fLastAttackUse[MAXPLAYERS+1];
Handle convar_shake = INVALID_HANDLE;
Handle convar_weapontweaks = INVALID_HANDLE;
bool g_bSwitchHookSuccessful[MAXPLAYERS+1];
//bool g_bFireHookSuccessful[MAXPLAYERS+1];

public Plugin:myinfo = 
{
	name = "NEOTOKYO: weapon enhancements.",
	author = "glub",
	description = "Anti SRS exploit. Exploiters should be abused.",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
}

public void OnPluginStart()
{
	convar_shake = CreateConVar("sm_nt_weaponshake", "1", "Enable added shake kickback effect on weapons");
	convar_weapontweaks = CreateConVar("sm_nt_weapontweaks", "1", "Enable balancing some weapons");
	
	HookEvent("player_disconnect", OnPlayerDisconnect);	

	AddTempEntHook("Shotgun Shot", TE_ShotHook);
	
	for(int client = 1; client < MaxClients; client++)
	{
		if(!IsValidEntity(client) || !IsClientConnected(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
			continue; 
	
		if(SDKHookEx(client, SDKHook_WeaponCanSwitchTo, Hook_CannotSwitch))
			g_bSwitchHookSuccessful[client] = true;
		else
			g_bSwitchHookSuccessful[client] = false;
		
		/*
		if(SDKHookEx(client, SDKHook_FireBulletsPost, Hook_FireBulletsPost))
			g_bFireHookSuccessful[client] = true;
		else
		{
			#if DEBUG > 0
			PrintToChatAll("FireBulletsPost hook unsuccessful for %i!!", client);
			#endif 
			g_bFireHookSuccessful[client] = false;
		}
		*/
	}
	
	// init random number generator
	SetRandomSeed(RoundToFloor(GetEngineTime()));
}

public void OnClientPostAdminCheck(int client)
{
	if(!g_bSwitchHookSuccessful[client])
	{
		if(SDKHookEx(client, SDKHook_WeaponCanSwitchTo, Hook_CannotSwitch))
			g_bSwitchHookSuccessful[client] = true;
		else
			g_bSwitchHookSuccessful[client] = false;
	}
	
	/*
	if(!g_bFireHookSuccessful[client])
	{
		if(SDKHookEx(client, SDKHook_FireBulletsPost, Hook_FireBulletsPost))
			g_bFireHookSuccessful[client] = true;
		else
		{	
			#if DEBUG > 0
			PrintToChatAll("FireBulletsPost hook unsuccessful for %i!!", client);
			#endif
			g_bFireHookSuccessful[client] = false;
		}
	}
	*/
}


public Action TE_ShotHook(const char[] te_name, const int[] Players, int numClients, float delay)
{
	int weapon = TE_ReadNum("m_iWeaponID");
	
	if(weapon == 28) //28 is weapon_SRS
	{
		int client = TE_ReadNum("m_iPlayer") + 1; //is shifted by 1 for some reason
		
		TE_WriteNum("m_bTracer", 1);
		if(GetConVarBool(convar_shake))
		{
			ShakeScreen(client, 20.0, 2.0, 1.0);
			float angles[3];
			GetClientEyeAngles(client, angles);
			angles[0] -= 1.3;
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
		}
		return Plugin_Continue; // don't block it
	}
	
	if(GetConVarBool(convar_weapontweaks))
	{
		if(weapon == 8) //8 is weapon_zr68l
		{
			int client = TE_ReadNum("m_iPlayer") + 1;
			int randombool;
			int randomroll = UTIL_GetRandomInt(0, 100);
			if(randomroll <= 62)
				randombool = 0;
			else 
				randombool = 1;
			
			TE_WriteNum("m_bTracer", randombool);
			if(GetConVarBool(convar_shake))
				ShakeScreen(client, 2.5, 1.2, 0.7);		
			return Plugin_Continue;
		}

		if(weapon == 25) //25 is weapon_aa13
		{
			int client = TE_ReadNum("m_iPlayer") + 1;
			TE_WriteNum("m_bTracer", 1);
			if(GetConVarBool(convar_shake))
				ShakeScreen(client, 12.0, 4.5, 1.2);
			float angles[3];
			GetClientEyeAngles(client, angles);
			angles[0] -= 2.5;
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			
			return Plugin_Continue;
		}
		
		if(weapon == 2) //2 is weapon_supa7
		{
			int client = TE_ReadNum("m_iPlayer") + 1;
			TE_WriteNum("m_bTracer", 1);
			float angles[3];
			GetClientEyeAngles(client, angles);
			angles[0] -= 1.5;
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			
			return Plugin_Continue;
		}
		
		if(weapon == 20) //20 is weapon_m41
		{
			int client = TE_ReadNum("m_iPlayer") + 1;
			TE_WriteNum("m_bTracer", 1);
			float angles[3];
			GetClientEyeAngles(client, angles);
			angles[0] -= 0.9;
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			
			return Plugin_Continue;
		}
		
		if(weapon == 29) //29 is weapon_m41s
		{
			int client = TE_ReadNum("m_iPlayer") + 1;
			float angles[3];
			GetClientEyeAngles(client, angles);
			angles[0] -= 0.8;
			TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
			
			return Plugin_Continue;
		}
	}
	
	#if DEBUG > 0
	//Unchanged wpn values: 27 mx_silenced, 17 jittescoped, 16 kitte, 11 srm, 12 srm_s, 26 knife, 5 tachi, 10 milso, 24 kyla
	else
	{
		int client = TE_ReadNum("m_iPlayer") + 1;
		float vecOrigin[3];
		float vecAngles[2];
		int tracer = TE_ReadNum("m_bTracer");
		TE_ReadVector("m_vecOrigin", vecOrigin);
		vecAngles[0] = TE_ReadFloat("m_vecAngles[0]");
		vecAngles[1] = TE_ReadFloat("m_vecAngles[1]");
		int m_iMode = TE_ReadNum("m_iMode");
		int m_iSeed = TE_ReadNum("m_iSeed");
		float m_flSpread = TE_ReadFloat("m_flSpread");
		PrintToChatAll("TE: player %i weapon %i tracer %b Origin %f %f %f, Angles %f %f mode %i seed %i spread %f", client, weapon, tracer, vecOrigin[0], vecOrigin[1], vecOrigin[2], vecAngles[0], vecAngles[1], m_iMode, m_iSeed, m_flSpread);
	}
	#endif 
	
	return Plugin_Continue;
}



public Action OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if(!IsValidEntity(client))
		return;
	
	int active_weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(active_weapon < 1)
		return; 
	
	char classbuffer[30];
	GetEntityClassname(active_weapon, classbuffer, sizeof(classbuffer));

	if(!StrEqual(classbuffer, "weapon_srs", false))
		return;
	
	if((buttons & IN_ATTACK) == IN_ATTACK)
	{
		if(g_bAttackHeld[client])
		{
			if((GetGameTime() - g_fLastAttackUse[client]) > SPAM_TIME)
			{
				#if DEBUG > 0
				//PrintToChatAll("ALLOWED after SPAM_TIME");
				#endif
				
				g_AntiSwitchBool[client] = true;
				ClearPreventSwitchingWeapon(client);
				
				g_fLastAttackUse[client] = GetGameTime();
			}
		}
		else
		{
			//g_AntiSwitchBool[client] = true;
			g_bAttackHeld[client] = true;
		}
	}
	else
	{
		//g_AntiSwitchBool[client] = false;
		g_bAttackHeld[client] = false;
	}
}


public void ClearPreventSwitchingWeapon(int client)
{
	CreateTimer(2.0, timer_clearCannotSwitchHook, client);
	
	#if DEBUG > 0
	PrintToChat(client, "TIMER to clear boolean");
	#endif
}

public Action timer_clearCannotSwitchHook(Handle timer, int client)
{
	g_AntiSwitchBool[client] = false;
	
	#if DEBUG > 0
	PrintToChat(client, "CLEARED switch hook %f", GetGameTime());
	#endif
}

public Action Hook_CannotSwitch(int client, int weapon)
{
	if(!g_AntiSwitchBool[client])
		return Plugin_Continue;
	
	char classname[15];
	GetEdictClassname(weapon, classname, sizeof(classname));
	if(StrEqual(classname, "weapon_srs"))
	{
		#if DEBUG > 0
		//PrintToChat(client, "Blocking %s", classname);
		#endif
		return Plugin_Stop;
	}
	else
		return Plugin_Continue;
}

/*
//This is not working in Neotokyo :(
public Hook_FireBulletsPost(int client, int shots, const char[] weaponname)
{
	#if DEBUG > 0
	PrintToChatAll("FireBulletsPost: %i is firing.", client);
	#endif
}
*/


public void OnPlayerDisconnect(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(g_bSwitchHookSuccessful[client])
	{
		SDKUnhook(client, SDKHook_WeaponCanSwitchTo, Hook_CannotSwitch);
		g_bSwitchHookSuccessful[client] = false;
	}
	
	g_AntiSwitchBool[client] = false;
	
	/*
	if(g_bFireHookSuccessful[client])
	{
		SDKUnhook(client, SDKHook_FireBulletsPost, Hook_FireBulletsPost);
		g_bFireHookSuccessful[client] = false;
	}
	*/
}


/*structure:
	byte // command, check SHAKE defines
	float // amplitude
	float // frequency
	float // duration
#define SHAKE_START				0	// Starts the screen shake for all players within the radius.
#define SHAKE_STOP				1	// Stops the screen shake for all players within the radius.
#define SHAKE_AMPLITUDE			2	// Modifies the amplitude of an active screen shake for all players within the radius.
#define SHAKE_FREQUENCY			3	// Modifies the frequency of an active screen shake for all players within the radius.
#define SHAKE_START_RUMBLEONLY	4	// Starts a shake effect that only rumbles the controller, no screen effect.
#define SHAKE_START_NORUMBLE	5	// Starts a shake that does NOT rumble the controller.
*/

public void ShakeScreen(int client, float amplitude, float frequency, float duration)
{
	#if DEBUG > 0
	PrintToChat(client, "SHAKIN' BOOTY");
	#endif 
	
	Handle hBuffer = StartMessageOne("Shake", client);
	if (hBuffer == INVALID_HANDLE)
		LogError("[SRSEXPLOIT] INVALID_HANDLE for client %N (%i)", client, client);
	else
	{
		BfWriteByte(hBuffer, 0); //start
		BfWriteFloat(hBuffer, amplitude);
		BfWriteFloat(hBuffer, frequency);
		BfWriteFloat(hBuffer, duration);
		EndMessage();
	}
	
}


stock Action TE_RelayShotTempent(int weaponID, float origin[3], float angle0, float angle1, float spread, int seed, int mode)
{
	TE_Start("Shotgun Shot");
	TE_WriteNum("m_iWeaponID", weaponID);
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteFloat("m_vecAngles[0]", angle0);
	TE_WriteFloat("m_vecAngles[1]", angle1);
	TE_WriteFloat("m_flSpread", spread);
	TE_WriteNum("m_iSeed", seed);
	TE_WriteNum("m_iMode", mode);
	TE_WriteNum("m_bTracer", 1);
	TE_SendToAll();
}

stock Action TE_SendCustom(const char[] TEname, int player, int weaponID, float origin[3], float angle0, float angle1, float spread, int seed, int mode, int tracer)
{
	TE_Start(TEname);
	TE_WriteNum("m_iPlayer", player);
	TE_WriteNum("m_iWeaponID", weaponID);
	TE_WriteVector("m_vecOrigin", origin);
	TE_WriteFloat("m_vecAngles[0]", angle0);
	TE_WriteFloat("m_vecAngles[1]", angle1);
	TE_WriteFloat("m_flSpread", spread);
	TE_WriteNum("m_iSeed", seed);
	TE_WriteNum("m_iMode", mode);
	TE_WriteNum("m_bTracer", tracer);
	TE_SendToAll();
	
	#if DEBUG > 0
	PrintToChatAll("fired custom tempent: %s", TEname);
	#endif
}


UTIL_GetRandomInt(int start, int end) {
    int rand;
    rand = GetURandomInt();
    return ( rand % (1 + end - start) ) + start;
}


public bool IsValidClient(int client) 
{
    if(client <= 0)
        return false;
    if(client > MaxClients)
        return false;

    return IsClientInGame(client);
}