/**
 * Some code for fast data processing.
 *
 * Copyright 2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module Team15.Algorithm;

struct BulkAllocator(T, uint BLOCKSIZE, alias ALLOCATOR = HeapAllocator)
{
	struct BLOCK
	{
		T[BLOCKSIZE] data;
	}

	T*[] blocks;

	T* lastBlock;
	uint index = BLOCKSIZE;

	ALLOCATOR!(BLOCK) allocator;

	T* allocate()
	{
		if (index==BLOCKSIZE)
			newBlock();
		return lastBlock + index++;
	}

	void newBlock()
	{
		lastBlock = (allocator.allocate()).data.ptr;
		blocks ~= lastBlock;
		index = 0;
	}

	static if (is(typeof(&allocator.free)))
	{
		void freeAll()
		{
			foreach (block; blocks)
				allocator.free(cast(BLOCK*)block);
		}
	}
}

struct HeapAllocator(T)
{
	T* allocate()
	{
		return new T;
	}

	void free(T* v)
	{
		delete v;
	}
}

/// BulkAllocator adapter for HashTable
template HashTableBulkAllocator(uint BLOCKSIZE, alias ALLOCATOR = HeapAllocator)
{
	template HashTableBulkAllocator(T)
	{
		alias BulkAllocator!(T, BLOCKSIZE, ALLOCATOR) HashTableBulkAllocator;
	}
}

struct HashTable(K, V, uint SIZE, alias ALLOCATOR, string HASHFUNC="k")
{
	// HASHFUNC returns a hash, get its type
	alias typeof(((){ K k; return mixin(HASHFUNC); })()) H;
	static assert(is(H : ulong), "Numeric hash type expected");

	struct Item
	{
		K k;
		Item* next;
		V v;
	}
	Item*[SIZE] items;

	ALLOCATOR!(Item) allocator;

	V* get(K k)
	{
		auto h = mixin(HASHFUNC) % SIZE;
		auto item = items[h];
		while (item)
		{
			if (item.k == k)
				return &item.v;
			item = item.next;
		}
		return null;
	}

	V* add(K k)
	{
		auto h = mixin(HASHFUNC) % SIZE;
		auto newItem = allocator.allocate();
		newItem.k = k;
		newItem.next = items[h];
		items[h] = newItem;
		return &newItem.v;
	}

	V* getOrAdd(K k)
	{
		auto h = mixin(HASHFUNC) % SIZE;
		auto item = items[h];
		while (item)
		{
			if (item.k == k)
				return &item.v;
			item = item.next;
		}

		auto newItem = allocator.allocate();
		newItem.k = k;
		newItem.next = items[h];
		items[h] = newItem;
		return &newItem.v;
	}

	int opApply(int delegate(ref K, ref V) dg)
	{
		int result = 0;

		outerLoop:
		for (uint h=0; h<SIZE; h++)
		{
			auto item = items[h];
			while (item)
			{
				result = dg(item.k, item.v);
				if (result)
					break outerLoop;
				item = item.next;
			}
		}
		return result;
	}

	void freeAll()
	{
		static if (is(typeof(allocator.freeAll())))
			allocator.freeAll();
	}
}
