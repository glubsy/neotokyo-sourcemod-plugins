#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <neotokyo>

#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif

#define EF_BONEMERGE            (1 << 0)
#define EF_NOSHADOW             (1 << 4)
#define EF_BONEMERGE_FASTCULL   (1 << 7)
#define EF_PARENT_ANIMATES      (1 << 9)

int TrackedProjectiles[NEO_MAX_CLIENTS];
int TrackedProjectiles_HEAD;


public Plugin:myinfo =
{
	name = "NEOTOKYO detpacks tweaks",
	author = "glub",
	description = "Detapacks can be destroyed and dropped",
	version = "0.1",
	url = "https://github.com/glubsy"
};

public OnPluginStart()
{
	RegConsoleCmd("sm_dropwpn", Commmand_DropWpn, "drop grenade slot weapon.");
	HookEvent("game_round_start", OnRoundStart);
	HookEvent("player_death", OnPlayerDeath);
}

// TODO: when a detpack is destroyed, remove the remote control (weapon_remotedet) from owner of projectile grenade_detapack
// TEST: parent the grenade_depatack to a physics_prop_override and see if we can move it
// TEST: you could pick up a remote control and activate its corresponding grenade_detapack
// TODO: press USE on a dropped detpack should put it back in inventory
// TODO: make detpacks totally invisible to opponents unless they use vision modes?
// TODO: drop remote on death for others to use, drop detpack if not already used



public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));

	DropGrenadeSlot(victim);
}


public void OnEntityCreated(int entity, const char[] classname)
{

	if(StrEqual(classname, "weapon_remotedet"))
	{
		PrintToServer("[dentities] Found %s %d", classname, entity);
		DataPack dp = CreateDataPack();
		WritePackString(dp, classname);
		WritePackCell(dp, EntIndexToEntRef(entity));
		CreateTimer(0.1, timer_RemoteDet, dp);
	}

	if (StrEqual(classname, "grenade_detapack"))
	{
		PrintToServer("[dentities] Found %s %d", classname, entity);
		AddToTrackedArray(EntIndexToEntRef(entity));
		DataPack dp = CreateDataPack();
		WritePackString(dp, classname);
		WritePackCell(dp, EntIndexToEntRef(entity));
		CreateTimer(0.1, timer_GrenadeDetapack, dp);
	}
}



public Action timer_RemoteDet(Handle timer, DataPack dp)
{
	ResetPack(dp);
	char classname[40];
	ReadPackString(dp, classname, sizeof(classname));
	int entity = EntRefToEntIndex(ReadPackCell(dp));

	if (entity <0)
		return Plugin_Stop;

	int m_bRemoveable = GetEntProp(entity, Prop_Data, "m_bRemoveable");

	int m_nSolidType = GetEntProp(entity, Prop_Data, "m_nSolidType");
	int m_usSolidFlags = GetEntProp(entity, Prop_Send, "m_usSolidFlags", 2);
	int m_nSurroundType = GetEntProp(entity, Prop_Send, "m_nSurroundType");
	int m_CollisionGroup = GetEntProp(entity, Prop_Data, "m_CollisionGroup");
	int movecollide = GetEntProp(entity, Prop_Send, "movecollide");
	int movetype = GetEntProp(entity, Prop_Send, "movetype");
	int m_lifeState = GetEntProp(entity, Prop_Data, "m_lifeState");
	int m_iEFlags = GetEntProp(entity, Prop_Data, "m_iEFlags");
	float m_flGravity = GetEntPropFloat(entity, Prop_Data, "m_flGravity");
	float m_flFriction = GetEntPropFloat(entity, Prop_Data, "m_flFriction");
	float m_flElasticity = GetEntPropFloat(entity, Prop_Data, "m_flElasticity");
	float m_vecMins[3], m_vecMaxs[3];
	GetEntPropVector(entity, Prop_Send, "m_vecMins", m_vecMins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", m_vecMaxs);

	PrintToServer("Remote BEFORE %s %d, m_nSolidType %d, m_CollisionGroup %d, \
m_usSolidFlags %d, m_nSurroundType %d, movecollide %d, m_vecMins %f %f %f, m_vecMaxs %f %f %f flags %d, \
m_lifeState %d, movetype %d, m_iEFlags %d, m_flGravity %f, m_flFriction %f, m_flElasticity %f, m_bRemoveable %d", 
	classname, entity, m_nSolidType, m_CollisionGroup, m_usSolidFlags,
	m_nSurroundType, movecollide, m_vecMins[0], m_vecMins[1], m_vecMins[2], 
	m_vecMaxs[0], m_vecMaxs[1], m_vecMaxs[2], GetEntityFlags(entity), m_lifeState, 
	movetype, m_iEFlags, m_flGravity, m_flFriction, m_flElasticity, m_bRemoveable);

	SetEntProp(entity, Prop_Data, "m_bRemoveable", 1);
	SDKHook(entity, SDKHook_TraceAttack, OnTraceAttack);

	// m_usSolidFlags &= ~4;

	SetEntProp(entity, Prop_Send, "m_usSolidFlags", m_usSolidFlags, 2); //ghost is 136
	SetEntProp(entity, Prop_Data, "m_nSolidType", 2);
	SetEntProp(entity, Prop_Data, "m_CollisionGroup", 11);
	SetEntProp(entity, Prop_Send, "m_CollisionGroup", 11);
	SetEntProp(entity, Prop_Data, "m_bRemoveable", 1);
	SetEntProp(entity, Prop_Send, "m_bSimulatedEveryTick", 1);
	SetEntProp(entity, Prop_Send, "m_bAnimatedEveryTick", 1);

	m_iEFlags = GetEntProp(entity, Prop_Data, "m_iEFlags");
	// m_iEFlags &= ~(1<<1); // EFL_DORMANT
	m_iEFlags |= (1<<14); // EFL_DIRTY_SURR_COLLISION_BOUNDS call after changing collision properties
	SetEntProp(entity, Prop_Data, "m_iEFlags", m_iEFlags);

	m_vecMaxs[0] += 10.0;
	m_vecMaxs[1] += 10.0;
	m_vecMaxs[2] += 10.0;
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", m_vecMaxs);

	PrintToServer("Remote changed: m_usSolidFlags %d, m_nSolidType %d, m_CollisionGroup %d, m_iEFlags %d", 
	GetEntProp(entity, Prop_Send, "m_usSolidFlags", 2),
	GetEntProp(entity, Prop_Data, "m_nSolidType"),
	GetEntProp(entity, Prop_Data, "m_CollisionGroup"),
	GetEntProp(entity, Prop_Data, "m_iEFlags"));

	// if (!AcceptEntityInput(entity, "Wake"))
	// 	PrintToServer("Couldn't call \"Wake\" on %d", entity);
	// if (!AcceptEntityInput(entity, "EnableMotion"))
	// 	PrintToServer("Couldn't call \"EnableMotion\" on %d", entity);
	if (!AcceptEntityInput(entity, "FireUser1"))
		PrintToServer("Couldn't call \"FireUser1\" on %d", entity);
	if (!AcceptEntityInput(entity, "FireUser2"))
		PrintToServer("Couldn't call \"FireUser1\" on %d", entity);
	if (!AcceptEntityInput(entity, "FireUser3"))
		PrintToServer("Couldn't call \"FireUser1\" on %d", entity);
	if (!AcceptEntityInput(entity, "FireUser4"))
		PrintToServer("Couldn't call \"FireUser1\" on %d", entity);

	HookSingleEntityOutput(entity, "OnCacheInteraction", OnRemote1, false);


	DispatchKeyValueFloat(entity, "inertiascale", 0.5);
	DispatchKeyValueFloat(entity, "massscale", 0.5);

	ChangeEdictState(entity);

	char buffer[60];
	Format(buffer, sizeof(buffer), "remotedet%d", EntIndexToEntRef(entity));
	DispatchKeyValue(entity, "target", buffer);

	SDKHook(entity, SDKHook_Touch, OnTouchEntity);

	return Plugin_Handled;

	// notes: solidtype, solidflags probably useless
}

public void OnRemote1(const char[] output, int caller, int activator, float delay)
{
	PrintToServer("OnRemote1()");
}


// Trying to make detpacks collide / take damage from bullets
public Action timer_GrenadeDetapack(Handle timer, DataPack dp)
{
	ResetPack(dp);
	char classname[40];
	ReadPackString(dp, classname, sizeof(classname));
	int entity = EntRefToEntIndex(ReadPackCell(dp));

	if (entity <0)
		return Plugin_Stop;

	int m_nSolidType = GetEntProp(entity, Prop_Data, "m_nSolidType");
	int m_usSolidFlags = GetEntProp(entity, Prop_Send, "m_usSolidFlags", 2);
	int m_nSurroundType = GetEntProp(entity, Prop_Send, "m_nSurroundType");
	int m_CollisionGroup = GetEntProp(entity, Prop_Data, "m_CollisionGroup");
	int movecollide = GetEntProp(entity, Prop_Send, "movecollide");
	int movetype = GetEntProp(entity, Prop_Send, "movetype");
	int m_lifeState = GetEntProp(entity, Prop_Data, "m_lifeState");
	int m_iEFlags = GetEntProp(entity, Prop_Data, "m_iEFlags");
	float m_flGravity = GetEntPropFloat(entity, Prop_Data, "m_flGravity");
	float m_flFriction = GetEntPropFloat(entity, Prop_Data, "m_flFriction");
	float m_flElasticity = GetEntPropFloat(entity, Prop_Data, "m_flElasticity");
	float m_fadeMinDist = GetEntPropFloat(entity, Prop_Data, "m_fadeMinDist");
	float m_fadeMaxDist = GetEntPropFloat(entity, Prop_Data, "m_fadeMaxDist");
	float m_flFadeScale = GetEntPropFloat(entity, Prop_Data, "m_flFadeScale");

	float m_vecMins[3], m_vecMaxs[3];
	GetEntPropVector(entity, Prop_Send, "m_vecMins", m_vecMins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", m_vecMaxs);

	PrintToServer("DETPACK BEFORE %s %d, m_nSolidType %d, m_CollisionGroup %d, \
m_usSolidFlags %d, m_nSurroundType %d, movecollide %d, m_vecMins %f %f %f, m_vecMaxs %f %f %f flags %d, \
m_lifeState %d, movetype %d, m_iEFlags %d, m_flGravity %f, m_flFriction %f m_flElasticity %f, \
m_fadeMinDist %f m_fadeMaxDist %f, m_flFadeScale %f", 
	classname, entity, m_nSolidType, m_CollisionGroup, m_usSolidFlags,
	m_nSurroundType, movecollide, m_vecMins[0], m_vecMins[1], m_vecMins[2], 
	m_vecMaxs[0], m_vecMaxs[1], m_vecMaxs[2], GetEntityFlags(entity), m_lifeState, 
	movetype, m_iEFlags, m_flGravity, m_flFriction, m_flElasticity, m_fadeMinDist, m_fadeMaxDist, m_flFadeScale);

	DispatchKeyValueFloat(entity, "gravity", 0.5);
	DispatchKeyValueFloat(entity, "friction", 0.5);
	SetEntPropFloat(entity, Prop_Data, "m_flElasticity", 5.0);

	SetEntProp(entity, Prop_Data, "m_takedamage", 2);
	SetEntProp(entity, Prop_Data, "m_iMaxHealth", 80);
	SetEntProp(entity, Prop_Data, "m_iHealth", 80);

	SDKHook(entity, SDKHook_TraceAttack, OnTraceAttack);


	// m_usSolidFlags &= ~4;

	SetEntProp(entity, Prop_Send, "m_usSolidFlags", m_usSolidFlags, 2); //ghost is 136
	SetEntProp(entity, Prop_Data, "m_nSolidType", 2);
	SetEntProp(entity, Prop_Data, "m_CollisionGroup", 11);
	SetEntProp(entity, Prop_Send, "m_CollisionGroup", 11);
	// SetEntProp(entity, Prop_Send, "movetype", MOVETYPE_VPHYSICS); // might need this when parenting later?
	// SetEntProp(entity, Prop_Data, "m_bRemoveable", 1);

	m_iEFlags &= ~(1<<1); // EFL_DORMANT
	m_iEFlags |= (1<<14); // EFL_DIRTY_SURR_COLLISION_BOUNDS call after changing collision properties
	SetEntProp(entity, Prop_Data, "m_iEFlags", m_iEFlags);

	// Entity_RemoveSolidFlags(entity, FSOLID_NOT_SOLID); // smlib

	m_vecMaxs[0] += 20.0;
	m_vecMaxs[1] += 20.0;
	m_vecMaxs[2] += 20.0;
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", m_vecMaxs);

	// int g_offsCollisionGroup = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	// SetEntData(entity, g_offsCollisionGroup, 11, 4, true); // same as above anyway

	PrintToServer("DETPACK CHANGED: m_usSolidFlags %d, m_nSolidType %d, m_CollisionGroup %d, m_iEFlags %d", 
	GetEntProp(entity, Prop_Send, "m_usSolidFlags", 2),
	GetEntProp(entity, Prop_Data, "m_nSolidType"),
	GetEntProp(entity, Prop_Data, "m_CollisionGroup"),
	GetEntProp(entity, Prop_Data, "m_iEFlags"));

	// if (!AcceptEntityInput(entity, "Wake"))
	// 	PrintToServer("Couldn't call \"Wake\" on %d", entity);
	// if (!AcceptEntityInput(entity, "EnableMotion"))
	// 	PrintToServer("Couldn't call \"EnableMotion\" on %d", entity);
	if (!AcceptEntityInput(entity, "FireUser1"))
		PrintToServer("Couldn't call \"FireUser1\" on %d", entity);
	if (!AcceptEntityInput(entity, "FireUser2"))
		PrintToServer("Couldn't call \"FireUser1\" on %d", entity);
	if (!AcceptEntityInput(entity, "FireUser3"))
		PrintToServer("Couldn't call \"FireUser1\" on %d", entity);
	if (!AcceptEntityInput(entity, "FireUser4"))
		PrintToServer("Couldn't call \"FireUser1\" on %d", entity);

	HookSingleEntityOutput(entity, "OnCacheInteraction", OnRemote1, false);

	DispatchKeyValueFloat(entity, "fademindist", 0.0);
	DispatchKeyValueFloat(entity, "fademaxdist", 250.0);
	// SetEntityFlags(entity, 0);
	// DispatchKeyValueFloat(entity, "fadescale", 10.0)

	DispatchKeyValueFloat(entity, "inertiascale", 0.5);
	DispatchKeyValueFloat(entity, "massScale", 0.5);

	DispatchKeyValue(entity, "damagetoenablemotion", "0.1");
	DispatchKeyValue(entity, "forcetoenablemotion", "0.1");

	SDKHook(entity, SDKHook_Touch, OnTouchEntity);

	ChangeEdictState(entity);
	// ActivateEntity(entity);

	CreatePhysicsProp(entity);

	return Plugin_Handled;

	// notes: solidtype, solidflags probably useless

}




public Action OnTouchEntity(int entity, int other)
{
	PrintToChatAll("%d touched %d", other, entity);
	// if(0 < other <= MaxClients && entity > 0 && !IsFakeClient(other) && IsValidClient(other) && IsValidEdict(other))
	// {
	// 	PrintToChatAll("%d touched %d", other, entity);
	// }
	return Plugin_Continue;
}


public void AddToTrackedArray(int entref)
{
	TrackedProjectiles[TrackedProjectiles_HEAD++] = entref;
	TrackedProjectiles_HEAD %= sizeof(TrackedProjectiles);
	PrintToServer("Stored %i. HEAD now %d", entref, TrackedProjectiles_HEAD);
}


public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	char classname[20];
	if (!GetEntityClassname(victim, classname, sizeof(classname)))
		return Plugin_Continue;

	PrintToServer("TakeDamage: %s %d, inflictor %d, attacker %d, damage %f, damagetype %d, ammotype %d, hitbox %d, hitgroup %d",
	classname, victim, inflictor, attacker, damage, damagetype, ammotype, hitbox, hitgroup);

	return Plugin_Continue;
}

public Action Commmand_DropWpn(int client, int args)
{
	DropGrenadeSlot(client);
}


// TODO: make sure we can pickup the remote somehow
void DropGrenadeSlot(int client)
{
	int weapon = GetPlayerWeaponSlot(client, SLOT_GRENADE);
	char classname[30];
	GetEntityClassname(weapon, classname, sizeof(classname));
	PrintToServer("Dropping equipped %s", classname);
	SDKHooks_DropWeapon(client, weapon);
}


void CreatePhysicsProp(int child)
{
	int iEnt = CreateEntityByName("prop_physics_override");
	PrintToServer("Created prop_physics_override %d", iEnt);
	DispatchKeyValue(iEnt, "model", "models/weapons/w_detpack.mdl");
	DispatchKeyValueFloat(iEnt, "gravity", 0.5);
	DispatchKeyValueFloat(iEnt, "friction", 0.5);
	DispatchKeyValueFloat(iEnt, "physdamagescale", 10.5);
	SetEntPropFloat(iEnt, Prop_Data, "m_flElasticity", 5.0);

	// BONEMERGE valveBiped.bip01_R_Hand
	// apply velocity on hit?


	// DispatchKeyValue(iEnt,"renderfx","0"); 
	// DispatchKeyValue(iEnt,"damagetoenablemotion","0.1");
	// DispatchKeyValue(iEnt,"forcetoenablemotion","0.1");
	// DispatchKeyValue(iEnt,"Damagetype","0");
	// DispatchKeyValue(iEnt,"disablereceiveshadows","1");
	// DispatchKeyValue(iEnt,"massScale","0");
	// DispatchKeyValue(iEnt,"nodamageforces","0");
	// DispatchKeyValue(iEnt,"shadowcastdist","0");
	// DispatchKeyValue(iEnt,"disableshadows","1");
	// DispatchKeyValue(iEnt,"spawnflags","1670");
	// DispatchKeyValue(iEnt,"PerformanceMode","1");
	// DispatchKeyValue(iEnt,"rendermode","10");
	// DispatchKeyValue(iEnt,"physdamagescale","0");
	// DispatchKeyValue(iEnt,"physicsmode","1");

	SetEntProp(iEnt, Prop_Send, "m_usSolidFlags", 132, 2); //ghost is 136
	SetEntProp(iEnt, Prop_Data, "m_nSolidType", 2);
	SetEntProp(iEnt, Prop_Data, "m_CollisionGroup", 11);
	SetEntProp(iEnt, Prop_Send, "m_CollisionGroup", 11);

	int m_iEFlags = GetEntProp(iEnt, Prop_Data, "m_iEFlags");
	m_iEFlags &= ~(1<<1); // EFL_DORMANT
	m_iEFlags |= (1<<14); // EFL_DIRTY_SURR_COLLISION_BOUNDS call after changing collision properties
	SetEntProp(iEnt, Prop_Data, "m_iEFlags", m_iEFlags);

	// SetEntProp(iEnt, Prop_Data, "m_MoveCollide", 2);
	DispatchSpawn(iEnt);


	float vecPos[3], vecAngle[3];
	GetEntPropVector(child, Prop_Data, "m_vecAbsOrigin", vecPos);
	GetEntPropVector(child, Prop_Data, "m_angAbsRotation", vecAngle);
	TeleportEntity(iEnt, vecPos, NULL_VECTOR, NULL_VECTOR);

	SetVariantString("!activator");
	AcceptEntityInput(child, "SetParent", iEnt, iEnt, 0);

	SetEntProp(child, Prop_Send, "movetype", MOVETYPE_VPHYSICS); // MOVETYPE_FLYGRAVITY MOVETYPE_VPHYSICS

	SetEntProp(child, Prop_Send, "m_fEffects", 
	EF_BONEMERGE|EF_NOSHADOW|EF_PARENT_ANIMATES); // seems to work

	// DispatchKeyValue(entity, "overridescript", "physicsmode,1")

	// SDKHooks_TakeDamage(iEnt, 7, 7, 0.0, DMG_GENERIC, -1, vecAngle, vecAngle);
	// SDKHooks_TakeDamage(child, 7, 7, 0.0, DMG_GENERIC, -1, vecAngle, vecAngle);
	SDKHook(iEnt, SDKHook_Touch, OnTouchEntity);
}


public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	#if DEBUG
	for (int i = 1; i <= MaxClients; ++i){

		if (!IsValidClient(i) || IsFakeClient(i))
			continue;
		SetEntProp(i, Prop_Data, "m_iFrags", 100);
		SetEntProp(i, Prop_Send, "m_iRank", 4);
	}
	#endif
}



public void OnEntityDestroyed(int entindex)
{
	int entityref = EntIndexToEntRef(entindex);
	char classname[60];
	GetEntityClassname(entindex, classname, sizeof(classname));

	if(StrEqual("grenade_detapack", classname))
	{
		PrintToServer("Destroyed %s entref %d, entindex %d", classname, entityref, entindex);
	}

	for (int i = 0; i < sizeof(TrackedProjectiles); ++i)
	{
		if (entityref == TrackedProjectiles[i])
		{
			int owner = GetEntPropEnt(EntRefToEntIndex(entityref), Prop_Data, "m_hThrower");
			PrintToServer("m_hThrower was %N", owner);

			int remote = INVALID_ENT_REFERENCE;
			while ((remote = FindEntityByClassname(remote, "weapon_remotedet")) != INVALID_ENT_REFERENCE)
			{
				char remotename[60], lookup[60];
				Format(lookup, sizeof(lookup), "remotedet%s", entityref);
				GetEntPropString(remote, Prop_Data, "m_target", remotename, sizeof(remotename));
				int remoteowner = GetEntPropEnt(remote, Prop_Data, "m_hOwner");

				if (remoteowner == owner)
				{
					PrintToServer("The owner of remote %d is %N", remote, owner);

					int weapon = GetPlayerWeaponSlot(owner, SLOT_GRENADE);
					SDKHooks_DropWeapon(owner, weapon);

					// RemoveEdict(weapon);
					AcceptEntityInput(weapon, "kill");
				}
				// if (StrEqual(lookup, remotename))
				// 	PrintToServer("FOUND the %s", lookup);
				// else 
				// 	PrintToServer("not found in %s", remotename);
			}
		}
	}
}



public void OnGhostSpawn(int entref)
{
	if (IsValidEntity(EntRefToEntIndex(entref)))
	{
		#if DEBUG
		PrintToServer("[dentities] OnGhostSpawn() valid: %d", EntRefToEntIndex(entref));
		#endif
		// CreateTimer(2.0, timer_HookGhost, entref, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}
	#if DEBUG
	PrintToServer("[dentities] OnGhostSpawn() returned INVALID entity index: %d!",
	EntRefToEntIndex(entref));
	#endif

	// g_bGhostIsCaptured = false;
	// g_bGhostIsHeld = false;
	// g_bEndOfRound = false;
}


// make ghost destructible
public Action timer_HookGhost(Handle timer, int entref)
{
	int ghost = EntRefToEntIndex(entref);
	#if DEBUG
	int m_takedamage = GetEntProp(ghost, Prop_Data, "m_takedamage");
	int m_iMaxHealth = GetEntProp(ghost, Prop_Data, "m_iMaxHealth");
	int m_iHealth = GetEntProp(ghost, Prop_Data, "m_iHealth");
	int m_hDamageFilter = GetEntPropEnt(ghost, Prop_Data, "m_hDamageFilter");
	char m_iszDamageFilterName[100];
	GetEntPropString(ghost, Prop_Data, "m_iszDamageFilterName", m_iszDamageFilterName, sizeof(m_iszDamageFilterName), 0);
	int m_iEFlags = GetEntProp(ghost, Prop_Data, "m_iEFlags"); // ((17 << 0), (24 << 0), (26 << 0)?

	PrintToServer("[dentities] BEFORE Ghost: m_takedamage %d m_iMaxHealth %d, m_iHealth %d \
m_hDamageFilter %d m_iszDamageFilterName %s m_iEFlags %d",
	m_takedamage, m_iMaxHealth, m_iHealth, m_hDamageFilter, m_iszDamageFilterName, 
	m_iEFlags);

	SetEntProp(ghost, Prop_Data, "m_takedamage", 2); // 0 takes no damage, 1 buddha, 2 mortal, 3 ?
	SetEntProp(ghost, Prop_Data, "m_iMaxHealth", 600);
	SetEntProp(ghost, Prop_Data, "m_iHealth", 600);

	ChangeEdictState(ghost);


	m_takedamage = GetEntProp(ghost, Prop_Data, "m_takedamage");
	m_iMaxHealth = GetEntProp(ghost, Prop_Data, "m_iMaxHealth");
	m_iHealth = GetEntProp(ghost, Prop_Data, "m_iHealth");
	m_hDamageFilter = GetEntPropEnt(ghost, Prop_Data, "m_hDamageFilter");
	m_iEFlags = GetEntProp(ghost, Prop_Data, "m_iEFlags");
	PrintToServer("[dentities] AFTER Ghost: m_takedamage %d m_iMaxHealth %d, m_iHealth %d \
m_hDamageFilter %d m_iszDamageFilterName %s m_iEFlags %d",
	m_takedamage, m_iMaxHealth, m_iHealth, m_hDamageFilter, m_iszDamageFilterName, 
	m_iEFlags);
	#endif

	// DispatchKeyValue(ghost, "renderfx", "256"); // EF_ITEM_BLINK
	
}


//(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2]);
public Action OnPlayerRunCmd(int client, int &buttons)
{
	if (client == 0 || IsFakeClient(client))
		return Plugin_Continue;

	if (buttons & IN_RELOAD)
	{
		int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
		char classname[25];
		if (weapon > 0)
			GetEntityClassname(weapon, classname, sizeof(classname));
		PrintToChatAll("Active weapon for %d: %d %s", client, weapon, classname);

		// int weapon = GetPlayerWeaponSlot(client, SLOT_PRIMARY);
		SetWeaponAmmo(client, GetAmmoType(GetActiveWeapon(client)), 90);
	}
	return Plugin_Continue;
}