#pragma semicolon 1

/* SM Includes */
#include <sourcemod>
#undef REQUIRE_EXTENSIONS
#include <cURL>
#include <socket>
#define REQUIRE_EXTENSIONS

/* Plugin Info */
#define PLUGIN_NAME 		"Updater"
#define PLUGIN_VERSION 		"1.0.2-dev"

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = "GoD-Tony",
	description = "Automatically updates SourceMod plugins and files",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=169095"
};

/* Globals */
#define DEBUG		// This will enable verbose logging. Useful for developers testing their updates.

#define CURL_AVAILABLE()	(GetFeatureStatus(FeatureType_Native, "curl_easy_init") == FeatureStatus_Available)
#define SOCKET_AVAILABLE()	(GetFeatureStatus(FeatureType_Native, "SocketCreate") == FeatureStatus_Available)

#define MAX_URL_LENGTH		256
#define TEMP_FILE_EXT		"temp"		// All files are downloaded with this extension first.

#define UPDATE_URL			"http://godtony.mooo.com/updater/updater.txt"

enum UpdateStatus {
	Status_Idle,		
	Status_Checking,		// Checking for updates.
	Status_Downloading,		// Downloading an update.
	Status_Updated,			// Update is complete.
	Status_Error,			// An error occured while downloading.
};

new Handle:g_hCvarVersion = INVALID_HANDLE;
new Handle:g_hCvarUpdater = INVALID_HANDLE;
new bool:g_bGetDownload, bool:g_bGetSource;

new Handle:g_hPluginPacks = INVALID_HANDLE;
new Handle:g_hDownloadQueue = INVALID_HANDLE;
new Handle:g_hRemoveQueue = INVALID_HANDLE;
new bool:g_bDownloading = false;

new Handle:g_hUpdateTimer = INVALID_HANDLE;
new String:g_sDataPath[PLATFORM_MAX_PATH];

/* Core Includes */
#include "updater/plugins.sp"
#include "updater/filesys.sp"
#include "updater/download.sp"
#include "updater/api.sp"

/* Plugin Functions */
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// cURL
	MarkNativeAsOptional("curl_OpenFile");
	MarkNativeAsOptional("curl_easy_init");
	MarkNativeAsOptional("curl_easy_setopt_int_array");
	MarkNativeAsOptional("curl_easy_setopt_handle");
	MarkNativeAsOptional("curl_easy_setopt_string");
	MarkNativeAsOptional("curl_easy_perform_thread");
	MarkNativeAsOptional("curl_easy_strerror");
	
	// Socket
	MarkNativeAsOptional("SocketCreate");
	MarkNativeAsOptional("SocketSetArg");
	MarkNativeAsOptional("SocketConnect");
	MarkNativeAsOptional("SocketSend");
	
	API_Init();
	RegPluginLibrary("updater");
	
	return APLRes_Success;
}

public OnPluginStart()
{
	if (!CURL_AVAILABLE() && !SOCKET_AVAILABLE())
	{
		SetFailState("This plugin requires the cURL or Socket extension.");
	}
	
	// ConVar handling.
	g_hCvarVersion = CreateConVar("sm_updater_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	OnVersionChanged(g_hCvarVersion, "", "");
	HookConVarChange(g_hCvarVersion, OnVersionChanged);
	
	g_hCvarUpdater = CreateConVar("sm_updater", "2", "Determines update functionality. (1 = Notify, 2 = Download, 3 = Include source code)", FCVAR_PLUGIN, true, 1.0, true, 3.0);
	OnSettingsChanged(g_hCvarUpdater, "", "");
	HookConVarChange(g_hCvarUpdater, OnSettingsChanged);
	
	// Initialize arrays.
	g_hPluginPacks = CreateArray();
	g_hDownloadQueue = CreateArray();
	g_hRemoveQueue = CreateArray();
	
	// Temp path for checking update files.
	BuildPath(Path_SM, g_sDataPath, sizeof(g_sDataPath), "data/updater.txt");
	
#if !defined DEBUG
	// Add this plugin to the autoupdater.
	Updater_AddPlugin(GetMyHandle(), UPDATE_URL);
#endif

	// Check for updates every 24 hours.
	g_hUpdateTimer = CreateTimer(86400.0, Timer_CheckUpdates, _, TIMER_REPEAT);
}

public OnAllPluginsLoaded()
{
	// Check for updates on startup.
	CreateTimer(10.0, Timer_FirstUpdate);
}

public Action:Timer_FirstUpdate(Handle:timer)
{
	TriggerTimer(g_hUpdateTimer, true);
	
	return Plugin_Stop;
}

public Action:Timer_CheckUpdates(Handle:timer)
{
	Updater_FreeMemory();
	
	// Update everything!
	new maxPlugins = GetMaxPlugins();
	for (new i = 0; i < maxPlugins; i++)
	{		
		if (Updater_GetStatus(i) == Status_Idle)
		{
			Updater_Check(i);
		}
	}
	
	return Plugin_Continue;
}

public OnVersionChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (!StrEqual(newValue, PLUGIN_VERSION))
	{
		SetConVarString(g_hCvarVersion, PLUGIN_VERSION);
	}
}

public OnSettingsChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	switch (GetConVarInt(convar))
	{
		case 1: // Notify only.
		{
			g_bGetDownload = false;
			g_bGetSource = false;
		}
		
		case 2: // Download updates.
		{
			g_bGetDownload = true;
			g_bGetSource = false;
		}
		
		case 3: // Download with source code.
		{
			g_bGetDownload = true;
			g_bGetSource = true;
		}
	}
}

#if !defined DEBUG
public Updater_OnPluginUpdated()
{
	// Reload this plugin.
	decl String:filename[64];
	GetPluginFilename(INVALID_HANDLE, filename, sizeof(filename));
	ServerCommand("sm plugins reload %s", filename);
}
#endif

Updater_Check(index)
{
	if (Fwd_OnPluginChecking(IndexToPlugin(index)) == Plugin_Continue)
	{
		decl String:url[MAX_URL_LENGTH];
		Updater_GetURL(index, url, sizeof(url));
		Updater_SetStatus(index, Status_Checking);
		AddToDownloadQueue(index, url, g_sDataPath);
	}
}

Updater_FreeMemory()
{
	// Make sure that no threads are active.
	if (g_bDownloading || GetArraySize(g_hDownloadQueue))
	{
		return;
	}
	
	// Remove all queued plugins.	
	new index;
	new maxPlugins = GetArraySize(g_hRemoveQueue);
	for (new i = 0; i < maxPlugins; i++)
	{
		index = PluginToIndex(GetArrayCell(g_hRemoveQueue, i));
		
		if (index != -1)
		{
			Updater_RemovePlugin(index);
		}
	}
	
	ClearArray(g_hRemoveQueue);
	
	// Remove plugins that have been unloaded.
	for (new i = 0; i < GetMaxPlugins(); i++)
	{
		if (!IsValidPlugin(IndexToPlugin(i)))
		{
			Updater_RemovePlugin(i);
			i--;
		}
	}
}

Updater_Log(const String:format[], any:...)
{
	decl String:buffer[256], String:path[PLATFORM_MAX_PATH];
	VFormat(buffer, sizeof(buffer), format, 2);
	BuildPath(Path_SM, path, sizeof(path), "logs/Updater.log");
	LogToFileEx(path, "%s", buffer);
}

#if defined DEBUG
Updater_DebugLog(const String:format[], any:...)
{
	decl String:buffer[256], String:path[PLATFORM_MAX_PATH];
	VFormat(buffer, sizeof(buffer), format, 2);
	BuildPath(Path_SM, path, sizeof(path), "logs/Updater_Debug.log");
	LogToFileEx(path, "%s", buffer);
}
#endif
