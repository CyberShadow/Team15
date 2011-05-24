/**
 * Wrapper for Data class, allowing an object to be swapped to disk
 * and automatically retreived as required.
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

module Team15.SwappedData;

import Team15.Data;
import Team15.Utils;
import std.file;
import std.string;
debug(SwappedData) import Team15.Logging;

final class SwappedData
{
	Data _data;
	string fileName;
	char* cFileName;

	private static const MIN_SIZE = 4096; // minimum size to swap out

	debug(SwappedData) private static Logger log;

	this(string fileName)
	{
		debug(SwappedData) { if (log is null) log = new FileAndConsoleLogger("SwappedData"); log(fileName ~ " - Creating"); }
		this.fileName = fileName;
		this.cFileName = unmanagedDup(fileName ~ \0);
		if (exists(fileName))
			remove(fileName);
	}

	void unload()
	{
		if (_data && _data.length >= MIN_SIZE)
		{
			debug(SwappedData) log(fileName ~ " - Unloading");
			write(fileName, _data.contents);
			_data = null;
		}
	}

	bool isLoaded()
	{
		return !exists(fileName);
	}

	// Getter
	Data data()
	{
		if (!_data)
		{
			debug(SwappedData) log(fileName ~ " - Reloading");
			if (!exists(fileName))
				return null;
			_data = readData(fileName);
			remove(fileName);
		}
		return _data;
	}

	// Setter
	void data(Data data)
	{
		debug(SwappedData) log(fileName ~ " - Setting");
		if (exists(fileName))
			remove(fileName);
		_data = data;
	}

	size_t length()
	{
		if (_data)
			return _data.length;
		else
		if (exists(fileName))
			return cast(size_t)getSize(fileName);
		else
			return 0;
	}

	~this()
	{
		//debug(SwappedData) log(fileName ~ " - Destroying");
		/*if (exists(fileName))
		{
			debug(SwappedData) log(fileName ~ " - Deleting");
			remove(fileName);
		}*/
		std.c.stdio.unlink(cFileName);
		std.c.stdlib.free(cFileName);
	}
}
