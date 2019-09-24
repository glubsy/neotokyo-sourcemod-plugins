#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <nt_entitytools>

#pragma semicolon 1
#define PLUGIN_VERSION "20190924"

Handle g_cvar_adminonly, g_cvar_enabled = INVALID_HANDLE;

public Plugin:myinfo =
{
	name = "NEOTOKYO entity tools",
	author = "glub",
	description = "Various prop manipulation tools.",
	version = PLUGIN_VERSION,
	url = "https://github.com/glubsy"
};

public OnPluginStart()
{
	CreateConVar("sm_nt_entitytools", PLUGIN_VERSION, "NEOTOKYO entitytools version", FCVAR_HIDDEN);

	g_cvar_adminonly = CreateConVar( "entitycreate_adminonly", "0",
									"0: every client can build, 1: only admin can build",
									FCVAR_NONE, true, 0.0, true, 1.0 ); // not used
	g_cvar_enabled = CreateConVar( "entitycreate_enabled", "1",
									"0: disable custom props spawning, 1: enable custom props spawning",
									FCVAR_NONE, true, 0.0, true, 1.0 ); //from LeftFortDead plugin, not used

	RegAdminCmd("create_physics_multiplayer", Command_Create_Prop_Physics_Multiplayer, ADMFLAG_SLAY, "create_physics_multiplayer()");
	RegAdminCmd("create_physics_override", CommandPropCreatePhysicsOverride, ADMFLAG_SLAY, "creates physics prop with specified model");
	//RegAdminCmd("create_physics_override_vector", CommandPropCreatePhysicsOverrideVector, ADMFLAG_SLAY, "test");
	RegAdminCmd("create_dynamic_override", CommandCreatePropDynamicOverride, ADMFLAG_SLAY, "creates dynamic prop with specified model");
	RegAdminCmd("getinfo", GetPropInfo, ADMFLAG_SLAY);
	RegAdminCmd("dontcollide", CommandPropNoCollide, ADMFLAG_SLAY, "test");
	RegAdminCmd("collide", CommandPropCollide, ADMFLAG_SLAY);
	RegAdminCmd("makeladder", CommandMakeLadder, ADMFLAG_SLAY);
	RegAdminCmd("spawnghostcapzone", CommandSpawnGhostCapZone, ADMFLAG_SLAY);
	RegAdminCmd("spawnvipentity", CommandSpawnVIPEntity, ADMFLAG_SLAY);

	RegAdminCmd("movetype", ChangeEntityMoveType, ADMFLAG_SLAY);

	RegAdminCmd("entity_remove", RemoveTargetEntity, ADMFLAG_SLAY, "DEBUG: to remove edict (fixme)");
	RegAdminCmd("setpropinfo", SetPropInfo, ADMFLAG_SLAY, "sets prop property");
	RegAdminCmd("TestSpawnFlags", TestSpawnFlags, ADMFLAG_SLAY, "sets prop property to all by name");
	RegAdminCmd("entity_rotate", Rotate_Entity, ADMFLAG_SLAY, "rotates an entity");
	RegAdminCmd("entity_rotateroll", Rotate_EntityRoll, ADMFLAG_SLAY, "rotates an entity (roll)");
	RegAdminCmd("entity_rotatepitch", Rotate_EntityPitch, ADMFLAG_SLAY, "rotates an entity (pitch)");

	RegAdminCmd("sm_strapon_target", Command_Strapon_Target, ADMFLAG_SLAY,  "DEBUG: Strap target to yourself (dangerous)");
	//RegAdminCmd("sm_unstrapon_target", Command_UnStrapon_Target, ADMFLAG_SLAY,  "unstrap self/all/target");
}

//==================================
//			Spawning UTILS
//==================================


public Action CommandPropCreatePhysicsOverride(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	if(args >= 3)
	{
		ReplyToCommand(client, "too many arguments");
		return Plugin_Handled;
	}

	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	if(args == 2)
	{
		new String:arg2[10];
		GetCmdArg(2, arg2, sizeof(arg2));

		CreatePropPhysicsOverride(client, arg1, StringToInt(arg2));
		return Plugin_Handled;
	}
	if(args == 1)
	{
		CreatePropPhysicsOverride(client, arg1, 100); // we default to 100 health points if none is entered
		return Plugin_Handled;
	}
	return Plugin_Handled;
}




public Action CommandPropCreatePhysicsOverrideVector(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_physics_override");

	if(!IsModelPrecached(arg1))
	{
		PrecacheModel(arg1);			// might have to restrict list of models to avoid crash (menu?)
	}
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{

//		SetEntityModel(EntIndex, arg1);   <-- this doesn't work, it spawns at 0 0 0 no matter what!
		//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);   // 4 should be OK, but it's set to 0 instead? <-- 1073741824 now don't collide with players but ignore collisions altogether
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);   //2, changed to 11 so that they collide bewteen each other!!
		SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);   // Do I need to change this to 9218?????  <- doesn't work, we need to try with prop_multiplayer
		SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);  //16 is suggested, ghost is 136!??     <- doesn't work, we need to try with prop_multiplayer

		int health=150;
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!


		SetEntPropFloat(EntIndex, Prop_Data, "m_flGravity", 0.2);  // doesn't seem to do anything?

//		DispatchKeyValue(EntIndex, "health", "100");    //not working
//		DispatchKeyValue(EntIndex, "rendercolor", "20,50,80,255");  //not working
//		SetEntityRenderColor(EntIndex, 255, 10, 255, 255); //not working

/*		new g_offsCollisionGroup;
		g_offsCollisionGroup = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");
		SetEntData(EntIndex, g_offsCollisionGroup, 2, 4, true);  //new!
*/
//		AcceptEntityInput(EntIndex, "DisableCollision", 0, 0);  // causes absolutely no collision at all?
//		AcceptEntityInput(EntIndex, "kill", 0, 0);

		DispatchKeyValue(EntIndex, "targetname", "test");
		DispatchKeyValue(EntIndex, "model", arg1);     //does the same as SetEntityModel but works better! can teleport!?
		DispatchKeyValue(EntIndex, "CCollisionProperty", "2");
//		DispatchKeyValueFloat(EntIndex, "solid", 2.0);  //remettre 2.0 !
		DispatchKeyValue(EntIndex, "Solid", "6");    // might need to disable this one (unnecessary?)



/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(EntIndex);
		PrintToConsole(client, "Entity: %d, solid: %d", EntIndex, solidtype);
		Entity_SetSolidType(EntIndex, 2);
*/
//		ChangeEdictState(EntIndex, 0);

		new Float:ClientOrigin[3];
		new Float:clientabsangle[3];
		new Float:propangles[3] = {0.0, 0.0, 0.0};
		new Float:ClientEyeAngles[3];
		new Float:clienteyeposition[3];
		new Float:PropStartOrigin[3];
		//new Float:eyes[3];


		GetClientAbsOrigin(client, ClientOrigin);
		GetClientAbsAngles(client, clientabsangle);
		GetClientEyePosition(client, clienteyeposition);
		GetClientEyeAngles(client, ClientEyeAngles);


		propangles[1] = clientabsangle[1];
		//ClientOrigin[2] += 20.0;
		//clienteyeposition[1] += 20.0;
		//ClientEyeAngles[1] += 20.0;

		GetAngleVectors(ClientEyeAngles, propangles, NULL_VECTOR, NULL_VECTOR);
		PropStartOrigin[0] = (ClientOrigin[0] + (100 * Cosine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[1] = (ClientOrigin[1] + (100 * Sine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[2] = (ClientOrigin[2] + 50);

//		GetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", PropStartOrigin);
		SetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", ClientEyeAngles);


		SetEntityMoveType(EntIndex, MOVETYPE_VPHYSICS);   //MOVETYPE_VPHYSICS seems oK, doesn't seem to change anything

/*		PrintToServer("PropStartOrigin: %f %f %f", PropStartOrigin[0], PropStartOrigin[1], PropStartOrigin[2]);
		PrintToServer("client origin: %f %f %f", ClientOrigin[0], ClientOrigin[1], ClientOrigin[2]);
		PrintToServer("GetAngleVectors: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("clientabsangle: %f %f %f", clientabsangle[0], clientabsangle[1], clientabsangle[2]);
		PrintToServer("ClientEyeAngles: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("propangles: %f %f %f", propangles[0], propangles[1], propangles[2]);
*/

		new Float:vAngles[3], Float:vOrigin[3], Float:pos[3];

		GetClientEyePosition(client,vOrigin);
		GetClientEyeAngles(client, vAngles);

		new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

		if(TR_DidHit(trace)){
			TR_GetEndPosition(pos, trace);

			//pos[2] += 10.0; // make sure he does not get stuck to the floor, increse Z pos
			DispatchKeyValueVector(EntIndex, "Origin", pos);  //spawn at end of raytrace first


		}
		CloseHandle(trace);


		//DispatchKeyValueVector(EntIndex, "Origin", PropStartOrigin); // works!
		DispatchKeyValueVector(EntIndex, "Angles", ClientEyeAngles); // works!
		//DispatchKeyValueVector(EntIndex, "basevelocity", clienteyeposition);
		DispatchKeyValue(EntIndex, "physdamagescale", "0.5");   // works! positive value = breaks when falling
		DispatchKeyValue(EntIndex, "friction", "1.5");
		DispatchKeyValue(EntIndex, "gravity", "0.1");
		TeleportEntity(EntIndex, ClientOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(EntIndex);

		GetPropInfo(client, EntIndex);

	}
	return Plugin_Handled;
}



public Action CommandCreatePropDynamicOverride(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	if(args >= 3)
	{
		ReplyToCommand(client, "too many arguments");
		return Plugin_Handled;
	}

	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	if(args == 2)
	{
		new String:arg2[10];
		GetCmdArg(2, arg2, sizeof(arg2));

		CreatePropDynamicOverride(client, arg1, StringToInt(arg2));
		return Plugin_Handled;
	}
	if(args == 1)
	{
		CreatePropDynamicOverride(client, arg1, 100); // we default to 100 health points if none is entered
		return Plugin_Handled;
	}
	return Plugin_Handled;
}





public Action CommandSpawnGhostCapZone(int client, int args)
{
	new aimed  = GetClientAimTarget(client, false);
	if(aimed != -1)
	{
		new String:arg1[5];
		//GetCmdArg(1, arg1, sizeof(arg1));
		GetCmdArgString(arg1,sizeof(arg1));

		new EntIndex = CreateEntityByName("neo_ghost_retrieval_point");
		if(EntIndex != -1)
		{
			PrintToChatAll("Aimed at: %i, Created: %i", aimed, EntIndex);
			new Float:VecOrigin[3];
			GetClientEyePosition(aimed, VecOrigin);
			DispatchKeyValueVector(EntIndex, "Origin", VecOrigin); // works!
			DispatchKeyValue(EntIndex, "team", "2");
			SetEntProp(EntIndex, Prop_Data, "m_iTeamNum", 1);



			DispatchKeyValue(EntIndex, "Radius", "128");


			//DispatchKeyValue(EntIndex, "model", "models/nt/a_lil_tiger.mdl");
			//SetEntityMoveType(EntIndex, MOVETYPE_NOCLIP);

			SetVariantString("!activator");
			AcceptEntityInput(EntIndex, "SetParent", aimed);

			//SetEntPropEnt(EntIndex, Prop_Data, "m_iParent", aimed);


			PrintToChatAll("dispatching %i", EntIndex);
			AcceptEntityInput(EntIndex, "start");

			//if(GetEdictFlags(EntIndex) & FL_EDICT_ALWAYS)
			SetEdictFlags(EntIndex, GetEdictFlags(EntIndex) ^ FL_EDICT_ALWAYS);


			SetEntPropEnt(EntIndex, Prop_Data, "m_hEffectEntity", aimed);
			CreateTimer(1.0, TimerSetParent, EntIndex, TIMER_REPEAT);
		}
	}
	return Plugin_Handled;
}


public Action CommandSpawnVIPEntity(int client, int args)
{
	char arg1[30];
	//GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArgString(arg1,sizeof(arg1));

	int newentity = CreateEntityByName(arg1); //use "neo_escape_point" or "neo_vip_entity"

	if(newentity != -1)
	{
		char classname[20];
		GetEdictClassname(newentity, classname, sizeof(classname));
		PrintToChatAll("[ENTITY] create %s, %i", classname, newentity);
		float VecOrigin[3], VecAngles[3], normal[3];

		GetClientEyePosition(client, VecOrigin);
		GetClientEyeAngles(client, VecAngles);

		TR_TraceRayFilter(VecOrigin, VecAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer, client);
		TR_GetEndPosition(VecOrigin);
		TR_GetPlaneNormal(INVALID_HANDLE, normal);
		GetVectorAngles(normal, normal);
		normal[0] += 90.0;

		//DispatchKeyValueVector(EntIndex, "Origin", VecOrigin);
		//DispatchKeyValueVector(EntIndex, "Angles", normal);

		DispatchKeyValue(newentity, "Radius", "140");
		//DispatchKeyValue(newentity, "Model", "models/player/vip.mdl");
		DispatchKeyValue(newentity, "modelindex", "353");

		float position[3];
		GetEntPropVector(newentity, Prop_Send, "m_Position", position);

		int radius;
		GetEntProp(newentity, Prop_Send, "m_Radius", radius);

		PrintToChatAll("Position of %s: %f %f %f", classname, VecOrigin[0], VecOrigin[1], VecOrigin[2]);
		PrintToChatAll("Position getentprop of %s: %f %f %f radius %i", classname, position[0], position[1], position[2], radius);

		TeleportEntity(newentity, VecOrigin, normal, NULL_VECTOR);
		DispatchSpawn(newentity);
	}
	return Plugin_Handled;
}


public Action:TimerSetParent(Handle:timer, entity)
{
	//SetVariantString("grenade2");
	//AcceptEntityInput(entity, "SetParentAttachment");
	//SetVariantString("grenade2");
	//AcceptEntityInput(entity, "SetParentAttachmentMaintainOffset");
	DispatchSpawn(entity);
}


//==================================
//			Make Ladder tests
//==================================

public Action:CommandMakeLadder(int client, int args)
{
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_dynamic");

	if(!IsModelPrecached(arg1))
	{
		PrecacheModel(arg1);
	}

	new String:name[130];
	new Float:VecOrigin[3];
	new Float:VecAngles[3];
	new Float:normal[3];

	DispatchKeyValue(EntIndex, "model", "models/nt/props_construction/ladder2.mdl");
	DispatchKeyValue(EntIndex, "Solid", "7");
	//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);
	//SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 5);
	//SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);
	//SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);


	GetClientEyePosition(client, VecOrigin);
	GetClientEyeAngles(client, VecAngles);
	TR_TraceRayFilter(VecOrigin, VecAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer, client);
	TR_GetEndPosition(VecOrigin);
	TR_GetPlaneNormal(INVALID_HANDLE, normal);
	GetVectorAngles(normal, normal);
	normal[0] += 90.0;
	DispatchKeyValueVector(EntIndex, "Origin", VecOrigin); // works!
	DispatchKeyValueVector(EntIndex, "Angles", normal); // works!

	SetEntityMoveType(EntIndex, MOVETYPE_LADDER);
	TeleportEntity(EntIndex, VecOrigin, normal, NULL_VECTOR);
	DispatchSpawn(EntIndex);

	new Float:degree = 180.0;  //rotating properly -glub
	decl Float:angles[3];
	GetEntPropVector(EntIndex, Prop_Data, "m_angRotation", angles);
	RotateYaw(angles, degree);

	DispatchKeyValueVector(EntIndex, "Angles", angles );
	GetClientName(client, name, sizeof(name));
	PrintToChatAll("%s spawned something", name);
	return Plugin_Handled;
}



public Action:ChangeEntityMoveType(int client, int args)   // doesn't seem to do anything
{
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = GetClientAimTarget(client, false);
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{
		new String:classname[32];
		GetEdictClassname(EntIndex, classname, 32);

		SetEntityMoveType(EntIndex, MOVETYPE_LADDER);
		//DispatchSpawn(EntIndex);  // <- do not use again! it works now.

		ChangeEdictState(EntIndex, 0);
		PrintToChatAll("movetype changed?, %d", GetEntityMoveType(EntIndex));

	}
	return Plugin_Handled;
}



////////////////////////////////////////////////////////////////////////////////
//
// interior functions
//
////////////////////////////////////////////////////////////////////////////////

//---------------------------------------------------------
// spawn a given entity type and assign it a model
//---------------------------------------------------------
/*
CreateEntity( client, const String:entity_name[], const String:item_name[], const String:model[] = "" )
{
    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot spawn entity over rcon/server console" );
        return -1;
    }

    new index = CreateEntityByName( entity_name );
    if ( index == -1 )
    {
        ReplyToCommand( player, "Failed to create %s !", item_name );
        return -1;
    }

    if ( strlen( model ) != 0 )
    {
        if ( !IsModelPrecached( model ) )
        {
            PrecacheModel( model );
        }
        SetEntityModel( index, model );
    }

    ReplyToCommand( player, "Successfully create %s (index %i)", item_name, index );

    return index;
}
*/




/****************
 *Math (Vectors)*
*****************/

public Float:CreateVectorFromPoints(const Float:vec1[3], const Float:vec2[3], Float:output[3])
{
  output[0]=vec2[0]-vec1[0];
  output[1]=vec2[1]-vec1[1];
  output[2]=vec2[2]-vec1[2];
}

public AddInFrontOf(Float:orig[3], Float:angle[3], Float:distance, Float:output[3])
{
  new Float:viewvector[3];
  ViewVector(angle,viewvector);
  output[0]=viewvector[0]*distance+orig[0];
  output[1]=viewvector[1]*distance+orig[1];
  output[2]=viewvector[2]*distance+orig[2];
}

public ViewVector(Float:angle[3], Float:output[3])
{
  output[0]=Cosine(angle[1]/(180/FLOAT_PI));
  output[1]=Sine(angle[1]/(180/FLOAT_PI));
  output[2]=-Sine(angle[0]/(180/FLOAT_PI));
}

public Float:GetDistanceBetween(Float:startvec[3], Float:endvec[3])
{
  return SquareRoot((startvec[0]-endvec[0])*(startvec[0]-endvec[0])+(startvec[1]-endvec[1])*(startvec[1]-endvec[1])+(startvec[2]-endvec[2])*(startvec[2]-endvec[2]));
}

/*********
 *Helpers*
**********/
new OriginOffset;
new Handle:hEyeAngles;
new Handle:hEyePosition;
new GetVelocityOffset_0;
new GetVelocityOffset_1;
new GetVelocityOffset_2;

public GetEntityOrigin(entity, Float:output[3])
{
  GetEntDataVector(entity,OriginOffset,output);
}

public GetAngles(client, Float:output[3])
{
  SDKCall(hEyeAngles,client,output);
}

public GetEyePosition(client, Float:output[3])
{
  SDKCall(hEyePosition,client,output);
}

public GetVelocity(int client, Float:output[3])
{
  output[0]=GetEntDataFloat(client,GetVelocityOffset_0);
  output[1]=GetEntDataFloat(client,GetVelocityOffset_1);
  output[2]=GetEntDataFloat(client,GetVelocityOffset_2);
}


public Action:CommandPropCreateDynamicOverride(int client, int args)  // not used right now
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_dynamic_override");

	if(!IsModelPrecached(arg1))
	{
		PrecacheModel(arg1);			// might have to restrict list of models to avoid crash (menu?)
	}
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{

//		SetEntityModel(EntIndex, arg1);   <-- this doesn't work, it spawns at 0 0 0 no matter what!
		//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);   // 4 should be OK, but it's set to 0 instead? <-- 1073741824 now don't collide with players but ignore collisions altogether
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);   //2, changed to 11 so that they collide bewteen each other!!
		SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);   // Do I need to change this to 9218?????  <- doesn't work, we need to try with prop_multiplayer
		SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);  //16 is suggested, ghost is 136!??     <- doesn't work, we need to try with prop_multiplayer

		int health=150;
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!


		SetEntPropFloat(EntIndex, Prop_Data, "m_flGravity", 0.5);  // doesn't seem to do anything?

//		DispatchKeyValue(EntIndex, "health", "100");    //not working
//		DispatchKeyValue(EntIndex, "rendercolor", "20,50,80,255");  //not working
//		SetEntityRenderColor(EntIndex, 255, 10, 255, 255); //not working

/*		new g_offsCollisionGroup;
		g_offsCollisionGroup = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");
		SetEntData(EntIndex, g_offsCollisionGroup, 2, 4, true);  //new!
*/
//		AcceptEntityInput(EntIndex, "DisableCollision", 0, 0)  // causes absolutely no collision at all?
//		AcceptEntityInput(EntIndex, "kill", 0, 0)

		DispatchKeyValue(EntIndex, "targetname", "test");
		DispatchKeyValue(EntIndex, "model", arg1);     //does the same as SetEntityModel but works better! can teleport!?
		DispatchKeyValue(EntIndex, "CCollisionProperty", "2");
//		DispatchKeyValueFloat(EntIndex, "solid", 2.0);  //remettre 2.0 !
		DispatchKeyValue(EntIndex, "Solid", "6");    // might need to disable this one (unnecessary?)

/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(EntIndex);
		PrintToConsole(client, "Entity: %d, solid: %d", EntIndex, solidtype);
		Entity_SetSolidType(EntIndex, 2);
*/
//		ChangeEdictState(EntIndex, 0);

		new Float:ClientOrigin[3];
		new Float:clientabsangle[3];
		new Float:propangles[3] = {0.0, 0.0, 0.0};
		new Float:ClientEyeAngles[3];
		new Float:clienteyeposition[3];
		new Float:PropStartOrigin[3];
		//new Float:eyes[3];


		GetClientAbsOrigin(client, ClientOrigin);
		GetClientAbsAngles(client, clientabsangle);
		GetClientEyePosition(client, clienteyeposition);
		GetClientEyeAngles(client, ClientEyeAngles);


		propangles[1] = clientabsangle[1];
		//ClientOrigin[2] += 20.0;
		//clienteyeposition[1] += 20.0;
		//ClientEyeAngles[1] += 20.0;

		GetAngleVectors(ClientEyeAngles, propangles, NULL_VECTOR, NULL_VECTOR);
		PropStartOrigin[0] = (ClientOrigin[0] + (100 * Cosine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[1] = (ClientOrigin[1] + (100 * Sine(DegToRad(ClientEyeAngles[1]))));
		PropStartOrigin[2] = (ClientOrigin[2] + 50);
//		GetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", PropStartOrigin);
		SetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", ClientEyeAngles);


//		SetEntityMoveType(EntIndex, MOVETYPE_NOCLIP);   //MOVETYPE_VPHYSICS seems oK, doesn't seem to change anything

/*		PrintToServer("PropStartOrigin: %f %f %f", PropStartOrigin[0], PropStartOrigin[1], PropStartOrigin[2]);
		PrintToServer("client origin: %f %f %f", ClientOrigin[0], ClientOrigin[1], ClientOrigin[2]);
		PrintToServer("GetAngleVectors: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("clientabsangle: %f %f %f", clientabsangle[0], clientabsangle[1], clientabsangle[2]);
		PrintToServer("ClientEyeAngles: %f %f %f", ClientEyeAngles[0], ClientEyeAngles[1], ClientEyeAngles[2]);
		PrintToServer("propangles: %f %f %f", propangles[0], propangles[1], propangles[2]);
*/



//RAYTRACING
		new Float:vAngles[3], Float:vOrigin[3], Float:pos[3];

		GetClientEyePosition(client,vOrigin);
		GetClientEyeAngles(client, vAngles);

		new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

		if(TR_DidHit(trace)){

			//TR_GetEndPosition(end, INVALID_HANDLE);    //Get position player looking at
			//TR_GetPlaneNormal(INVALID_HANDLE, normal);    //???
			//GetVectorAngles(normal, normal);    //Get angles of vector, which is returned by GetPlaneNormal
			//normal[0] += 90.0;    //Add some angle to existing angles

			TR_GetEndPosition(pos, trace);

			pos[2] += 10.0; // make sure he does not get stuck to the floor, increse Z pos

			DispatchKeyValueVector(EntIndex, "Origin", pos);

		}
		CloseHandle(trace);


		//DispatchKeyValueVector(EntIndex, "Origin", PropStartOrigin); // works!
		DispatchKeyValueVector(EntIndex, "Angles", ClientEyeAngles); // works!
		//DispatchKeyValueVector(EntIndex, "basevelocity", clienteyeposition);
		DispatchKeyValue(EntIndex, "physdamagescale", "0.5");   // works! positive value = breaks when falling
		DispatchKeyValue(EntIndex, "friction", "1.5");
		DispatchKeyValue(EntIndex, "gravity", "0.1");
		TeleportEntity(EntIndex, ClientOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(EntIndex);

		GetPropInfo(client, EntIndex);


	}
	return Plugin_Handled;
}



public Action:GetPropInfo(client, args)
{
	new aimed = GetClientAimTarget(client, false);
	if (aimed != 1 && !IsValidEntity(aimed))
	{
		PrintToConsole(client, "not a valid entity you're aiming at");
	}
	if (aimed != -1 && IsValidEntity(aimed))
	{
		new String:classname[32];
		new String:m_ModelName[130];
		new String:m_nSolidType[130];
//		new String:movetype[130];
		int m_CollisionGroup, m_spawnflags, m_iMaxHealth, m_usSolidFlags;
		new Float:m_flGravity;
//		new Float:m_massScale;

		GetEdictClassname(aimed, classname, 32);
		GetEntPropString(aimed, Prop_Data, "m_ModelName", m_ModelName, 130);   //OK
		GetEntPropString(aimed, Prop_Data, "m_nSolidType", m_nSolidType, 130);  //OK
		m_CollisionGroup = GetEntProp(aimed, Prop_Data, "m_CollisionGroup", m_CollisionGroup);
		m_spawnflags = GetEntProp(aimed, Prop_Data, "m_spawnflags");
		m_iMaxHealth = GetEntProp(aimed, Prop_Data, "m_iMaxHealth", m_iMaxHealth);
		m_flGravity = GetEntPropFloat(aimed, Prop_Data, "m_flGravity");
//		m_massScale = GetEntPropFloat(aimed, Prop_Data, "m_massScale");
		m_usSolidFlags = GetEntProp(aimed, Prop_Data, "m_usSolidFlags");

		PrintToConsole(client, "Entity: %d, classname: %s, m_ModelName: %s, m_usSolidFlags: %d, movetype: %d", aimed, classname, m_ModelName, m_usSolidFlags, GetEntityMoveType(aimed));
		PrintToConsole(client, "m_CollisionGroup: %d, m_spawnflags: %d, m_nSolidType: %d, m_iMaxHealth: %d, m_flGravity: %f", m_CollisionGroup, m_spawnflags, m_nSolidType, m_iMaxHealth, m_flGravity);

/*
		m_iszBasePropData
		m_iInteractions
		m_bIsWalkableSetByPropData
		m_flGroundSpeed
		m_flLastEventCheck
		m_nHitboxSet
		m_flModelWidthScale
		m_iClassname
		m_iGlobalname
		m_iParent
		m_nRenderFX  renderfx
		m_nRenderMode   rendermode
		m_fEffects   effects
		m_clrRender   rendercolor
		m_nModelIndex   modelindex
		touchStamp
		m_aThinkFunctions
		m_ResponseContexts
		m_iszResponseContext  ResponseContext
		m_iEFlags
		m_iName
		Sub-Class Table (1 Deep): m_Collision - CCollisionProperty
		- m_vecMins
		- m_vecMaxs
		- m_nSolidType solid
		- m_usSolidFlags
		- m_nSurroundType
		- m_triggerBloat
		m_MoveType
		m_MoveCollide <-
		m_pPhysicsObject
		m_hGroundEntity
		m_ModelName  model
		m_vecBaseVelocity  basevelocity
		m_vecAbsVelocity
		m_vecAngVelocity   avelocity
		m_pBlocker
		m_flLocalTime
		m_vecAbsOrigin
		m_vecVelocity  - velocity
		m_spawnflags    spawnflags
		m_angAbsRotation (Save)(12 Bytes)
		m_vecOrigin (Save)(12 Bytes)
		m_angRotation
		m_vecViewOffset - view_ofs
		m_fFlags
		InputUse
		CBaseEntitySUB_Remove
		CBaseEntitySUB_Remove (FunctionTable)
		CBaseEntitySUB_DoNothing (FunctionTable)
		CBaseEntitySUB_StartFadeOut (FunctionTable)
		CBaseEntitySUB_StartFadeOutInstant (FunctionTable)
		CBaseEntitySUB_FadeOut (FunctionTable)
		CBaseEntitySUB_Vanish (FunctionTable)
		CBaseEntitySUB_CallUseToggle (FunctionTable)
		CBaseEntityShadowCastDistThink (FunctionTable)
		m_hEffectEntity <-

		MOVETYPE_LADDER (x) that's for player when on a ladder
		!HasSpawnFlags(SF_TRIG_PUSH_AFFECT_PLAYER_ON_LADDER)

		netprops:
		CBaseEntity
		movetype (offset 222) (type integer)
		movecollide (offset 223) (type integer) (bits 3) (Unsigned)

		CFuncLadder
		m_bFakeLadder


		MIGHT BE THIS?!
		SetEntityMoveType(Entindex,MOVETYPE_LADDER);
*/
		new Float:coords[3];
		GetEntPropVector(aimed, Prop_Send, "m_vecOrigin", coords);
		new Float:angles[3];
		GetEntPropVector(aimed, Prop_Data, "m_angRotation", angles);

		PrintToConsole(client, "m_CollisionGroup: %d, m_spawnflags: %d, m_nSolidType: %d, m_iMaxHealth: %d, m_flGravity: %f", m_CollisionGroup, m_spawnflags, m_nSolidType, m_iMaxHealth, m_flGravity);
		PrintToConsole(client, "m_CollisionGroup: %d, m_spawnflags: %d, m_nSolidType: %d, m_iMaxHealth: %d, m_flGravity: %f", m_CollisionGroup, m_spawnflags, m_nSolidType, m_iMaxHealth, m_flGravity);
		PrintToConsole(client, "m_CollisionGroup: %d, m_spawnflags: %d, m_nSolidType: %d, m_iMaxHealth: %d, m_flGravity: %f", m_CollisionGroup, m_spawnflags, m_nSolidType, m_iMaxHealth, m_flGravity);
		PrintToConsole(client, "index %d, coord[0]: %f, coord[1]: %f, coord[2]: %f, angle[0]: %f, angle[1]: %f,angle[2]: %f", aimed, coords[0], coords[1], coords[2], angles[0], angles[1], angles[2]);
	}
	return Plugin_Handled;
}



public Action:TestSpawnFlags(client, args)
{
	new aimed = CreateEntityByName("weapon_mx");
	new Float:vpos[3];
	GetClientEyePosition(client,vpos);
	vpos[0] += 50.0;

	if (IsValidEntity(aimed))
	{
		DispatchKeyValue(aimed, "spawnflags", "1073741824"); //1073741824
		SetEntProp(aimed, Prop_Data, "m_spawnflags", 1073741824);
		DispatchKeyValueVector(aimed, "Origin", vpos);
		DispatchSpawn(aimed);
		PrintToConsole(client, "Spawned  mx: spawnflags: %d", GetEntProp(aimed, Prop_Data, "m_spawnflags"));
	}
	return Plugin_Handled;
}


public Action:SetPropInfo(client, args)
{
	new aimed = GetClientAimTarget(client, false);
	if (aimed != 1 && !IsValidEntity(aimed))
	{
		PrintToConsole(client, "not a valid entity you're aiming at");
	}
	if (aimed != -1 && IsValidEntity(aimed))
	{
		//new String:m_ModelName[130];
		//new Float:m_flGravity;
		new Float:vec[3] = {100.0, 100.0, 100.0};
		DispatchKeyValueVector(aimed, "basevelocity", vec);
		//SetEntityModel(aimed, "models/nt/a_lil_tiger.mdl"); // GONNA CRASH!
		//DispatchSpawn(aimed);
		PrintToConsole(client, "dispatched %d", vec);


		decl String:Buffer[64];
		Format(Buffer, sizeof(Buffer), "Client%d", client);
		DispatchKeyValue(client, "targetname", Buffer);

		SetVariantString("!activator");
		AcceptEntityInput(aimed, "SetParent", client);
        //SetVariantString(Buffer);
        //AcceptEntityInput(aimed, "SetParent");

		SetVariantString("grenade2");
		AcceptEntityInput(aimed, "SetParentAttachment");
		AcceptEntityInput(aimed, "SetParentAttachmentMaintainOffset");
	}
	return Plugin_Handled;
}


// strap onto ourselves whatever is under our crosshair (dangerous!)
public Action Command_Strapon_Target(int client, int args)
{
	new aimed = GetClientAimTarget(client, false);
	if (aimed != -1 && IsValidEntity(aimed))
	{
		new String:classname[32];
		new String:m_ModelName[130];
		new String:m_nSolidType[130];
		int m_CollisionGroup, m_spawnflags;

		GetEdictClassname(aimed, classname, 32);
		if(StrContains(classname, "player"))
		{
			PrintToChat(client, "Can't strapon \"player\" classname");
			return Plugin_Handled;
		}
		GetEntPropString(aimed, Prop_Data, "m_ModelName", m_ModelName, 130);
		GetEntPropString(aimed, Prop_Data, "m_nSolidType", m_nSolidType, 130);
		GetEntProp(aimed, Prop_Data, "m_CollisionGroup", m_CollisionGroup);
		GetEntProp(aimed, Prop_Data, "m_spawnflags", m_spawnflags);

		decl String:Buffer[64];
		Format(Buffer, sizeof(Buffer), "Client%d", client);
		DispatchKeyValue(client, "targetname", Buffer);

		SetVariantString("!activator");
		AcceptEntityInput(aimed, "SetParent", client);
		//SetVariantString(Buffer);
		//AcceptEntityInput(aimed, "SetParent");

		SetVariantString("grenade2");
		AcceptEntityInput(aimed, "SetParentAttachment");
		SetVariantString("grenade2");
		AcceptEntityInput(aimed, "SetParentAttachmentMaintainOffset");
		/*new Float:angle[3];
		coords[0] -= 60.0;
		coords[1] -= 60.0;
		coords[2] += 100.0;
		DispatchKeyValueVector(aimed, "Origin", coords);*/    // Testing offsetting stuffs
	}
	return Plugin_Handled;
}


/*
    if (!IsModelPrecached(model))
        PrecacheModel(model);

    g_prop = CreateEntityByName("prop_dynamic_override");
    if (IsValidEntity(g_prop)) {
        SetVariantString("!activator");
        AcceptEntityInput(g_prop, "SetParent", target, g_prop, 0);
        SetVariantString("head");
        AcceptEntityInput(g_prop, "SetParentAttachment", g_prop, g_prop, 0);
        DispatchKeyValue(g_prop, "model", model);
        if (GetClientTeam(target) == 3)
            DispatchKeyValue(g_prop, "skin", "1");
        DispatchKeyValue(g_prop, "solid", "0");
        DispatchKeyValue(g_prop, "targetname", "potw_hat1");
        DispatchSpawn(g_prop);
        AcceptEntityInput(g_prop, "TurnOn", g_prop, g_prop, 0);
    }
*/



public Action Command_Create_Prop_Physics_Multiplayer(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "Please enter a modelname");
		return Plugin_Handled;
	}
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_physics_multiplayer");

	if(!IsModelPrecached(arg1))
	{
		PrecacheModel(arg1);			// might have to restrict list of models to avoid crash (menu?)
	}
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{

//		SetEntityModel(EntIndex, arg1);  // <-- this doesn't work, it spawns at 0 0 0 no matter what?
		SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);   // 4 should be OK, but it's set to 0 instead? <-- now don't collide with players but ignores collisions altogether?
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);   //2, changed to 11 so that they collide bewteen each other!!
		SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);   // Do I need to change this to 9218?????  <- doesn't work, we need to try with prop_multiplayer
		SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);  //16 is suggested, ghost is 136!??     <- doesn't work, we need to try with prop_multiplayer
//		SetEntityMoveType(EntIndex, MOVETYPE_VPHYSICS);   //MOVETYPE_VPHYSICS seems oK, doesn't seem to change anything

		int health=300;
//		health = 300
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!


		SetEntPropFloat(EntIndex, Prop_Send, "m_flGravity", 0.5); // doesn't do anything. FIXME: Changed from Prop_Data

//		DispatchKeyValue(EntIndex, "health", "100");    //not working
//		DispatchKeyValue(EntIndex, "rendercolor", "255,255,80,80");  //no working

/*		new g_offsCollisionGroup;
		g_offsCollisionGroup = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");
		SetEntData(EntIndex, g_offsCollisionGroup, 2, 4, true);  //new!
*/
//		AcceptEntityInput(EntIndex, "DisableCollision", 0, 0)  // causes absolutely no collision at all?
//		AcceptEntityInput(EntIndex, "kill", 0, 0)

		DispatchKeyValue(EntIndex, "targetname", "test");
		DispatchKeyValue(EntIndex, "model", arg1);     //does the same as SetEntityModel but works better! can teleport!?
		DispatchKeyValue(EntIndex, "CCollisionProperty", "2");
//		DispatchKeyValueFloat(EntIndex, "solid", 2.0);  //remettre 2.0 !
		DispatchKeyValue(EntIndex, "StartDisabled", "false");
		DispatchKeyValue(EntIndex, "spawnflags", "1073741824");   // <<- please check! new

		DispatchSpawn(EntIndex);


/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(EntIndex);
		PrintToConsole(client, "Entity: %d, solid: %d", EntIndex, solidtype);
		Entity_SetSolidType(EntIndex, 2);
*/
//		ChangeEdictState(EntIndex, 0);


		new Float:origin[3];
		origin[2] += 150.0;
//		GetClientAbsOrigin(client, origin);
		GetClientEyePosition(client, origin);
		//GetClientEyeAngles(client, angle);

//		GetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", origin);

		TeleportEntity(client, origin, NULL_VECTOR, NULL_VECTOR);

//		SetEntPropVector(EntIndex, Prop_Send, "m_vecOrigin", origin);
		PrintToConsole(client, "position: %f %f %f", origin[0], origin[1], origin[2]);
		GetPropInfo(client, EntIndex);

	}
	return Plugin_Handled;
}




public Action CommandPropNoCollide(int client, int args)
{
	new EntIndex = GetClientAimTarget(client, false);
	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{
		new String:classname[32];
		GetEdictClassname(EntIndex, classname, 32);

		new String:modelname[130];
		new String:solid[130];
		int collisiongroup, spawnflags;
		GetEntPropString(EntIndex, Prop_Data, "m_ModelName", modelname, 130);
		GetEntProp(EntIndex, Prop_Data, "m_CollisionGroup", collisiongroup);
		GetEntProp(EntIndex, Prop_Data, "m_spawnflags", spawnflags);
		GetEntPropString(EntIndex, Prop_Data, "m_nSolidType", solid, 130);

		int health=150;
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!

		SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 4);    //if 4, props go through each others.
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 2);

		AcceptEntityInput(EntIndex, "DisableCollision", 0, 0);
//		AcceptEntityInput(EntIndex, "kill", 0, 0)

		DispatchKeyValue(EntIndex, "targetname", "test");
//		DispatchKeyValue(EntIndex, "model", "models/d/d_s01.mdl");  // ok it works, no need anymore, just use in another command as changing models for fun :)
		DispatchKeyValue(EntIndex, "CCollisionProperty", "0");
		DispatchKeyValueFloat(EntIndex, "solid", 2.0);
		//DispatchSpawn(EntIndex);   <- do not use again! it works now.

/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(EntIndex);
		PrintToConsole(client, "Entity: %d, solid: %d", EntIndex, solidtype);
		Entity_SetSolidType(EntIndex, 2);
*/

		ChangeEdictState(EntIndex, 0);

		new Float:origin[3];
		GetClientAbsOrigin(client, origin);
		origin[2] += 20.0;
		TeleportEntity(EntIndex, origin, NULL_VECTOR, NULL_VECTOR);


//		ReplyToCommand(client, "Entity: %d, classname: %s, Modelname: %s", EntIndex, classname, modelname);
		PrintToConsole(client, "Entity: %d, classname: %s, Modelname: %s", EntIndex, classname, modelname);
		PrintToConsole(client, "Entity: %d, collision: %d, spawnflags: %d, solid: %d", EntIndex, collisiongroup, spawnflags, solid);

	}
	return Plugin_Handled;
}



public Action CommandPropCollide(int client, int args)
{
	new Ent = GetClientAimTarget(client, false);
	if (Ent != -1 && IsValidEntity(Ent))
	{
		new String:classname[32];
		GetEdictClassname(Ent, classname, 32);

		new String:modelname[130];
		new String:solid[130];
		int collisiongroup, spawnflags;

		GetEntPropString(Ent, Prop_Data, "m_ModelName", modelname, 130);
		GetEntProp(Ent, Prop_Data, "m_CollisionGroup", collisiongroup);
		GetEntProp(Ent, Prop_Data, "m_spawnflags", spawnflags);
		GetEntPropString(Ent, Prop_Data, "m_nSolidType", solid, 130);


		SetEntProp(Ent, Prop_Data, "m_spawnflags", 4);
		SetEntProp(Ent, Prop_Send, "m_CollisionGroup", 6);
//		SetEntProp(Ent, Prop_Send, "m_nSolidType", 9218);   //new


		AcceptEntityInput(Ent, "DisableCollision", 0, 0);
//		AcceptEntityInput(Ent, "kill", 0, 0);

		DispatchKeyValue(Ent, "targetname", "test");
//		DispatchKeyValue(Ent, "model", "models/d/d_s01.mdl");
		DispatchKeyValue(Ent, "CCollisionProperty", "0");
//		DispatchKeyValueFloat(Ent, "solid", 2.0);


/*		SMLIB
		new String:solidtype[130];
		Entity_GetSolidType(Ent);
		PrintToConsole(client, "Entity: %d, solid: %d", Ent, solidtype);
		Entity_SetSolidType(Ent, 2);
*/

		ChangeEdictState(Ent, 0);

		new Float:origin[3];
		GetClientAbsOrigin(client, origin);
		origin[2] += 20.0;
		TeleportEntity(Ent, origin, NULL_VECTOR, NULL_VECTOR);

		PrintToConsole(client, "Entity: %d, classname: %s, Modelname: %s", Ent, classname, modelname);
		PrintToConsole(client, "Entity: %d, collision: %d, spawnflags: %d, solid: %d", Ent, collisiongroup, spawnflags, solid);


		GetPropInfo(client, Ent);
	}
	return Plugin_Handled;
}



bool IsAccessGranted( int client )
{
    new bool:granted = true;

    // client = 0 means server, server always got access
    if ( client != 0 && GetConVarInt( g_cvar_adminonly ) > 0 )
    {
        if ( !GetAdminFlag( GetUserAdmin( client ), Admin_Generic, Access_Effective ) )
        {
            ReplyToCommand( client, "[Left FORT Dead] Server set only admin can use this command" );
            granted = false;
        }
    }

    if ( granted )
    {
        if ( GetConVarInt( g_cvar_enabled ) <= 0 )
        {
            ReplyToCommand( client, "MOD disabled on server side" );
            granted = false;
        }
    }

    return granted;
}



public Action RemoveTargetEntity( int client, int args )
{
    if ( !IsAccessGranted( client ) )
    {
        return Plugin_Handled;
    }

    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot spawn entity over rcon/server console" );
        return Plugin_Handled;
    }

    new index = -1;
    if ( args > 0 )
    {
        new String:param[128];
        GetCmdArg( 1, param, sizeof(param) );
        index = StringToInt( param );
    }
    else
    {
        index = GetClientAimedLocationData( client, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR );
    }

    if ( index > MaxClients )
    {
	new ent;
	ent = EntRefToEntIndex(ent);

	// only grab physics entities
	new String:edictname[128];
	GetEdictClassname(ent, edictname, 128);

	//if(strncmp("prop_", edictname, 5, false)==0 || strncmp("weapon_", edictname, 5, false)==0){  //filtering out prop_ and weapon_! -glub (works!)
	//(StrEqual(edictname, "prop_physics") || StrEqual(edictname, "prop_physics_multiplayer"))


	RemoveEdict( index );

	PrintToConsole( player, "Entity (index %i) removed", index );
	//}
    }
    else if ( index > 0 )
    {
        PrintToConsole( player, "Cannot remove player (index %i)", index );
    }
    else
    {
        PrintToConsole( player, "Nothing picked to remove" );
    }

    return Plugin_Handled;
}




public Action Rotate_Entity( int client, int args )
{
    if ( !IsAccessGranted( client ) )
    {
        return Plugin_Handled;
    }

    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot do over rcon/server console" );
        return Plugin_Handled;
    }

    new index = GetClientAimedLocationData( client, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR );
    if ( index <= 0 )
    {
        ReplyToCommand( player, "Nothing picked to rotate" );
        return Plugin_Handled;
    }

    new String:param[128];

    new Float:degree;
    if ( args > 0 )
    {
        GetCmdArg( 1, param, sizeof(param) );
        degree = StringToFloat( param );
    }

    GetEdictClassname( index, param, 128 );

    decl Float:angles[3];
    GetEntPropVector(index, Prop_Data, "m_angRotation", angles);
    RotateYaw(angles, degree);

    DispatchKeyValueVector(index, "Angles", angles);

    return Plugin_Handled;
}



public Action Rotate_EntityRoll( int client, int args )
{
    if ( !IsAccessGranted( client ) )
    {
        return Plugin_Handled;
    }

    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot do over rcon/server console" );
        return Plugin_Handled;
    }

    new index = GetClientAimedLocationData( client, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR );
    if ( index <= 0 )
    {
        ReplyToCommand( player, "Nothing picked to rotate" );
        return Plugin_Handled;
    }

    new String:param[128];

    new Float:degree;
    if ( args > 0 )
    {
        GetCmdArg( 1, param, sizeof(param) );
        degree = StringToFloat( param );
    }

    GetEdictClassname( index, param, 128 );

    decl Float:angles[3];
    GetEntPropVector(index, Prop_Data, "m_angRotation", angles);
    RotateRoll(angles, degree);

    DispatchKeyValueVector(index, "Angles", angles);

    return Plugin_Handled;
}



public Action Rotate_EntityPitch( int client, int args )
{
    if ( !IsAccessGranted( client ) )
    {
        return Plugin_Handled;
    }

    new player = GetPlayerIndex( client );

    if ( player == 0 )
    {
        ReplyToCommand( player, "Cannot do over rcon/server console" );
        return Plugin_Handled;
    }

    new index = GetClientAimedLocationData( client, NULL_VECTOR, NULL_VECTOR, NULL_VECTOR );
    if ( index <= 0 )
    {
        ReplyToCommand( player, "Nothing picked to rotate" );
        return Plugin_Handled;
    }

    new String:param[128];

    new Float:degree;
    if ( args > 0 )
    {
        GetCmdArg( 1, param, sizeof(param) );
        degree = StringToFloat( param );
    }

    GetEdictClassname( index, param, 128 );

    decl Float:angles[3];
    GetEntPropVector(index, Prop_Data, "m_angRotation", angles);
    RotatePitch(angles, degree);

    DispatchKeyValueVector(index, "Angles", angles);

    return Plugin_Handled;
}

