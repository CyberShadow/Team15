/**
 * Simplistic command-line parsing.
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

module Team15.CommandLine;

import std.string;
import Team15.Logging;
public import Team15.Logging:Logger;

alias void delegate() SwitchProcessor;
alias void delegate(string value) OptionProcessor;
SwitchProcessor[string] longSwitchProcessors;
SwitchProcessor[char] shortSwitchProcessors;
OptionProcessor[string] longOptionProcessors;
OptionProcessor[char] shortOptionProcessors;
string[] arguments;

bool parsed = false;

static this()
{
	shortSwitchProcessors['q'] =
	longSwitchProcessors["quiet"] = {quiet = true;};
}

void parseCommandLine(string[] args)
{
	for (int n=1; n < args.length; n++)
	{
		string arg = args[n];
		if (arg.length>=2 && arg[0]=='-')
			if (arg[1]=='-')
			{
				if (arg.length==2) // --
				{
					arguments ~= args[n+1..$];
					return;
				}
				int eq = arg.find('=');
				arg = arg[2..$];
				if (eq>0)
				{
					string name = arg[0..eq];
					string value = arg[eq+1..$];
					if (name in longOptionProcessors)
						longOptionProcessors[name](value);
					else
						throw new Exception("Unrecognized option: --" ~ arg);
				}
				else
					if (arg in longSwitchProcessors)
						longSwitchProcessors[arg]();
					else
						throw new Exception("Unrecognized switch: --" ~ arg);
			}
			else
			{
				foreach (c; arg[1..$-1])
					if (c in shortSwitchProcessors)
						shortSwitchProcessors[c]();
					else
						throw new Exception("Unrecognized option: -" ~ c);

				char c = arg[$-1];
				if (c in shortSwitchProcessors)
					shortSwitchProcessors[c]();
				else
				if (c in shortOptionProcessors)
				{
					if (n < args.length-1)
						shortOptionProcessors[c](args[++n]);
					else
						throw new Exception("Expected parameter for option -" ~ c);
				}
				else
					throw new Exception("Unrecognized option: -" ~ c);
			}
		else
			arguments ~= arg;
	}
	parsed = true;
}

bool quiet;

// helper
Logger createLogger(string name)
{
	assert(parsed, "The command line hasn't been parsed!");
	if (quiet)
		return new FileLogger(name);
	else
		return new FileAndConsoleLogger(name);
}
