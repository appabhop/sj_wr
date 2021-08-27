#include <sourcemod>
#include <ripext>
#include <shavit>

public Plugin myinfo =
{
	name = "SourceJump Global WR Lookup",
	author = "appa & Blank",
	description = "SourceJump Global WR Lookup",
	version = "2.0",
	url = "https://github.com/appabhop/sj_wr"
};

ConVar gCV_ApiKey;
char gS_apiURL[64] = "https://sourcejump.net"

char gS_maps[MAXPLAYERS + 1][128];

char gS_currentMap[128];
char gS_wrMapTime[16];
char gS_wrMapPlayer[32];
bool gB_mapHasRecord = false;

ConVar gCV_ShowSJWR_SpecialString;
bool gB_showSJWR[MAXPLAYERS + 1];

enum struct RecordInfo
{
    char name[32];
    char map[128];
    char hostname[128];
    char time[16];
    char steamid[32];
    char date[32];
    float sync;
    int strafes;
    int jumps;
}

StringMap Maps;

HTTPClient httpClient;

public void OnPluginStart()
{
    RegConsoleCmd("sm_global", Command_WrLookup, "View the global leaderboards of a map from the SourceJump API");
    RegConsoleCmd("sm_gwr", Command_WrLookup, "View the global leaderboards of a map from the SourceJump API");
    RegConsoleCmd("sm_wrsj", Command_WrLookup, "View the global leaderboards of a map from the SourceJump API");

    gCV_ApiKey = CreateConVar("sj_api_key", "", "Replace with your SourceJump API key");
    gCV_ShowSJWR_SpecialString = CreateConVar("sj_wr_specialstring", "sjwr", "Special string for styles to show the SourceJump Global WR in HUD");

    AutoExecConfig();

    Maps = new StringMap();
}

public void OnMapStart()
{
    Maps.Clear();

    GetCurrentMap(gS_currentMap, sizeof(gS_currentMap));
    GetCurrentMapWR();

    CreateTimer(30.0, GetCurrentMapWR_Timer, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void ContactApi(int client)
{
    char ApiKey[64];
    gCV_ApiKey.GetString(ApiKey, sizeof(ApiKey));

    httpClient = new HTTPClient(gS_apiURL);
    httpClient.SetHeader("api-key", ApiKey);

    char endpoint[140];
    Format(endpoint, sizeof(endpoint), "api/records/%s", gS_maps[client]);

    httpClient.Get(endpoint, WrLookup_OnReceived, client);
}

public Action Command_WrLookup(int client, int args)
{
	if(client > 0 && !IsFakeClient(client))
	{
        char sMap[128];

        if(args == 0)
        {
            GetCurrentMap(sMap, sizeof(sMap));
        }
        else
        {
            GetCmdArgString(sMap, sizeof(sMap));

            if(!(StrContains(sMap, "bhop_") == 0) && !(StrContains(sMap, "kz_") == 0))
            {
                Format(sMap, sizeof(sMap), "bhop_%s", sMap);
            }
        }

        gS_maps[client] = sMap;

        ContactApi(client);
    }
}

void WrLookup_OnReceived(HTTPResponse response, int client)
{
    if (response.Status != HTTPStatus_OK) {
        PrintToChat(client, "Failed retreiving records on %s (%d)", gS_maps[client], response.Status);
        return; 
    } 

    JSONArray JSON_records = view_as<JSONArray>(response.Data); 

    if(JSON_records.Length <= 0)
    {
        PrintToChat(client, "No records found on %s", gS_maps[client]);
        return;
    }

    ArrayList records;
    records = new ArrayList(sizeof(RecordInfo));

    Maps.SetValue(gS_maps[client], records, true);
        
    JSONObject JSON_record;

    for(int i = 0; i < JSON_records.Length; i++)
    {
        JSON_record = view_as<JSONObject>(JSON_records.Get(i));

        RecordInfo record;
        
        JSON_record.GetString("name", record.name, sizeof(record.name));
        JSON_record.GetString("map", record.map, sizeof(record.map));
        JSON_record.GetString("hostname", record.hostname, sizeof(record.hostname));
        JSON_record.GetString("time", record.time, sizeof(record.time));
        JSON_record.GetString("steamid", record.steamid, sizeof(record.steamid));
        JSON_record.GetString("date", record.date, sizeof(record.date));
        record.sync = JSON_record.GetFloat("sync");
        record.strafes = JSON_record.GetInt("strafes");
        record.jumps = JSON_record.GetInt("jumps");

        records.PushArray(record);
    }

    delete JSON_record;
    delete JSON_records;

    GlobalLeaderboard_Menu(client);
}

void GlobalLeaderboard_Menu(int client)
{
    Menu menu = CreateMenu(MenuHandler_GlobalLeaderboard);

    SetMenuTitle(menu, "Global Records on %s:", gS_maps[client]);

    ArrayList records;
    if(Maps.GetValue(gS_maps[client], records))
    {
        for(int i = 0; i < records.Length; i++)
        {
            RecordInfo record;
            records.GetArray(i, record, sizeof(record));

            char title[128];
            Format(title, sizeof(title), "#%d - %s - %s (%d jumps)", i + 1, record.name, record.time, record.jumps);

            AddMenuItem(menu, record.map, title);
        }
    }
    
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_GlobalLeaderboard(Menu menu, MenuAction action, int client, int option)
{
	if(action == MenuAction_Select)
	{
		ViewRecordDetails_Menu(client, option);
    }
    else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void ViewRecordDetails_Menu(int client, int recordIndex)
{
	Menu menu = CreateMenu(MenuHandler_ViewRecordDetails);
    
    ArrayList records;
    if(Maps.GetValue(gS_maps[client], records))
    {
        RecordInfo record;
        records.GetArray(recordIndex, record, sizeof(record));

        SetMenuTitle(menu, "%s %s\n--- %s:", record.name, record.steamid, record.map);

        char info[128];

        Format(info, sizeof(info), "Time: %s", record.time);
        AddMenuItem(menu, "time", info);

        Format(info, sizeof(info), "Jumps: %d", record.jumps);
        AddMenuItem(menu, "jumps", info);

        Format(info, sizeof(info), "Strafes: %d (%.2f%%)", record.strafes, record.sync);
        AddMenuItem(menu, "strafes", info);

        Format(info, sizeof(info), "Server: %s", record.hostname);
        AddMenuItem(menu, "server", info);

        Format(info, sizeof(info), "Date: %s", record.date);
        AddMenuItem(menu, "time", info);
    }
	
    menu.ExitBackButton = true;
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_ViewRecordDetails(Menu menu, MenuAction action, int client, int option)
{
    if(action == MenuAction_Cancel && option == MenuCancel_ExitBack)
    {
        GlobalLeaderboard_Menu(client);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	char sSpecial[128];
	Shavit_GetStyleStrings(newstyle, sSpecialString, sSpecial, sizeof(sSpecial));

    char showSJWR_SpecialString[32];
    gCV_ShowSJWR_SpecialString.GetString(showSJWR_SpecialString, sizeof(showSJWR_SpecialString));

	gB_showSJWR[client] = (StrContains(sSpecial, showSJWR_SpecialString) != -1);
}

public Action GetCurrentMapWR_Timer(Handle timer)
{
    GetCurrentMapWR();
}

void GetCurrentMapWR()
{
    char ApiKey[64];
    gCV_ApiKey.GetString(ApiKey, sizeof(ApiKey));

    httpClient = new HTTPClient(gS_apiURL);
    httpClient.SetHeader("api-key", ApiKey);

    char endpoint[140];
    Format(endpoint, sizeof(endpoint), "api/records/%s", gS_currentMap);

    httpClient.Get(endpoint, GetCurrentMapWR_OnReceived);
}

void GetCurrentMapWR_OnReceived(HTTPResponse response, any value)
{
    if (response.Status != HTTPStatus_OK) {
		gB_mapHasRecord = false;
        return;
    } 

    JSONArray JSON_records = view_as<JSONArray>(response.Data); 

    if(JSON_records.Length <= 0)
    {
		gB_mapHasRecord = false;
        return;
    }

	gB_mapHasRecord = true;

    JSONObject JSON_record;
    JSON_record = view_as<JSONObject>(JSON_records.Get(0));

	JSON_record.GetString("time", gS_wrMapTime, sizeof(gS_wrMapTime));
	JSON_record.GetString("name", gS_wrMapPlayer, sizeof(gS_wrMapPlayer));

    delete JSON_record;
    delete JSON_records;
}

public Action Shavit_OnTopLeftHUD(int client, int target, char[] topleft, int topleftlength)
{
    if((Shavit_GetBhopStyle(client) != 0) && (!gB_showSJWR[client]))
        return;

    if(!gB_mapHasRecord)
        return;

    if(Shavit_GetClientTrack(client) != 0)
        return;

    if(strlen(topleft))
        Format(topleft, topleftlength, "%s\nSJ Global: %s (%s)", topleft, gS_wrMapTime, gS_wrMapPlayer);
    else 
        Format(topleft, topleftlength, "SJ Global: %s (%s)", gS_wrMapTime, gS_wrMapPlayer);
}   
