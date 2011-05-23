/**
 * An improved HttpResponse class to ease writing pages.
 *
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
 * HostingBuddy is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with the Team15 library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

module Team15.Http.ResponseEx;

import std.string;
import std.file;
import std.path;
public import Team15.Http.Common;
import Team15.Data;
import Team15.Http.Json;

debug (REFCOUNT) import Team15.Utils;

/// HttpResponse with some code to ease creating responses
final class HttpResponseEx : HttpResponse
{
public:
	this()
	{
		debug (REFCOUNT) refcount("Http/ResponseEx",1);
	}

	~this()
	{
		debug (REFCOUNT) refcount("Http/ResponseEx",0);
	}

	/// Set the response status code and message
	void setStatus(HttpStatusCode code)
	{
		status = code;
		statusMessage = getStatusMessage(code);
	}

	/// Redirect the UA to another location
	HttpResponseEx redirect(string location)
	{
		setStatus(HttpStatusCode.SeeOther);
		headers["Location"] = location;
		return this;
	}

	HttpResponseEx serveData(string data, string contentType = "text/html")
	{
		return serveData(new Data(data), contentType);
	}

	HttpResponseEx serveData(Data data, string contentType)
	{
		setStatus(HttpStatusCode.OK);
		headers["Content-Type"] = contentType;
		this.data = data;
		return this;
	}

	string jsonCallback;
	HttpResponseEx serveJson(T)(T v)
	{
		string data = toJson(v);
		if (jsonCallback)
			return serveData(jsonCallback~'('~data~')', "text/javascript");
		else
			return serveData(data, "application/json");
	}

	/// Send a file from the disk
	HttpResponseEx serveFile(string file, string location)
	{
		if (file.length && (file.find("..") != -1 || file[0]=='/' || file[0]=='\\' || file.find("//") != -1 || file.find("\\\\") != -1))
		{
			writeError(HttpStatusCode.Forbidden);
			return this;
		}

		string filename = location ~ file;
		if(!(exists(filename) && isfile(filename)))
			if(exists(filename ~ "index.html"))
				filename ~= "index.html";
			else
			{
				writeError(HttpStatusCode.NotFound);
				return this;
			}

		setStatus(HttpStatusCode.OK);
		switch(tolower(getExt(filename)))
		{
			case "txt":
				headers["Content-Type"] = "text/plain";
				break;
			case "htm":
			case "html":
				headers["Content-Type"] = "text/html";
				break;
			case "js":
				headers["Content-Type"] = "text/javascript";
				break;
			case "css":
				headers["Content-Type"] = "text/css";
				break;
			case "png":
				headers["Content-Type"] = "image/png";
				break;
			case "gif":
				headers["Content-Type"] = "image/gif";
				break;
			case "jpg":
			case "jpeg":
				headers["Content-Type"] = "image/jpeg";
				break;
			case "ico":
				headers["Content-Type"] = "image/vnd.microsoft.icon";
				break;
			default:
				// let the UA decide
				break;
		}
		data = readData(filename);
		return this;
	}

	static string loadTemplate(string filename, string[string] dictionary)
	{
		string data = cast(string) read(filename);
		for(;;)
		{
			int startpos = data.find("<?");
			if(startpos==-1)
				return data;
			int endpos = data[startpos .. $].find("?>");
			if(endpos<2)
				throw new Exception("Bad syntax in template");
			string token = data[startpos+2 .. startpos+endpos];
			if(!(token in dictionary))
				throw new Exception("Unrecognized token: " ~ token);
			data = data[0 .. startpos] ~ dictionary[token] ~ data[startpos+endpos+2 .. $];
		}
	}

	void writePageContents(string title, string content)
	{
		string[string] dictionary;
		dictionary["title"] = title;
		dictionary["content"] = content;
		data = new Data(loadTemplate("files/page.htt", dictionary));
		headers["Content-Type"] = "text/html";
	}

	void writePage(string title, string[] text ...)
	{
		string content;
		foreach (string p; text)
			content ~= "<p>" ~ p ~ "</p>\n";

		string[string] dictionary;
		dictionary["title"] = title;
		dictionary["content"] = content;
		writePageContents(title, loadTemplate("files/content.htt", dictionary));
	}

	static string getStatusExplanation(HttpStatusCode code)
	{
		switch(code)
		{
			case 400: return "The request could not be understood by the server due to malformed syntax.";
			case 401: return "You are not authorized to access this resource.";
			case 403: return "You have tried to access a restricted or unavailable resource, or attempted to circumvent server security.";
			case 404: return "The resource you are trying to access does not exist on the server.";

			case 500: return "An unexpected error has occured within the server software.";
			case 501: return "The resource you are trying to access represents an unimplemented functionality.";
			default: return "";
		}
	}

	HttpResponseEx writeError(HttpStatusCode code, string details=null)
	{
		setStatus(code);

		string[string] dictionary;
		dictionary["code"] = .toString(cast(int)code);
		dictionary["message"] = getStatusMessage(code);
		dictionary["explanation"] = getStatusExplanation(code);
		dictionary["details"] = details ? "Error details:<br/><strong>" ~ details ~ "</strong>"  : "";
		string data = loadTemplate("files/error.htt", dictionary);

		writePageContents(.toString(cast(int)code) ~ " - " ~ getStatusMessage(code), data);
		return this;
	}

	void setRefresh(int seconds, string location=null)
	{
		headers["Refresh"] = .toString(seconds);
		if (location)
			headers["Refresh"] ~= ";URL=" ~ location;
	}

	void disableCache()
	{
		headers["Expires"] = "Mon, 26 Jul 1997 05:00:00 GMT";  // disable IE caching
		//headers["Last-Modified"] = "" . gmdate( "D, d M Y H:i:s" ) . " GMT";
		headers["Cache-Control"] = "no-cache, must-revalidate";
		headers["Pragma"] = "no-cache";
	}
}
