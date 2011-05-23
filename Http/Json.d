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
 * HostingBuddy is distributed in the hope that it will be useful,
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
	static if (is(T==string))
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
