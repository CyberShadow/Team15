/**
 * Some code to simplify using multipart/x-mixed-replace streaming.
 *
 * Copyright 2009  Vladimir Panteleev <thecybershadow@gmail.com>
 */

module Team15.Http.Streaming;

import Team15.ASockets;
import Team15.Http.Common;
import Team15.Http.ResponseEx;
import Team15.Utils;
import Team15.Data;

class HttpStream
{
	string boundary;
	ClientSocket conn;

	this(ClientSocket conn)
	{
		this.conn = conn;
		conn.handleDisconnect = null;
		this.boundary = randomString();
	}

	HttpResponse makeResponse(void[] initialData=null, string contentType = "text/plain; charset=utf-8")
	{
		HttpResponseEx resp = new HttpResponseEx();
		resp.setStatus(HttpStatusCode.OK);
		resp.leaveOpen = true;
		resp.headers["Content-Type"] = "multipart/x-mixed-replace; boundary=\"" ~ boundary ~ \";
		resp.data = new Data("--" ~ boundary ~ "\r\n");
		if (initialData)
			resp.data ~= formatChunk(initialData, contentType);
			//resp.data = new Data(formatChunk(initialData, contentType));
		return resp;
	}

	void send(void[] data, string contentType = "text/plain; charset=utf-8")
	{
		// TODO: use Data?
		conn.send(formatChunk(data, contentType));
		conn.markNonIdle();
	}

	private void[] formatChunk(void[] data, string contentType)
	{
		return "Content-Type: " ~ contentType ~ "\r\n\r\n" ~ data ~ "\r\n--" ~ boundary ~ "\r\n";
	}
}