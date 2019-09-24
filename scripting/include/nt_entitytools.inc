// This include is very messy and unstable, don't use it!

stock CreatePropPhysicsOverride(int client, const String:modelname[], int health)
{
	new String:arg1[130];
	GetCmdArg(1, arg1, sizeof(arg1));

	new EntIndex = CreateEntityByName("prop_physics_override");

//	if (GetCmdArgs() < 2){
//	health=400;
//	}

	if (EntIndex != -1 && IsValidEntity(EntIndex))
	{
		if(!IsModelPrecached(arg1))
		{
			PrecacheModel(arg1);			// might have to restrict list of models to avoid crash (menu?)
		}

//		SetEntityModel(EntIndex, arg1);   <-- this doesn't work, it spawns at 0 0 0 no matter what!
		//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);   // 4 should be OK, but it's set to 0 instead? <-- 1073741824 now don't collide with players, but ignore collisions altogether
		SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);   //2, changed to 11 so that they collide bewteen each other! 11 = weapon!
		SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);   // Do I need to change this to 9218?????  <- doesn't work, we need to try with prop_multiplayer
		SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);  //16 is suggested, ghost is 136!??     <- doesn't work, we need to try with prop_multiplayer

		//int health=150
		SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);  // Prop_Send didn't work but this works!
		SetEntProp(EntIndex, Prop_Data, "m_iMaxHealth", health, 1);

		SetEntPropFloat(EntIndex, Prop_Data, "m_flGravity", 1.0);  // doesn't seem to do anything?
		SetEntityGravity(EntIndex, 0.5); 						// (default = 1.0, half = 0.5, double = 2.0)

		SetEntPropFloat(EntIndex, Prop_Data, "m_massScale", 1.0);  //FIXME!
		DispatchKeyValue(EntIndex, "massScale", "1.0");
		DispatchKeyValue(EntIndex, "physdamagescale", "1.0");  // FIXME! not sure if it works


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
		DispatchKeyValue(EntIndex, "model", modelname);     //does the same as SetEntityModel but works better! can teleport!?
		//DispatchKeyValue(EntIndex, "CCollisionProperty", "2");
		//DispatchKeyValueFloat(EntIndex, "solid", 2.0);  //remettre 2.0 !
		//DispatchKeyValue(EntIndex, "Solid", "6");    // might need to disable this one (unnecessary?)
		DispatchKeyValue(EntIndex, "inertiaScale", "1.0");



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

/*
		new Float:vAngles[3], Float:vOrigin[3], Float:pos[3];

		GetClientEyePosition(client,vOrigin);
		GetClientEyeAngles(client, vAngles);

		new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

		if(TR_DidHit(trace)){
			TR_GetEndPosition(pos, trace);

			pos[2] += 10.0; // make sure he does not get stuck to the floor, increse Z pos

			TeleportEntity( target, pos, NULL_VECTOR, NULL_VECTOR ); //Teleport target player on hitpos

		}
		CloseHandle(trace);


*/


		DispatchKeyValueVector(EntIndex, "Origin", PropStartOrigin); // works!
		DispatchKeyValueVector(EntIndex, "Angles", ClientEyeAngles); // works!
		//DispatchKeyValueVector(EntIndex, "basevelocity", clienteyeposition);
		DispatchKeyValue(EntIndex, "physdamagescale", "0.1");   // works! positive value = breaks when falling
		DispatchKeyValue(EntIndex, "friction", "1.0");
		DispatchKeyValue(EntIndex, "gravity", "0.8");
		//TeleportEntity(EntIndex, ClientOrigin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(EntIndex);

		//GetPropInfo(client, EntIndex);

	}
	return EntIndex;
}


stock int CreatePropDynamicOverride(int client, const String:modelname[], int health)
{
	new EntIndex = CreateEntityByName("prop_dynamic_override");

	if(!IsModelPrecached(modelname))
	{
		PrecacheModel(modelname);
	}

	new String:name[130];
	new Float:VecOrigin[3];
	new Float:VecAngles[3];
	new Float:normal[3];

	DispatchKeyValue(EntIndex, "model", modelname);
	DispatchKeyValue(EntIndex, "Solid", "6");
	//SetEntProp(EntIndex, Prop_Data, "m_spawnflags", 1073741824);
	SetEntProp(EntIndex, Prop_Send, "m_CollisionGroup", 11);
	SetEntProp(EntIndex, Prop_Data, "m_nSolidType", 6);
	SetEntProp(EntIndex, Prop_Data, "m_usSolidFlags", 136);

	SetEntProp(EntIndex, Prop_Data, "m_iHealth", health, 1);
	SetEntProp(EntIndex, Prop_Data, "m_iMaxHealth", health, 1);


	GetClientEyePosition(client, VecOrigin);
	GetClientEyeAngles(client, VecAngles);
	TR_TraceRayFilter(VecOrigin, VecAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer, client);
	TR_GetEndPosition(VecOrigin);
	TR_GetPlaneNormal(INVALID_HANDLE, normal);
	GetVectorAngles(normal, normal);
	normal[0] += 90.0;
	DispatchKeyValueVector(EntIndex, "Origin", VecOrigin); // works!
	DispatchKeyValueVector(EntIndex, "Angles", normal); // works!


	TeleportEntity(EntIndex, VecOrigin, normal, NULL_VECTOR);
	DispatchSpawn(EntIndex);

	new Float:degree = 180.0;  //rotating properly -glub
	decl Float:angles[3];
	GetEntPropVector(EntIndex, Prop_Data, "m_angRotation", angles);
	RotateYaw(angles, degree);

	DispatchKeyValueVector(EntIndex, "Angles", angles );  // rotates 180 degrees! -glub
	GetClientName(client, name, sizeof(name));
	//PrintToChatAll("%s spawned something", name);
	return EntIndex;
}


stock bool:TraceEntityFilterPlayer(entity, contentsMask){
	return ((entity > MaxClients) || entity == 0);
}


//---------------------------------------------------------
// get position, angles and normal of aimed location if the parameters are not NULL_VECTOR
// return the index of entity you aimed
//---------------------------------------------------------
stock GetClientAimedLocationData( client, Float:position[3], Float:angles[3], Float:normal[3] )
{
    new index = -1;

    new player = GetPlayerIndex( client );

    decl Float:_origin[3], Float:_angles[3];
    GetClientEyePosition( player, _origin );
    GetClientEyeAngles( player, _angles );

    new Handle:trace = TR_TraceRayFilterEx( _origin, _angles, MASK_ALL, RayType_Infinite, TraceEntityFilterPlayers );  //was MASK_SOLID_BRUSHONLY -glub
    if( !TR_DidHit( trace ) )
    {
        ReplyToCommand( player, "Failed to pick the aimed location" );
        index = -1;
    }
    else
    {
        TR_GetEndPosition( position, trace );
        TR_GetPlaneNormal( trace, normal );
        angles[0] = _angles[0];
        angles[1] = _angles[1];
        angles[2] = _angles[2];

        index = TR_GetEntityIndex( trace );
    }
    CloseHandle( trace );
    return index;
}

//---------------------------------------------------------
// return 0 if it is a server
//---------------------------------------------------------
stock GetPlayerIndex( int client )
{
    if ( client == 0 && !IsDedicatedServer() )
    {
        return 1;
    }

    return client;
}

stock Float:GetAngleBetweenVectors( const Float:vector1[3], const Float:vector2[3], const Float:direction[3] )
{
    decl Float:vector1_n[3], Float:vector2_n[3], Float:direction_n[3], Float:cross[3];
    NormalizeVector( direction, direction_n );
    NormalizeVector( vector1, vector1_n );
    NormalizeVector( vector2, vector2_n );
    new Float:degree = ArcCosine( GetVectorDotProduct( vector1_n, vector2_n ) ) * 57.29577951;   // 180/Pi
    GetVectorCrossProduct( vector1_n, vector2_n, cross );

    if ( GetVectorDotProduct( cross, direction_n ) < 0.0 )
    {
        degree *= -1.0;
    }

    return degree;
}


stock bool:TraceEntityFilterPlayers(entity, contentsMask, any:data)
{
    return entity > MaxClients && entity != data;
}


stock bool:TraceFilterIgnorePlayers(entity, contentsMask, any:client)
{
    if(entity >= 1 && entity <= MaxClients)
    {
        return false;
    }

    return true;
}



stock RotateYaw( Float:angles[3], Float:degree )
{
    decl Float:direction[3], Float:normal[3];
    GetAngleVectors( angles, direction, NULL_VECTOR, normal );

    new Float:sin = Sine( degree * 0.01745328 );     // Pi/180
    new Float:cos = Cosine( degree * 0.01745328 );
    new Float:a = normal[0] * sin;
    new Float:b = normal[1] * sin;
    new Float:c = normal[2] * sin;
    new Float:x = direction[2] * b + direction[0] * cos - direction[1] * c;
    new Float:y = direction[0] * c + direction[1] * cos - direction[2] * a;
    new Float:z = direction[1] * a + direction[2] * cos - direction[0] * b;
    direction[0] = x;
    direction[1] = y;
    direction[2] = z;

    GetVectorAngles( direction, angles );

    decl Float:up[3];
    GetVectorVectors( direction, NULL_VECTOR, up );

    new Float:roll = GetAngleBetweenVectors( up, normal, direction );
    angles[2] += roll;
}

stock RotatePitch( Float:angles[3], Float:degree )  			// !!! TODO !!! unfinished, doesn't work as intended. I suck at maths. -glub
{
	angles[1] += degree;
}

stock RotateRoll( Float:angles[3], Float:degree )
{
    angles[2] += degree;
}