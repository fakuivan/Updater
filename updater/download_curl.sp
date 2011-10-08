
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
#if defined DEBUG
		// Logging this on official builds will annoy server owners running unmaintained plugins.
		decl String:error_buffer[256];
		curl_easy_strerror(code, error_buffer, sizeof(error_buffer));
		LogError("cURL error: %s", error_buffer);
#endif
		DownloadEnded(false);
	}
}
