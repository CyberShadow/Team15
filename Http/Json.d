/**
 * JSON encoding.
 *
 * Copyright 2010-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module Team15.Http.Json;

import std.string;

string jsonEscape(string str)
{
	string result;
	foreach(c;str)
		if (c=='\\' || c=='"')
			result ~= "\\" ~ [c];
		else
		if (c<'\x20')
			result ~= format(`\u%04x`, c);
		else
		if (c=='\b')
			result ~= `\b`;
		else
		if (c=='\f')
			result ~= `\f`;
		else
		if (c=='\n')
			result ~= `\n`;
		else
		if (c=='\r')
			result ~= `\r`;
		else
		if (c=='\t')
			result ~= `\t`;
		else
			result ~= [c];
	return result;
}

string toJson(T)(T v)
{
	static if (is(T : string))
		return "\"" ~ jsonEscape(v) ~ "\"";
	else
	static if (is(T : long))
		return .toString(v);
	else
	static if (is(T U : U[]))
	{
		string[] items;
		foreach (item; v)
			items ~= toJson(item);
		return "[" ~ join(items, ",") ~ "]";
	}
	else
	static if (is(T==struct))
	{
		string json;
		foreach (i, field; v.tupleof)
			json ~= toJson(v.tupleof[i].stringof[2..$]) ~ ":" ~ toJson(field) ~ ",";
		if(json.length>0)
			json=json[0..$-1];
		return "{" ~ json ~ "}";
	}
	else
	static if (is(typeof(T.keys)) && is(typeof(T.values)))
	{
		string json;
		foreach(key,value;v)
			json ~= toJson(key) ~ ":" ~ toJson(value) ~ ",";
		if(json.length>0)
			json=json[0..$-1];
		return "{" ~ json ~ "}";
	}
	else
	static if (is(typeof(*v)))
		return toJson(*v);
	else
		static assert(0, "Can't encode " ~ T.stringof ~ " to JSON");
}

unittest
{
	struct X { int a; string b; }
	X x = {17, "aoeu"};
	assert(toJson(x) == `{"a":17,"b":"aoeu"}`);
	int[] arr = [1,5,7];
	assert(toJson(arr) == `[1,5,7]`);
}

// -------------------------------------------------------------------------------------------

import std.ctype;
import std.utf;
import std.conv;
import Team15.Utils;

private struct JsonParser
{
	string s;
	int p;

	char next()
	{
		enforce(p < s.length);
		return s[p++];
	}

	string readN(uint n)
	{
		string r;
		for (int i=0; i<n; i++)
			r ~= next();
		return r;
	}

	char peek()
	{
		enforce(p < s.length);
		return s[p];
	}

	void skipWhitespace()
	{
		while (iswhite(peek))
			p++;
	}

	void expect(char c)
	{
		enforce(next==c, c ~ " expected");
	}

	T read(T)()
	{
		static if (is(T==string))
			return readString();
		else
		static if (is(T==bool))
			return readBool();
		else
		static if (is(T : long))
			return readInt!(T)();
		else
		static if (is(T U : U[]))
			return readArray!(U)();
		else
		static if (is(T==struct))
			return readObject!(T)();
		else
		static if (is(typeof(T.keys)) && is(typeof(T.values)) && is(typeof(T.keys[0])==string))
			return readAA!(T)();
		else
		static if (is(T U : U*))
			return readPointer!(U)();
		else
			static assert(0, "Can't decode " ~ T.stringof ~ " from JSON");
	}

	string readString()
	{
		skipWhitespace();
		expect('"');
		string result;
		while (true)
		{
			auto c = next;
			if (c=='"')
				break;
			else
			if (c=='\\')
				switch (next)
				{
					case '"':  result ~= '"'; break;
					case '/':  result ~= '/'; break;
					case '\\': result ~= '\\'; break;
					case 'b':  result ~= '\b'; break;
					case 'f':  result ~= '\f'; break;
					case 'n':  result ~= '\n'; break;
					case 'r':  result ~= '\r'; break;
					case 't':  result ~= '\t'; break;
					case 'u':  result ~= toUTF8([cast(wchar)fromHex(readN(4))]); break;
					default: enforce(false, "Unknown escape");
				}
			else
				result ~= c;
		}
		return result;
	}

	bool readBool()
	{
		skipWhitespace();
		if (peek=='t')
		{
			enforce(readN(4) == "true", "Bad boolean");
			return true;
		}
		else
		{
			enforce(readN(5) == "false", "Bad boolean");
			return false;
		}
	}

	T readInt(T)()
	{
		skipWhitespace();
		T v;
		string s;
		char c;
		while (c=peek, c=='-' || (c>='0' && c<='9'))
			s ~= c, p++;
		static if (is(T==byte))
			return toByte(s);
		else
		static if (is(T==ubyte))
			return toUbyte(s);
		else
		static if (is(T==short))
			return toShort(s);
		else
		static if (is(T==ushort))
			return toUshort(s);
		else
		static if (is(T==int))
			return toInt(s);
		else
		static if (is(T==uint))
			return toUint(s);
		else
		static if (is(T==long))
			return toLong(s);
		else
		static if (is(T==ulong))
			return toUlong(s);
		else
			static assert(0, "Don't know how to parse numerical type " ~ T.stringof);
	}

	T[] readArray(T)()
	{
		skipWhitespace();
		expect('[');
		skipWhitespace();
		if (peek==']')
		{
			p++;
			return [];
		}
		T[] result;
		while(true)
		{
			result ~= read!(T)();
			skipWhitespace();
			if (peek==']')
			{
				p++;
				return result;
			}
			else
				expect(',');
		}
	}

	T readObject(T)()
	{
		skipWhitespace();
		expect('{');
		skipWhitespace();
		T v;
		if (peek=='}')
			return v;

		while (true)
		{
			string jsonField = readString();
			skipWhitespace();
			expect(':');

			bool found;
			foreach (i, field; v.tupleof)
				if (v.tupleof[i].stringof[2..$] == jsonField)
				{
					v.tupleof[i] = read!(typeof(v.tupleof[i]))();
					found = true;
					break;
				}
			enforce(found, "Unknown field " ~ jsonField);

			skipWhitespace();
			if (peek=='}')
			{
				p++;
				return v;
			}
			else
				expect(',');
		}
	}
}

T jsonParse(T)(string s) { return JsonParser(s).read!(T); }
