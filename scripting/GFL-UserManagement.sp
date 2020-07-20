#include <sourcemod>
#include <sdktools>
#include <GFL-Core>
#include <multicolors>
#include <ripext>

#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL "http://updater.gflclan.com/GFL-UserManagement.txt"
#define PL_VERSION "1.0.0"

// Groups
GroupId g_gidMember;
GroupId g_gidSupporter;
GroupId g_gidVIP;

const int GROUP_MEMBER = 1;
const int GROUP_SUPPORTER = 2;
const int GROUP_VIP = 3;

// ConVars
ConVar g_cvURL = null;
ConVar g_cvEndpoint = null;
ConVar g_cvToken = null;
ConVar g_cvDebug = null;

// ConVar Values
char g_sURL[1024];
char g_sEndpoint[1024];
char g_sToken[64];
bool g_bDebug = false;

bool g_bResponseFailed[MAXPLAYERS + 1];
int g_iClientGroup[MAXPLAYERS + 1];
bool g_bClientPreAdminChecked[MAXPLAYERS + 1];

HTTPClient httpClient;

public Plugin myinfo = {
	name = "GFL-UserManagement",
	author = "Roy (Christian Deacon) and N1ckles",
	description = "USer management plugin for Members, Supporters, and VIPs.",
	version = PL_VERSION,
	url = "GFLClan.com"
};

public void OnPluginStart() {
	// Load Translations.
	LoadTranslations("GFL-UserManagement.phrases.txt");

	g_cvURL = CreateConVar("sm_gflum_url", "something.com", "The Restful API URL.");
	g_cvEndpoint = CreateConVar("sm_gflum_endpoint", "index.php", "The Restful API endpoint. ");
	g_cvToken = CreateConVar("sm_gflum_token", "", "The token to use when accessing the API.");
	g_cvDebug = CreateConVar("sm_gflum_debug", "0", "Logging level increased for debugging.");

	AutoExecConfig(true, "GFL-UserManagement");
}

public void OnAllPluginsLoaded() {
	// Add to updater, if the library exists.
	if (LibraryExists("updater")) {
        Updater_AddPlugin(UPDATE_URL)
    }
}

public OnLibraryAdded(const char[] name) {
    if (StrEqual(name, "updater")) {
        Updater_AddPlugin(UPDATE_URL)
    }
}

public void OnConfigsExecuted() {
	// Fetch values
	ForwardValues();

	// Hook cv changes
	HookConVarChange(g_cvURL, CVarChanged);
	HookConVarChange(g_cvToken, CVarChanged);
	HookConVarChange(g_cvDebug, CVarChanged);
}

public void OnRebuildAdminCache(AdminCachePart part) {	
	// Only do something if admins are being rebuild
	if(part != AdminCache_Admins) {
		return;
	}

	if(g_bDebug) {
		GFLCore_LogMessage("", "[GFL-UserManagement] OnRebuildAdminCache() :: Cache is being rebuilt! Delaying execution to respect SourceBans.");
	}

	// Reload users after a second.
	CreateTimer(1.0, Timer_RebuildCache);
}

public void CVarChanged(Handle hCVar, const char[] OldV, const char[] NewV) {
	if(g_bDebug) {
		GFLCore_LogMessage("", "[GFL-UserManagement] CVarChanged() :: A CVar has been altered.");
	}

	// Get values again
	ForwardValues();
}

public Action Timer_RebuildCache(Handle timer) {
	if (g_bDebug) {
		GFLCore_LogMessage("", "[GFL-UserManagement] Timer_RebuildCache() :: Executed...");
	}

	ValidateGroups();

	for(int client = 1; client <= MaxClients; client++) {
		if(g_bClientPreAdminChecked[client] && g_iClientGroup[client] > 0) {
			if (g_bDebug) {
				GFLCore_LogMessage("", "[GFL-UserManagement] Timer_RebuildCache() :: Assigning perks for %L since they are cached.", client);
			}
			AssignPerks(client);
		}
	}
}

public void OnClientConnected(int client) {
	ResetClient(client);
}

public void OnClientDisconnect(int client) {
	ResetClient(client);
}

public void OnClientAuthorized(int client, const char[] sAuth2) {
	// Get their Steam ID 64.
	char steamID64[64];
	GetClientAuthId(client, AuthId_SteamID64, steamID64, sizeof(steamID64), true);

	// Format the GET string.
	char path[256];
	Format(path, sizeof(path), "%s?steamid=%s", g_sEndpoint, steamID64);

	// Set authentication header.
	httpClient.SetHeader("Authorization", g_sToken);

	// Execute the GET request.
	httpClient.Get(path, PerkJSONReceived, GetClientUserId(client));

	// Debug.
	if (g_bDebug) {
		GFLCore_LogMessage("", "[GFL-UserManagement] OnClientAuthorized() :: Fetching perks for %L now...", client);
	}
}

public void PerkJSONReceived(HTTPResponse response, any userID) {
	// Receive client ID.
	int client = GetClientOfUserId(userID);

	if (!client) return;

	// Get their Steam ID 64.
	char steamID64[64];
	GetClientAuthId(client, AuthId_SteamID64, steamID64, sizeof(steamID64), true);

	// Check if the response errored out.
	if (response.Status != HTTPStatus_OK) {
		// Welp, fuck...
		GFLCore_LogMessage("", "[GFL-UserManagement] PerkJSONReceived() :: Error with GET reqeust (Error code: %d, Steam ID: %s)", response.Status, steamID64);
		g_bResponseFailed[client] = true;
		if(g_bClientPreAdminChecked[client]) NotifyPostAdminCheck(client);
		return;
	}

	// Check if the JSON response is valid.
	if (response.Data == null) {
		// RIP...
		GFLCore_LogMessage("", "[GFL-UserManagement] PerkJSONReceived() :: Data is null. (Steam ID: %s)", steamID64);
		g_bResponseFailed[client] = true;
		if(g_bClientPreAdminChecked[client]) NotifyPostAdminCheck(client);
		return;
	}

	JSONObject stuff = view_as<JSONObject>(response.Data);

	// First, let's check for a custom error.
	int error = stuff.GetInt("error");

	// Check if invalid token.
	if (error == 401) {
		GFLCore_LogMessage("", "[GFL-UserManagement] PerkJSONReceived() :: INVALID TOKEN. PLEASE CONTACT A DIRECTOR. (Steam ID: %s)", steamID64);
		g_bResponseFailed[client] = true;
		if(g_bClientPreAdminChecked[client]) NotifyPostAdminCheck(client);
		return;
	}

	// Receive the perk.
	g_iClientGroup[client] = stuff.GetInt("group");

	// Debugging...
	if (g_bDebug) {
		GFLCore_LogMessage("", "[GFL-UserManagement] PerkJSONReceived() :: Received perks for %L group ID is %i", client, g_iClientGroup[client]);
	}

	if(g_bClientPreAdminChecked[client]) {
		// Debugging...
		if (g_bDebug) {
			GFLCore_LogMessage("", "[GFL-UserManagement] PerkJSONReceived() :: Received perks for %L late. Calling NotifyPostAdminCheck", client);
		}
		NotifyPostAdminCheck(client);
	}
}

public Action OnClientPreAdminCheck(int client) {
	g_bClientPreAdminChecked[client] = true;
	if(g_iClientGroup[client] >= 0 || g_bResponseFailed[client]) {
		if (g_bDebug) {
			GFLCore_LogMessage("", "[GFL-UserManagement] OnClientPreAdminCheck() :: Passing %L through since perks are fetched or failed.", client);
		}
		return Plugin_Continue;
	}

	if (g_bDebug) {
		GFLCore_LogMessage("", "[GFL-UserManagement] OnClientPreAdminCheck() :: Delaying OnClientPostAdminCheck for %L since their API request is in progress.", client);
	}

	RunAdminCacheChecks(client);
	return Plugin_Handled;
}

public void OnClientPostAdminFilter(int client) {
	if (!g_bResponseFailed[client]) {
		AssignPerks(client);
	}
}

stock void AssignPerks(int client) {
	int groupID = g_iClientGroup[client];

	if (groupID <= 0) {
		if (g_bDebug) {
			GFLCore_LogMessage("", "[GFL-UserManagement] AssignPerks() :: Ignoring invalid perks to %L (group ID is %i)", client, groupID);
		}
		return;
	}

	// Debugging...
	if (g_bDebug) {
		GFLCore_LogMessage("", "[GFL-UserManagement] AssignPerks() :: Assigning perks to %L (group ID is %i)", client, groupID);
	}

	// Check if valid group range.
	if (groupID < 1 || groupID > 3) {	
		// What, the fuck...
		GFLCore_LogMessage("", "[GFL-UserManagement] AssignPerks() :: %L has a group ID (%d) out-of-range. Either doesn't exist or bad range.", client, groupID);
		return;
	}

	// Get the admin.
	AdminId aAdmin = GetUserAdmin(client);

	// Check if they're an admin already.
	if (aAdmin == INVALID_ADMIN_ID) {
		if (g_bDebug) {
			GFLCore_LogMessage("", "[GFL-UserManagement] AssignPerks() :: Admin not built for %L. Building...", client);
		}

		aAdmin = CreateAdmin("");
		SetUserAdmin(client, aAdmin, true);
	} else {
		if (g_bDebug) {
			GFLCore_LogMessage("", "[GFL-UserManagement] AssignPerks() :: Admin already built for %L. Continuing...", client);
		}
	}

	// Check if Member.
	if (groupID == GROUP_MEMBER) aAdmin.InheritGroup(g_gidMember);
	else if (groupID == GROUP_SUPPORTER) aAdmin.InheritGroup(g_gidSupporter);
	else if (groupID == GROUP_VIP) aAdmin.InheritGroup(g_gidVIP);

	// Debug message FTW!!!
	if (g_bDebug) {
		GFLCore_LogMessage("", "[GFL-UserManagement] AssignPerks() :: Assigned group #%d to %L.", groupID, client);
	}
}

stock void ValidateGroups() {
	// Debugging...
	if (g_bDebug) {
		GFLCore_LogMessage("", "[GFL-UserManagement] ValidateGroups() :: Executed...");
	}

	// Find the groups firstly.
	g_gidMember = FindAdmGroup("Member");
	g_gidSupporter = FindAdmGroup("Supporter");
	g_gidVIP = FindAdmGroup("VIP");

	if (g_gidMember == INVALID_GROUP_ID) {
		SetFailState("[GFL-UserManagement] ValidateGroups() :: Member group has an invalid group ID. Please make sure the group exists in SourceBans and has at least one flag.");
	}	

	if (g_gidSupporter == INVALID_GROUP_ID)	{
		SetFailState("[GFL-UserManagement] ValidateGroups() :: Supporter group has an invalid group ID. Please make sure the group exists in SourceBans and has at least one flag.");
	}	

	if (g_gidVIP == INVALID_GROUP_ID) {
		SetFailState("[GFL-UserManagement] ValidateGroups() :: VIP group has an invalid group ID. Please make sure the group exists in SourceBans and has at least one flag.");
	}
}

stock void ForwardValues() {
	GetConVarString(g_cvURL, g_sURL, sizeof(g_sURL));
	GetConVarString(g_cvEndpoint, g_sEndpoint, sizeof(g_sEndpoint));
	GetConVarString(g_cvToken, g_sToken, sizeof(g_sToken));
	g_bDebug = g_cvDebug.BoolValue;

	// Create the httpClient.
	if (httpClient != null) {
		delete httpClient;
	}

	httpClient = new HTTPClient(g_sURL);
}

stock void ResetClient(int client) {
	g_bClientPreAdminChecked[client] = false;
	g_bResponseFailed[client] = false;
	g_iClientGroup[client] = -1;
}