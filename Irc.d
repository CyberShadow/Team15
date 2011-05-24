/**
 * Common IRC code.
 *
 * Copyright 2006       Stéphan Kochen <stephan@kochen.nl>
 * Copyright 2006-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
 * Copyright 2007       Vincent Povirk <madewokherd@gmail.com>
 * Copyright 2007-2010  Simon Arlott
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

module Team15.Irc;

import std.string;
import std.date : TicksPerSecond, TicksPerMinute;

import Team15.ASockets;

/// Types of a chat message.
enum IrcMessageType
{
	NORMAL,
	ACTION,
	NOTICE
}

// RFC1459 case mapping
static assert(tolower("[") == "[" && toupper("[") == "[");
static assert(tolower("]") == "]" && toupper("]") == "]");
static assert(tolower("{") == "{" && toupper("{") == "{");
static assert(tolower("}") == "}" && toupper("}") == "}");
static assert(tolower("|") == "|" && toupper("|") == "|");
static assert(tolower("\\") == "\\" && toupper("\\") == "\\");

string rfc1459toLower(string name)
{
	return tolower(name).tr("[]\\","{}|");
}

string rfc1459toUpper(string name)
{
	return toupper(name).tr("{}|","[]\\");
}

unittest
{
	assert(rfc1459toLower("{}|[]\\") == "{}|{}|");
	assert(rfc1459toUpper("{}|[]\\") == "[]\\[]\\");
}

class IrcSocket : LineBufferedSocket
{
	this()
	{
		super(90 * TicksPerSecond);
		handleIdleTimeout = &onIdleTimeout;
	}

	this(Socket conn)
	{
		super.setIdleTimeout(TicksPerMinute);
		super(conn);
		handleIdleTimeout = &onIdleTimeout;
	}

	override void markNonIdle()
	{
		if (pingSent)
			pingSent = false;
		super.markNonIdle();
	}

	void delegate (IrcSocket sender) handleInactivity;
	void delegate (IrcSocket sender) handleTimeout;

private:
	void onIdleTimeout(ClientSocket sender)
	{
		if (pingSent || handleInactivity is null)
		{
			if (handleTimeout)
				handleTimeout(this);
			else
				disconnect("Time-out", DisconnectType.Error);
		}
		else
		{
			handleInactivity(this);
			pingSent = true;
		}
	}

	bool pingSent;
}

alias GenericServerSocket!(IrcSocket) IrcServerSocket;

// use WormNET's set
const string IRC_NICK_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-`";
const string IRC_USER_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const string IRC_HOST_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.";
