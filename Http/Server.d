/**
 * A simple HTTP server.
 *
 * Copyright 2006       Stéphan Kochen <stephan@kochen.nl>
 * Copyright 2006-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
 * Copyright 2007       Simon Arlott
 *
 * License:
 * This file is part of the Team15 library.
 *
 * The Team15 library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 3 of the
 * License, or (at your option) any later version.
 *
 * HostingBuddy is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with the Team15 library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

module Team15.Http.Server;

import std.string;
import std.conv;
import std.date:d_time;
import std.date:TicksPerSecond;
import std.uri;

import Team15.ASockets;
import Team15.Data;

debug (REFCOUNT) import Team15.Utils;

public import Team15.Http.Common;

class HttpServer
{
private:
	ServerSocket conn;
	d_time timeout;

private:
	class Connection
	{
		ClientSocket conn;
		Data inBuffer;

		HttpRequest currentRequest;
		int expect;  // VP 2007.01.21: changing from size_t to int because size_t is unsigned

		this(ClientSocket conn)
		{
			debug (REFCOUNT) refcount("Http/Server/Connection",1);

			this.conn = conn;
			conn.handleReadData = &onNewRequest;
			conn.setIdleTimeout(timeout);
			inBuffer = new Data;
		}

		~this()
		{
			debug (REFCOUNT) refcount("Http/Server/Connection",0);
		}

		void onNewRequest(ClientSocket sender, void[] data)
		{
			inBuffer ~= data;

			auto inBufferStr = cast(string)inBuffer.contents;
			int headersend = find(inBufferStr, "\r\n\r\n");
			if (headersend == -1)
				return;

			string[] lines = splitlines(inBufferStr[0 .. headersend]);
			string reqline = lines[0];
			lines = lines[1 .. lines.length];

			currentRequest = new HttpRequest();

			int methodend = find(reqline, ' ');
			if (methodend == -1)
				return;
			currentRequest.method = reqline[0 .. methodend].dup;
			reqline = reqline[methodend + 1 .. reqline.length];

			int resourceend = find(reqline, ' ');
			if (resourceend == -1)
				return;
			currentRequest.resource = reqline[0 .. resourceend].dup;

			//string httpversion = reqline[resourceend + 1 .. reqline.length];

			foreach (string line; lines)
			{
				int valuestart = find(line, ": ");
				if (valuestart > 0)
					currentRequest.headers[line[0 .. valuestart].dup] = line[valuestart + 2 .. line.length].dup;
			}

			expect = 0;
			if ("Content-Length" in currentRequest.headers)
				expect = toUint(currentRequest.headers["Content-Length"]);

			inBuffer = inBuffer[headersend+4..inBuffer.length];

			if (expect > 0)
			{
				if (expect > inBuffer.length)
					conn.handleReadData = &onContinuation;
				else
					processRequest(inBuffer[0 .. expect]);
			}
			else
				processRequest(null);
		}

		void processRequest(Data data)
		{
			currentRequest.data = data;
			if (handleRequest)
				sendResponse(handleRequest(currentRequest, conn));
			conn.disconnect();
		}

		void onContinuation(ClientSocket sender, void[] data)
		{
			inBuffer ~= cast(string)data;

			if (inBuffer.length >= expect)
				processRequest(inBuffer[0 .. expect]);
		}

		void sendResponse(HttpResponse response)
		{
			string respMessage = "HTTP/1.0 ";
			if (response)
			{
				if (!response.leaveOpen)
				{
					if ("Accept-Encoding" in currentRequest.headers)
						response.compress(currentRequest.headers["Accept-Encoding"]);
					response.headers["Content-Length"] = (response && response.data) ? .toString(response.data.length) : "0";
				}
				response.headers["X-Powered-By"] = "DHttp";

				respMessage ~= .toString(response.status) ~ " " ~ response.statusMessage ~ "\r\n";
				foreach (string header, string value; response.headers)
					respMessage ~= header ~ ": " ~ value ~ "\r\n";

				respMessage ~= "\r\n";
			}
			else
			{
				respMessage ~= "500 Internal Server Error\r\n\r\n";
			}

			Data data = new Data(respMessage);
			if (response && response.data)
				data ~= response.data;

			conn.send(data.contents);

			if (response && response.leaveOpen)
				expect = 0;
		}

		void disconnect()
		{
			conn.disconnect();
		}
	}

private:
	void onClose()
	{
		if (handleClose)
			handleClose();
	}

	void onAccept(ClientSocket incoming)
	{
		new Connection(incoming);
	}

public:
	this(d_time timeout=(30 * TicksPerSecond))
	{
		debug (REFCOUNT) refcount("Http/Server",1);

		assert(timeout > 0);
		this.timeout = timeout;

		conn = new ServerSocket();
		conn.handleClose = &onClose;
		conn.handleAccept = &onAccept;
	}

	~this()
	{
		/+
			// If something refers to us, we won't be collected.
			// If nothing refers to us, the program must be exiting.
			// If the program is exiting then the sockets will be closed.

			Connection[] clients = this.clients;
			this.clients.length = 0;
			foreach (Connection client; clients)
				client.disconnect();
		+/

		debug (REFCOUNT) refcount("Http/Server",0);
	}

	ushort listen(ushort port, string addr = null)
	{
		return conn.listen(port, addr);
	}

	void close()
	{
		conn.close();
		conn = null;
	}

public:
	/// Callback for when the socket was closed.
	void delegate() handleClose;
	/// Callback for an incoming request.
	HttpResponse delegate(HttpRequest request, ClientSocket conn) handleRequest;
}
