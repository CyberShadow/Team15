/**
 * Growable memory-mapped file.
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

module Team15.GMMF;

version(Windows)
{
	import std.c.windows.windows;
	import std.windows.charset;
	import std.windows.syserror;

	union LARGE_INTEGER {
		struct {
			uint LowPart;
			int  HighPart;
		}
		long QuadPart;
	}
	alias LARGE_INTEGER* PLARGE_INTEGER;

	union ULARGE_INTEGER {
		struct {
			uint LowPart;
			uint HighPart;
		}
		ulong QuadPart;
	}
	alias ULARGE_INTEGER* PULARGE_INTEGER;
	extern(Windows) BOOL GetFileSizeEx(HANDLE, PLARGE_INTEGER);
}
else
	static assert(0, "Non-Windows platforms not yet implemented");


// The offset of the actual end of the written data is stored in an unsigned
// long at the start of the file, because the length of the file will always
// be a BLOCK_SIZE multiple.

// Important! Pointers to data are not valid after an append/allocation.
final class GMMF
{
private:
	enum { BLOCK_SIZE = 4*1024*1024 }
	string filename;
	HANDLE hFile, hMapping;
	void* ptr;
	size_t size;

public:
	this(string filename)
	{
		this.filename = filename;

		hFile = wenforce(CreateFileA(
			toMBSz(filename),
			GENERIC_READ | GENERIC_WRITE,
			FILE_SHARE_READ,
			null,
			OPEN_ALWAYS,
			0,
			null
		), "Can't open file " ~ filename);
		scope(failure) close();

		LARGE_INTEGER liFileSize;
		wenforce(GetFileSizeEx(hFile, &liFileSize), "Can't get file size");
		long size = liFileSize.QuadPart;

		bool empty = size==0;
		if (empty)
		{
			size = ulong.sizeof;
			DWORD written;
			wenforce(WriteFile(hFile, &size, size.sizeof, &written, null), "Can't write file length");
		}
		if (size > size_t.max)
			throw new Exception("File size exceeds address space");
		map(cast(size_t)size);
	}

	~this()
	{
		if (ptr)
			unmap();
		if (hFile)
			close();
	}

	private void close()
	{
		wenforce(CloseHandle(hFile), "Can't close file");
	}

	private void map(size_t minSize)
	{
		size = (minSize+BLOCK_SIZE-1)&-BLOCK_SIZE;

		LARGE_INTEGER liSize;
		liSize.QuadPart = size;

		hMapping = wenforce(CreateFileMappingA(
			hFile,
			null,
			PAGE_READWRITE,
			liSize.HighPart,
			liSize.LowPart,
			null
		), "Can't map file");

		ptr = wenforce(MapViewOfFile(hMapping, FILE_MAP_ALL_ACCESS, 0, 0, 0), "Can't map view of file");
	}

	private void unmap()
	{
		wenforce(UnmapViewOfFile(ptr), "Can't unmap view of file");
		wenforce(CloseHandle(hMapping), "Can't unmap file");
		ptr = hMapping = null;
	}

	private size_t dataEnd() { return *(cast(size_t*)ptr); }
	private void dataEnd(size_t value) { *(cast(ulong*)ptr) = value; }

	public void* dataPtr() { return (cast(ulong*)ptr) + 1; }
	public size_t dataLength() { return dataEnd() - ulong.sizeof; }

	/// Warning: do not attempt to resize or append to this
	public void[] data() { return dataPtr[0..dataLength]; }

	public void* allocateBytes(size_t length)
	{
		size_t end = dataEnd();
		size_t newEnd = end + length;
		if (newEnd > size)
		{
			unmap();
			map(newEnd);
		}
		assert(newEnd <= size);
		dataEnd = newEnd;
		return cast(ubyte*)ptr + end;
	}

	public T* allocate(T)()
	{
		return cast(T*)allocateBytes(T.sizeof);
	}

	public void* append(void[] newData)
	{
		auto p = allocateBytes(newData.length);
		p[0..newData.length] = newData;
		return p;
	}
}

private T wenforce(T)(T x, string message)
{
	if (!x)
		throw new Exception(message ~ ": " ~ sysErrorString(GetLastError()));
	return x;
}
