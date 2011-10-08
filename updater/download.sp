
/* Download Manager */

#include "updater/download_curl.sp"
#include "updater/download_socket.sp"

FinalizeDownload(index)
{
	/* Strip the temporary file extension from downloaded files. */
	decl String:newpath[PLATFORM_MAX_PATH], String:oldpath[PLATFORM_MAX_PATH];
	new Handle:hFiles = Updater_GetFiles(index);
	
	new maxFiles = GetArraySize(hFiles);
	for (new i = 0; i < maxFiles; i++)
	{
		GetArrayString(hFiles, i, newpath, sizeof(newpath));
		Format(oldpath, sizeof(oldpath), "%s.%s", newpath, TEMP_FILE_EXT);
		
		// Rename doesn't overwrite on Windows. Make sure the path is clear.
		if (FileExists(newpath))
		{
			DeleteFile(newpath);
		}
		
		RenameFile(newpath, oldpath);
	}
	
	ClearArray(hFiles);
}

AbortDownload(index)
{
	/* Delete all downloaded temporary files. */
	decl String:path[PLATFORM_MAX_PATH];
	new Handle:hFiles = Updater_GetFiles(index);
	
	new maxFiles = GetArraySize(hFiles);
	for (new i = 0; i < maxFiles; i++)
	{
		GetArrayString(hFiles, 0, path, sizeof(path));
		Format(path, sizeof(path), "%s.%s", path, TEMP_FILE_EXT);
		
		if (FileExists(path))
		{
			DeleteFile(path);
		}
	}
	
	ClearArray(hFiles);
}

ProcessDownloadQueue()
{
	if (g_bDownloading || !GetArraySize(g_hDownloadQueue))
	{
		return;
	}
	
	new Handle:hQueuePack = GetArrayCell(g_hDownloadQueue, 0);
	SetPackPosition(hQueuePack, 8);
	
	decl String:url[MAX_URL_LENGTH], String:dest[PLATFORM_MAX_PATH];
	ReadPackString(hQueuePack, url, sizeof(url));
	ReadPackString(hQueuePack, dest, sizeof(dest));
	
	if (CURL_AVAILABLE())
	{
		Download_cURL(url, dest);
	}
	else if (SOCKET_AVAILABLE())
	{
		Download_Socket(url, dest);
	}
	else
	{
		SetFailState("This plugin requires the cURL or Socket extension.");
	}
	
#if defined DEBUG
	Updater_DebugLog("Download started:");
	Updater_DebugLog("  [0]  URL: %s", url);
	Updater_DebugLog("  [1]  Destination: %s", dest);
#endif
	
	g_bDownloading = true;
}

AddToDownloadQueue(index, const String:url[], const String:dest[])
{
	new Handle:hQueuePack = CreateDataPack();
	WritePackCell(hQueuePack, index);
	WritePackString(hQueuePack, url);
	WritePackString(hQueuePack, dest);
	
	PushArrayCell(g_hDownloadQueue, hQueuePack);
	
	ProcessDownloadQueue();
}

DownloadEnded(bool:successful)
{
	new Handle:hQueuePack = GetArrayCell(g_hDownloadQueue, 0);
	ResetPack(hQueuePack);
	
	decl String:url[MAX_URL_LENGTH], String:dest[PLATFORM_MAX_PATH];
	new index = ReadPackCell(hQueuePack);
	ReadPackString(hQueuePack, url, sizeof(url));
	ReadPackString(hQueuePack, dest, sizeof(dest));
	
	// Remove from the queue.
	CloseHandle(hQueuePack);
	RemoveFromArray(g_hDownloadQueue, 0);
	
#if defined DEBUG
	Updater_DebugLog("  [2]  Successful: %s", successful ? "Yes" : "No");
#endif
	
	switch (Updater_GetStatus(index))
	{
		case Status_Checking:
		{
			if (!successful || !ParseUpdateFile(index, dest))
			{
				Updater_SetStatus(index, Status_Idle);
			}
		}
		
		case Status_Downloading:
		{
			if (successful)
			{
				// Check if this was the last file we needed.
				decl String:lastfile[PLATFORM_MAX_PATH];
				new Handle:hFiles = Updater_GetFiles(index);
				
				GetArrayString(hFiles, GetArraySize(hFiles) - 1, lastfile, sizeof(lastfile));
				Format(lastfile, sizeof(lastfile), "%s.%s", lastfile, TEMP_FILE_EXT);
				
				if (StrEqual(dest, lastfile))
				{
					new Handle:hPlugin = IndexToPlugin(index);
					Fwd_OnPluginUpdating(hPlugin);
					FinalizeDownload(index);
					Fwd_OnPluginUpdated(hPlugin);
					Updater_SetStatus(index, Status_Updated);
				}
			}
			else
			{
				// Failed during an update.
				AbortDownload(index);
				Updater_SetStatus(index, Status_Error);
				
				decl String:filename[64];
				GetPluginFilename(IndexToPlugin(index), filename, sizeof(filename));
				Updater_Log("Error downloading update for plugin \"%s\"", filename);
				Updater_Log("  [0]  URL: %s", url);
				Updater_Log("  [1]  Destination: %s", dest);
			}
		}
		
		case Status_Error:
		{
			// Delete any additional files that this plugin had queued.
			if (successful && FileExists(dest))
			{
				DeleteFile(dest);
			}
		}
	}
	
	g_bDownloading = false;
	ProcessDownloadQueue();
}
