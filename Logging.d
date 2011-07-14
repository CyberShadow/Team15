/**
 * Logging support.
 *
 * Copyright 2007-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module Team15.Logging;

import std.stdio;
import std.date;
import std.string;
import std.file;
public import Team15.Utils;

int logFormatVersion = 0;

private string formatTime(d_time time)
{
	switch (logFormatVersion)
	{
		case 0:
			return std.date.toString(time);
		case 1:
		{
			auto s = fastDateToString(time);
			assert(s.length == 24);
			static assert(TicksPerSecond == 1000);
			return format("%s.%03d%s", s[0..19], time % TicksPerSecond, s[19..24]);
		}
		default:
			assert(0);
	}
}

private d_time getTimeForFileName()
{
	switch (logFormatVersion)
	{
		case 0:
			return UTCtoLocalTime(getFastUTCtime());
		case 1:
			return getFastUTCtime();
		default:
			assert(0);
	}
}

abstract class Logger
{
public:
	alias log opCall;

	this(string name)
	{
		this.name = name;
		open();
	}

	abstract Logger log(string str);

	void rename(string name)
	{
		close();
		this.name = name;
		open();
	}

	void close() {}

protected:
	string name;

	void open() {}
	void reopen() {}
}

class RawFileLogger : Logger
{
	bool timestampedFilenames;

	this(string name, bool timestampedFilenames = false)
	{
		this.timestampedFilenames = timestampedFilenames;
		super(name);
	}

	override Logger log(string str)
	{
		if (f is null) // hack
		{
			if (fileName is null)
				throw new Exception("Can't write to a closed log");
			reopen();
			RawFileLogger.log(str);
			close();
			return this;
		}
		fwrite(str.ptr, 1, str.length, f);
		fprintf(f, "\n");
		fflush(f);
		return this;
	}

protected:
	string fileName;
	FILE* f;

	override void open()
	{
		string path = "logs/" ~ name;
		int p = path.rfind('/');
		string baseName = path[p+1..$];
		path = path[0..p];
		string[] segments = path.split("/");
		foreach (i, segment; segments)
		{
			string subpath = segments[0..i+1].join("/");
			if (!exists(subpath))
				mkdir(subpath);
		}
		d_time t = getTimeForFileName();
		string timestamp = timestampedFilenames ? format(" %02d-%02d-%02d", HourFromTime(t), MinFromTime(t), SecFromTime(t)) : null;
		fileName = format("%s/%04d-%02d-%02d%s - %s.log", path, YearFromTime(t), MonthFromTime(t)+1, DateFromTime(t), timestamp, baseName);
		f = fopen(fileName.toStringz(), "at");
		if (f is null)
			throw new Exception("Can't open log file: " ~ fileName);
	}

	override void reopen()
	{
		f = fopen(fileName.toStringz(), "at".toStringz());
		if (f is null)
			throw new Exception("Can't open log: " ~ fileName);
	}
}

class FileLogger : RawFileLogger
{
	this(string name, bool timestampedFilenames = false)
	{
		super(name, timestampedFilenames);
	}

	override Logger log(string str)
	{
		d_time ut = getFastUTCtime();
		if (DateFromTime(getTimeForFileName()) != currentDate)
		{
			fwritefln(f, "\n---- (continued in next day's log) ----");
			fclose(f);
			open();
			fwritefln(f, "---- (continued from previous day's log) ----\n");
		}
		super.log("[" ~ formatTime(ut) ~ "] " ~ str);
		return this;
	}

	override void close()
	{
		//assert(f !is null);
		if(f !is null)
			fclose(f);
		f = null;
	}

private:
	int currentDate;

protected:
	final override void open()
	{
		super.open();
		currentDate = DateFromTime(getTimeForFileName());
		fwritef(f, "\n\n--------------- %s ---------------\n\n\n", formatTime(getFastUTCtime()));
	}

	final override void reopen()
	{
		super.reopen();
		fwritef(f, "\n\n--------------- %s ---------------\n\n\n", formatTime(getFastUTCtime()));
	}
}

class ConsoleLogger : Logger
{
	this(string name)
	{
		super(name);
	}

	override Logger log(string str)
	{
		string output = name ~ ": " ~ str ~ "\n";
		fwrite(output.ptr, 1, output.length, stdout);
		fflush(stdout);
		return this;
	}
}

class MultiLogger : Logger
{
	this(Logger[] loggers ...)
	{
		this.loggers = loggers.dup;
		super(null);
	}

	override Logger log(string str)
	{
		foreach (logger; loggers)
			logger.log(str);
		return this;
	}

	override void rename(string name)
	{
		foreach (logger; loggers)
			logger.rename(name);
	}

	override void close()
	{
		foreach (logger; loggers)
			logger.close();
	}

private:
	Logger[] loggers;
}

class FileAndConsoleLogger : MultiLogger
{
	this(string name)
	{
		super(new FileLogger(name), new ConsoleLogger(name));
	}
}
