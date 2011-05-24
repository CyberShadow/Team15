/**
 * Some common utility code.
 *
 * Copyright 2007-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
 * Copyright 2008       Stéphan Kochen <stephan@kochen.nl>
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

module Team15.Utils;

import std.string;
import std.compiler : version_major;
import std.utf;

static if(!is(string)) alias char[] string;  // GDC hack
static if(!is(wstring)) alias wchar[] wstring;  // for Tangobos
static if(!is(dstring)) alias dchar[] dstring;  // ditto

debug (REFCOUNT) static int[string] refcounts;
debug (REFCOUNT) static int[string] total_refcounts;
debug (REFCOUNT) static int[string] max_refcounts;

debug (REFCOUNT) static void refcount(string name, int type) {
	if (type == 1)
		refcounts[name]++;
	else
		refcounts[name]--;
	total_refcounts[name]++;
	if (!(name in max_refcounts) || max_refcounts[name] < refcounts[name])
		max_refcounts[name] = refcounts[name];
}

T[] toArray(T)(inout T data)
{
	return (&data)[0..1];
}

// ************************************************************************

template CommonType(T...)
{
	static if (T.length == 1)
		alias T[0] CommonType;
	else
	static if (T.length == 2)
		alias typeof(T[0].init<T[1].init?T[0].init:T[1].init) CommonType;
	else
		alias CommonType!(T[0], CommonType!(T[1..$])) CommonType;
}

CommonType!(T) min(T...)(T arg)
{
	static if (arg.length==0)
		static assert(0);
	else
	static if (arg.length==1)
		return arg[0];
	else
	static if (arg.length==2)
		return arg[0]<arg[1] ? arg[0] : arg[1];
	else
		return min(min(arg[0..$/2]), min(arg[$/2..$]));
}

CommonType!(T) max(T...)(T arg)
{
	static if (arg.length==0)
		static assert(0);
	else
	static if (arg.length==1)
		return arg[0];
	else
	static if (arg.length==2)
		return arg[0]>arg[1] ? arg[0] : arg[1];
	else
		return max(max(arg[0..$/2]), max(arg[$/2..$]));
}

T abs(T)(T x) { return x<0?-x:x; }
T sqr(T)(T x) { return x*x; }

/// compile-time version of toString
/// BUGS: doesn't work with negative numbers
public char[] ctToString(int i)
{
	char[][] numbers = [ "0"[],"1","2","3","4","5","6","7","8","9" ];

	char[] ret;
	do
	{
		ret = numbers[i%10] ~ ret;
		i /= 10;
	} while (i);

	return ret;
}

bool inArray(T)(T[] arr, T val)
{
	foreach (v; arr)
		if (v == val)
			return true;
	return false;
}

/// Get a value from an AA, with a fallback default value
V aaGet(K, V)(V[K] aa, K key, V def)
{
	auto p = key in aa;
	if (p)
		return *p;
	else
		return def;
}

V[K] aaDup(K, V)(V[K] aa)
{
	V[K] result;
	foreach (k, ref v; aa)
		result[k] = v;
	return result;
}


T[][] newMatrix(T)(size_t x, size_t y)
{
	T[] container = new T[x*y];
	T[][] result = new T[][x];
	size_t p = 0;
	foreach (ref r; result)
	{
		size_t p2 = p + y;
		r = container[p..p2];
		p = p2;
	}
	return result;
}

// ************************************************************************

int stringDistance(string s, string t)
{
	int n=s.length;
	int m=t.length;
	if(n == 0) return m;
	if(m == 0) return n;
	int[][] distance = newMatrix!(int)(n+1, m+1); // matrix
	int cost=0;
	//init1
	for(int i=0; i <= n; i++) distance[i][0]=i;
	for(int j=0; j <= m; j++) distance[0][j]=j;
	//find min distance
	for(int i=1; i <= n; i++)
		for(int j=1; j <= m;j++)
		{
			cost=(t[j-1] == s[i-1] ? 0 : 1);
			distance[i][j] = min(distance[i - 1][j] + 1, distance[i][j - 1] + 1, distance[i - 1][j - 1] + cost);
		}
	return distance[n][m];
}

float stringSimilarity(string string1, string string2)
{
	float dis=stringDistance(string1, string2);
	float maxLen=string1.length;
	if (maxLen < string2.length)
		maxLen = string2.length;
	if (maxLen == 0.0F)
		return 1.0F;
	else
		return 1.0F - dis/maxLen;
}

string selectBestFrom(string[] items, string target, float threshold = 0.7)
{
	string found = null;
	float best = 0;

	foreach(item;items)
	{
		float match = stringSimilarity(tolower(item),tolower(target));
		if(match>threshold && match>=best)
		{
			best = match;
			found = item;
		}
	}

	return found;
}

bool startsWith(string str, string start)
{
	return str.length >= start.length && str[0..start.length]==start;
}

bool istartsWith(string str, string start)
{
	int startlen = start.utflen();
	return str.utflen() >= startlen && icmp(str.subutf(0, startlen), start)==0;
}

bool endsWith(string str, string end)
{
	return str.length >= end.length && str[$-end.length..$]==end;
}

import std.c.string;

bool containsOnly(string s, string chars)
{
	foreach (c; s)
		if (!memchr(chars.ptr, c, chars.length))
			return false;
	return true;
}

string listToString(string[] list)
{
	if (list.length)
		return list.join(", ");
	else
		return "None";
}

import std.random;

string randomString(int length=20, string chars="abcdefghijklmnopqrstuvwxyz")
{
	string result;
	for (int i=0; i<length; i++)
		result ~= chars[rand()%chars.length];
	return result;
}

string repeatReplace(string s, string from, string to)
{
	string old;
	do
	{
		old = s;
		s = s.replace(from, to);
	} while (old != s);
	return s;
}

T* unmanagedDup(T)(T[] arr)
{
	T* p = cast(T*)std.c.stdlib.malloc(arr.length);
	p[0..arr.length] = arr[];
	return p;
}

// ************************************************************************

string hexDump(void[] b)
{
	auto data = cast(ubyte[]) b;
	int i=0;
	string s;
	while(i<data.length)
	{
		s ~= format("%08X:  ", i);
		for(int x=0;x<16;x++)
		{
			if(i+x<data.length)
				s ~= format("%02X ", data[i+x]);
			else
				s ~= "   ";
			if(x==7)
				s ~= "| ";
		}
		s ~= "  ";
		for(int x=0;x<16;x++)
		{
			if(i+x<data.length)
				if(data[i+x]==0)
					s ~= ' ';
				else
				if(data[i+x]<32 || data[i+x]>=128)
					s ~= '.';
				else
					s ~= cast(char)data[i+x];
			else
				s ~= ' ';
		}
		s ~= \n;
		i += 16;
	}
	return s;
}

ushort reverse(ushort x)
{
	return cast(ushort) ((x<<8)|(x>>>8));
}

uint reverse(uint x)
{
	return
		(((x      ) & 0xFF) << 24) |
		(((x >>  8) & 0xFF) << 16) |
		(((x >> 16) & 0xFF) <<  8) |
		(((x >> 24)       )      ) ;
}

version(LittleEndian)
{
	uint fromLE(uint x) { return x; }
	ushort fromLE(ushort x) { return x; }
	uint fromBE(uint x) { return reverse(x); }
	ushort fromBE(ushort x) { return reverse(x); }
}
else
{
	uint fromLE(uint x) { return reverse(x); }
	ushort fromLE(ushort x) { return reverse(x); }
	uint fromBE(uint x) { return x; }
	ushort fromBE(ushort x) { return x; }
}
alias fromLE toLE;
alias fromBE toBE;

uint fromHex(string s)
{
	uint n = 0;
	while (s.length)
	{
		int d;
		switch (s[0])
		{
			case '0':           d =  0; break;
			case '1':           d =  1; break;
			case '2':           d =  2; break;
			case '3':           d =  3; break;
			case '4':           d =  4; break;
			case '5':           d =  5; break;
			case '6':           d =  6; break;
			case '7':           d =  7; break;
			case '8':           d =  8; break;
			case '9':           d =  9; break;
			case 'a': case 'A': d = 10; break;
			case 'b': case 'B': d = 11; break;
			case 'c': case 'C': d = 12; break;
			case 'd': case 'D': d = 13; break;
			case 'e': case 'E': d = 14; break;
			case 'f': case 'F': d = 15; break;
			default: assert(0);
		}
		s = s[1..$];
		n = (n << 4) + d;
	}
	return n;
}

uint[256] crc32_table = [
	0x00000000,0x77073096,0xee0e612c,0x990951ba,0x076dc419,0x706af48f,0xe963a535,0x9e6495a3,0x0edb8832,0x79dcb8a4,0xe0d5e91e,0x97d2d988,0x09b64c2b,0x7eb17cbd,0xe7b82d07,0x90bf1d91,
	0x1db71064,0x6ab020f2,0xf3b97148,0x84be41de,0x1adad47d,0x6ddde4eb,0xf4d4b551,0x83d385c7,0x136c9856,0x646ba8c0,0xfd62f97a,0x8a65c9ec,0x14015c4f,0x63066cd9,0xfa0f3d63,0x8d080df5,
	0x3b6e20c8,0x4c69105e,0xd56041e4,0xa2677172,0x3c03e4d1,0x4b04d447,0xd20d85fd,0xa50ab56b,0x35b5a8fa,0x42b2986c,0xdbbbc9d6,0xacbcf940,0x32d86ce3,0x45df5c75,0xdcd60dcf,0xabd13d59,
	0x26d930ac,0x51de003a,0xc8d75180,0xbfd06116,0x21b4f4b5,0x56b3c423,0xcfba9599,0xb8bda50f,0x2802b89e,0x5f058808,0xc60cd9b2,0xb10be924,0x2f6f7c87,0x58684c11,0xc1611dab,0xb6662d3d,
	0x76dc4190,0x01db7106,0x98d220bc,0xefd5102a,0x71b18589,0x06b6b51f,0x9fbfe4a5,0xe8b8d433,0x7807c9a2,0x0f00f934,0x9609a88e,0xe10e9818,0x7f6a0dbb,0x086d3d2d,0x91646c97,0xe6635c01,
	0x6b6b51f4,0x1c6c6162,0x856530d8,0xf262004e,0x6c0695ed,0x1b01a57b,0x8208f4c1,0xf50fc457,0x65b0d9c6,0x12b7e950,0x8bbeb8ea,0xfcb9887c,0x62dd1ddf,0x15da2d49,0x8cd37cf3,0xfbd44c65,
	0x4db26158,0x3ab551ce,0xa3bc0074,0xd4bb30e2,0x4adfa541,0x3dd895d7,0xa4d1c46d,0xd3d6f4fb,0x4369e96a,0x346ed9fc,0xad678846,0xda60b8d0,0x44042d73,0x33031de5,0xaa0a4c5f,0xdd0d7cc9,
	0x5005713c,0x270241aa,0xbe0b1010,0xc90c2086,0x5768b525,0x206f85b3,0xb966d409,0xce61e49f,0x5edef90e,0x29d9c998,0xb0d09822,0xc7d7a8b4,0x59b33d17,0x2eb40d81,0xb7bd5c3b,0xc0ba6cad,
	0xedb88320,0x9abfb3b6,0x03b6e20c,0x74b1d29a,0xead54739,0x9dd277af,0x04db2615,0x73dc1683,0xe3630b12,0x94643b84,0x0d6d6a3e,0x7a6a5aa8,0xe40ecf0b,0x9309ff9d,0x0a00ae27,0x7d079eb1,
	0xf00f9344,0x8708a3d2,0x1e01f268,0x6906c2fe,0xf762575d,0x806567cb,0x196c3671,0x6e6b06e7,0xfed41b76,0x89d32be0,0x10da7a5a,0x67dd4acc,0xf9b9df6f,0x8ebeeff9,0x17b7be43,0x60b08ed5,
	0xd6d6a3e8,0xa1d1937e,0x38d8c2c4,0x4fdff252,0xd1bb67f1,0xa6bc5767,0x3fb506dd,0x48b2364b,0xd80d2bda,0xaf0a1b4c,0x36034af6,0x41047a60,0xdf60efc3,0xa867df55,0x316e8eef,0x4669be79,
	0xcb61b38c,0xbc66831a,0x256fd2a0,0x5268e236,0xcc0c7795,0xbb0b4703,0x220216b9,0x5505262f,0xc5ba3bbe,0xb2bd0b28,0x2bb45a92,0x5cb36a04,0xc2d7ffa7,0xb5d0cf31,0x2cd99e8b,0x5bdeae1d,
	0x9b64c2b0,0xec63f226,0x756aa39c,0x026d930a,0x9c0906a9,0xeb0e363f,0x72076785,0x05005713,0x95bf4a82,0xe2b87a14,0x7bb12bae,0x0cb61b38,0x92d28e9b,0xe5d5be0d,0x7cdcefb7,0x0bdbdf21,
	0x86d3d2d4,0xf1d4e242,0x68ddb3f8,0x1fda836e,0x81be16cd,0xf6b9265b,0x6fb077e1,0x18b74777,0x88085ae6,0xff0f6a70,0x66063bca,0x11010b5c,0x8f659eff,0xf862ae69,0x616bffd3,0x166ccf45,
	0xa00ae278,0xd70dd2ee,0x4e048354,0x3903b3c2,0xa7672661,0xd06016f7,0x4969474d,0x3e6e77db,0xaed16a4a,0xd9d65adc,0x40df0b66,0x37d83bf0,0xa9bcae53,0xdebb9ec5,0x47b2cf7f,0x30b5ffe9,
	0xbdbdf21c,0xcabac28a,0x53b39330,0x24b4a3a6,0xbad03605,0xcdd70693,0x54de5729,0x23d967bf,0xb3667a2e,0xc4614ab8,0x5d681b02,0x2a6f2b94,0xb40bbe37,0xc30c8ea1,0x5a05df1b,0x2d02ef8d,
];

uint fastCRC(void[] data) // the standard Phobos crc32 function relies on inlining for usable performance
{
	uint crc = cast(uint)-1;
	foreach (val; cast(ubyte[])data)
		crc = crc32_table[cast(ubyte) crc ^ val] ^ (crc >> 8);
	return crc;
}

uint murmurHash2(void[] data, uint seed=0)
{
	enum { m = 0x5bd1e995, r = 24 }
	uint len = cast(uint)data.length;
	uint h = seed ^ len;
	ubyte* p = cast(ubyte*)data.ptr;

	while (len >= 4)
	{
		uint k = *cast(uint*)p;

		k *= m;
		k ^= k >> r;
		k *= m;

		h *= m;
		h ^= k;

		p += 4;
		len -= 4;
	}

	switch(len)
	{
	case 3: h ^= p[2] << 16;
	case 2: h ^= p[1] << 8;
	case 1: h ^= p[0];
	/*   */ h *= m;
	case 0: break;
	default: assert(0);
	};

	// Do a few final mixes of the hash to ensure the last few
	// bytes are well-incorporated.

	h ^= h >> 13;
	h *= m;
	h ^= h >> 15;

	return h;
}

// ************************************************************************

/// Get the number of characters (not code points) in a string
size_t utflen(string s)
{
	return toUCSindex(s, s.length);
}

/// String slice, but measuring characters and not code points
string subutf(string s, size_t start, size_t end)
{
	return s[toUTFindex(s, start)..toUTFindex(s, end)];
}

/// convert any data to valid UTF-8, so D's string functions can properly work on it
string rawToUTF8(string s)
{
	dstring d;
	foreach (char c; s)
		d ~= c;
	return toUTF8(d);
}

string UTF8ToRaw(string r)
{
	string s;
	foreach (dchar c; r)
	{
		assert(c < '\u0100');
		s ~= c;
	}
	return s;
}

unittest
{
	char[1] c;
	for (int i=0; i<256; i++)
	{
		c[0] = cast(char)i;
		assert(UTF8ToRaw(rawToUTF8(c[])) == c[]);
	}
}

string nullStringTransform(string s) { return s.dup; }

// ************************************************************************

// fake data access for Valgrind
debug(Valgrind)
{
	import std.stdio;

	void validate(void[] arr)
	{
		validateArr(cast(ubyte[])arr);
	}

	void validateArr(T)(T[] arr)
	{
		writefln("Validating ", arr.ptr, " (", arr.length*arr[0].sizeof, " bytes)");
		int n=0;
		foreach(i,elem;arr)
		{
			//writefln(i);
			writef(i);
			if(elem == elem.init)
				n++;
			writefln(" - ", elem);
		}
		if(n<0) arr[0]=arr[0].init;
		writefln();
	}

	void validateData(T)(ref T value)
	{
		validate(toBuffer(value));
	}
}

// ************************************************************************

/// Stolen/adapted from D2 Phobos
private import std.date : d_time, TicksPerSecond;
static import std.file;

version(Windows)
{
	static import std.c.windows.windows;
	import std.c.windows.windows : FILETIME, BOOL, HANDLE;
	import std.windows.charset : toMBSz;
	extern(Windows) BOOL SetFileTime(HANDLE, FILETIME *,FILETIME *,FILETIME *);

	enum : ulong { ticksFrom1601To1970 = 11_644_473_600UL * TicksPerSecond }

	FILETIME d_time2FILETIME(d_time dt)
	{
		static assert(10_000_000 >= TicksPerSecond);
		static assert(10_000_000 % TicksPerSecond == 0);
		ulong t = (dt + ticksFrom1601To1970) * (10_000_000 / TicksPerSecond);
		FILETIME result = void;
		result.dwLowDateTime = cast(uint) (t & uint.max);
		result.dwHighDateTime = cast(uint) (t >> 32);
		return result;
	}

	d_time FILETIME2d_time(FILETIME* ft)
	{
		auto ftl = *cast(long*)ft;
		return ftl / (10_000_000 / TicksPerSecond) - ticksFrom1601To1970;
	}

	void setTimes(in char[] name, d_time fta, d_time ftm)
	{
		auto ta = d_time2FILETIME(fta);
		auto tm = d_time2FILETIME(ftm);
		with(std.c.windows.windows)
		{
			auto h = std.file.useWfuncs
				? CreateFileW(std.utf.toUTF16z(name), GENERIC_WRITE, 0, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, HANDLE.init)
				: CreateFileA(toMBSz(name),           GENERIC_WRITE, 0, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, HANDLE.init);
			if (h == INVALID_HANDLE_VALUE)
				throw new std.file.FileException(name, GetLastError());
			scope(exit) CloseHandle(h);
			if (!SetFileTime(h, null, &ta, &tm))
				throw new std.file.FileException(name, GetLastError());
		}
	}
}

version(linux)
{
	import std.c.linux.linux : timeval;

	extern(C) int utimes(in char*, in timeval[2]);

	void setTimes(in char[] name, d_time fta, d_time ftm)
	{
		timeval[2] t = void;
		t[0].tv_sec = cast(int)(fta / TicksPerSecond);
		t[0].tv_usec = cast(int)
			(cast(long) ((cast(double) fta / TicksPerSecond)
					* 1_000_000) % 1_000_000);
		t[1].tv_sec = cast(int)(ftm / TicksPerSecond);
		t[1].tv_usec = cast(int)
			(cast(long) ((cast(double) ftm / TicksPerSecond)
					* 1_000_000) % 1_000_000);
		if (utimes(toStringz(name), t) != 0)
			throw new Exception("utimes failed");
	}
}

d_time getMTime(string name)
{
	version(Windows)
	{
		WIN32_FIND_DATAW wfd;
		auto h = FindFirstFileW(std.utf.toUTF16z(name), &wfd);
		enforce(h!=INVALID_HANDLE_VALUE, "FindFirstFile");
		FindClose(h);
		return FILETIME2d_time(&wfd.ftLastWriteTime);
	}
	else
	{
		d_time ftc, fta, ftm;
		std.file.getTimes(name, ftc, fta, ftm);
		return ftm;
	}
}

private import std.date : MakeDate, MakeDay, MakeTime, TicksPerHour;
private import std.conv : toInt;
private import std.c.time;

version(Windows)
{
	private import std.c.windows.windows : LPCSTR;
	extern(Windows) BOOL SetEnvironmentVariableA(LPCSTR, LPCSTR);
}
static this()
{
	version(Posix)
		std.c.stdlib.setenv("TZ", "UTC", 1);
	else
	version(Windows)
		SetEnvironmentVariableA("TZ", "UTC");
}

/// A wrapper around mktime.
/// This takes UTC time values (it depends on the setenv above).
time_t makeUnixTime(int year, int month, int day, int hour, int minute, int second)
{
	tm t;
	t.tm_year  = year-1900;
	t.tm_mon   = month;
	t.tm_mday  = day;
	t.tm_hour  = hour;
	t.tm_min   = minute;
	t.tm_sec   = second;
	t.tm_isdst = -1;
	auto a = mktime(&t);
	lazyEnforce(a != -1, format("mktime failed: %d.%02d.%02d %02d:%02d:%02d", year, month+1, day, hour, minute, second));
	debug
	{
		//auto t2 = localtime(&a);
		auto t2 = gmtime(&a);
		assert(t.tm_year == t2.tm_year);
		assert(t.tm_mon  == t2.tm_mon );
		assert(t.tm_mday == t2.tm_mday);
		assert(t.tm_hour == t2.tm_hour);
		assert(t.tm_min  == t2.tm_min );
		assert(t.tm_sec  == t2.tm_sec );
	}
	return a;
}

/// std.date.MakeDate alternative using C time functions.
/// This takes UTC time values (it depends on the setenv above).
/// Warning: like with MakeDate, month is 0..11!
d_time fastMakeDate(int year, int month, int day, int hour, int minute, int second)
{
	return makeUnixTime(year, month, day, hour, minute, second) * cast(d_time)TicksPerSecond;
}

/// Quickly parse a date in the format generated by std.date.toString.
d_time fastDateParse(string line)
{
	// 012345678901234567890123456789012
	// Thu Aug 09 09:17:15 GMT+0300 2007

	assert(line.length == 33);

	int year   = toInt(line[29..33]);
	int month;
	switch (line[4..7])
	{
		case "Jan": month =  0; break;
		case "Feb": month =  1; break;
		case "Mar": month =  2; break;
		case "Apr": month =  3; break;
		case "May": month =  4; break;
		case "Jun": month =  5; break;
		case "Jul": month =  6; break;
		case "Aug": month =  7; break;
		case "Sep": month =  8; break;
		case "Oct": month =  9; break;
		case "Nov": month = 10; break;
		case "Dec": month = 11; break;
		default: assert(0);
	}
	int day    = toInt(line[ 8..10]);
	int hour   = toInt(line[11..13]);
	int minute = toInt(line[14..16]);
	int second = toInt(line[17..19]);
	int tz     = toInt(line[23..26]);

	//return MakeDate(
	//	MakeDay (year, month, day),
	//	MakeTime(hour, minute, second, 0)
	//) - tz * TicksPerHour;
	return fastMakeDate(
		year, month, day,
		hour, minute, second
	) - tz * TicksPerHour;
}

/// Quickly format a Unix time to some human-readable format.
string fastUnixTimeToString(time_t time)
{
	//return toString(ctime(&time))[0..$-1];
	return toString(asctime(gmtime(&time)))[0..$-1];
}

/// Quickly format a d_time to a string (not necessarily same format as std.date.toString).
string fastDateToString(d_time date)
{
	return fastUnixTimeToString(cast(time_t)(date / TicksPerSecond));
}

/// Parse a date in the format generated by fastDateToString.
d_time fastUnixDateParse(string line)
{
	// 012345678901234567890123
	// Sun Nov 14 20:45:17 2010

	assert(line.length == 24);
	if (line[8]==' ')
		line[8] = '0';
	return fastDateParse(line[0..20] ~ "GMT+0000 " ~ line[20..24]);
}

d_time getFastUTCtime()
{
	version(Windows)
	{
		FILETIME ft;
		GetSystemTimeAsFileTime(&ft);
		return FILETIME2d_time(&ft);
	}
	else
	{
		/*timeval t;
		gettimeofday(&t, null);
		return t.tv_sec * cast(d_time)TicksPerSecond;*/
		return std.date.getUTCtime(); // TODO
	}
}

// ************************************************************************

void safeWrite(string fn, void[] data)
{
	std.file.write(fn ~ ".tmp", data);
	if (std.file.exists(fn)) std.file.remove(fn);
	std.file.rename(fn ~ ".tmp", fn);
}

// ************************************************************************

final class PersistentStringSet
{
	this(string filename)
	{
		this.filename = filename;

		if (std.file.exists(filename))
		{
			foreach(line;splitlines(cast(string)std.file.read(filename)))
				set[line] = true;
			set = set.rehash;
		}
	}

	bool* opIn_r(string key)
	{
		return key in set;
	}

	void opIndexAssign(bool value, string key)
	{
		set[key] = value;
		save();
	}

	void remove(string key)
	{
		set.remove(key);
		save();
	}

	size_t length()
	{
		return set.length;
	}

private:
	bool[string] set;
	string filename;

	void save()
	{
		std.file.write(filename, join(set.keys,newline));
	}
}

// ************************************************************************

version(Windows)
{
	import std.c.windows.windows : SetConsoleCP, SetConsoleOutputCP;
	static this()
	{
		SetConsoleCP(65001);
		SetConsoleOutputCP(65001);
	}
}

// ************************************************************************

version(Windows)
{
	import std.c.windows.windows;
	extern(Windows) void OutputDebugStringA(char* str);
}

void stackTrace()
{
	version(Windows) // ddbg must be running
	{
		OutputDebugStringA(toStringz("Ddbg: us; r"));
		MessageBeep(0);
	}
}

void breakPoint()
{
	version(Windows) // ddbg must be running
		OutputDebugStringA(toStringz("Ddbg: us"));
	asm { int 3; }
}

void enforce(bool condition, /*lazy*/ string message = "Precondition failed")
{
	if (!condition)
		throw new Exception(message);
}

void lazyEnforce(bool condition, lazy string message = "Precondition failed")
{
	if (!condition)
		throw new Exception(message);
}

// ************************************************************************

/// Much faster version of std.file.listdir, which does not waste time on expensive date conversion
version(Windows)
{
	string[] fastlistdir(string pathname)
	{
		string[] result;
		string c;
		HANDLE h;

		c = std.path.join(pathname, "*.*");
		WIN32_FIND_DATAW fileinfo;

		h = FindFirstFileW(std.utf.toUTF16z(c), &fileinfo);
		if (h != INVALID_HANDLE_VALUE)
		{
			try
			{
				do
				{
					// Skip "." and ".."
					if (std.string.wcscmp(fileinfo.cFileName.ptr, ".") == 0 ||
						std.string.wcscmp(fileinfo.cFileName.ptr, "..") == 0)
						continue;

					size_t clength = std.string.wcslen(fileinfo.cFileName.ptr);
					result ~= std.utf.toUTF8(fileinfo.cFileName[0 .. clength]);
				} while (FindNextFileW(h,&fileinfo) != FALSE);
			}
			finally
			{
				FindClose(h);
			}
		}
		return result;
	}
}
else
version (linux)
{
	private import std.c.stdlib : getErrno;
	private import std.c.linux.linux : DIR, dirent, opendir, readdir, closedir;

	string[] fastlistdir(string pathname)
	{
		string[] result;
		DIR* h;
		dirent* fdata;

		h = opendir(toStringz(pathname));
		if (h)
		{
			try
			{
				while((fdata = readdir(h)) != null)
				{
					// Skip "." and ".."
					if (!std.c.string.strcmp(fdata.d_name.ptr, ".") ||
						!std.c.string.strcmp(fdata.d_name.ptr, ".."))
							continue;

					size_t len = std.c.string.strlen(fdata.d_name.ptr);
					result ~= fdata.d_name[0 .. len].dup;
				}
			}
			finally
			{
				closedir(h);
			}
		}
		else
		{
			throw new std.file.FileException(pathname, getErrno());
		}
		return result;
	}
}
else
	alias std.file.listdir fastlistdir;

// ************************************************************************

static import std.process;

string run(string command)
{
	static int counter;
	if (!std.file.exists("data"    )) std.file.mkdir("data");
	if (!std.file.exists("data/tmp")) std.file.mkdir("data/tmp");
	string tempfn = "data/tmp/run-" ~ .toString(rand()) ~ "-" ~ .toString(counter++) ~ ".txt"; // HACK
	version(Windows)
		std.process.system(command ~ " 2>&1 > " ~ tempfn);
	else
		std.process.system(command ~ " &> " ~ tempfn);
	string result = cast(string)std.file.read(tempfn);
	std.file.remove(tempfn);
	return result;
}

string escapeShellArg(string s)
{
	string r;
	foreach (c; s)
		if (c=='\'')
			r ~= `'\''`;
		else
			r ~= c;
	return '\'' ~ r ~ '\'';
}

string run(string[] args)
{
	string[] escaped;
	foreach (ref arg; args)
		escaped ~= escapeShellArg(arg);
	return run(escaped.join(" "));
}

// ************************************************************************

static import std.uri;

string shortenURL(string url)
{
	if (std.file.exists("data/bitly.txt"))
		return strip(download(format("http://api.bitly.com/v3/shorten?%s&longUrl=%s&format=txt&domain=j.mp", cast(string)std.file.read("data/bitly.txt"), std.uri.encodeComponent(url))));
	else
		return url;
}

string download(string url, string postprocess = null)
{
	return run(`wget -q --no-check-certificate -O - "`~url~`"` ~ postprocess);
}
