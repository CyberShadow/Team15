/**
 * A simple HTTP client.
 *
 * Copyright 2006       Stéphan Kochen <stephan@kochen.nl>
 * Copyright 2006-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
 * Copyright 2007-2009  Simon Arlott
 *
 * License:
 * This file is part of the Team15 library.
 *
 * The Team15 library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 3 of the
 * License, or (at your option) any later version.
 *
 * The Team15 library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with the Team15 library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

module Team15.Http.Client;

import std.string;
import std.conv;
import std.date:d_time;
import std.date:TicksPerSecond;
import std.uri;

import Team15.ASockets;
import Team15.Data;
debug (REFCOUNT) import Team15.Utils;
debug import std.stdio;

public import Team15.Http.Common;


class HttpClient
{
private:
	ClientSocket conn;
	Data inBuffer;

	HttpRequest currentRequest;

	HttpResponse currentResponse;
	size_t expect;

protected:
	void onConnect(ClientSocket sender)
	{
		string reqMessage = currentRequest.method ~ " ";
		if (currentRequest.proxy !is null) {
			reqMessage ~= "http://" ~ currentRequest.host;
			if (compat || currentRequest.port != 80)
				reqMessage ~= format(":%d", currentRequest.port);
		}
		reqMessage ~= currentRequest.resource ~ " HTTP/1.0\r\n";

		if (!("User-Agent" in currentRequest.headers))
			currentRequest.headers["User-Agent"] = agent;
		if (!compat) {
			if (!("Accept-Encoding" in currentRequest.headers))
				currentRequest.headers["Accept-Encoding"] = "gzip, deflate, *;q=0";
			if (currentRequest.data)
				currentRequest.headers["Content-Length"] = .toString(currentRequest.data.length);
		} else {
			if (!("Pragma" in currentRequest.headers))
				currentRequest.headers["Pragma"] = "No-Cache";
		}
		foreach (string header, string value; currentRequest.headers)
			reqMessage ~= header ~ ": " ~ value ~ "\r\n";

		reqMessage ~= "\r\n";

		Data data = new Data(reqMessage);
		if (currentRequest.data)
			data ~= currentRequest.data;

		//debug (HTTP) writefln("%s", fromWAEncoding(reqMessage));
		conn.send(data.contents);
	}

	void onNewResponse(ClientSocket sender, void[] data)
	{
		inBuffer ~= cast(string)data;

		conn.markNonIdle();

		//debug (HTTP) writefln("%s", fromWAEncoding(cast(string)data));

		auto inBufferStr = cast(string)inBuffer.contents;
		int headersend = find(inBufferStr, "\r\n\r\n");
		if (headersend == -1)
			return;

		string[] lines = splitlines(inBufferStr[0 .. headersend]);
		string statusline = lines[0];
		lines = lines[1 .. lines.length];

		int versionend = find(statusline, ' ');
		if (versionend == -1)
			return;
		string httpversion = statusline[0 .. versionend];
		statusline = statusline[versionend + 1 .. statusline.length];

		currentResponse = new HttpResponse();

		int statusend = find(statusline, ' ');
		if (statusend == -1)
			return;
		currentResponse.status = toUshort(statusline[0 .. statusend]);
		currentResponse.statusMessage = statusline[statusend + 1 .. statusline.length].dup;

		foreach (string line; lines)
		{
			int valuestart = find(line, ": ");
			if (valuestart > 0)
				currentResponse.headers[line[0 .. valuestart].dup] = line[valuestart + 2 .. line.length].dup;
		}

		expect = size_t.max;
		if ("Content-Length" in currentResponse.headers)
			try
				expect = toUint(strip(currentResponse.headers["Content-Length"]));
			catch(Object o)
				debug writefln(currentResponse.headers["Content-Length"]);

		inBuffer = inBuffer[(headersend + 4) * char.sizeof .. inBuffer.length];

		if (expect > inBuffer.length)
			conn.handleReadData = &onContinuation;
		else
		{
			currentResponse.data = inBuffer[0 .. expect];
			conn.disconnect("All data read");
		}
	}

	void onContinuation(ClientSocket sender, void[] data)
	{
		inBuffer ~= data;
		sender.markNonIdle();

		if (expect!=size_t.max && inBuffer.length >= expect)
		{
			currentResponse.data = inBuffer[0 .. expect];
			conn.disconnect("All data read");
		}
	}

	void onDisconnect(ClientSocket sender, string reason, DisconnectType type)
	{
		if (type == DisconnectType.Error)
			currentResponse = null;
		else
		if (currentResponse)
			currentResponse.data = inBuffer[];

		if (handleResponse)
			handleResponse(currentResponse, reason);

		currentRequest = null;
		currentResponse = null;
		inBuffer.clear;
		expect = -1;
		conn.handleReadData = null;
	}

public:
	string agent = "DHttp/0.1";
	bool compat = false;
	string[] cookies;

public:
	this(d_time timeout=(30 * TicksPerSecond))
	{
		debug (REFCOUNT) refcount("Http/Client/HttpClient",1);
		assert(timeout > 0);
		conn = new ClientSocket();
		conn.setIdleTimeout(timeout);
		conn.handleConnect = &onConnect;
		conn.handleDisconnect = &onDisconnect;
		inBuffer = new Data;
	}

	~this()
	{
		debug (REFCOUNT) refcount("Http/Client/HttpClient",0);
	}

	void request(HttpRequest request)
	{
		//debug writefln("New HTTP request: %s", request.url);
		currentRequest = request;
		currentResponse = null;
		conn.handleReadData = &onNewResponse;
		expect = 0;
		if (request.proxy !is null)
			conn.connect(request.proxyHost, request.proxyPort);
		else
			conn.connect(request.host, request.port);
	}

	bool connected()
	{
		return currentRequest !is null;
	}

public:
	// Provide the following callbacks
	void delegate(HttpResponse response, string disconnectReason) handleResponse;
}
