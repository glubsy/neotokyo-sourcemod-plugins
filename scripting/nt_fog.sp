#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>
#include  <smlib>
#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif

new const g_iFogColor[] = {25, 25, 25, 220};

// OBJECTIVE: set a thick black fog on the ghost carrier for spooky effect

// TODO: see whether it's possible to set transparency for player models with render effects / transparency
// -> probably can't do
// TODO: cloak investigations: check most suspicious variable properties on game frame while cloaked and see what moves
// -> CMaterialModifyControl (netprop)?

public Plugin:myinfo =
{
	name = "NEOTOKYO thick fog",
	author = "glub",
	description = "Fog that makes it hard to see",
	version = "0.1",
	url = "https://github.com/glubsy"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_flashlight", Command_Flashlight, "DEBUG Toggle flashlight effect.");

	OnConfigsExectured();

	#if DEBUG
	int count = 0;
	int fog = INVALID_ENT_REFERENCE;
	while ((fog = FindEntityByClassname(fog, "env_fog_controller")) != INVALID_ENT_REFERENCE)
	{
		++count;
	}
	if (count)
		PrintToServer("[fog] Number of fog controllers found in this map: %d", count);
	#endif
}

public void OnConfigsExectured()
{
	#if DEBUG
	// ChangeFogParams();
	for (int i = MaxClients; i; --i)
	{
		if (!IsClientInGame(i))
			continue;

		SetTransparency(i);

		if (!IsFakeClient(i))
			ChangeFogForPlayer(i);
	}
	#endif
}

public void OnGhostSpawn(int entref){
	int entity = EntRefToEntIndex(entref);

	if (!IsValidEntity(entity))
		return;
	HookSingleEntityOutput(entity, "OnPlayerPickup", OnPlayerPickup, false);
}

public void OnPlayerPickup(const char[] output, int caller, int activator, float delay){
	ChangeFogForPlayer(caller);
}

public void OnGhostDrop(int client){
	ChangeFogForPlayer(client, true);
}


// Set a thick black for for the ghost carrier
void ChangeFogForPlayer(int client, bool reset=false)
{
	static int enable, color, color2;
	static int skybox_enable, skybox_color, skybox_color2;
	static float start, end, farz;
	static float skybox_start, skybox_end;

	if (reset)
	{
		SetEntProp(client, Prop_Send, "m_fog.enable", enable);
		SetEntProp(client, Prop_Send, "m_fog.colorPrimary", color);
		SetEntProp(client, Prop_Send, "m_fog.colorSecondary", color2);
		SetEntPropFloat(client, Prop_Send, "m_fog.start", start);
		SetEntPropFloat(client, Prop_Send, "m_fog.end", end);
		SetEntPropFloat(client, Prop_Send, "m_fog.farz", farz);

		SetEntProp(client, Prop_Send, "m_skybox3d.fog.enable", skybox_enable);
		SetEntProp(client, Prop_Send, "m_skybox3d.fog.colorPrimary", skybox_color);
		SetEntProp(client, Prop_Send, "m_skybox3d.fog.colorSecondary", skybox_color2);
		SetEntPropFloat(client, Prop_Send, "m_skybox3d.fog.start", skybox_start);
		SetEntPropFloat(client, Prop_Send, "m_skybox3d.fog.end", skybox_end);
		return;
	}

	enable = GetEntProp(client, Prop_Send, "m_fog.enable");
	color = GetEntProp(client, Prop_Send, "m_fog.colorPrimary");
	color2 = GetEntProp(client, Prop_Send, "m_fog.colorSecondary");
	start = GetEntPropFloat(client, Prop_Send, "m_fog.start");
	end = GetEntPropFloat(client, Prop_Send, "m_fog.end");
	farz = GetEntPropFloat(client, Prop_Send, "m_fog.farz");

	skybox_enable = GetEntProp(client, Prop_Send, "m_skybox3d.fog.enable");
	skybox_color = GetEntProp(client, Prop_Send, "m_skybox3d.fog.colorPrimary");
	skybox_color2 = GetEntProp(client, Prop_Send, "m_skybox3d.fog.colorSecondary");
	skybox_start = GetEntPropFloat(client, Prop_Send, "m_skybox3d.fog.start");
	skybox_end = GetEntPropFloat(client, Prop_Send, "m_skybox3d.fog.end");

	#if DEBUG
	PrintToServer("[fog] Default values for fog: m_fog.enable %d, m_fog.colorPrimary %d, m_fog.colorSecondary %d, \
m_fog.start %f, m_fog.end %f, m_fog.farz %f, m_skybox3d.fog.enable %d, m_skybox3d.fog.colorPrimary %d, m_skybox3d.fog.colorSecondary %d, \
m_skybox3d.fog.start %f, m_skybox3d.fog.end %f",
	enable, color, color2, start, end, farz,
	skybox_enable, skybox_color, skybox_color2, skybox_start, skybox_end);
	#endif

	SetEntProp(client, Prop_Data, "m_nNextThinkTick", -1);

	int iColorCombined = (g_iFogColor[3] << 24) | (g_iFogColor[2] << 16) | (g_iFogColor[1] << 8) | g_iFogColor[0];

	// FIXME: this doesn't work in NT... great.
	SetEntProp(client, Prop_Send, "m_fog.enable", 0);
	SetEntProp(client, Prop_Send, "m_fog.colorPrimary", iColorCombined);
	// SetEntProp(client, Prop_Send, "m_fog.colorSecondary", iColorCombined);
	// SetEntProp(client, Prop_Send, "m_fog.colorPrimaryLerpTo", iColorCombined);
	// SetEntProp(client, Prop_Send, "m_fog.colorSecondaryLerpTo", iColorCombined);
	SetEntPropFloat(client, Prop_Send, "m_fog.start", 3.0);
	SetEntPropFloat(client, Prop_Send, "m_fog.end", 100.0);
	SetEntPropFloat(client, Prop_Send, "m_fog.farz", 500.0);
	// SetEntPropFloat(client, Prop_Send, "m_fog.duration", 2000.0);
	// SetEntPropFloat(client, Prop_Send, "m_fog.lerptime", 2000.0);
	// SetEntPropFloat(client, Prop_Send, "m_fog.startLerpTo", 1.0);
	// SetEntPropFloat(client, Prop_Send, "m_fog.endLerpTo", 20.0);

	// this works just fine
	SetEntProp(client, Prop_Send, "m_skybox3d.fog.enable", 1);
	SetEntProp(client, Prop_Send, "m_skybox3d.fog.colorPrimary", iColorCombined);
	SetEntProp(client, Prop_Send, "m_skybox3d.fog.colorSecondary", iColorCombined);
	SetEntPropFloat(client, Prop_Send, "m_skybox3d.fog.start", 10.0);
	SetEntPropFloat(client, Prop_Send, "m_skybox3d.fog.end", 300.0);
}


stock void ChangeGlobalFogParams(int client)
{
	int  dist = 10;
	int  end_dist = 300; // 1024
	int  plane = 4000;
	char color[32] = {"50 50 50"};
	char color2[32] = {"70 10 20"};
	float fogvector[3] = {1.0, 0.0, 0.0};
	int  fog = FindEntityByClassname(-1, "env_fog_controller");
	if(fog != -1)
	{
		DispatchKeyValueFloat(fog, "fogmaxdensity", 0.80);
		DispatchKeyValueVector(fog, "fogdir", fogvector);
		// DispatchKeyValue(fog, "fogblend", "1");
		DispatchKeyValue(fog, "SpawnFlags", "1");
		SetVariantInt(dist);
		AcceptEntityInput(fog, "SetStartDist");
		SetVariantInt(end_dist);
		AcceptEntityInput(fog, "SetEndDist");
		SetVariantInt(plane);
		AcceptEntityInput(fog, "SetFarZ");
		SetVariantString(color);
		AcceptEntityInput(fog, "SetColor");
		SetVariantString(color2);
		AcceptEntityInput(fog, "SetColorSecondary");
		SetVariantString(color);
		AcceptEntityInput(fog, "SetColorLerpTo");
		SetVariantString(color2);
		AcceptEntityInput(fog, "SetColorSecondaryLerpTo");

		AcceptEntityInput(fog, "TurnOff");
		AcceptEntityInput(fog, "TurnOn");
	}
	else
	{
		#if DEBUG
		PrintToServer("[fog] Created env_fog_controller as it didn't exist already.");
		#endif

		fog = CreateEntityByName("env_fog_controller");
		if (fog != -1)
		{
			DispatchKeyValue(fog, "fogenable", "1");
			DispatchKeyValue(fog, "fogblend", "0");
			DispatchKeyValue(fog, "SpawnFlags", "1");
			DispatchKeyValueFloat(fog, "fogmaxdensity", 1.0);
			DispatchKeyValueVector(fog, "fogdir", fogvector);

			SetVariantInt(dist);
			AcceptEntityInput(fog, "SetStartDist");
			SetVariantInt(end_dist);
			AcceptEntityInput(fog, "SetEndDist");
			SetVariantInt(plane);
			AcceptEntityInput(fog, "SetFarZ");
			SetVariantString(color);
			AcceptEntityInput(fog, "SetColor");
			SetVariantString(color2);
			AcceptEntityInput(fog, "SetColorSecondary");
			SetVariantString(color);
			AcceptEntityInput(fog, "SetColorLerpTo");
			SetVariantString(color2);
			AcceptEntityInput(fog, "SetColorSecondaryLerpTo");

			DispatchSpawn(fog);
			ActivateEntity(fog);

			AcceptEntityInput(fog, "TurnOn");
		}
	}

	int sky_camera = FindEntityByClassname(-1, "sky_camera");
	if (sky_camera != -1)
	{
		#if DEBUG
		PrintToServer("[fog] enabled fog in sky_camera");
		#endif
		// DispatchKeyValue(sky_camera, "scale", "1.6");
		DispatchKeyValue(sky_camera, "fogenable", "1");
		// DispatchKeyValue(sky_camera, "fogblend", "1");
		DispatchKeyValue(sky_camera, "fogcolor", "255 0 255");
		DispatchKeyValue(sky_camera, "fogcolor2", "255 0 255");
		DispatchKeyValue(sky_camera, "fogstart", "10");
		DispatchKeyValue(sky_camera, "fogend", "300");
		DispatchKeyValueVector(sky_camera, "fogdir", fogvector);
	}
}



stock void SetTransparency(int client)
{
	// DispatchKeyValue(client, "skin", "1");
	// DispatchKeyValue(client, "body", "1");
	// DispatchKeyValue(client, "SetBodyGroup", "1");

	PrintToServer("BEFORE %N has m_iNMFlash %d", client, GetEntProp(client, Prop_Send, "m_iThermoptic"));
	SetEntProp(client, Prop_Send, "m_iThermoptic", 1);
	// SetEntProp(client, Prop_Send, "m_nRenderFX", 22);
	PrintToServer("AFTER %N has m_iNMFlash %d", client, GetEntProp(client, Prop_Send, "m_iThermoptic"));
	// ToggleFlashlightEffect(client);

	// PrintToServer("%N has Skin %d", client, GetEntProp(client, Prop_Send, "m_nSkin"));

	// doesn't really work, not true transparency
	DispatchKeyValue(client, "rendermode", "0");
	// DispatchKeyValue(client, "renderamt", "90");

	// SetVariantInt(90);
	// AcceptEntityInput(client, "alpha");
}

// Check hsm_visibility Plugin for potential better invisiblity:
//https://github.com/Hatser/Hidden-Mod/blob/f47b8897dc1cc2ec639518a4e08fa0cb00e7f885/csgo/hidden_mod/basic.sp
//https://github.com/Hatser/Hidden-Mod/blob/f47b8897dc1cc2ec639518a4e08fa0cb00e7f885/csgo/hidden_mod/client.sp (SetClientAlpha())
/*stock void renderfx()
{
	if (mode) SetEntProp(client, Prop_Send, "m_nRenderFX", 16, 4)

	PrecacheModel(gszVisibleModel)			// Fuck you non-precached models
	SetEntityModel(client, gszVisibleModel)	// Set new model

	SetEntProp(client, Prop_Send, "m_nSkin", 0, 4)
	SetEntProp(client, Prop_Send, "m_nBody", 1, 4)

	// Get client details for log output
	decl String:szClientName[MAX_NAME_LENGTH]
	decl String:szClientAuth[MAX_NAME_LENGTH]
	GetClientName(client, szClientName, MAX_NAME_LENGTH)
	GetClientAuthString(client, szClientAuth, MAX_NAME_LENGTH)

	LogToGame(
		"\"%s<%i><%s><Hidden>\" Appeared!",
		szClientName,
		GetClientUserId(client),
		szClientAuth
	)

	SetEntPropVector(client, Prop_Send, "m_vecMins", cflHiddenMins)
	SetEntPropVector(client, Prop_Send, "m_vecMaxs", cflHiddenMaxs)
}*/

public Action Command_Flashlight(int client, int args)
{
	ToggleFlashlightEffect(client);
	return Plugin_Handled;
}

// this effect places a dynamic light at the origin (player's feet)
// but also activates the flashlight on the client side!
void ToggleFlashlightEffect(int client)
{
	int m_fEffects = GetEntProp(client , Prop_Data, "m_fEffects");

	if (m_fEffects & (2 << 1))
	{
		m_fEffects &= ~(2 << 1); // 4 EF_DIMLIGHT 2 EF_BRIGHTLIGHT
	}
	else
	{
		m_fEffects |= (2 << 1);
	}
	SetEntProp(client, Prop_Data, "m_fEffects", m_fEffects);

	// ChangeEdictState(client);
}