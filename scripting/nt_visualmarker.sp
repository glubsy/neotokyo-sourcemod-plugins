#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif

int laser_color[4] = {210, 210, 0, 128};
int giBeaconSprite[NEO_MAX_CLIENTS+1][2];
int giBeaconBeam[NEO_MAX_CLIENTS+1] = {-1, ...};
int giHeadTarget[NEO_MAX_CLIENTS+1] = {-1, ...};
int giTargetStart[NEO_MAX_CLIENTS+1] = {-1, ...};
int giTargetEnd[NEO_MAX_CLIENTS+1] = {-1, ...};
int g_modelHalo, g_modelLaser, giCircleModel, giQmarkModel;
bool gbIsObserver[NEO_MAX_CLIENTS+1];
bool gbCanUpdatePos[NEO_MAX_CLIENTS+1];
int giRadiusInc[NEO_MAX_CLIENTS+1];

enum SpriteType { QMARK = 0, CIRCLE };

public Plugin:myinfo =
{
	name = "NEOTOKYO target marker",
	author = "glub",
	description = "Place a marker in the world for teammates to see.",
	version = "0.1",
	url = "https://github.com/glubsy"
};

/*
TODO:
- have a "ignore z" laser
- have their name displayed at the ping location? (visual clutter?)
- emit a brief sound when placed
- share spotted beacon from ghost carrier when clicking while aiming at a beacon/player
- only show visual pings from people in same squad
- display a small halo ring upon creation
*/

#define USE_TE 1

public void OnPluginStart()
{
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("game_round_start", OnRoundStart);

	for (int i = 0; i < sizeof(giBeaconSprite); ++i)
	{
		giBeaconSprite[i][QMARK] = -1;
		giBeaconSprite[i][CIRCLE] = -1;
	}
}

// #define LASERMDL "custom/radio.vmt"
// #define LASERMDL "materials/sprites/laser.vmt"
#define LASERMDL "materials/sprites/redglow1.vmt" // good for animation

public OnMapStart()
{
	// g_modelLaser = PrecacheModel("materials/sprites/laser.vmt");
	g_modelLaser = PrecacheModel(LASERMDL);
	g_modelHalo = PrecacheModel("materials/sprites/halo01.vmt");

	giQmarkModel = PrecacheModel("materials/vgui/hud/cp/cp_none.vmt"); // question mark
	giCircleModel = PrecacheModel("materials/vgui/hud/ctg/g_beacon_circle.vmt"); // circle
}


public Action OnPlayerSpawn(Event event, const char[] name, bool dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsValidClient(client))
		return Plugin_Continue;

	if (IsClientObserver(client)){
		gbIsObserver[client] = true;
	}

	gbCanUpdatePos[client] = true;

	return Plugin_Continue;
}


public Action OnRoundStart(Event event, const char[] name, bool dontbroadcast)
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (!IsValidClient(i) || IsFakeClient(i))
			continue;

		if (IsValidEntity(giBeaconSprite[i][QMARK])){
			AcceptEntityInput(giBeaconSprite[i][QMARK], "ClearParent");
			AcceptEntityInput(giBeaconSprite[i][QMARK], "kill");
			giBeaconSprite[i][QMARK] = -1;
		}
		if (IsValidEntity(giBeaconSprite[i][CIRCLE])){
			AcceptEntityInput(giBeaconSprite[i][CIRCLE], "ClearParent");
			AcceptEntityInput(giBeaconSprite[i][CIRCLE], "kill");
			giBeaconSprite[i][CIRCLE] = -1;
		}
		if (IsValidEntity(giBeaconBeam[i])){
			AcceptEntityInput(giBeaconBeam[i], "ClearParent");
			AcceptEntityInput(giBeaconBeam[i], "kill");
			giBeaconBeam[i] = -1;
		}
		if (IsValidEntity(giTargetStart[i])){
			AcceptEntityInput(giTargetStart[i], "ClearParent");
			AcceptEntityInput(giTargetStart[i], "kill");
			giTargetStart[i] = -1;
		}
		if (IsValidEntity(giTargetEnd[i])){
			AcceptEntityInput(giTargetEnd[i], "ClearParent");
			AcceptEntityInput(giTargetEnd[i], "kill");
			giTargetEnd[i] = -1;
		}
		if (IsValidEntity(giHeadTarget[i])){
			AcceptEntityInput(giHeadTarget[i], "ClearParent");
			AcceptEntityInput(giHeadTarget[i], "kill");
			giHeadTarget[i] = -1;
		}
	}
}


int CreateBeaconEnt(SpriteType type)
{
	int iEnt = CreateEntityByName("env_sprite");

	if (!IsValidEntity(iEnt))
		return -1;

	if (type == QMARK)
	{
		DispatchKeyValue(iEnt, "model", "materials/vgui/hud/cp/cp_none.vmt");

		DispatchKeyValue(iEnt, "rendermode", "9"); // 3 glow keeps size
		DispatchKeyValueFloat(iEnt, "GlowProxySize", 10.0);
		// DispatchKeyValueFloat(iEnt, "HDRColorScale", 1.0); // needs testing
		DispatchKeyValue(iEnt, "renderamt", "255"); // transparency
		DispatchKeyValue(iEnt, "disablereceiveshadows", "1");
		DispatchKeyValue(iEnt, "renderfx", "9"); // 9 slow strobe
		DispatchKeyValue(iEnt, "rendercolor", "240 12 0");
		DispatchKeyValue(iEnt, "alpha", "255");

		SetVariantFloat(0.1);
		AcceptEntityInput(iEnt, "SetScale");  // this works!
		// SetEntPropFloat(ent, Prop_Data, "m_flSpriteScale", 0.2); // doesn't seem to work
		//DispatchKeyValueFloat(iEnt, "scale", 1.0); // doesn't seem to work
		// AcceptEntityInput(iEnt, "scale"); // doesn't work
	}
	else
	{
		DispatchKeyValue(iEnt, "model", "materials/vgui/hud/ctg/g_beacon_circle.vmt");

		DispatchKeyValue(iEnt, "rendermode", "9"); // 3 glow keeps size
		DispatchKeyValueFloat(iEnt, "GlowProxySize", 10.0);
		// DispatchKeyValueFloat(iEnt, "HDRColorScale", 1.0); // needs testing
		DispatchKeyValue(iEnt, "renderamt", "255"); // transparency
		DispatchKeyValue(iEnt, "disablereceiveshadows", "1");
		// DispatchKeyValue(iEnt, "renderfx", "9"); // 9 slow strobe
		DispatchKeyValue(iEnt, "rendercolor", "240 12 0");
		DispatchKeyValue(iEnt, "alpha", "255");

		SetVariantFloat(0.2);
		AcceptEntityInput(iEnt, "SetScale");  // this works!
		// SetEntPropFloat(ent, Prop_Data, "m_flSpriteScale", 0.2); // doesn't seem to work
		//DispatchKeyValueFloat(iEnt, "scale", 1.0); // doesn't seem to work
		// AcceptEntityInput(iEnt, "scale"); // doesn't work
	}

	DispatchSpawn(iEnt);
	return iEnt;
}


int CreateBeamEnt(int client)
{
	int iLaserEnt = CreateEntityByName("env_beam");

	char ent_name[20];
	Format(ent_name, sizeof(ent_name), "beaconbeam%d", client);
	DispatchKeyValue(iLaserEnt, "targetname", ent_name);

	ent_name[0] = '\0';
	Format(ent_name, sizeof(ent_name), "headtarget%d", client);
	DispatchKeyValue(iLaserEnt, "LightningStart", ent_name);

	// Note: there is no "targetpoint" key value like mentioned on the wiki in NT!
	ent_name[0] = '\0';
	Format(ent_name, sizeof(ent_name), "targetstart%d", client);
	DispatchKeyValue(iLaserEnt, "LightningEnd", ent_name);

	// https://github.com/Phil25/RTD/blob/907177084f86199e8b80b09357ed6fae333317f6/scripting/rtd/stocks.sp
	// SetEntPropEnt(iBeam, Prop_Send, "m_hAttachEntity", EntIndexToEntRef(iEntStart));
	// SetEntPropEnt(iBeam, Prop_Send, "m_hAttachEntity", EntIndexToEntRef(iEntEnd), 1);
	// SetEntProp(iBeam, Prop_Send, "m_nNumBeamEnts", 2);
	// SetEntProp(iBeam, Prop_Send, "m_nBeamType", 2);

	// Positioning
	// DispatchKeyValueVector(iLaserEnt, "origin", mine_pos);
	// TeleportEntity(iLaserEnt, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	// SetEntPropVector(iLaserEnt, Prop_Data, "m_vecEndPos", beam_end_pos);

	// Setting Appearance
	DispatchKeyValue(iLaserEnt, "texture", LASERMDL);
	DispatchKeyValue(iLaserEnt, "model", LASERMDL); // ?
	DispatchKeyValue(iLaserEnt, "decalname", "redglowalpha");

	DispatchKeyValue(iLaserEnt, "renderamt", "30"); // TODO(?): low renderamt, increase when activate
	DispatchKeyValue(iLaserEnt, "renderfx", "15"); // distort?
	DispatchKeyValue(iLaserEnt, "rendercolor", "200 25 25 30");
	DispatchKeyValue(iLaserEnt, "BoltWidth", "1.0");
	DispatchKeyValue(iLaserEnt, "spawnflags", "256"); // fade towards ending entity

	// something else..
	DispatchKeyValue(iLaserEnt, "life", "0.7");
	DispatchKeyValue(iLaserEnt, "StrikeTime", "0");
	DispatchKeyValue(iLaserEnt, "TextureScroll", "35");
	// DispatchKeyValue(iLaserEnt, "TouchType", "3");

	DispatchSpawn(iLaserEnt);
	SetEntityModel(iLaserEnt, LASERMDL);

	ActivateEntity(iLaserEnt); // not sure what that is (for texture animation?)

	// Link between weapon and laser indirectly. NEEDS TESTING
	// SetEntPropEnt(client, Prop_Send, "m_hEffectEntity", iLaserEnt);
	// SetEntPropEnt(iLaserEnt, Prop_Data, "m_hMovePeer", client); // should it be the attachment prop or weapon even?

	return iLaserEnt;
}




int CreateTarget(int client, char[] sTag)
{
	int iEnt = CreateEntityByName("info_target");
	// int iEnt = CreateEntityByName("prop_physics");
	// DispatchKeyValue(iEnt, "model", "models/nt/a_lil_tiger.mdl");

	char ent_name[20];
	Format(ent_name, sizeof(ent_name), "%s%d", sTag, client);
	DispatchKeyValue(iEnt, "targetname", ent_name);

	PrintToServer("[nt_visualping] Created info_target on %N (%d) :%s",
	client, iEnt, ent_name);

	DispatchSpawn(iEnt);

	SetVariantString("!activator"); // useless?
	AcceptEntityInput(iEnt, "SetParent", client, client, 0);

	DataPack dp = CreateDataPack();
	WritePackCell(dp, EntIndexToEntRef(iEnt));
	WritePackString(dp, sTag);

	CreateTimer(0.1, timer_SetAttachment, dp,
	TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);


	TeleportEntity(iEnt, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	return iEnt;
}


public Action timer_SetAttachment(Handle timer, DataPack dp)
{
	ResetPack(dp);
	int iEnt = EntRefToEntIndex(ReadPackCell(dp));
	char type[15];
	ReadPackString(dp, type, sizeof(type));

	#if DEBUG
	PrintToServer("[nt_visualping] SetParentAttachment to eyes for info_target %d.",
	iEnt);
	#endif

	SetVariantString("grenade0");
	AcceptEntityInput(iEnt, "SetParentAttachment");

	float origin[3];
	GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", origin);
	DispatchSpawn(iEnt);

	origin[0] += 12.0; // forward axis
	origin[1] += 15.9; // up down axis
	origin[2] += 15.5; // horizontal

	SetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", origin);

	return Plugin_Handled;
}


// attach two info_target to target entity to draw ring around it
int CreateTargetForBeacon(char[] sTag, int client, int parent_entity=0)
{
	int iEnt = CreateEntityByName("info_target");
	// int iEnt = CreateEntityByName("prop_physics_override");
	// DispatchKeyValue(iEnt, "model", "models/nt/a_lil_tiger.mdl");

	char ent_name[20];
	Format(ent_name, sizeof(ent_name), "%s%d", sTag, client);
	DispatchKeyValue(iEnt, "targetname", ent_name); // to attach beam

	PrintToServer("[nt_visualping] Created info_target \"%s\", parent: %d",
	ent_name, parent_entity);

	DispatchSpawn(iEnt);

	TeleportEntity(iEnt, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR); // no idea

	if (parent_entity)
	{
		SetVariantString("!activator"); // useless?
		AcceptEntityInput(iEnt, "SetParent", parent_entity, parent_entity, 0);

		// AcceptEntityInput(iEnt, "SetParentAttachment", parent_entity);

		if (StrContains("targetend", sTag) != -1) // offset the second point
		{
			float origin[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", origin);

			// DEBUG values
			origin[0] = 17.0; // forward axis
			origin[1] = 17.9; // up down axis
			origin[2] = 17.5; // horizontal

			SetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", origin);
		}
	}
	return iEnt;
}



public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (client == 0 /*|| gbIsObserver[client]*/ || IsFakeClient(client))
		return Plugin_Continue;

	if (buttons & (1 << 5)) // IN_USE
	{
		if (gbCanUpdatePos[client])
		{
			gbCanUpdatePos[client] = false;
			PlaceBeacon(client);
			CreateTimer(5.1, timer_ClearBlockingFlag, GetClientUserId(client),
			TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	return Plugin_Continue;
}


public Action timer_ClearBlockingFlag(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	gbCanUpdatePos[client] = true;
	return Plugin_Handled;
}


void PlaceBeacon(int client)
{
	float vecEnd[3], vecStart[3];
	GetClientEyePosition(client, vecStart);
	GetEndPositionFromClient(client, vecEnd);

	// OBSOLETE TESTING
	// SpawnTESprite(vecEnd, giQmarkModel, 0.2);
	// SpawnTESprite(vecEnd, giCircleModel, 0.5);

	if (giBeaconSprite[client][QMARK] <= 0) // FIXME more tests?
	{
		giBeaconSprite[client][QMARK] = CreateBeaconEnt(QMARK);
		giBeaconSprite[client][CIRCLE] = CreateBeaconEnt(CIRCLE);

		// giHeadTarget[client] = CreateTarget(client, "headtarget");

		/* OBSOLETE used for SpawnRing()
		// NOTE parenting an info_target to the sprite works
		giTargetStart[client] = CreateTargetForBeacon("targetstart",
		client, giBeaconSprite[client][QMARK]);

		// OBSOLETE used for SpawnRing()
		// giTargetEnd[client] = CreateTargetForBeacon("targetend",
		// client, giBeaconSprite[client]);
		*/

		#if !USE_TE
		giBeaconBeam[client] = CreateBeamEnt(client);
		#endif
	}

	AcceptEntityInput(giBeaconSprite[client][QMARK], "ShowSprite");
	AcceptEntityInput(giBeaconSprite[client][CIRCLE], "ShowSprite");

	#if !USE_TE
	AcceptEntityInput(giBeaconBeam[client], "TurnOn");
	#else
	TELaserBeam(client, giBeaconSprite[client][QMARK]);
	SendTE(GetClientTeam(client));
	#endif

	#if DEBUG
	PrintToServer("TurnOn sprite\nTurnOn BEAM");
	#endif

	TeleportEntity(giBeaconSprite[client][QMARK], vecEnd, NULL_VECTOR, NULL_VECTOR);
	TeleportEntity(giBeaconSprite[client][CIRCLE], vecEnd, NULL_VECTOR, NULL_VECTOR);
	// TeleportEntity(giTargetStart[client], vecEnd, NULL_VECTOR, NULL_VECTOR);
	// TeleportEntity(giTargetEnd[client], vecEnd, NULL_VECTOR, NULL_VECTOR);


	// attempt to draw a circle in increasing radius around target: FAIL
	// SpawnRing(client, giBeaconSprite[client][QMARK], giTargetEnd[client]);
	// giRadiusInc[client] = 0;
	// CreateTimer(0.1, timer_IncreaseEndRadius, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(5.0, timer_ToggleBeaconOff, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_IncreaseEndRadius(Handle timer, int client)
{
	float vecPos[3];
	GetEntPropVector(giTargetEnd[client], Prop_Send, "m_vecOrigin", vecPos);

	if (giRadiusInc[client] >= 10)
	{
		// DEBUG values
		vecPos[0] = 5.0;
		vecPos[1] = 5.0;
		vecPos[2] = 5.0;
		SetEntPropVector(giTargetEnd[client], Prop_Send, "m_vecOrigin", vecPos);
		// TeleportEntity(giTargetEnd[client], vecPos, NULL_VECTOR, NULL_VECTOR);
		return Plugin_Stop;
	}

	vecPos[2] += 10.0;
	SetEntPropVector(giTargetEnd[client], Prop_Send, "m_vecOrigin", vecPos);
	// TeleportEntity(giTargetEnd[client], NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	// TeleportEntity(giTargetEnd[client], vecPos, NULL_VECTOR, NULL_VECTOR);

	#if DEBUG
	GetEntPropVector(giTargetEnd[client], Prop_Send, "m_vecOrigin", vecPos);
	PrintToServer("END vecOrigin after %f %f %f", vecPos[0], vecPos[1], vecPos[2]);
	#endif
	giRadiusInc[client]++;
	return Plugin_Continue;
}


public Action timer_ToggleBeaconOff(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	ToggleBeacon(client);
	gbCanUpdatePos[client] = true;
	return Plugin_Handled;
}


void ToggleBeacon(int client)
{
	#if DEBUG
	PrintToServer("TurnOff sprite");
	#endif
	AcceptEntityInput(giBeaconSprite[client][QMARK], "HideSprite");
	AcceptEntityInput(giBeaconSprite[client][CIRCLE], "HideSprite");

	#if !USE_TE
	#if DEBUG
	PrintToServer("TurnOff BEAM");
	#endif
	AcceptEntityInput(giBeaconBeam[client], "TurnOff");
	#endif
}


void DestroyBeacon(int client)
{
	if (giBeaconSprite[client][QMARK] > 0)
	{
		AcceptEntityInput(giBeaconSprite[client][QMARK], "kill");
	}
	if (giBeaconBeam[client] > 0);
		AcceptEntityInput(giBeaconBeam[client], "kill");
}


void TELaserBeam(int iStartEnt=0, int iEndEnt=0,
float[3] vecStart=NULL_VECTOR, float[3] vecEnd=NULL_VECTOR)
{
	#if DEBUG
	PrintToServer("TELaserBeam(%d, %d, {%f %f %f}, {%f %f %f})",
	iStartEnt, iEndEnt, vecStart[0], vecStart[1], vecStart[2], vecEnd[0], vecEnd[1], vecEnd[2]);
	#endif
	// TE_Start("BeamPoints");
	// TE_Start("BeamEntPoint");
	TE_Start("BeamEnts");
	// TE_WriteVector("m_vecStartPoint", vecStart);
	// TE_WriteVector("m_vecEndPoint", vecEnd);
	TE_WriteNum("m_nFlags", FBEAM_NOTILE|FBEAM_FOREVER|FBEAM_ISACTIVE|FBEAM_SINENOISE|
	FBEAM_STARTENTITY|FBEAM_ENDENTITY|FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT);

	// specific to BeamEntPoint TE
	TE_WriteEncodedEnt("m_nStartEntity", iEndEnt); // inverted to allow animation in the proper direction
	TE_WriteEncodedEnt("m_nEndEntity", iStartEnt);

	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo); 	// NOTE: Halo can be set to "0"!
	TE_WriteNum("m_nStartFrame", 1);
	TE_WriteNum("m_nFrameRate", 2);
	TE_WriteFloat("m_fLife", 0.7);
	TE_WriteFloat("m_fWidth", 1.5);
	TE_WriteFloat("m_fEndWidth", 0.2);
	TE_WriteFloat("m_fAmplitude", 0.0);
	TE_WriteNum("r", laser_color[0]);
	TE_WriteNum("g", laser_color[1]);
	TE_WriteNum("b", laser_color[2]);
	TE_WriteNum("a", laser_color[3]);
	TE_WriteNum("m_nSpeed", 35);
	TE_WriteNum("m_nFadeLength", 10);
}

// Doesn't seem to work with info_target? Shame. Only work on physics props with model?
void TELaserBeamFollow(int entity)
{
	TE_Start("BeamFollow");
	TE_WriteEncodedEnt("m_iEntIndex", entity);
	TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_STARTVISIBLE|FBEAM_ENDVISIBLE);
	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo);
	TE_WriteNum("m_nStartFrame", 0);
	TE_WriteNum("m_nFrameRate", 1);
	TE_WriteFloat("m_fLife", 1.1);
	TE_WriteFloat("m_fWidth", 3.0);
	TE_WriteFloat("m_fEndWidth", 2.0);
	TE_WriteNum("m_nFadeLength", 2);
	TE_WriteNum("r", laser_color[0]);
	TE_WriteNum("g", laser_color[1]);
	TE_WriteNum("b", laser_color[2]);
	TE_WriteNum("a", laser_color[3]);
}

// Not ideal: can't change color, size changes with distance and is too big
// however, it does ignore the z buffer properly
void SpawnTESprite(float[3] Pos, int Model, float Size)
{
	TE_Start("GlowSprite");
	TE_WriteVector("m_vecOrigin", Pos);
	TE_WriteNum("m_nModelIndex", Model);
	TE_WriteFloat("m_fScale", Size);
	TE_WriteFloat("m_fLife", 5.0);
	TE_WriteNum("m_nBrightness", 30);
}

// filter out team iTeam
void SendTE(int iTeam)
{
	// FIXME do this elsewhere and cache it
	int iTEClients[NEO_MAX_CLIENTS+1], nTEClients;
	for(int j = 1; j <= sizeof(iTEClients); ++j)
	{
		if(!IsValidClient(j) || GetClientTeam(j) != iTeam) // only draw for others
			continue;
		iTEClients[nTEClients++] = j;
	}
	TE_Send(iTEClients, nTEClients);
}


// This doesn't seem to display anything with info_target, only with physics_prop with model :(
// BeamRingPoint works but can't be facing the player (rotated) so not a perfect alternative
// TODO: use env_beam with spawnflag 8 to draw a ring!
void SpawnRing(int client, int StartEntity, int EndEntity)
{
	#if DEBUG
	PrintToServer("Spawning BeamRing TE.");

	float vecStart[3], vecEnd[3], vecAbsStart[3];
	GetEntPropVector(StartEntity, Prop_Send, "m_vecOrigin", vecStart);
	GetEntPropVector(EndEntity, Prop_Send, "m_vecOrigin", vecEnd);
	GetEntPropVector(StartEntity, Prop_Data, "m_vecAbsOrigin", vecAbsStart);
	PrintToServer("SpawnRing: START m_vecOrigin %f %f %f END m_vecOrigin %f %f %f, \
START m_vecAbsOrigin %f %f %f",
	vecStart[0], vecStart[1], vecStart[2],
	vecEnd[0], vecEnd[1], vecEnd[2],
	vecAbsStart[0], vecAbsStart[1], vecAbsStart[2]);
	#endif

	TE_Start("BeamRing");
	TE_WriteEncodedEnt("m_nStartEntity", StartEntity);
	TE_WriteEncodedEnt("m_nEndEntity", EndEntity);
	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo);
	TE_WriteNum("m_nStartFrame", 0);
	TE_WriteNum("m_nFrameRate", 1);
	TE_WriteFloat("m_fLife", 2.0);
	TE_WriteFloat("m_fWidth", 3.0);
	TE_WriteFloat("m_fEndWidth", 3.0);
	TE_WriteFloat("m_fAmplitude", 0.1);
	TE_WriteNum("r", laser_color[0]);
	TE_WriteNum("g", laser_color[1]);
	TE_WriteNum("b", laser_color[2]);
	TE_WriteNum("a", laser_color[3]);
	TE_WriteNum("m_nSpeed", 10);
	TE_WriteNum("m_nFadeLength", 0);
	TE_WriteNum("m_nFlags", FBEAM_STARTENTITY|FBEAM_ENDENTITY);
}


// trace from client, return true on hit
stock bool GetEndPositionFromClient(int client, float[3] vecEnd)
{
	decl Float:start[3], Float:angle[3];
	GetClientEyePosition(client, start);
	GetClientEyeAngles(client, angle);
	TR_TraceRayFilter(start, angle,
	CONTENTS_SOLID|CONTENTS_MOVEABLE|CONTENTS_MONSTER|CONTENTS_DEBRIS|CONTENTS_HITBOX,
	RayType_Infinite, TraceEntityFilterPlayer, client);

	if (TR_DidHit(INVALID_HANDLE))
	{
		TR_GetEndPosition(vecEnd, INVALID_HANDLE);
		return true;
	}
	return false;
}


public bool:TraceEntityFilterPlayer(entity, contentsMask, any:data)
{
	// return entity > MaxClients;
	return entity != data; // only avoid collision with ourself (or data)
}
