/**
 * Generic class which reloads a file resource when it was changed on disk.
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

module Team15.CachedFile;

import std.date;
import std.file;
import std.stdio;
import std.string;
import Team15.Utils;

class CachedFile
{
	string fileName;
	d_time lastFtm;

	this(string fileName)
	{
		this.fileName = fileName;
		//reload();
	}

	void checkReload()
	{
		d_time ftm = getMTime(fileName);
		if (ftm != lastFtm)
			lastFtm = ftm,
			reload();
	}

	abstract void reload();
}

class CachedStringListFile : CachedFile
{
	protected string[] lines;

	this(string fileName)
	{
		super(fileName);
	}

	override void reload()
	{
		lines = splitlines(cast(string)read(fileName));
	}

	string[] getLines()
	{
		checkReload();
		return lines;
	}
}
