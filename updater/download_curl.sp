
/* Extension Helper - cURL */

Download_cURL(const String:url[], const String:dest[])
{
	new Handle:hFile = curl_OpenFile(dest, "wb");
	
	if (hFile == INVALID_HANDLE)
	{
		DownloadEnded(false);
		ThrowError("Error writing to file: %s", dest);
	}
	
	new CURL_Default_opt[][2] = {
		{_:CURLOPT_NOSIGNAL,		1},
		{_:CURLOPT_NOPROGRESS,		1},
		{_:CURLOPT_TIMEOUT,			30},
		{_:CURLOPT_CONNECTTIMEOUT,	60},
		{_:CURLOPT_VERBOSE,			0}
	};
	
	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array(curl, CURL_Default_opt, sizeof(CURL_Default_opt));
	curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, hFile);
	curl_easy_setopt_string(curl, CURLOPT_URL, url);
	curl_easy_setopt_string(curl, CURLOPT_HTTPHEADER, "Pragma: no-cache");
	curl_easy_setopt_string(curl, CURLOPT_HTTPHEADER, "Cache-Control: no-cache");
	curl_easy_perform_thread(curl, OnCurlComplete, hFile);
}

public OnCurlComplete(Handle:curl, CURLcode:code, any:hFile)
{
	CloseHandle(hFile);
	CloseHandle(curl);
	
	if(code == CURLE_OK)
	{
		DownloadEnded(true);
	}
	else
	{
		decl String:sError[256];
		curl_easy_strerror(code, sError, sizeof(sError));
		Format(sError, sizeof(sError), "cURL error: %s", sError);
		DownloadEnded(false, sError);
	}
}
