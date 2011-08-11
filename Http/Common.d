/**
 * Concepts shared between HTTP clients and servers.
 *
 * Copyright 2006       Stéphan Kochen <stephan@kochen.nl>
 * Copyright 2006-2010  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module Team15.Http.Common;

import std.string, std.conv, std.ctype;
static import zlib = Team15.Zlib;
static import gzip = Team15.Gzip;
public import Team15.Utils;
import Team15.Data;

/// Base HTTP message class
private abstract class HttpMessage
{
public:
	string[string] headers;
	Data data;
}

/// HTTP request class
class HttpRequest : HttpMessage
{
public:
	string method = "GET";
	string proxy;
	ushort port = 80; // client only

	this()
	{
		debug (REFCOUNT) refcount("Http/Common/HttpRequest",1);
	}

	this(string resource)
	{
		this();
		this.resource = resource;
	}

	~this()
	{
		debug (REFCOUNT) refcount("Http/Common/HttpRequest",0);
	}

	string resource()
	{
		return resource_;
	}

	void resource(string value)
	{
		resource_ = value;

		// applies to both Client/Server as some clients put a full URL in the GET line instead of using a "Host" header
		if (resource_.length>7 && resource_[0 .. 7] == "http://")
		{
			int pathstart = find(resource_[7 .. $], '/');
			if (pathstart == -1)
			{
				host = resource_[7 .. $];
				resource_ = "/";
			}
			else
			{
				host = resource_[7 .. 7 + pathstart];
				resource_ = resource_[7 + pathstart .. $];
			}
			int portstart = find(host, ':');
			if (portstart != -1)
			{
				port = toUshort(host[portstart+1..$]);
				host = host[0..portstart];
			}
		}
	}

	string host()
	{
		return headers["Host"];
	}

	void host(string value)
	{
		headers["Host"] = value;
	}

	string url()
	{
		return "http://" ~ host ~ (port==80 ? null : .toString(port)) ~ resource;
	}

	string proxyHost()
	{
		int portstart = find(proxy, ':');
		if (portstart != -1)
			return proxy[0..portstart];
		return proxy;
	}

	ushort proxyPort()
	{
		int portstart = find(proxy, ':');
		if (portstart != -1)
			return toUshort(proxy[portstart+1..$]);
		return 80;
	}

	string[string] decodePostData()
	{
		auto data = cast(string)data.contents;
		if (data.length is 0)
			return null;

		string contentType;
		foreach (header, value; headers)
			if (icmp(header, "Content-Type")==0)
				contentType = value;
		if (contentType is null)
			throw new Exception("Can't get content type header");

		switch (contentType)
		{
			case "application/x-www-form-urlencoded":
				return decodeUrlParameters(data);
			default:
				throw new Exception("Unknown Content-Type: " ~ *contentType);
		}
	}

private:
	string resource_;
}

/// HTTP response status codes
enum HttpStatusCode : ushort
{
	Continue=100,
	SwitchingProtocols=101,

	OK=200,
	Created=201,
	Accepted=202,
	NonAuthoritativeInformation=203,
	NoContent=204,
	ResetContent=205,
	PartialContent=206,

	MultipleChoices=300,
	MovedPermanently=301,
	Found=302,
	SeeOther=303,
	NotModified=304,
	UseProxy=305,
	//(Unused)=306,
	TemporaryRedirect=307,

	BadRequest=400,
	Unauthorized=401,
	PaymentRequired=402,
	Forbidden=403,
	NotFound=404,
	MethodNotAllowed=405,
	NotAcceptable=406,
	ProxyAuthenticationRequired=407,
	RequestTimeout=408,
	Conflict=409,
	Gone=410,
	LengthRequired=411,
	PreconditionFailed=412,
	RequestEntityTooLarge=413,
	RequestUriTooLong=414,
	UnsupportedMediaType=415,
	RequestedRangeNotSatisfiable=416,
	ExpectationFailed=417,

	InternalServerError=500,
	NotImplemented=501,
	BadGateway=502,
	ServiceUnavailable=503,
	GatewayTimeout=504,
	HttpVersionNotSupported=505
}

/// HTTP reply class
class HttpResponse : HttpMessage
{
public:
	ushort status;
	string statusMessage;

	this()
	{
		debug (REFCOUNT) refcount("Http/Common/HttpResponse",1);
	}

	~this()
	{
		debug (REFCOUNT) refcount("Http/Common/HttpResponse",0);
	}

	static string getStatusMessage(HttpStatusCode code)
	{
		switch(code)
		{
			case 100: return "Continue";
			case 101: return "Switching Protocols";

			case 200: return "OK";
			case 201: return "Created";
			case 202: return "Accepted";
			case 203: return "Non-Authoritative Information";
			case 204: return "No Content";
			case 205: return "Reset Content";
			case 206: return "Partial Content";
			case 300: return "Multiple Choices";
			case 301: return "Moved Permanently";
			case 302: return "Found";
			case 303: return "See Other";
			case 304: return "Not Modified";
			case 305: return "Use Proxy";
			case 306: return "(Unused)";
			case 307: return "Temporary Redirect";

			case 400: return "Bad Request";
			case 401: return "Unauthorized";
			case 402: return "Payment Required";
			case 403: return "Forbidden";
			case 404: return "Not Found";
			case 405: return "Method Not Allowed";
			case 406: return "Not Acceptable";
			case 407: return "Proxy Authentication Required";
			case 408: return "Request Timeout";
			case 409: return "Conflict";
			case 410: return "Gone";
			case 411: return "Length Required";
			case 412: return "Precondition Failed";
			case 413: return "Request Entity Too Large";
			case 414: return "Request-URI Too Long";
			case 415: return "Unsupported Media Type";
			case 416: return "Requested Range Not Satisfiable";
			case 417: return "Expectation Failed";

			case 500: return "Internal Server Error";
			case 501: return "Not Implemented";
			case 502: return "Bad Gateway";
			case 503: return "Service Unavailable";
			case 504: return "Gateway Timeout";
			case 505: return "HTTP Version Not Supported";
			default: return "";
		}
	}

	/// If the data is compressed, return the decompressed data
	// this is not a property on purpose - to avoid using it multiple times as it will unpack the data on every access
	Data getContent()
	{
		if (data is null)
			return null;
		else
		if ("Content-Encoding" in headers && headers["Content-Encoding"]=="deflate")
			return zlib.uncompress(data);
		else
		if ("Content-Encoding" in headers && headers["Content-Encoding"]=="gzip")
			return gzip.uncompress(data);
		else
			return data;
	}

	void setContent(Data content, string[] supported)
	{
		foreach(method;supported ~ ["*"])
			switch(method)
			{
				case "deflate":
					headers["Content-Encoding"] = method;
					data = zlib.compress(content);
					return;
				case "gzip":
					headers["Content-Encoding"] = method;
					data = gzip.compress(content);
					return;
				case "*":
					if("Content-Encoding" in headers)
						headers.remove("Content-Encoding");
					data = content;
					return;
				default:
					break;
			}
		assert(0);
	}

	/// called by the server to compress content if possible
	void compress(string acceptEncoding)
	{
		if ("Content-Encoding" in headers || data is null)
			return;
		setContent(data, parseItemList(acceptEncoding));
	}
}

/// parses a list in the format of "a, b, c;q=0.5, d" and returns an array of items sorted by "q" (["a", "b", "d", "c"])
// NOTE: this code is crap.
string[] parseItemList(string s)
{
	string[] items = s.split(",");
	foreach(ref item;items)
		item = strip(item);

	struct Item
	{
		float q=1.0;
		string str;

		int opCmp(Item* i)
		{
			if(q<i.q) return  1;
			else
			if(q>i.q) return -1;
			else      return  0;
		}

		static Item opCall(string s)
		{
			Item i;
			int p;
			while((p=s.rfind(';'))!=-1)
			{
				string param = s[p+1..$];
				s = strip(s[0..p]);
				int p2 = param.find('=');
				assert(p2!=-1);
				string name=strip(param[0..p2]), value=strip(param[p2+1..$]);
				switch(name)
				{
					case "q":
						i.q = .toFloat(value);
						break;
					default:
					// fail on unsupported
				}
			}
			i.str = s;
			return i;
		}
	}

	Item[] structs;
	foreach(item;items)
		structs ~= [Item(item)];
	structs.sort;
	string[] result;
	foreach(item;structs)
		result ~= [item.str];
	return result;
}

string httpEscape(string str)
{
	string result;
	foreach(c;str)
		switch(c)
		{
			case '<':
				result ~= "&lt;";
				break;
			case '>':
				result ~= "&gt;";
				break;
			case '&':
				result ~= "&amp;";
				break;
			case '\xDF':  // the beta-like symbol
				result ~= "&szlig;";
				break;
			default:
				result ~= [c];
		}
	return result;
}

unittest
{
	assert(parseItemList("a, b, c;q=0.5, d") == ["a", "b", "d", "c"]);
}

string encodeUrlParameter(string param)
{
	string s;
	foreach (c; param)
		if (!isalnum(c) && c!='-' && c!='_')
			s ~= format("%%%02X", cast(ubyte)c);
		else
			s ~= c;
	return s;
}

string encodeUrlParameters(string[string] dic)
{
	string[] segs;
	foreach (name, value; dic)
		segs ~= encodeUrlParameter(name) ~ '=' ~ encodeUrlParameter(value);
	return join(segs, "&");
}

string decodeUrlParameter(string encoded)
{
	string s;
	for (int i=0; i<encoded.length; i++)
		if (encoded[i] == '%')
		{
			s ~= cast(char)fromHex(encoded[i+1..i+3]);
			i += 2;
		}
		else
		if (encoded[i] == '+')
			s ~= ' ';
		else
			s ~= encoded[i];
	return s;
}

string[string] decodeUrlParameters(string qs)
{
	string[] segs = split(qs, "&");
	string[string] dic;
	foreach (pair; segs)
	{
		int p = pair.find('=');
		if (p < 0)
			dic[decodeUrlParameter(pair)] = null;
		else
			dic[decodeUrlParameter(pair[0..p])] = decodeUrlParameter(pair[p+1..$]);
	}
	return dic;
}

static import std.date;
import std.date : d_time;

string httpDate(d_time t)
{
	string s = std.date.toString(t);
	// Sun Sep 20 04:01:19 GMT+0300 2009
	// 0123456789012345678901234567890123
	// Mon, 15 Aug 2005 15:52:01 +0000
	assert(s.length==33, "Invalid date length: " ~ s);
	return s[0..3] ~ ", " ~ s[8..11] ~ s[4..8] ~ s[29..33] ~ s[10..20] ~ s[23..28];
}

d_time parseHtml5Date(string date)
{
	enforce(date.length==10 && date[4]=='-' && date[7]=='-', "Malformed date, should be in YYYY-MM-DD format");
	return MakeDate(MakeDay(.toInt(date[0..4]), .toInt(date[5..7])-1, .toInt(date[8..10])), 0);
}
