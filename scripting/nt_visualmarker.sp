#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif

#define USE_TE 1
#define REDCOLOR "240 12 0"
#define YELLOWCOLOR "200 200 20"
#define PINKCOLOR "240 12 210"

enum SpriteType { QMARK = 0, CIRCLE, TARGET, LABEL, MAX };

int laser_color[4] = {210, 210, 0, 128};
int giBeaconSprite[NEO_MAX_CLIENTS+1][MAX];
#if !USE_TE
int giBeaconBeam[NEO_MAX_CLIENTS+1] = {-1, ...};
int giHeadTarget[NEO_MAX_CLIENTS+1] = {-1, ...};
int giTargetStart[NEO_MAX_CLIENTS+1] = {-1, ...};
int giTargetEnd[NEO_MAX_CLIENTS+1] = {-1, ...};
#endif

int g_modelHalo, g_modelLaser, giCircleModel, giQmarkModel;
bool gbIsObserver[NEO_MAX_CLIENTS+1];
bool gbCanUpdatePos[NEO_MAX_CLIENTS+1];
int giRadiusInc[NEO_MAX_CLIENTS+1];
int giHiddenEnts[NEO_MAX_CLIENTS+1][MAX][NEO_MAX_CLIENTS+1]; // assuming opposing team will never have more than 20 players
Handle gCvarTimeToLive, gCvarAllowedClasses, gCvarShowSpectators, gCvarShowOpponents = INVALID_HANDLE;
Handle ghToggleTimer[NEO_MAX_CLIENTS+1] = INVALID_HANDLE;
bool gbKeyHeld[NEO_MAX_CLIENTS+1];
bool gbCanPlace[NEO_MAX_CLIENTS+1], gbLimitToClass;

#define LASERMDL "materials/sprites/redglow1.vmt" // good for animation, but no ignorez and only red
#define BEEPSND "buttons/button15.wav"
// #define LASERMDL "custom/radio.vmt"
// #define LASERMDL "materials/sprites/laser.vmt"
// #define BEEPSND "sound/buttons/button16.wav"
// #define BEEPSND "sound/buttons/button18.wav"

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
- have a "ignore z" laser too (need proper sprite vmt)
- have emitter's name displayed at the ping location (visual clutter?)
- share spotted beacon from ghost carrier when clicking while aiming at a beacon/player
- only show visual pings from people in same squad (only if requested because clutter)
- display a small halo ring upon creation -> could animate surrounding sprite with dynamic scaling? (see Prop_Send properties)
- display beacons as green / blue for spectators (also longer beams?)
- add env_hudhint to advertise the use key
- limit ability to place markers to some classes
*/


public void OnPluginStart()
{
	gCvarTimeToLive = CreateConVar("sm_marker_ttl", "5.0",
	"Time in seconds before marker disappears.", _, true, 1.0, true, 10.0);
	gCvarAllowedClasses = CreateConVar("sm_marker_classes", "7",
	"Classes allowed to place markers, as an octal representation. 1: recons 2: assaults 4: supports. 7 means all, 0 means nobody!",
	_, true, 0.0, true, 7.0);
	gCvarShowSpectators = CreateConVar("sm_marker_spectators", "1",
	"Display visual pings to spectators", _, true, 0.0, true, 1.0);
	gCvarShowOpponents = CreateConVar("sm_marker_opponents", "0",
	"Display visual pings to ennemy team members", _, true, 0.0, true, 1.0);

	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("game_round_end", OnRoundEnd);
	// HookEvent("player_team", OnPlayerTeam);

	#if DEBUG
	HookConVarChange(FindConVar("neo_restart_this"), OnNeoRestartThis);
	#endif

	AutoExecConfig(true, "nt_visualmarker");

	for (int i = 0; i < sizeof(giBeaconSprite); ++i)
	{
		giBeaconSprite[i][TARGET] = -1;
		giBeaconSprite[i][QMARK] = -1;
		giBeaconSprite[i][CIRCLE] = -1;
		// giBeaconSprite[i][LABEL] = -1;
	}
}

#define RECON_ALLOWED (1 << 0)
#define ASSAULT_ALLOWED (2 << 0)
#define SUPPORT_ALLOWED (3 << 0)


public void OnConfigExectured()
{
	int classes = GetConVarInt(gCvarAllowedClasses);
	gbLimitToClass = classes < 7 ? true : false;
}


public void OnClientPutInServer(int client)
{
	if (gbLimitToClass)
		gbCanPlace[client] = false;
	else
		gbCanPlace[client] = true;
}


public void OnMapStart()
{
	// g_modelLaser = PrecacheModel("materials/sprites/laser.vmt");
	g_modelLaser = PrecacheModel(LASERMDL);
	g_modelHalo = PrecacheModel("materials/sprites/halo01.vmt");

	giQmarkModel = PrecacheModel("materials/vgui/hud/cp/cp_none.vmt"); // question mark
	giCircleModel = PrecacheModel("materials/vgui/hud/ctg/g_beacon_circle.vmt"); // circle

	PrecacheSound(BEEPSND);
}

#if DEBUG
public void OnNeoRestartThis(ConVar convar, const char[] oldValue, const char[] newValue)
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (IsValidEntity(giBeaconSprite[i][TARGET])){
			AcceptEntityInput(giBeaconSprite[i][TARGET], "ClearParent");
			AcceptEntityInput(giBeaconSprite[i][TARGET], "kill");
		}
		if (IsValidEntity(giBeaconSprite[i][CIRCLE])){
			AcceptEntityInput(giBeaconSprite[i][CIRCLE], "ClearParent");
			AcceptEntityInput(giBeaconSprite[i][CIRCLE], "kill");
		}
		if (IsValidEntity(giBeaconSprite[i][QMARK])){
			AcceptEntityInput(giBeaconSprite[i][QMARK], "ClearParent");
			AcceptEntityInput(giBeaconSprite[i][QMARK], "kill");
		}
		giBeaconSprite[i][TARGET] = -1;
		giBeaconSprite[i][QMARK] = -1;
		giBeaconSprite[i][CIRCLE] = -1;

		#if !USE_TE
		if (IsValidEntity(giBeaconBeam[i])){
			AcceptEntityInput(giBeaconBeam[i], "ClearParent");
			AcceptEntityInput(giBeaconBeam[i], "kill");
			giBeaconBeam[i] = -1;
		}
		if (IsValidEntity(giTargetEnd[i])){
			AcceptEntityInput(giTargetEnd[i], "ClearParent");
			AcceptEntityInput(giTargetEnd[i], "kill");
			giTargetEnd[i] = -1;
		}
		#endif // !USE_TE
	}
}
#endif // DEBUG

public Action OnPlayerSpawn(Event event, const char[] name, bool dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsValidClient(client))
		return Plugin_Continue;

	if (IsClientObserver(client)){
		gbIsObserver[client] = true;
	}
	else
	{
		gbIsObserver[client] = false;
		if (gbLimitToClass)
		{
			int class = GetEntProp(client, Prop_Send, "m_iClassType");
			if (class == 3)
				++class;

			if (class & GetConVarInt(gCvarAllowedClasses))
			{
				PrintToServer("%N can place", client);
				gbCanPlace[client] = true;
			}
		}
		else
			gbCanPlace[client] = true;
	}

	#if DEBUG
	PrintToServer("[visualmarker] Spawning player %N is %s.", client,
	gbIsObserver[client] ? "observer" : "not observer");
	#endif

	gbCanUpdatePos[client] = true;

	return Plugin_Continue;
}


// public Action OnPlayerTeam(Event event, const char[] name, bool dontbroadcast)
// {
// 	int client = GetClientOfUserId(GetEventInt(event, "userid"));
// 	BuildFilter(client, giBeaconSprite[client][QMARK], QMARK);
// 	BuildFilter(client, giBeaconSprite[client][CIRCLE], CIRCLE);
// }


public void OnClientDisconnect(int client)
{
	// if (ghToggleTimer[client] != INVALID_HANDLE)
	// 	TriggerTimer(ghToggleTimer[client])
	DestroyBeacon(client);
}


public Action OnRoundEnd(Event event, const char[] name, bool dontbroadcast)
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		// if (ghToggleTimer[i] != INVALID_HANDLE)
		// 	TriggerTimer(ghToggleTimer[i])

		SDKUnhook(giBeaconSprite[i][TARGET], SDKHook_SetTransmit, Hook_SetTransmit);
		SDKUnhook(giBeaconSprite[i][QMARK], SDKHook_SetTransmit, Hook_SetTransmit);
		SDKUnhook(giBeaconSprite[i][CIRCLE], SDKHook_SetTransmit, Hook_SetTransmit);

		// Supposedly the entities have been destroyed
		giBeaconSprite[i][TARGET] = -1;
		giBeaconSprite[i][QMARK] = -1;
		giBeaconSprite[i][CIRCLE] = -1;
		// giBeaconSprite[i][LABEL] = -1;
	}
}


int CreateSpriteEnt(SpriteType type)
{
	int iEnt = CreateEntityByName("env_sprite");

	if (!IsValidEntity(iEnt))
		return -1;

	if (type == QMARK)
	{
		DispatchKeyValue(iEnt, "model", "materials/vgui/hud/cp/cp_none.vmt");

		DispatchKeyValue(iEnt, "rendermode", "5"); // 3 glow keeps size, 9 doesn't, 1,5,8 ignore z buffer
		DispatchKeyValueFloat(iEnt, "GlowProxySize", 2.0);
		// DispatchKeyValueFloat(iEnt, "HDRColorScale", 1.0); // needs testing
		DispatchKeyValue(iEnt, "renderamt", "125"); // this doesn't seem to work
		DispatchKeyValue(iEnt, "disablereceiveshadows", "1");
		DispatchKeyValue(iEnt, "renderfx", "9"); // 9 slow strobe
		DispatchKeyValue(iEnt, "rendercolor", YELLOWCOLOR);
		DispatchKeyValue(iEnt, "alpha", "125"); // this doesn't seem to work
		DispatchKeyValue(iEnt, "m_bWorldSpaceScale", "0");

		SetVariantFloat(0.1);
		AcceptEntityInput(iEnt, "SetScale");  // this works!
		// SetEntPropFloat(ent, Prop_Data, "m_flSpriteScale", 0.2); // doesn't seem to work
		// DispatchKeyValueFloat(iEnt, "scale", 1.0); // doesn't seem to work
		// AcceptEntityInput(iEnt, "scale"); // doesn't work
	}
	else if (type == CIRCLE)
	{
		DispatchKeyValue(iEnt, "model", "materials/vgui/hud/ctg/g_beacon_circle.vmt");

		DispatchKeyValue(iEnt, "rendermode", "5"); // 3 glow keeps size, 9 doesn't, 1,5,8 ignore z buffer
		DispatchKeyValueFloat(iEnt, "GlowProxySize", 2.0);
		// DispatchKeyValueFloat(iEnt, "HDRColorScale", 1.0); // needs testing
		DispatchKeyValue(iEnt, "renderamt", "125"); // this doesn't seem to work
		DispatchKeyValue(iEnt, "disablereceiveshadows", "1");
		// DispatchKeyValue(iEnt, "renderfx", "19"); // 19 clamp max size
		DispatchKeyValue(iEnt, "rendercolor", YELLOWCOLOR);
		DispatchKeyValue(iEnt, "alpha", "125"); // this doesn't seem to work

		SetVariantFloat(0.2);
		AcceptEntityInput(iEnt, "SetScale");  // this works!
		// SetEntPropFloat(ent, Prop_Data, "m_flSpriteScale", 0.2); // doesn't seem to work
		// DispatchKeyValueFloat(iEnt, "scale", 1.0); // doesn't seem to work
		// AcceptEntityInput(iEnt, "scale"); // doesn't work
	}
	else
		return -1;

	DispatchSpawn(iEnt);
	return iEnt;
}


stock int CreateBeamEnt(int client)
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
	DispatchKeyValue(iLaserEnt, "rendercolor", "200 25 25 40");
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


int CreateTargetProp(int client, char[] sTag, bool attachtoclient=true)
{
	// int iEnt = CreateEntityByName("info_target");
	int iEnt = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(iEnt, "model", "models/nt/props_debris/can01.mdl");

	// stupid hacks because Source Engine is weird! (info_target is not a networked entity)
	DispatchKeyValue(iEnt,"renderfx","0");
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

	char ent_name[20];
	Format(ent_name, sizeof(ent_name), "%s%d", sTag, client);
	DispatchKeyValue(iEnt, "targetname", ent_name);

	#if DEBUG
	PrintToServer("[visualmarker] Created target on %N (%d) :%s",
	client, iEnt, ent_name);
	#endif

	DispatchSpawn(iEnt);

	if (attachtoclient)
	{
		SetVariantString("!activator"); // useless?
		AcceptEntityInput(iEnt, "SetParent", client, client, 0);

		DataPack dp = CreateDataPack();
		WritePackCell(dp, EntIndexToEntRef(iEnt));
		WritePackString(dp, sTag);

		CreateTimer(0.1, timer_SetAttachment, dp,
		TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
	}
	/* Obsolete
	else
	{
		if (StrContains("targetend", sTag) != -1) // offset the second point for radius
		{
			float origin[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", origin);

			// DEBUG values
			origin[0] = 17.0; // forward axis
			origin[1] = 17.9; // up down axis
			origin[2] = 17.5; // horizontal

			SetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", origin);
		}

		// rewrite same parenting code here (no need for attachment point)
	}
	*/


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
	PrintToServer("[visualmarker] SetParentAttachment to eyes for info_target %d.",
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


public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (client == 0 || !gbCanPlace[client] || IsFakeClient(client))
		return Plugin_Continue;

	if (buttons & (1 << 5)) // IN_USE
	{
		if (!gbCanUpdatePos[client])
			return Plugin_Continue;

		if (!gbKeyHeld[client])
		{
			CreateMarker(client);
		}
		MovePreviewMarker(client);
		gbKeyHeld[client] = true; // we spam this :/
	}
	else
	{
		if (gbKeyHeld[client])
		{
			if (gbCanUpdatePos[client])
			{
				gbCanUpdatePos[client] = false;
				PlaceFinalMarker(client);
			}
		}
		gbKeyHeld[client] = false;
	}
	return Plugin_Continue;
}


public Action timer_ClearBlockingFlag(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	gbCanUpdatePos[client] = true;
	return Plugin_Handled;
}


void MovePreviewMarker(int client)
{
	float vecEnd[3], vecStart[3], vecAngle[3];
	GetClientEyePosition(client, vecStart);
	GetClientEyeAngles(client, vecAngle);
	GetEndPosition(client, vecEnd, vecStart, vecAngle);

	TeleportEntity(giBeaconSprite[client][TARGET], vecEnd, NULL_VECTOR, NULL_VECTOR);
	// TeleportEntity(giBeaconSprite[client][QMARK], vecEnd, NULL_VECTOR, NULL_VECTOR);
	// TeleportEntity(giBeaconSprite[client][CIRCLE], vecEnd, NULL_VECTOR, NULL_VECTOR);
}


void MakeParent(int child, int parent)
{
	SetVariantString("!activator"); // useless?
	AcceptEntityInput(child, "SetParent", parent, parent, 0);
}


bool CreateMarker(int client)
{
	if (giBeaconSprite[client][TARGET] > 0){ // FIXME more tests?
		#if DEBUG
		PrintToServer("[visualmarker] BeaconSprite TARGET already existed for %N. Reusing",
		client);
		#endif

		BuildFilter(client, giBeaconSprite[client][TARGET], TARGET, true);
		BuildFilter(client, giBeaconSprite[client][QMARK], QMARK, true);
		BuildFilter(client, giBeaconSprite[client][CIRCLE], CIRCLE, true);

		SDKHook(giBeaconSprite[client][TARGET], SDKHook_SetTransmit, Hook_SetTransmit);
		SDKHook(giBeaconSprite[client][QMARK], SDKHook_SetTransmit, Hook_SetTransmit);
		SDKHook(giBeaconSprite[client][CIRCLE], SDKHook_SetTransmit, Hook_SetTransmit);

		// revert back to etheral state
		DispatchKeyValue(giBeaconSprite[client][QMARK], "rendercolor", YELLOWCOLOR);
		DispatchKeyValue(giBeaconSprite[client][QMARK], "alpha", "15");
		DispatchKeyValue(giBeaconSprite[client][QMARK], "renderamt", "15");
		DispatchKeyValue(giBeaconSprite[client][CIRCLE], "rendercolor", YELLOWCOLOR);
		DispatchKeyValue(giBeaconSprite[client][CIRCLE], "alpha", "15");
		DispatchKeyValue(giBeaconSprite[client][CIRCLE], "renderamt", "15");

		AcceptEntityInput(giBeaconSprite[client][QMARK], "ShowSprite");
		AcceptEntityInput(giBeaconSprite[client][CIRCLE], "ShowSprite");
		// AcceptEntityInput(giBeaconSprite[client][LABEL], "Enable");
		return false;
	}

	giBeaconSprite[client][TARGET] = CreateTargetProp(client, "pmarker", false);
	giBeaconSprite[client][QMARK] = CreateSpriteEnt(QMARK);
	giBeaconSprite[client][CIRCLE] = CreateSpriteEnt(CIRCLE);
	// giBeaconSprite[client][LABEL] = CreateLabelProp(client, "TEST_LABEL");
	// TeleportEntity(giBeaconSprite[client][LABEL], vecEnd, NULL_VECTOR, NULL_VECTOR);

	MakeParent(giBeaconSprite[client][QMARK], giBeaconSprite[client][TARGET]);
	MakeParent(giBeaconSprite[client][CIRCLE], giBeaconSprite[client][TARGET]);
	// MakeParent(giBeaconSprite[client][LABEL], giBeaconSprite[client][TARGET]);

	BuildFilter(client, giBeaconSprite[client][TARGET], TARGET, true);
	BuildFilter(client, giBeaconSprite[client][QMARK], QMARK, true);
	BuildFilter(client, giBeaconSprite[client][CIRCLE], CIRCLE, true);

	// giHeadTarget[client] = CreateTargetProp(client, "headtarget");

	/* OBSOLETE used for SpawnRing()
	// NOTE parenting an info_target to the sprite works
	giTargetStart[client] = CreateTargetProp(client, "targetstart", giBeaconSprite[client][QMARK]);

	// OBSOLETE used for SpawnRing()
	// giTargetEnd[client] = CreateTargetProp(client, "targetend", giBeaconSprite[client]);
	*/

	#if !USE_TE
	giBeaconBeam[client] = CreateBeamEnt(client);
	#endif

	// As usual, we have all the downsides with none of the advantages. Hook'em all!
	SDKHook(giBeaconSprite[client][TARGET], SDKHook_SetTransmit, Hook_SetTransmit);
	SDKHook(giBeaconSprite[client][QMARK], SDKHook_SetTransmit, Hook_SetTransmit);
	SDKHook(giBeaconSprite[client][CIRCLE], SDKHook_SetTransmit, Hook_SetTransmit);

	AcceptEntityInput(giBeaconSprite[client][QMARK], "ShowSprite");
	AcceptEntityInput(giBeaconSprite[client][CIRCLE], "ShowSprite");
	// AcceptEntityInput(giBeaconSprite[client][LABEL], "Enable");

	return true;
}


void PlaceFinalMarker(int client)
{
	float vecEnd[3], vecStart[3], vecAngle[3];
	GetClientEyePosition(client, vecStart);
	GetClientEyeAngles(client, vecAngle);
	GetEndPosition(client, vecEnd, vecStart, vecAngle);

	// filter out team if not same team
	int iTEClients[NEO_MAX_CLIENTS+1];
	int numTEClients = BuildFilterForTE(GetClientTeam(client), iTEClients);

	#if DEBUG
	PrintToServer("[visualmarker] Emitting sound + beam to %d clients", numTEClients);
	#endif

	vecStart[2] += 20.0;
	EmitSound(iTEClients, numTEClients, BEEPSND, SOUND_FROM_WORLD, SNDCHAN_AUTO,
		55, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, vecStart, vecAngle);

	#if !USE_TE
	AcceptEntityInput(giBeaconBeam[client], "TurnOn");
	#else
	TELaserBeam(client, giBeaconSprite[client][TARGET]);
	TE_Send(iTEClients, numTEClients);
	#endif

	#if DEBUG > 1
	PrintToServer("[visualmarker] TurnOn sprites & TurnOn BEAM");
	#endif

	BuildFilter(client, giBeaconSprite[client][TARGET], TARGET, false);
	BuildFilter(client, giBeaconSprite[client][QMARK], QMARK, false);
	BuildFilter(client, giBeaconSprite[client][CIRCLE], CIRCLE, false);

	DispatchKeyValue(giBeaconSprite[client][QMARK], "rendercolor", REDCOLOR);
	DispatchKeyValue(giBeaconSprite[client][QMARK], "alpha", "255");
	DispatchKeyValue(giBeaconSprite[client][QMARK], "renderamt", "255");

	DispatchKeyValue(giBeaconSprite[client][CIRCLE], "rendercolor", REDCOLOR);
	DispatchKeyValue(giBeaconSprite[client][CIRCLE], "alpha", "255");
	DispatchKeyValue(giBeaconSprite[client][CIRCLE], "renderamt", "255");

	TeleportEntity(giBeaconSprite[client][TARGET], vecEnd, NULL_VECTOR, NULL_VECTOR);
	// TeleportEntity(giBeaconSprite[client][QMARK], vecEnd, NULL_VECTOR, NULL_VECTOR);
	// TeleportEntity(giBeaconSprite[client][CIRCLE], vecEnd, NULL_VECTOR, NULL_VECTOR);

	// OBSOLETE
	// TeleportEntity(giTargetStart[client], vecEnd, NULL_VECTOR, NULL_VECTOR);
	// TeleportEntity(giTargetEnd[client], vecEnd, NULL_VECTOR, NULL_VECTOR);

	// attempt to draw a circle in increasing radius around target: FAIL
	// SpawnRing(client, giBeaconSprite[client][QMARK], giTargetEnd[client]);
	// giRadiusInc[client] = 0;
	// CreateTimer(0.1, timer_IncreaseEndRadius, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	if (ghToggleTimer[client] == INVALID_HANDLE)
		ghToggleTimer[client] = CreateTimer(GetConVarFloat(gCvarTimeToLive), timer_ToggleBeaconOff, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

stock Action timer_IncreaseEndRadius(Handle timer, int client)
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
	PrintToServer("[visualmarker] END vecOrigin after %.2f %.2f %.2f", vecPos[0], vecPos[1], vecPos[2]);
	#endif
	giRadiusInc[client]++;
	return Plugin_Continue;
}


public Action timer_ToggleBeaconOff(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	ToggleBeacon(client);
	gbCanUpdatePos[client] = true;

	SDKUnhook(giBeaconSprite[client][TARGET], SDKHook_SetTransmit, Hook_SetTransmit);
	SDKUnhook(giBeaconSprite[client][QMARK], SDKHook_SetTransmit, Hook_SetTransmit);
	SDKUnhook(giBeaconSprite[client][CIRCLE], SDKHook_SetTransmit, Hook_SetTransmit);

	ghToggleTimer[client] = INVALID_HANDLE;
	return Plugin_Stop;
}


void ToggleBeacon(int client)
{
	#if DEBUG
	PrintToServer("[visualmarker] TurnOff SPRITEs");
	#endif
	AcceptEntityInput(giBeaconSprite[client][QMARK], "HideSprite");
	AcceptEntityInput(giBeaconSprite[client][CIRCLE], "HideSprite");
	// AcceptEntityInput(giBeaconSprite[client][LABEL], "Disable");

	#if !USE_TE
	#if DEBUG
	PrintToServer("[visualmarker] TurnOff BEAM");
	#endif
	AcceptEntityInput(giBeaconBeam[client], "TurnOff");
	#endif
}



void DestroyBeacon(int client)
{
	if (IsValidEntity(giBeaconSprite[client][QMARK]) && giBeaconSprite[client][QMARK] > MaxClients)
	{
		AcceptEntityInput(giBeaconSprite[client][QMARK], "ClearParent");
		AcceptEntityInput(giBeaconSprite[client][QMARK], "kill");
		giBeaconSprite[client][QMARK] = -1;
	}
	if (IsValidEntity(giBeaconSprite[client][CIRCLE]) && giBeaconSprite[client][CIRCLE] > MaxClients){
		AcceptEntityInput(giBeaconSprite[client][CIRCLE], "ClearParent");
		AcceptEntityInput(giBeaconSprite[client][CIRCLE], "kill");
		giBeaconSprite[client][CIRCLE] = -1;
	}
	if (IsValidEntity(giBeaconSprite[client][TARGET]) && giBeaconSprite[client][TARGET] > MaxClients)
	{
		AcceptEntityInput(giBeaconSprite[client][TARGET], "kill");
		giBeaconSprite[client][TARGET] = -1;
	}

	#if !USE_TE
	if (giBeaconBeam[client] > MaxClients);
		AcceptEntityInput(giBeaconBeam[client], "kill");
	#endif
}


#if !DEBUG
void TELaserBeam(int iStartEnt=0, int iEndEnt=0)
#else
void TELaserBeam(int iStartEnt=0, int iEndEnt=0, float[3] vecStart=NULL_VECTOR, float[3] vecEnd=NULL_VECTOR)
#endif
{
	#if DEBUG
	PrintToServer("[visualmarker] TELaserBeam(%d, %d, {%.2f %.2f %.2f}, {%.2f %.2f %.2f})",
	iStartEnt, iEndEnt, vecStart[0], vecStart[1], vecStart[2], vecEnd[0], vecEnd[1], vecEnd[2]);
	#endif
	// TE_Start("BeamPoints");
	// TE_Start("BeamEntPoint");
	TE_Start("BeamEnts");
	// TE_WriteVector("m_vecStartPoint", vecStart);
	// TE_WriteVector("m_vecEndPoint", vecEnd);
	TE_WriteNum("m_nFlags", FBEAM_NOTILE|FBEAM_FOREVER|FBEAM_ISACTIVE|FBEAM_SINENOISE|
	FBEAM_STARTENTITY|FBEAM_ENDENTITY|FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT); // no idea

	// specific to BeamEntPoint TE
	TE_WriteEncodedEnt("m_nStartEntity", iEndEnt); // inverted to allow animation in the proper direction
	TE_WriteEncodedEnt("m_nEndEntity", iStartEnt);

	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo); 	// NOTE: Halo can be set to "0"!
	TE_WriteNum("m_nStartFrame", 1);
	TE_WriteNum("m_nFrameRate", 2);
	TE_WriteFloat("m_fLife", 1.0);
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

// Emulate a fast laser trail instead of single constant beam
// Doesn't seem to work with info_target. Shame. Only work on networked entity with model?
// TODO: try with prop_dynamic and velocity!
// TODO: try with info_target but with flag to transmit in PVS!
// TODO: try env_tracer too, or env_spritetrail
stock void TELaserBeamFollow(int entity)
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
stock void SpawnTESprite(float[3] Pos, int Model, float Size)
{
	TE_Start("GlowSprite");
	TE_WriteVector("m_vecOrigin", Pos);
	TE_WriteNum("m_nModelIndex", Model);
	TE_WriteFloat("m_fScale", Size);
	TE_WriteFloat("m_fLife", 5.0);
	TE_WriteNum("m_nBrightness", 30);
}


void BuildFilter(int client, int entity, SpriteType type, bool hidden=false)
{
	#if DEBUG
	PrintToServer("[visualmarker] Calling BuildFilter(%d, %d) %s",
	client, entity, hidden ? "HIDDEN" : "not hidden");
	#endif

	if (entity <= 0) // perhaps we better not do this check
		return;

	if (hidden) // only show for us
	{
		for (int i = MaxClients; i; --i)
		{
			if (!IsValidClient(i))
				continue;
			if (i == client)
			{
				giHiddenEnts[i][type][client] = -1;
				continue;
			}

			giHiddenEnts[i][type][client] = entity;
		}
		return;
	}

	int team = GetClientTeam(client);
	for (int i = MaxClients; i; --i)
	{
		if (!IsValidClient(i) || GetClientTeam(i) == team)
		{
			giHiddenEnts[i][type][client] = -1;
			continue;
		}
		giHiddenEnts[i][type][client] = entity;

		#if DEBUG
		PrintToServer("[visualmarker] giHiddenEnts[%d][%s][%d]=%d", i,
		type ? "CIRCLE" : "QMARK", client, entity);
		#endif
	}
}

public Action Hook_SetTransmit(int entity, int client)
{
	for (int i = sizeof(giHiddenEnts) -1; i; --i)
	{
		if ( giHiddenEnts[client][TARGET][i] == entity
			|| giHiddenEnts[client][QMARK][i] == entity
			|| giHiddenEnts[client][CIRCLE][i] == entity )
			return Plugin_Handled;
	}
	return Plugin_Continue;
}


// filter out team iTeam
int BuildFilterForTE(int iTeam, int iTEClients[NEO_MAX_CLIENTS+1])
{
	// FIXME do this elsewhere and cache it
	int numTEClients = 0;
	for(int j = NEO_MAX_CLIENTS; j; --j)
	{
		if(!IsValidClient(j) || GetClientTeam(j) != iTeam) // only draw for others
			continue;
		iTEClients[numTEClients++] = j;
		#if DEBUG > 1
		PrintToServer("[visualmarker] Affected client: %N", j);
		#endif
	}
	#if DEBUG > 1
	PrintToServer("[visualmarker] Total affected clients: %d", numTEClients);
	#endif
	return numTEClients;
}


// This doesn't seem to display anything with info_target, only with networked ents with model :(
// BeamRingPoint works but can't be facing the player (rotated) so not a perfect alternative
// TODO: try using env_beam with spawnflag 8 (Ring) to draw a ring instead!
stock void SpawnRing(int client, int StartEntity, int EndEntity)
{
	#if DEBUG > 1
	PrintToServer("Spawning BeamRing TE.");

	float vecStart[3], vecEnd[3], vecAbsStart[3];
	GetEntPropVector(StartEntity, Prop_Send, "m_vecOrigin", vecStart);
	GetEntPropVector(EndEntity, Prop_Send, "m_vecOrigin", vecEnd);
	GetEntPropVector(StartEntity, Prop_Data, "m_vecAbsOrigin", vecAbsStart);
	PrintToServer("SpawnRing: \
START m_vecOrigin %.2f %.2f %.2f \
END m_vecOrigin %.2f %.2f %.2f, \
START m_vecAbsOrigin %.2f %.2f %.2f",
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
stock bool GetEndPosition(int client, float[3] vecEnd, float[3] vecPos, float[3] vecAngle)
{
	TR_TraceRayFilter(vecPos, vecAngle,
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


// doesn't seem to work in NT?
stock int CreateLabelProp(int client, char[] message)
{
	int iEnt = CreateEntityByName("point_message");

	#if DEBUG
	PrintToServer("[visualmarker] created point_message %d", iEnt);
	#endif

	DispatchKeyValue(iEnt, "message", message);
	DispatchKeyValue(iEnt, "radius", "1000");
	DispatchKeyValue(iEnt, "developeronly", "0");
	SetEntProp(iEnt, Prop_Data, "m_drawText", 1);
	SetEntProp(iEnt, Prop_Data, "m_bEnabled", 1);
	AcceptEntityInput(iEnt, "Enable");

	DispatchSpawn(iEnt);
	// ActivateEntity(iEnt);
	TeleportEntity(iEnt, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR);
	return iEnt;

}