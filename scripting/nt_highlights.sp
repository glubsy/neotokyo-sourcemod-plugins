#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <nt_menu>
#include <neotokyo>
#define NEO_MAX_CLIENTS 32

#if !defined DEBUG
	#define DEBUG 0
#endif

String:g_sModelName[][] = {
	"materials/sprites/laser.vmt",
	"materials/sprites/halo01.vmt",
	"materials/sprites/laserdot.vmt"
}
int blue_laser_color[3] = {20, 20, 210};
int green_laser_color[3] = {10, 210, 10};
int iBulletTrailAlphaAmount = 180;
float fBulletTrailTTL = 0.3;
int iProjectileTrailAlphaAmount = 180;
float fProjectileTrailTTL = 3.0;
int g_modelLaser, g_modelHalo;

// Handle CVAR_hurt_trails, CVAR_grenade_trails = INVALID_HANDLE;
Handle CVAR_BulletTrailAlpha, CVAR_GrenadeTrailAlpha, CVAR_BulletTrailTTL, CVAR_GrenadeTrailTTL = INVALID_HANDLE;
// int m_hThrower, m_hOwnerEntity; // offsets
int g_iBulletTrailClient[NEO_MAX_CLIENTS+1];
int g_nBulletTrailClients = 0;
int g_iGrenadeTrailClient[NEO_MAX_CLIENTS+1];
int g_nGrenadeTrailClients = 0;
bool g_bClientWantsBulletTrails[NEO_MAX_CLIENTS+1];
bool g_bClientWantsGrenadeTrails[NEO_MAX_CLIENTS+1];
Handle g_RefreshArrayTimer = INVALID_HANDLE;

//cookies
Handle g_hBulletPrefCookie, g_hGrenadePrefCookie = INVALID_HANDLE;

// menus
TopMenuObject g_hTopMainMenu_topmenuobj = INVALID_TOPMENUOBJECT;
TopMenuObject g_tmo_prefs = INVALID_TOPMENUOBJECT;
TopMenu g_hTopMenu; // handle to the nt_menu plugin topmenu
Handle g_hPrefsMenu;

public Plugin:myinfo =
{
	name = "NEOTOKYO highlights",
	author = "glub",
	description = "Highlight bullets and grenades trails for spectators",
	version = "0.1",
	url = "https://github.com/glubsy"
};

// TODO: change thickness of beam depending on damage done

public void OnPluginStart()
{
	// CVAR_hurt_trails = CreateConVar("sm_hurt_trails", "1", "Enable (1) or completely disable (0) drawing beams between a hit player and their attacker.", _, true, 0.0, true, 1.0);
	// CVAR_grenade_trails = CreateConVar("sm_grenade_trails", "1", "Enable (1) or completely disable (0) drawing trails on thrown projectiles.", _, true, 0.0, true, 1.0);

	CVAR_BulletTrailAlpha = CreateConVar("sm_highlights_bullet_alpha", "180.0", "Transparency amount for bullet trails while spectating.", _, true, 30.0, true, 255.0);
	CVAR_GrenadeTrailAlpha = CreateConVar("sm_highlights_grenade_alpha", "180.0", "Transparency amount for grenade trails while spectating.", _, true, 30.0, true, 255.0);
	CVAR_BulletTrailTTL = CreateConVar("sm_highlights_bullet_ttl", "0.1", "Lifespan of grenade trails.", _, true, 0.1, true, 20.0);
	CVAR_GrenadeTrailTTL = CreateConVar("sm_highlights_grenade_ttl", "3.0", "Lifespan of grenade trails.", _, true, 0.1, true, 20.0);
	HookConVarChange(CVAR_BulletTrailAlpha, OnConVarChanged);
	HookConVarChange(CVAR_GrenadeTrailAlpha, OnConVarChanged);
	HookConVarChange(CVAR_BulletTrailTTL, OnConVarChanged);
	HookConVarChange(CVAR_GrenadeTrailTTL, OnConVarChanged);

	RegConsoleCmd("sm_highlights_prefs", ConCommand_MenuPrefs, "Access menu for highlights preferences.");
	RegConsoleCmd("sm_highlights_bullets_prefs", ConCommand_ToggleBulletPrefs, "Toggle seeing highlighted bullet trails as a spectator.");
	RegConsoleCmd("sm_highlights_grenade_prefs", ConCommand_ToggleGrenadePrefs, "Toggle seeing highlighted grenade trails as a spectator.");

	g_hBulletPrefCookie = FindClientCookie("wants-bullet-trails");
	if (g_hBulletPrefCookie == INVALID_HANDLE)
		g_hBulletPrefCookie = RegClientCookie("wants-bullet-trails", "player opted to see highlighted bullet trails as spectator", CookieAccess_Protected);

	g_hGrenadePrefCookie = FindClientCookie("wants-grenade-trails");
	if (g_hGrenadePrefCookie == INVALID_HANDLE)
		g_hGrenadePrefCookie = RegClientCookie("wants-grenade-trails", "player opted to see highlighted grenade trails as spectator", CookieAccess_Protected);

	AutoExecConfig(true, "nt_highlights");

	HookEvent("player_hurt", Event_OnPlayerHurt, EventHookMode_Pre);
	HookEvent("player_death", Event_OnPlayerDeath);
	// HookEvent("game_round_start", Event_OnRoundStart);
	HookEvent("player_spawn", Event_OnPlayerSpawn);

	// HookEvent("player_shoot", Event_OnPlayerShoot); // doesn't work in NT

	// m_hThrower = FindSendPropInfo("CBaseGrenadeProjectile", "m_hThrower");
	// if (m_hThrower <= 0)
	// 	PrintToServer("[nt_highlights] DEBUG offset m_hThrower was -1");
	// m_hOwnerEntity = FindSendPropInfo("CBaseGrenadeProjectile", "m_hOwnerEntity");
	// if (m_hOwnerEntity <= 0)
	// 	ThrowError("[nt_highlights] DEBUG offset m_hOwnerEntity was -1");

	// late loading read cookies
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (!IsValidClient(i) || !IsClientConnected(i) || !IsClientInGame(i))
			continue;

		if (!AreClientCookiesCached(i))
			continue;

		OnClientCookiesCached(i);
	}

	// prebuild menus
	g_hPrefsMenu = BuildSubMenu(0);

	// Is our menu already loaded?
	TopMenu topmenu;
	if (LibraryExists("nt_menu") && ((topmenu = GetNTTopMenu()) != null))
	{
		OnNTMenuReady(topmenu);
	}
	else
	{
		// library missing, we build our own
		g_hTopMenu = CreateTopMenu(TopMenuCategory_Handler);
		BuildTopMenu();
	}

}


public OnNTMenuReady(Handle aTopMenu)
{
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

	// Block us from being called twice
	if (topmenu == g_hTopMenu)
		return;

	// Save the Handle
	g_hTopMenu = topmenu;

	BuildTopMenu();
}

public void OnConfigsExecuted()
{
	#if DEBUG > 1
	for (int client = MaxClients; client > 0; client--)
	{
		if (!IsValidClient(client) || !IsClientConnected(client) || !IsClientInGame(client))
			continue;

		SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
		SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	}
	#endif //DEBUG

	UpdateAffectedClientsArray(-1); // force rebuild
}



void BuildTopMenu()
{
	g_hTopMainMenu_topmenuobj = FindTopMenuCategory(g_hTopMenu, "Various effects"); // get the category provided by nt_menu plugin

	if (g_hTopMainMenu_topmenuobj != INVALID_TOPMENUOBJECT)
	{
		// AddToTopMenu(g_hTopMenu, "nt_menu", TopMenuObject_Item, TopCategory_Handler, g_hTopMainMenu_topmenuobj, "nt_menu", 0);
		g_tmo_prefs = g_hTopMenu.AddItem("sm_highlights_prefs", TopMenuCategory_Handler, g_hTopMainMenu_topmenuobj, "sm_highlights_prefs");
		return;
	}

	// didn't find categories, must be missing nt_menu plugin, so build our own category and attach to it
	g_hTopMainMenu_topmenuobj = g_hTopMenu.AddCategory("Various effects", TopMenuCategory_Handler);

	g_tmo_prefs = AddToTopMenu(g_hTopMenu, "sm_highlights_prefs", TopMenuObject_Item, TopMenuCategory_Handler, g_hTopMainMenu_topmenuobj, "sm_highlights_prefs");
}



public TopMenuCategory_Handler (Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if ((action == TopMenuAction_DisplayOption) || (action == TopMenuAction_DisplayTitle))
	{
		// GetTopMenuObjName(topmenu, object_id, buffer, maxlength);

		if (object_id == INVALID_TOPMENUOBJECT)
			Format(buffer, maxlength, "Neotokyo Menu", param);
		if (object_id == g_tmo_prefs)
			Format(buffer, maxlength, "%s", "Highlights effects", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		if (object_id == g_tmo_prefs)
			DisplayMenu(g_hPrefsMenu, param, 20);
	}
}


public Menu BuildSubMenu(int type)
{
	Menu menu;

	switch (type)
	{
		case 0: // in case we need more later
		{
			menu = new Menu(PropsPrefsMenuHandler, MENU_ACTIONS_ALL);
			menu.SetTitle("Spectator highlights preference:");
			menu.AddItem("a", "Set bullet trails preference");
			menu.AddItem("b", "Set grenade trails preference");
			menu.ExitButton = true;
			menu.ExitBackButton = true;
		}
	}
	return menu;
}

public int PropsPrefsMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			// CloseHandle(menu);
			//delete menu; (should we here?)
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
			}
		}
		// case MenuAction_Display:
		// {
		// 	char title[255];
		// 	Format(title, sizeof(title), "Hurt sfx preferences:", param1);

		// 	Panel panel = view_as<Panel>(param2);
		// 	panel.SetTitle(title);
		// }
		case MenuAction_Select:
		{
			decl String:info[2];
			GetMenuItem(menu, param2, info, sizeof(info));

			switch (info[0])
			{
				case 'a': // bullet trails
				{
					TogglePrefs(param1, 0);
					DisplayMenu(g_hPrefsMenu, param1, 20);
				}
				case 'b': // grenade trails
				{
					TogglePrefs(param1, 1);
					DisplayMenu(g_hPrefsMenu, param1, 20);
				}
				default:
				{
					CloseHandle(g_hTopMenu);
					return 0;
				}
			}
		}

		case MenuAction_DisplayItem:
		{
			char info[2];
			menu.GetItem(param2, info, sizeof(info));

			char display[35];

			if (StrEqual(info, "a")) // toggle item
			{
				Format(display, sizeof(display), "Bullet highlights are: [%s]", (g_bClientWantsBulletTrails[param1] ? "enabled" : "disabled" ));
				return RedrawMenuItem(display);
			}
			if (StrEqual(info, "b")) // toggle item
			{
				Format(display, sizeof(display), "Grenade highlights are: [%s]", (g_bClientWantsGrenadeTrails[param1] ? "enabled" : "disabled" ));
				return RedrawMenuItem(display);
			}
			return 0;
		}
	}
	return 0;
}


public Action ConCommand_ToggleBulletPrefs(int client, int args)
{
	TogglePrefs(client, 0);
}
public Action ConCommand_ToggleGrenadePrefs(int client, int args)
{
	TogglePrefs(client, 1);
}

public Action ConCommand_MenuPrefs(int client, int args)
{
	if (!DisplayTopMenuCategory(g_hTopMenu, FindTopMenuCategory(g_hTopMenu, "Various effects"), client))
		g_hTopMenu.Display(client, TopMenuPosition_Start); // fall back to the top menu
}


void TogglePrefs(int client, int type)
{
	switch(type)
	{
		case 0:
		{
			ToggleCookiePreference(client, type);
			PrintToChat(client, "[nt_highlights] You have %s see spectator bullet traces.", (g_bClientWantsBulletTrails[client] ? "opted to" : "opted not to"));
		}
		case 1:
		{
			ToggleCookiePreference(client, type);
			PrintToChat(client, "[nt_highlights] You have %s see spectator grenade trails.", (g_bClientWantsGrenadeTrails[client] ? "opted to" : "opted not to"));
		}
	}
}


public OnMapStart()
{
	// laser beam
	// g_modelLaser = PrecacheModel("sprites/laser.vmt");
	g_modelLaser = PrecacheModel(g_sModelName[0]);

	// laser halo
	g_modelHalo = PrecacheModel(g_sModelName[1]);
}


public void OnConVarChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (convar == CVAR_BulletTrailAlpha)
	{
		iBulletTrailAlphaAmount = GetConVarInt(convar);
		return;
	}
	if (convar == CVAR_GrenadeTrailAlpha)
	{
		iProjectileTrailAlphaAmount = GetConVarInt(convar);
		return;
	}
	if (convar == CVAR_BulletTrailTTL)
	{
		fBulletTrailTTL = GetConVarFloat(convar);
		return;
	}
	if (convar == CVAR_GrenadeTrailTTL)
	{
		fProjectileTrailTTL = GetConVarFloat(convar);
		return;
	}
}


// not sure when this is called
public OnClientCookiesCached(int client)
{
	ReadCookies(client);
}


public OnClientPostAdminCheck(int client)
{
	if (AreClientCookiesCached(client))
	{
		ReadCookies(client);
	}
}


public Action timer_AdvertiseHelp(Handle timer, int client)
{
	if (!IsValidClient(client) || !IsClientConnected(client))
		return Plugin_Stop;

	PrintToChat(client, "[nt_highlights] You can toggle bullet trails for spectators with !highlights_prefs");
	return Plugin_Stop;
}


public void OnClientDisconnect(int client)
{
	// might not be needed since we check and set on connect
	g_bClientWantsBulletTrails[client] = true;
	g_bClientWantsGrenadeTrails[client] = true;
	CreateTimer(1.0, timer_RefreshAffectedArray, -1, TIMER_FLAG_NO_MAPCHANGE);
}


// returns true only if previous cookies were found
void ReadCookies(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client))
		return;

	char cookie[2];
	GetClientCookie(client, g_hBulletPrefCookie, cookie, sizeof(cookie));

	#if DEBUG
	PrintToServer("[nt_highlights] DEBUG ReadCookies(%N) cookie \"wants-bullet-trails\" is: \"%s\"",
	client, ((cookie[0] != '\0' && StringToInt(cookie)) ? cookie : "null" ));
	#endif

	if (cookie[0] != '\0')
	{
		g_bClientWantsBulletTrails[client] = view_as<bool>(StringToInt(cookie));
	}
	else
	{
		//default to opted-in
		g_bClientWantsBulletTrails[client] = true;
	}
	#if DEBUG
	PrintToServer("[nt_highlights] bullet trail pref for %N is %s", client, (g_bClientWantsBulletTrails[client] ? "true" : "false"));
	#endif

	cookie[0] = '\0';

	GetClientCookie(client, g_hGrenadePrefCookie, cookie, sizeof(cookie));

	#if DEBUG
	PrintToServer("[nt_highlights] DEBUG ReadCookies(%N) cookie \"wants-grenade-trails\" is: \"%s\"",
	client, ((cookie[0] != '\0' && StringToInt(cookie)) ? cookie : "null" ));
	#endif

	if (cookie[0] != '\0')
	{
		g_bClientWantsGrenadeTrails[client] = view_as<bool>(StringToInt(cookie));
	}
	else
	{
		//default to opted-in
		g_bClientWantsGrenadeTrails[client] = true;
	}
	#if DEBUG
	PrintToServer("[nt_highlights] grenade trail pref for %N is %s", client, (g_bClientWantsGrenadeTrails[client] ? "true" : "false"));
	#endif
}


// Toggle bool + cookie
void ToggleCookiePreference(int client, int type)
{
	if (!IsValidClient(client))
		return;

	switch (type)
	{
		case 0: // bullet hits
		{
			#if DEBUG
			PrintToServer("[nt_highlights] DEBUG Pref for %N was %s -> bool toggled.", client, (g_bClientWantsBulletTrails[client] ? "true" : "false"));
			#endif
			g_bClientWantsBulletTrails[client] = !g_bClientWantsBulletTrails[client];
			SetClientCookie(client, g_hBulletPrefCookie, (g_bClientWantsBulletTrails[client] ? "1" : "0"));
			UpdateAffectedClientsArray(-1);

		}
		case 1: // grenade trails
		{
			#if DEBUG
			PrintToServer("[nt_highlights] DEBUG Pref for %N was %s -> bool toggled.", client, (g_bClientWantsGrenadeTrails[client] ? "true" : "false"));
			#endif
			g_bClientWantsGrenadeTrails[client] = !g_bClientWantsGrenadeTrails[client];
			SetClientCookie(client, g_hGrenadePrefCookie, (g_bClientWantsGrenadeTrails[client] ? "1" : "0"));
			UpdateAffectedClientsArray(-1);
		}
	}
}


public void OnClientPutInServer(int client)
{
	#if DEBUG > 1
	SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
	SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	#endif //DEBUG

	// default to opted-in
	g_bClientWantsBulletTrails[client] = true;
	g_bClientWantsGrenadeTrails[client] = true;
	UpdateAffectedClientsArray(client);
	CreateTimer(180.0, timer_AdvertiseHelp, client, TIMER_FLAG_NO_MAPCHANGE);
}


public Action Event_OnPlayerDeath(Event event, const char[] name, bool dontbroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!g_bClientWantsBulletTrails[victim] && !g_bClientWantsGrenadeTrails[victim])
		// no need for update
		return Plugin_Continue;

	// need short delay to read deadflag; also fade to black is blocking view anyway
	if (g_RefreshArrayTimer == INVALID_HANDLE)
		g_RefreshArrayTimer = CreateTimer(5.0, timer_RefreshAffectedArray, victim, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


public Action Event_OnPlayerSpawn(Event event, const char[] name, bool dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsValidClient(client))
		return Plugin_Continue;

	#if DEBUG
	PrintToServer("[nt_highlights] Event_OnPlayerSpawn(%d) (%N)", client, client);
	#endif

	if (GetEntProp(client, Prop_Send, "m_iHealth") <= 1 || GetEntProp(client, Prop_Send, "deadflag"))
	{
		#if DEBUG
		PrintToServer("[nt_highlights] client %N spawned but is actually dead!", client);
		#endif
		return Plugin_Continue;
	}

	// for players spawning after freeze time has already ended
	if (g_RefreshArrayTimer == INVALID_HANDLE)
		g_RefreshArrayTimer = CreateTimer(5.0, timer_RefreshAffectedArray, -1, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


// FIXME: this one might not be needed, we already call from the first player (re)spawning anyway. REMOVE
public Action Event_OnRoundStart(Event event, const char[] name, bool dontbroadcast)
{
	#if DEBUG
	PrintToServer("[nt_highlights] OnRoundStart()")
	#endif

	// 15 seconds should be right when freeze time ends
	g_RefreshArrayTimer = CreateTimer(15.0, timer_RefreshAffectedArray, -1, TIMER_FLAG_NO_MAPCHANGE);
}


public Action timer_RefreshAffectedArray(Handle timer, int client)
{
	#if DEBUG
	PrintToServer("[nt_highlights] Timer is now calling UpdateAffectedClientsArray(%d).", client);
	#endif

	UpdateAffectedClientsArray(client); // should be -1 here, forcing refresh for all arrays

	g_RefreshArrayTimer = INVALID_HANDLE;
	return Plugin_Stop;
}


public void OnEntityCreated(int iEnt, const char[] classname)
{
	if(StrContains(classname, "_projectile", true) != -1)
	{
		//NOTE: we need to delay reading properties values or it will return -1 apparently
		// so perhaps just a timer of 0.1 would do the trick also (untested)
		SDKHook(iEnt, SDKHook_SpawnPost, SpawnPost_Grenade);
	}
}


public void SpawnPost_Grenade(int iEnt)
{
	char sClassname[30];
	GetEntityClassname(iEnt, sClassname, sizeof(sClassname))
	int iOwnerEntity;
	switch (sClassname[0])
	{
		case 'g':
		{
			#if DEBUG
			int iOwner;
			iOwner = GetEntPropEnt(iEnt, Prop_Data, "m_hThrower"); // always -1?
			iOwner = iOwner == -1 ? 0 : IsClientInGame(iOwner) ? iOwner : 0;
			// iOwner = GetEntDataEnt2(iEnt, m_hThrower);
			#endif

			iOwnerEntity = GetEntPropEnt(iEnt, Prop_Data, "m_hOwnerEntity");
			// iOwnerEntity = GetEntDataEnt2(iEnt, m_hOwnerEntity);
			iOwnerEntity = iOwnerEntity == -1 ? 0 : IsClientInGame(iOwnerEntity) ? iOwnerEntity : 0;

			#if DEBUG
			PrintToServer("[nt_highlights] grenade_projectile created, iOwner %d, iOwnerEntity %d", iOwner, iOwnerEntity);
			#endif
		}

		case 's':
		{
			#if DEBUG
			int iOwner;
			iOwner = GetEntPropEnt(iEnt, Prop_Data, "m_hThrower"); // always -1?
			iOwner = iOwner == -1 ? 0 : IsClientInGame(iOwner) ? iOwner : 0;
			// iOwner = GetEntDataEnt2(iEnt, m_hThrower);
			#endif

			iOwnerEntity = GetEntPropEnt(iEnt, Prop_Data, "m_hOwnerEntity");
			// iOwnerEntity = GetEntDataEnt2(iEnt, m_hOwnerEntity);
			iOwnerEntity = iOwnerEntity == -1 ? 0 : IsClientInGame(iOwnerEntity) ? iOwnerEntity : 0;

			#if DEBUG
			PrintToServer("[nt_highlights] smokegrenade_projectile created, iOwner %d, iOwnerEntity %d", iOwner, iOwnerEntity);
			#endif
		}
	}
	if (GetClientTeam(iOwnerEntity) == 3) //NSF
		DrawBeamFromProjectile(iEnt, false);
	else
		DrawBeamFromProjectile(iEnt, true);
}


public Action Event_OnPlayerHurt(Event event, const char[] name, bool dontbroadcast)
{
	// int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	// int health = GetEventInt(event, "health");

	if (/*!IsValidClient(client) ||*/ !IsValidClient(attacker))
		return Plugin_Continue;

	if (GetClientTeam(attacker) == 3)
		DrawBeamFromClient(attacker, false);
	else
		DrawBeamFromClient(attacker, true);

	return Plugin_Continue;
}


void DrawBeamFromProjectile(int entity, bool jinrai=true)
{
	#if DEBUG
	PrintToServer("[nt_highlights] Drawing %s PROJECTILE trail with transparency %d for %d clients.",
	(jinrai ? "JINRAI" : "NSF"), iProjectileTrailAlphaAmount, g_nGrenadeTrailClients);
	for (int i = 0; i < g_nGrenadeTrailClients; i++)
		PrintToServer("[nt_highlights] [%d] %d (%N)",
		i, g_iGrenadeTrailClient[i], ((g_iGrenadeTrailClient[i] == -1) ? 0 : g_iGrenadeTrailClient[i] ));
	#endif

	TE_Start("BeamFollow");
	TE_WriteEncodedEnt("m_iEntIndex", entity);
	// TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);
	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo);
	TE_WriteNum("m_nStartFrame", 0);
	TE_WriteNum("m_nFrameRate", 0);
	TE_WriteFloat("m_fLife", fProjectileTrailTTL);
	TE_WriteFloat("m_fWidth", 2.0);
	TE_WriteFloat("m_fEndWidth", 1.0);
	TE_WriteNum("m_nFadeLength", 1);
	if (jinrai)
	{
		TE_WriteNum("r", green_laser_color[0]);
		TE_WriteNum("g", green_laser_color[1]);
		TE_WriteNum("b", green_laser_color[2]);
	}
	else
	{
		TE_WriteNum("r", blue_laser_color[0]);
		TE_WriteNum("g", blue_laser_color[1]);
		TE_WriteNum("b", blue_laser_color[2]);
	}
	TE_WriteNum("a", iProjectileTrailAlphaAmount);
	TE_Send(g_iGrenadeTrailClient, g_nGrenadeTrailClients);
}


void DrawBeamFromClient(int attacker, bool green_laser=true)
{
	float origin[3], end[3], angle[3];
	GetClientEyePosition(attacker, origin);
	GetClientEyeAngles(attacker, angle);
	GetEndPositionFromClient(attacker, origin, angle, end);

	// GetClientEyePosition(victim, end); // not precise enough for our end point


	#if DEBUG > 1
	PrintToServer("[nt_highlights] Drawing beam from {%f %f %f} to {%f %f %f} laser %d halo %d",
	origin[0], origin[1], origin[2], end[0], end[1], end[2], g_modelLaser, g_modelHalo);
	#endif

	/*TE_SetupBeamPoints(const Float:start[3], const Float:end[3], ModelIndex, HaloIndex, StartFrame, FrameRate, Float:Life,
				Float:Width, Float:EndWidth, FadeLength, Float:Amplitude, const Color[4], Speed)*/
	// TE_SetupBeamPoints(origin, end, g_modelLaser, g_modelHalo, 0, 1, 0.1,
	// 				0.2, 0.2, 2, 0.1, (green_laser ? green_laser_color : blue_laser_color), 1);

	TE_Start("BeamPoints");
	TE_WriteVector("m_vecStartPoint", origin);
	TE_WriteVector("m_vecEndPoint", end);
	//TE_WriteNum("m_nFlags", FBEAM_HALOBEAM|FBEAM_FADEOUT|FBEAM_SHADEOUT|FBEAM_FADEIN|FBEAM_SHADEIN);
	TE_WriteNum("m_nModelIndex", g_modelLaser);
	TE_WriteNum("m_nHaloIndex", g_modelHalo);
	TE_WriteNum("m_nStartFrame", 0);
	TE_WriteNum("m_nFrameRate", 1);
	TE_WriteFloat("m_fLife", fBulletTrailTTL);
	TE_WriteFloat("m_fWidth", 0.2);
	TE_WriteFloat("m_fEndWidth", 0.2);
	TE_WriteFloat("m_fAmplitude", 0.1);
	if (green_laser)
	{
		TE_WriteNum("r", green_laser_color[0]);
		TE_WriteNum("g", green_laser_color[1]);
		TE_WriteNum("b", green_laser_color[2]);
	}
	else
	{
		TE_WriteNum("r", blue_laser_color[0]);
		TE_WriteNum("g", blue_laser_color[1]);
		TE_WriteNum("b", blue_laser_color[2]);
	}
	TE_WriteNum("a", iBulletTrailAlphaAmount);
	TE_WriteNum("m_nSpeed", 1);
	TE_WriteNum("m_nFadeLength", 2);

	TE_Send(g_iBulletTrailClient, g_nBulletTrailClients);
}


// client -1 means rebuild, otherwise add dead players as they arrive
void UpdateAffectedClientsArray(int client)
{
	if (client <= 0) // rebuild entire array!
	{
		g_nBulletTrailClients = 0;
		g_nGrenadeTrailClients = 0;
		for(int j = 1; j <= MaxClients; j++)
		{
			if(!IsValidClient(j) || !IsClientInGame(j) || IsFakeClient(j))
				continue;

			if (!IsPlayerObserving(j) || !(GetEntProp(j, Prop_Send, "m_iHealth") <= 1) || !GetEntProp(j, Prop_Send, "deadflag")) // only draw for specs here
			{
				#if DEBUG
				PrintToServer("[nt_highlights] Skipping %N. deadflag: %d, team: %d, health: %d.",
				j, GetEntProp(j, Prop_Send, "deadflag"), GetClientTeam(j), GetEntProp(j, Prop_Send, "m_iHealth"));
				#endif
				continue;
			}

			if (g_bClientWantsBulletTrails[j])
			{
				#if DEBUG
				PrintToServer("[nt_highlights] can send bullet trail TE to %N.", j);
				#endif
				g_iBulletTrailClient[g_nBulletTrailClients++] = j;
			}

			if (g_bClientWantsGrenadeTrails[j])
			{
				#if DEBUG
				PrintToServer("[nt_highlights] can send grenade trail TE to %N.", j);
				#endif
				g_iGrenadeTrailClient[g_nGrenadeTrailClients++] = j;
			}
		}

		#if DEBUG
		for (int f = 0; f < g_nBulletTrailClients; f++)
			PrintToServer("[nt_highlights] SUMMARY can send BULLET trail TE to: %d (%N)",
			g_iBulletTrailClient[f], (g_iBulletTrailClient[f] > 0 ? g_iBulletTrailClient[f] : 0));
		for (int f = 0; f < g_nGrenadeTrailClients; f++)
			PrintToServer("[nt_highlights] SUMMARY can send GRENADE trail TE to: %d (%N)",
			g_iGrenadeTrailClient[f], (g_iBulletTrailClient[f] > 0 ? g_iBulletTrailClient[f] : 0));
		#endif
	}
	else if (client > 1) // should be called by OnPlayerDeath
	{
		if (!IsClientInGame(client))
			return;

		#if DEBUG
		PrintToServer("[nt_highlights] UpdateAffectedClientsArray(%d) %N asked to be updated and has deadflag bit %s.",
		client, client, (GetEntProp(client, Prop_Send, "deadflag") ? "set" : "not set"));
		#endif
		if(GetClientTeam(client) < 2 || IsPlayerObserving(client) || (GetEntProp(client, Prop_Send, "m_iHealth") <= 1) || GetEntProp(client, Prop_Send, "deadflag")) // only draw for specs here
		{
			if (g_bClientWantsBulletTrails[client])
				g_iBulletTrailClient[g_nBulletTrailClients++] = client;
			if (g_bClientWantsGrenadeTrails[client])
				g_iGrenadeTrailClient[g_nGrenadeTrailClients++] = client;
		}
	}
}


void GetEndPositionFromClient(int client, float[3] start, float[3] angle, float[3] end)
{
	TR_TraceRayFilter(start, angle, (CONTENTS_SOLID|CONTENTS_MOVEABLE|CONTENTS_MONSTER|CONTENTS_DEBRIS|CONTENTS_HITBOX), RayType_Infinite, TraceEntityFilterPlayer, client);
	if (TR_DidHit(INVALID_HANDLE))
	{
		TR_GetEndPosition(end, INVALID_HANDLE);
	}
	// adjusting alignment
	// end[0] += 5.0;
	// end[1] += 5.0;
	// end[2] += 5.0;
}


public bool:TraceEntityFilterPlayer(entity, contentsMask, any:data)
{
	// return entity > MaxClients; // this filters all players
	return entity != data; // only avoid collision with ourself (or whatever data represents)
}



bool IsPlayerObserving(int client)
{
	int mode = GetEntProp(client, Prop_Send, "m_iObserverMode");

	#if DEBUG
	// note movetype is most likely 10 too
	PrintToServer("[nt_highlights] %N %s observing: m_iObserverMode %d", client, (mode ? "is" : "is not"), mode);
	#endif

	if(mode) // 0 means most likely alive
		return true;
	return false;
}


#if DEBUG > 2
// SDKHooks is not reading values at the right offsets and returns garbage values
public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	PrintToServer("[nt_highlights] OnTraceAttack victim %N attacker %N inflictor %d damage %f damagetype %d ammotype %d hitbox %d hitgroup %d",
	victim, attacker, inflictor, damage, damagetype, ammotype, hitbox, hitgroup);
	return Plugin_Continue;
}

// SDKHooks is not reading values at the right offsets and returns garbage values
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	PrintToServer("[nt_highlights] OnTakeDamage victim %N attacker %N inflictor %d damage %f damagetype %d weapon %d damageForce {%f,%f,%f} damagePosition {%f,%f,%f}",
	victim, attacker, inflictor, damage, damagetype, weapon, damageForce[0], damageForce[1], damageForce[2], damagePosition[0], damagePosition[1], damagePosition[2]);
	return Plugin_Continue;
}

// Of course it doesn't work in NT either, never hooked
public void OnFireBulletsPost(int client, int shots, const char[] weaponname)
{
	PrintToServer("[nt_highlights] Bulletpost() client %d shots %d weaponname %s", client, shots, weaponname);
}
#endif //DEBUG
