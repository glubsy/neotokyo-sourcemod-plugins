#include <sourcemod>
#include <clientprefs>
#include <sdktools>
#pragma semicolon 1
#define NEO_MAX_CLIENTS 32
#if !defined DEBUG
	#define DEBUG 0
#endif
Handle g_hCookie = INVALID_HANDLE;
bool g_Muted[NEO_MAX_CLIENTS+1];

public Plugin:myinfo =
{
	name = "NEOTOKYO global mute",
	author = "glub",
	description = "Mute beligerent or griefing players.",
	version = "0.1",
	url = "https://github.com/glubsy"
};


public void OnPluginStart()
{
	RegAdminCmd("sm_gmute", Command_Mute_SteamId, ADMFLAG_CHAT, "sm_gmute <STEAM_ID> - \
Removes a player's ability to use text, voice, nickchange.");
	RegAdminCmd("sm_gunmute", Command_UnMute_SteamId, ADMFLAG_CHAT, "sm_gunmute <STEAM_ID> - \
Restores a player's ability to use text, voice, nickchange.");
	RegAdminCmd("sm_gmute_userid", Command_Mute_UserId, ADMFLAG_CHAT, "sm_gmute_userid <userID> - \
Removes a player's ability to use text, voice, nickchange.");

	HookEvent("player_changename", OnPlayerChangeName, EventHookMode_Pre);
	// HookEvent("player_info", OnPlayerChangeName, EventHookMode_Pre);

	#if DEBUG
	HookUserMessage(GetUserMessageId("SayText"), OnSayText, true);
	#endif

	g_hCookie = FindClientCookie("gmuted");
	if (g_hCookie == INVALID_HANDLE)
		g_hCookie = RegClientCookie("gmuted", "player is globally muted", CookieAccess_Private);

	// for late loading
	for (int i = MaxClients; i; --i)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		OnClientCookiesCached(i);
	}
}


bool ReadCookies(int client)
{
	char cookie[2];
	GetClientCookie(client, g_hCookie, cookie, sizeof(cookie));

	#if DEBUG
	PrintToServer("[gmute] DEBUG ReadCookies(%N) cookie is: \"%s\"",
	client, ((cookie[0] != '\0' && StringToInt(cookie)) ? cookie : "null" ));
	#endif

	if (cookie[0] != '\0')
		return view_as<bool>(StringToInt(cookie));
	else
		return (cookie[0] != '\0' && StringToInt(cookie));
}


stock void ToggleCookieClient(int client)
{
	if (!client || !IsClientInGame(client))
		return;

	#if DEBUG
	PrintToServer("[gmute] DEBUG Pref for %N was %s -> bool toggled.",
	client, (g_Muted[client] ? "true" : "false"));
	#endif

	g_Muted[client] = !g_Muted[client];

	SetClientCookie(client, g_hCookie, (g_Muted[client] ? "1" : "0"));
}


public Action Command_Mute_UserId(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "usage sm_gmute_userid <userID> (use status command) to toggle mute on that user." );
		return Plugin_Handled;
	}

	char arg[5];
	GetCmdArg(1, arg, sizeof(arg));
	int userid = StringToInt(arg);
	int targetclient = GetClientOfUserId(userid);

	if (userid <= 0)
	{
		ReplyToCommand(client, "Invalid userId!" );
		return Plugin_Handled;
	}

	#if DEBUG
	PrintToServer("[gmute] Issued mute on userid %d (client index %d)",
	userid, targetclient);
	#endif

	LogAction(client, -1, "[gmute] %N issued a global mute on client %L",
	client, targetclient);

	ToggleCookieClient(targetclient);
	OnClientCookiesCached(targetclient);

	ReplyToCommand(client, "Client %N is now %s.", targetclient, g_Muted[targetclient] ? "gmuted" : "not gmuted");

	// FIXME we're not updating voice flags here, they'll have to reconnect.

	return Plugin_Handled;
}


public Action Command_UnMute_SteamId(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[gmute] Usage: sm_gunmute <STEAMID> or sm_gmute_client <USERID>");
		return Plugin_Handled;
	}

	char authid[65];
	GetCmdArg(1, authid, sizeof(authid));

	if (!IsValidAuthId(authid))
	{
		ReplyToCommand(client, "[gmute] Invalid SteamID specified");
		return Plugin_Handled;
	}

	SetAuthIdCookie(authid, g_hCookie, "0");

	UpdateUserOfSteamID(authid);

	ReplyToCommand(client, "[gmute] client of %s is now un-muted.", authid);

	return Plugin_Handled;
}


public Action Command_Mute_SteamId(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[gmute] Usage: sm_gmute <STEAMID> or sm_gmute_client <USERID>");
		return Plugin_Handled;
	}

	char authid[65];
	GetCmdArg(1, authid, sizeof(authid));

	if (!IsValidAuthId(authid))
	{
		ReplyToCommand(client, "[gmute] Invalid SteamID specified");
		return Plugin_Handled;
	}

	SetAuthIdCookie(authid, g_hCookie, "1");

	UpdateUserOfSteamID(authid);

	ReplyToCommand(client, "[gmute] client of %s is now muted globally!", authid);

	return Plugin_Handled;
}


void UpdateUserOfSteamID(char[] authid)
{
	for (int i = MaxClients; i; --i)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		char clientauthid[65];
		if (!GetClientAuthId(i, AuthId_Steam2, clientauthid, sizeof(clientauthid)))
		{
			#if DEBUG
			PrintToServer("[gmute] Failed to fetch authid from %N!", i);
			#endif
			continue;
		}
		else
		{
			#if DEBUG
			PrintToServer("[gmute] Authid from for %L is %s", i, clientauthid);
			#endif
		}

		if (StrEqual(authid, clientauthid, false))
		{
			g_Muted[i] = ReadCookies(i);
			#if DEBUG
			PrintToServer("[gmute] Updated mute status for client %N is now %s",
			i, g_Muted[i] ? "gmuted" : "not gmuted");
			#endif
		}
	}
}


bool IsValidAuthId(char[] authid)
{
	if (!strncmp(authid, "STEAM_", 6) && authid[7] == ':')
		return true;
	else if (!strncmp(authid, "[U:", 3))
		return true;
	return false;
}


public void OnClientCookiesCached(int client)
{
	if (!client || IsFakeClient(client))
		return;

	EnforceNeutralName(client);

	g_Muted[client] = ReadCookies(client);

	SetClientListeningFlags(client, VOICE_MUTED);
}


public void OnPlayerDisconnect(int client)
{
	SetClientListeningFlags(client, VOICE_NORMAL);
}

// prevent haters from spreading hate
char BannedWords[][] = {"fuck"};

void EnforceNeutralName(client)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	TrimString(name);

	for (int i = 0; i < sizeof(BannedWords); ++i)
	{
		if (StrContains(name, BannedWords[i], false) != -1)
		{
			LogAction(client, -1, "Found banned word \"%s\" in player name \
\"%s\". Changed to \"NeotokyoScum\"", BannedWords[i], name);
			SetClientName(client, "NeotokyoScum");
		}
	}
}

// This returns the original text message to the client, as if it was sent to others.
public Action OnClientSayCommand(client, const String:command[], const String:sArgs[])
{
	if (client && g_Muted[client])
	{
		char buffer[255], teamtag[12];
		int team = GetClientTeam(client);
		switch (team)
		{
			case 2: // TEAM_JINRAI
				strcopy(teamtag, sizeof(teamtag), "[Jinrai]");
			case 3: // TEAM_NSF
				strcopy(teamtag, sizeof(teamtag), "[NSF]");
			default: // 0 TEAM_NONE, 1 TEAM_SPECTATOR
				strcopy(teamtag, sizeof(teamtag), "[Spectator]");
		}

		if (IsPlayerAlive(client))
			Format(buffer, sizeof(buffer), "%s %N: %s", teamtag, client, sArgs);
		else if (team <= 1)
			Format(buffer, sizeof(buffer), "%s %N: %s", teamtag, client, sArgs);
		else // dead
			Format(buffer, sizeof(buffer), "[DEAD]%s %N: %s", teamtag, client, sArgs);

		SendFakeUserMessage(client, buffer);

		LogAction(client, -1, "Sent back \"%s\" to gmuted %N.", buffer, client);

		return Plugin_Handled; // this blocks the usermessage
	}
	return Plugin_Continue;
}


void SendFakeUserMessage(int client, char[] buffer, bool grey=false)
{
	int players[1];
	players[0] = client; // only send to this same player

	Handle message = StartMessageEx(GetUserMessageId("SayText"), players, sizeof(players));
	BfWrite bf = UserMessageToBfWrite(message);

	if (!grey)
		BfWriteByte(bf, client);
	else
		BfWriteByte(bf, 0);
	// BfWriteByte(bf, 0); // seems to block the message
	BfWriteString(bf, buffer);
	// this byte probably signifies to the client to attribute the color to the appropriate team
	// if it is missing, the color will be grey, as in server message.
	if (!grey)
		BfWriteByte(bf, 0x01); // 1 = client should parse for color?
	else
		BfWriteByte(bf, 0x00); // 0 client doesn't apply color
	EndMessage();
}

	#if DEBUG
public Action OnSayText(UserMsg msg_id, Handle bf, players[], playersNum, bool reliable, bool init)
{
	// if(!reliable)
	// 	return Plugin_Continue;

	char buffer[500];
	int client, byte;
	client = BfReadByte(bf);
	BfReadString(bf, buffer, sizeof(buffer));
	byte = BfReadByte(bf);

	PrintToServer("[gmute] OnSayText: client \"%d\": \"%s\", extra byte: %d",
	client, buffer, byte);

	return Plugin_Continue;
}
#endif


public Action OnPlayerChangeName(Handle event, const char[] name, bool Dontbroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	if (!g_Muted[client])
		return Plugin_Continue;

	Dontbroadcast = true;
	SetEventBroadcast(event, true);

	char userName[MAX_NAME_LENGTH], oldName[MAX_NAME_LENGTH];
	GetEventString(event, "newname", userName, sizeof(userName));
	GetEventString(event, "oldname", oldName, sizeof(oldName));

	LogAction(client, -1, "Player \"%s\" is gmuted, blocking name change to \"%s\".",
	oldName, userName);
	SetEventString(event, "newname", oldName); // only sets the event parameters
	SetClientName(client, oldName); // actually overrides name change with old name

	char buffer[255];
	Format(buffer, sizeof(buffer), "%s changed name to %s", oldName, userName);
	SendFakeUserMessage(client, buffer, true);

	return Plugin_Continue;
}
