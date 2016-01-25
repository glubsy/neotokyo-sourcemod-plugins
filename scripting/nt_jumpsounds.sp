#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <neotokyo>

#define PLUGIN_VERSION "0.1"
#pragma semicolon 1
#define DEBUG 0
#define SPAM_TIME 0.20

//bool g_bJumpHeld[MAXPLAYERS+1];
//bool g_bJumped[MAXPLAYERS+1];
//float g_fLastJumpUse[MAXPLAYERS+1];

int g_iJumpNum[MAXPLAYERS+1];
bool g_bSoundLocked[MAXPLAYERS+1];
bool g_bJumpsDisabled;

Handle convar_nt_funnysounds = INVALID_HANDLE;
Handle convar_nt_jumpsounds = INVALID_HANDLE;


char g_sCustomJumpSound[][] = {
	"custom/nyanpasu.mp3",
	"custom/Time_Walk.mp3",
	"custom/pururin.mp3"
};

char g_sStockSound[][] = {
	"physics/cardboard/cardboard_box_impact_hard2.wav",		//wet low, good for heavy
	"physics/cardboard/cardboard_box_impact_hard6.wav",		//dryer low, good for recon
	"physics/flesh/flesh_impact_bullet3.wav",				//dry high, sounds like crowbar hits
	"physics/flesh/flesh_strider_impact_bullet2.wav",		//medium, a bit choppy
	"physics/metal/metal_computer_impact_soft1.wav",		//light, not very good (sounds like a spring)
	"physics/metal/metal_computer_impact_soft2.wav",		//light, not very good (sounds like a spring)
	"physics/metal/metal_grenade_impact_soft3.wav",			//medium, decent for lighter classes
	"physics/wood/wood_box_impact_bullet4.wav",				//wooden, sounds like a bottle cap being removed
	"buttons/button1.wav",									//buzzing sound
	"buttons/button15.wav",									//can be played super fast over short time
	"buttons/combine_button3.wav",							//both high and low (not good)
	"ambient/levels/prison/radio_random11.wav",				//high pitch (not very good)
	"vehicles/atv_ammo_close.wav",							//dry and high, mediocre
	"vehicles/atv_ammo_open.wav"							//more wet, better, good for heavy or assault
};

public Plugin:myinfo = 
{
	name = "NEOTOKYO: jumping sound effects",
	author = "glub, soft as HELL",
	description = "Adds sound effect to jumps",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
}

public void OnPluginStart()
{
	convar_nt_funnysounds = CreateConVar("nt_funnyjumpsounds", "0", "Custom sound effect for jumping 0=disabled, 1-3");
	convar_nt_jumpsounds = CreateConVar("nt_jumpsounds", "1", "Enables jump sound effects");
	//OnConfigsExecuted();
	HookEvent("game_round_start", OnRoundStart);
}

public void OnConfigsExecuted()
{
	for(int snd = 0; snd < sizeof(g_sCustomJumpSound); snd++)
	{
		PrecacheSound(g_sCustomJumpSound[snd], true);
		decl String:buffer[120];
		Format(buffer, sizeof(buffer), "sound/%s", g_sCustomJumpSound[snd]);
		AddFileToDownloadsTable(buffer);
	}
	for(int snd = 0; snd < sizeof(g_sStockSound); snd++)
	{
		PrecacheSound(g_sStockSound[snd], true);
	}
}

public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	g_bJumpsDisabled = true;
	
	CreateTimer(15.0, timer_clearsoundlock, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action timer_clearsoundlock(Handle timer)
{
	g_bJumpsDisabled = false;
}



/*
public void OnGameFrame()
{
	for(int client = 1; client < MaxClients; client++)
	{
		if(!IsValidEntity(client) || !IsClientConnected(client))
			continue;
		if(IsFakeClient(client))
			continue;
		
		static Float:fVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);
		
		if (fVelocity[0] >= 150.0 || fVelocity[1] >= 150.0)
		{
			//EmitBasicJumpSound(client, 4);
			#if DEBUG > 0
			PrintToChatAll("%N: velocity: %f %f %f", client, fVelocity[0],fVelocity[1],fVelocity[2]);
			#endif
		}
	}	
}*/

public Action OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if(g_bJumpsDisabled)
		return;

	if(!GetConVarBool(convar_nt_jumpsounds))
		return;

	if(!IsValidEntity(client) || !IsPlayerAlive(client))
		return;

	if(buttons & IN_JUMP)
	{
		if(GetEntityMoveType(client) & MOVETYPE_LADDER)
		{
			return; // Do nothing on ladder
		}

		//if((GetGameTime() - g_fLastJumpUse[client]) > SPAM_TIME)
		{
			if(GetEntityFlags(client) & FL_ONGROUND)
			{
				CountJumps(client);
				if(GetConVarInt(convar_nt_funnysounds) == 0)
					EmitBasicJumpSound(client, 5, false);
				else
					EmitBasicJumpSound(client, (GetConVarInt(convar_nt_funnysounds) -1), true);
			}
			//g_fLastJumpUse[client] = GetGameTime();
		}
		
	}
	else
	{
		// Released jump
		g_iJumpNum[client] = 0;
		g_bSoundLocked[client] = false;
	}
}


public Action EmitBasicJumpSound(int client, int soundindex, bool classoverride)
{
	if(g_bSoundLocked[client])
		return;
	
	g_bSoundLocked[client] = true;
	
	float vecEyeAngles[3], vecOrigin[3];
	GetClientEyeAngles(client, vecEyeAngles);
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vecOrigin);
	vecOrigin[0] += 15.0 * Cosine(DegToRad(vecEyeAngles[1]));
	vecOrigin[1] += 15.0 * Sine(DegToRad(vecEyeAngles[1]));
	vecOrigin[2] -= 15;
	
	if(classoverride)
	{
		if(soundindex == 2) //pururin
		{
			EmitSoundToAll(g_sCustomJumpSound[soundindex], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, SNDVOL_NORMAL, 100, -1, vecOrigin, vecEyeAngles);
			StopSoundPerm(client, g_sCustomJumpSound[soundindex]);
		}
		if(soundindex == 1) //timewalk
		{
			EmitSoundToAll(g_sCustomJumpSound[soundindex], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, vecEyeAngles);
			StopSoundPerm(client, g_sCustomJumpSound[soundindex]);
		}
		if(soundindex == 0) //nyanpasu
		{
			EmitSoundToAll(g_sCustomJumpSound[soundindex], SOUND_FROM_WORLD, SNDCHAN_AUTO, 70, SND_NOFLAGS, SNDVOL_NORMAL, GetRandomInt(85, 110), -1, vecOrigin, vecEyeAngles);
			StopSoundPerm(client, g_sCustomJumpSound[soundindex]);
		}
	}
	else
	{
		int PlayerClass = GetEntProp(client, Prop_Send, "m_iClassType");
		if(PlayerClass == 1) //recon
		{		
			EmitSoundToAll(g_sStockSound[6], SOUND_FROM_WORLD, SNDCHAN_AUTO, 90, SND_NOFLAGS, 0.7, GetRandomInt(85, 110), -1, vecOrigin, vecEyeAngles);
		}
		else if(PlayerClass == 2) //assault
		{
			EmitSoundToAll(g_sStockSound[1], SOUND_FROM_WORLD, SNDCHAN_AUTO, 90, SND_NOFLAGS, 0.7, GetRandomInt(85, 110), -1, vecOrigin, vecEyeAngles);
		}
		else if(PlayerClass == 3) //support
		{
			EmitSoundToAll(g_sStockSound[0], SOUND_FROM_WORLD, SNDCHAN_AUTO, 90, SND_NOFLAGS, 0.7, GetRandomInt(85, 110), -1, vecOrigin, vecEyeAngles);
		}
	}
	
	CreateTimer(0.2, timer_ClearSoundLock, client);
}


//only good to control jump key BEINB pressed CONTINUALLY
public Action CountJumps(int client)
{
	g_iJumpNum[client]++;
	
	#if DEBUG > 0
	PrintToChatAll("Jump counter: %i", g_iJumpNum[client]);
	#endif
	
	if(g_iJumpNum[client] > 1)
		g_bSoundLocked[client] = true;
}

public Action timer_ClearSoundLock(Handle timer, int client)
{
	#if DEBUG > 0
	PrintToChatAll("timer unlock");
	#endif 
	g_bSoundLocked[client] = false;
}

 
stock void StopSoundPerm(int client, char[] sound)
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
		PrintToChatAll("Stopped sound for %N", client);
		#endif
	}
}
