/**
 * Various online blacklists client.
 *
 * Copyright 2008-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module Team15.Blacklists;

import std.string;
import Team15.ASockets;
//import std.c.socket;

string getIP(string hostname)
{
	try
		return (new InternetAddress(hostname, 0)).toAddrString;
	catch (Object o)
		return null;
}

int lookupAgainst(string ip, string db)
{
	string[] sections = split(ip, ".");
	assert(sections.length == 4);
	string addr = sections[3] ~ "." ~ sections[2] ~ "." ~ sections[1] ~ "." ~ sections[0] ~ "." ~ db;
	InternetHost ih = new InternetHost;
	if (ih.getHostByName(addr))
		return ih.addrList[0] & 0xFF;
	else
		return 0;
}

string lookupDroneBL(string ip)
{
	switch(lookupAgainst(ip, "dnsbl.dronebl.org"))
	{
		case  0: return null;
		case  2: return "Sample";
		case  3: return "IRC Drone";
		case  5: return "Bottler";
		case  6: return "Unknown spambot or drone";
		case  7: return "DDOS Drone";
		case  8: return "SOCKS Proxy";
		case  9: return "HTTP Proxy";
		case 10: return "ProxyChain";
		case 13: return "Brute force attackers";
		case 14: return "Open Wingate Proxy";
		case 15: return "Compromised router / gateway";
		default: return "Unknown";
	}
}

string lookupEfnetRBL(string ip)
{
	switch(lookupAgainst(ip, "rbl.efnetrbl.org"))
	{
		case  0: return null;
		case  1: return "Open Proxy";
		case  2: return "spamtrap666";
		case  3: return "spamtrap50";
		case  4: return "TOR";
		case  5: return "Drones / Flooding";
		default: return "Unknown";
	}
}

string[] blacklistCheck(string hostname)
{
	string ip = getIP(hostname);
	string result;

	result = lookupDroneBL(ip);
	if (result) return [result, "DroneBL"  , "http://dronebl.org/lookup?ip="~ip];

	result = lookupEfnetRBL(ip);
	if (result) return [result, "EFnet RBL", "http://rbl.efnetrbl.org/?i="  ~ip];

	return null;
}
