/**
 * Simple Gzip compression/decompression.
 *
 * Copyright 2007       Simon Arlott
 * Copyright 2007-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module Team15.Gzip;

static import zlib = Team15.Zlib;
static import stdcrc32 = crc32;
debug import std.stdio, std.file;
import Team15.Data;
import Team15.Utils;

private enum
{
	FTEXT = 1,
	FHCRC = 2,
	FEXTRA = 4,
	FNAME = 8,
	FCOMMENT = 16
}

uint crc32(void[] data)
{
	uint crc = stdcrc32.init_crc32();
	foreach(v;cast(ubyte[])data)
		crc = stdcrc32.update_crc32(v, crc);
	return ~crc;
}

Data compress(Data data)
{
	ubyte[] header;
	header.length = 10;
	header[0] = 0x1F;
	header[1] = 0x8B;
	header[2] = 0x08;
	header[3..8] = 0;  // TODO: set MTIME
	header[8] = 4;
	header[9] = 3;     // TODO: set OS
	uint[2] footer = [crc32(data.contents), data.length];
	Data compressed = zlib.compress(data, 9);
	return header ~ compressed[2..compressed.length-4] ~ cast(ubyte[])footer;
}

Data uncompress(Data data)
{
	enforce(data.length>=10, "Gzip too short");
	ubyte[] bytes = cast(ubyte[])data.contents;
	enforce(bytes[0] == 0x1F && bytes[1] == 0x8B, "Invalid Gzip signature");
	enforce(bytes[2] == 0x08, "Unsupported Gzip compression method");
	ubyte flg = bytes[3];
	enforce((flg & FHCRC)==0, "FHCRC not supported");
	enforce((flg & FEXTRA)==0, "FEXTRA not supported");
	enforce((flg & FCOMMENT)==0, "FCOMMENT not supported");
	uint start = 10;
	if (flg & FNAME)
	{
		while (bytes[start]) start++;
		start++;
	}
	Data uncompressed = zlib.uncompress(data[start..data.length-8], 0, -15);
	enforce(uncompressed.length == *cast(uint*)(&data.contents[$-4]), "Decompressed data length mismatch");
	return uncompressed;
}
