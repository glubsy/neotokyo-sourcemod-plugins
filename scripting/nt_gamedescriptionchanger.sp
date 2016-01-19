#include <sdkhooks>
#include <sourcemod>
#include <sdktools>

static bool:ismaploaded = false;

new Handle:GameDescriptionTitle = INVALID_HANDLE;
new String:Gametitle[64];

public Plugin:myinfo =
{
    name = "GameDescChanger",
    author = "glub",
    description = "Neotokyo description changer",
    version = "1.0",
    url = ""
};

public OnPluginStart()
{
	GameDescriptionTitle = CreateConVar("sm_gamedescription", "Neotokyon~", "change game description usage: sm_gamedescription <title>)")
	HookConVarChange(GameDescriptionTitle, ChangeGameDescriptionCvar);
}

public ChangeGameDescriptionCvar(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	GetConVarString(GameDescriptionTitle, Gametitle, 64)
	OnGetGameDescription(Gametitle);
}


public OnMapStart()
{
	ismaploaded = true;
	GetConVarString(GameDescriptionTitle, Gametitle, 64)
}

public OnMapEnd()
{
	ismaploaded = false;
}


public Action:OnGetGameDescription(String:gameDesc[64])
{
	if(ismaploaded)
	{
		new String:newTitle[64];
		//Format(newTitle, 64, "Neotokyooooon~");
		Format(newTitle, 64, Gametitle)
		
		strcopy(gameDesc, sizeof(gameDesc), newTitle);
		
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}