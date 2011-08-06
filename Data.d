/**
 * Wrapper for data located in external memory, to prevent faux references.
 *
 * Copyright 2009-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module Team15.Data;

static import std.c.stdlib;
import std.c.string : memmove;
static import std.gc;
import std.outofmemory;
debug import std.stdio;
debug import std.string;
debug import Team15.Utils;

/** Wrapper for data located in external memory, to prevent faux references.
	Represents a slice of data managed by a DataWrapper class.

	This class has been designed to be "safe" (and opaque) as long as the "contents" isn't accessed directly.
	Therefore, try to minimize direct access to contained data when possible.

	Be careful with assignments! Assigning a Data to a Data will copy a reference to the data reference,
	so a .clear on one reference will affect both. To create a shallow copy, use the [] operator: a = b[];

	Notes on accesing memory from a Data class directly:
	* concatenations (not appends) will work, but when using more than a few hundred bytes, better to use Data classes instead
	* appends to data contents will probably crash the runtime, or cause reallocs (both are to be avoided) - use Data classes instead
	* be sure not to lose Data references while using their contents!
**/

final class Data
{
private:
	/// Reference to the wrapper of the actual data.
	DataWrapper wrapper;
	/// Real allocated capacity. If 0, then contents represents a slice of memory owned by another Data class.
	size_t start, end;

	/// Maximum preallocation for append operations.
	enum { MAX_PREALLOC = 4*1024*1024 } // must be power of 2

	invariant
	{
		assert(wrapper !is null || end == 0);
		if (wrapper)
			assert(end <= wrapper.capacity);
		assert(start <= end);
	}

public:
	/// Create new instance with a copy of the given data.
	this(void[] data)
	{
		wrapper = new DataWrapper(data.length);
		start = 0;
		end = data.length;
		contents[] = data;
	}

	/// Create a new instance with given size/capacity. Capacity defaults to size.
	this(size_t size = 0, size_t capacity = 0)
	{
		if (!capacity)
			capacity = size;

		assert(size <= capacity);
		if (capacity)
			wrapper = new DataWrapper(capacity);
		else
			wrapper = null;
		start = 0;
		end = size;
	}

	/// Create new instance as a slice over an existing DataWrapper.
	private this(DataWrapper wrapper, size_t start = 0, size_t end = size_t.max)
	{
		this.wrapper = wrapper;
		this.start = start;
		this.end = end==size_t.max ? wrapper.capacity : end;
	}

	/// UNSAFE! Use only when you know there is only one reference to the data.
	void deleteContents()
	{
		delete wrapper;
		assert(wrapper is null);
		start = end = 0;
	}

	void clear()
	{
		wrapper = null;
		start = end = 0;
	}

	Data opCat(void[] data)
	{
		Data result = new Data(length + data.length);
		result.contents[0..this.length] = contents;
		result.contents[this.length..$] = data;
		return result;
	}

	Data opCat(Data data)
	{
		return this.opCat(data.contents);
	}

	Data opCat_r(void[] data)
	{
		Data result = new Data(data.length + length);
		result.contents[0..data.length] = data;
		result.contents[data.length..$] = contents;
		return result;
	}

	private static size_t getPreallocSize(size_t length)
	{
		if (length < MAX_PREALLOC)
			return nextPowerOfTwo(length);
		else
			return ((length-1) | (MAX_PREALLOC-1)) + 1;
	}

	/// Note that unlike opCat (a ~ b), opCatAssign (a ~= b) will preallocate.
	Data opCatAssign(void[] data)
	{
		if (data.length==0)
			return this;
		if (start==0 && wrapper && end + data.length <= wrapper.capacity)
		{
			wrapper.contents[end .. end + data.length] = data;
			end += data.length;
			return this;
		}
		else
		{
			// Create a new DataWrapper with all the data
			size_t newLength = length + data.length;
			size_t newCapacity = getPreallocSize(newLength);
			auto newWrapper = new DataWrapper(newCapacity);
			newWrapper.contents[0..this.length] = contents;
			newWrapper.contents[this.length..newLength] = data;

			wrapper = newWrapper;
			start = 0;
			end = newLength;

			return this;
		}
	}

	Data opCatAssign(Data data)
	{
		return this.opCatAssign(data.contents);
	}

	Data opCatAssign(ubyte value) // hack?
	{
		return this.opCatAssign((&value)[0..1]);
	}

	/// Inserts data at pos. Will preallocate, like opCatAssign.
	Data splice(size_t pos, void[] data)
	{
		if (data.length==0)
			return this;
		// 0 | start | start+pos | end | wrapper.capacity
		assert(pos <= length);
		if (start==0 && wrapper && end + data.length <= wrapper.capacity)
		{
			// overlapping array copy - use memmove
			auto splicePtr = cast(ubyte*)ptr + pos;
			memmove(splicePtr + data.length, splicePtr, length-pos);
			memmove(splicePtr, data.ptr, data.length);
			end += data.length;
			return this;
		}
		else
		{
			// Create a new DataWrapper with all the data
			size_t newLength = length + data.length;
			size_t newCapacity = getPreallocSize(newLength);
			auto newWrapper = new DataWrapper(newCapacity);
			newWrapper.contents[0..pos] = contents[0..pos];
			newWrapper.contents[pos..pos+data.length] = data;
			newWrapper.contents[pos+data.length..newLength] = contents[pos..$];

			wrapper = newWrapper;
			start = 0;
			end = newLength;

			return this;
		}
	}

	Data opSlice()  // duplicate reference, not content
	{
		return new Data(wrapper, start, end);
	}

	Data opSlice(size_t x, size_t y)
	{
		assert(x <= y);
		assert(y <= length);
		return new Data(wrapper, start + x, start + y);
	}

	void[] contents()
	{
		return wrapper ? wrapper.contents[start..end] : null;
	}

	void* ptr()
	{
		return contents.ptr;
	}

	size_t length()
	{
		return end - start;
	}

	void length(size_t value)
	{
		if (value == length) // no change
			return;
		if (value < length) // shorten
			end = start + value;
		else
		if (start==0 && start + value <= wrapper.capacity) // lengthen - with available space
			end = start + value;
		else // reallocate
		{
			auto newWrapper = new DataWrapper(value);
			newWrapper.contents[0..this.length] = contents;
			//(cast(ubyte[])newWrapper.contents)[this.length..value] = 0;

			wrapper = newWrapper;
			start = 0;
			end = value;
		}
	}

	Data dup()
	{
		return new Data(contents);
	}
}

// ************************************************************************

import std.stream;

Data readStreamData(Stream s)
{
	auto size = s.size - s.position;
	assert(size < size_t.max);
	auto data = new Data(cast(size_t)size);
	s.readExact(data.ptr, data.length);
	return data;
}

Data readData(string filename)
{
	scope file = new File(filename);
	scope(exit) file.close();
	return readStreamData(file);
}

// ************************************************************************

static size_t dataMemory, dataMemoryPeak;
static uint   dataCount, allocCount;

private:

version (Windows)
	import std.c.windows.windows;
else version (FreeBSD)
	import std.c.freebsd.freebsd;
else version (Solaris)
	import std.c.solaris.solaris;
else version (linux)
	import std.c.linux.linux;

/// Actual wrapper.
final class DataWrapper
{
	/// Pointer to actual data.
	final void* data;
	/// Allocated capacity.
	final size_t capacity;

	/// Threshold of allocated memory to trigger a collect.
	enum { COLLECT_THRESHOLD = 8*1024*1024 } // 8MB
	/// Counter towards the threshold.
	static size_t allocatedThreshold;

	/// Create a new instance with given capacity.
	this(size_t capacity)
	{
		data = malloc(capacity);
		if (data is null)
		{
			debug printf("Garbage collect triggered by failed Data allocation... ");
			//debug printStats();
			std.gc.fullCollect();
			//debug printStats();
			debug printf("Done\n");
			data = malloc(capacity);
			allocatedThreshold = 0;
		}
		if (data is null)
			_d_OutOfMemory();

		/*debug if (capacity > 32*1024*1024)
		{
			printf("Data - allocated %d bytes at %p\n", capacity, data);
			breakPoint();
		}*/
		debug if (capacity > 8*1024*1024)
		{
			printf("Data - allocated %d bytes at %p\n", capacity, data);
			stackTrace();
			printf("===============================================================================\n");
		}

		dataMemory += capacity;
		if (dataMemoryPeak < dataMemory)
			dataMemoryPeak = dataMemory;
		dataCount ++;
		allocCount ++;
		//debug printStats();

		this.capacity = capacity;

		// also collect
		allocatedThreshold += capacity;
		if (allocatedThreshold > COLLECT_THRESHOLD)
		{
			debug printf("Garbage collect triggered by total allocated Data exceeding threshold... ");
			std.gc.fullCollect();
			debug printf("Done\n");
			debug printStats();
			allocatedThreshold = 0;
		}
	}

	/// Destructor - destroys the wrapped data.
	~this()
	{
		free(data, capacity);
		data = null;
		// If DataWrapper is created and manually deleted, there is no need to cause frequent collections
		if (allocatedThreshold > capacity)
			allocatedThreshold -= capacity;
		else
			allocatedThreshold = 0;

		dataMemory -= capacity;
		dataCount --;
	}

	void[] contents()
	{
		return data[0..capacity];
	}

	static void printStats()
	{
		std.gc.GCStats stats;
		std.gc.getStats(stats);
		with(stats)
			printf("poolsize=%d, usedsize=%d, freeblocks=%d, freelistsize=%d, pageblocks=%d", poolsize, usedsize, freeblocks, freelistsize, pageblocks);
		printf(" | %d bytes in %d objects\n", dataMemory, dataCount);
	}

	version(Windows)
	{
		static size_t pageSize;

		static this()
		{
			SYSTEM_INFO si;
			GetSystemInfo(&si);
			pageSize = si.dwPageSize;
		}
	}
	else
	version(linux)
	{
		static size_t pageSize;

		static this()
		{
			version(linux) const _SC_PAGE_SIZE = 30;
			pageSize = sysconf(_SC_PAGE_SIZE);
		}
	}

	static void* malloc(ref size_t size)
	{
		if (is(typeof(pageSize)))
			size = ((size-1) | (pageSize-1))+1;

		version(Windows)
		{
			return VirtualAlloc(null, size, MEM_COMMIT, PAGE_READWRITE);
		}
		else
		version(Posix)
		{
			auto p = mmap(null, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
			return (p == MAP_FAILED) ? null : p;
		}
		else
			return std.c.malloc(size);
	}

	static void free(void* p, size_t size)
	{
		(cast(ubyte*)p)[0..size] = 0xBA;
		version(Windows)
			return VirtualFree(p, 0, MEM_RELEASE);
		else
		version(Posix)
			return munmap(p, size);
		else
			return std.c.free(size);
	}
}

// Source: http://bits.stephan-brumme.com/roundUpToNextPowerOfTwo.html
size_t nextPowerOfTwo(size_t x)
{
	x |= x >> 1;  // handle  2 bit numbers
	x |= x >> 2;  // handle  4 bit numbers
	x |= x >> 4;  // handle  8 bit numbers
	x |= x >> 8;  // handle 16 bit numbers
	x |= x >> 16; // handle 32 bit numbers
	static if (size_t.sizeof==8)
		x |= x >> 32; // handle 64 bit numbers
	x++;

	return x;
}

// Source: Win32 bindings project
version(Windows)
{
	struct SYSTEM_INFO {
		union {
			DWORD dwOemId;
			struct {
				WORD wProcessorArchitecture;
				WORD wReserved;
			}
		}
		DWORD dwPageSize;
		PVOID lpMinimumApplicationAddress;
		PVOID lpMaximumApplicationAddress;
		DWORD dwActiveProcessorMask;
		DWORD dwNumberOfProcessors;
		DWORD dwProcessorType;
		DWORD dwAllocationGranularity;
		WORD  wProcessorLevel;
		WORD  wProcessorRevision;
	}
	alias SYSTEM_INFO* LPSYSTEM_INFO;

	extern(Windows) VOID GetSystemInfo(LPSYSTEM_INFO);
}

version(Posix)
{
	extern (C) int sysconf(int);
}
