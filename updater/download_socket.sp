
/* Extension Helper - Socket */

Download_Socket(const String:url[], const String:dest[])
{
	new Handle:hFile = OpenFile(dest, "wb");
	
	if (hFile == INVALID_HANDLE)
	{
		DownloadEnded(false);
		ThrowError("Error writing to file: %s", dest);
	}
	
	// Format HTTP GET method.
	decl String:hostname[64], String:location[128], String:filename[64], String:sRequest[MAX_URL_LENGTH+128];
	ParseURL(url, hostname, sizeof(hostname), location, sizeof(location), filename, sizeof(filename));
	Format(sRequest, sizeof(sRequest), "GET %s/%s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n", location, filename, hostname);
	
	new Handle:hDLPack = CreateDataPack();
	WritePackCell(hDLPack, _:hFile);
	WritePackString(hDLPack, sRequest);
	
	new Handle:socket = SocketCreate(SOCKET_TCP, OnSocketError);
	SocketSetArg(socket, hDLPack);
	SocketConnect(socket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, hostname, 80);
}

public OnSocketConnected(Handle:socket, any:hDLPack)
{
	decl String:sRequest[MAX_URL_LENGTH+128];
	SetPackPosition(hDLPack, 8);
	ReadPackString(hDLPack, sRequest, sizeof(sRequest));
	
	SocketSend(socket, sRequest);
}

public OnSocketReceive(Handle:socket, String:data[], const size, any:hDLPack)
{
	ResetPack(hDLPack);
	new Handle:hFile = Handle:ReadPackCell(hDLPack);
	
	// Skip the header data.
	new pos = StrContains(data, "\r\n\r\n");
	pos = (pos != -1) ? pos + 4 : 0;
	
	for (new i = pos; i < size; i++)
	{
		WriteFileCell(hFile, data[i], 1);
	}
}

public OnSocketDisconnected(Handle:socket, any:hDLPack)
{
	ResetPack(hDLPack);
	CloseHandle(Handle:ReadPackCell(hDLPack));	// hFile
	CloseHandle(hDLPack);
	CloseHandle(socket);
	
	DownloadEnded(true);
}

public OnSocketError(Handle:socket, const errorType, const errorNum, any:hDLPack)
{
	ResetPack(hDLPack);
	CloseHandle(Handle:ReadPackCell(hDLPack));	// hFile
	CloseHandle(hDLPack);
	CloseHandle(socket);

	decl String:sError[256];
	FormatEx(sError, sizeof(sError), "Socket error: %d (Error code %d)", errorType, errorNum);
	DownloadEnded(false, sError);
}
