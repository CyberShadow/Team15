/**
 * An abstract class for timeouts.
 *
 * Copyright 2007-2010  Simon Arlott
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
 * The Team15 library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with the Team15 library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

module Team15.Timing;

import std.date;
import std.stdio;
import std.bind;

debug (REFCOUNT) import Team15.Utils;
import Team15.Utils : max, getFastUTCtime;

final static const d_time BACKGROUND_TASK_RESOLUTION = TicksPerSecond / 1000 * 5;

final class Timer {
private:
	TimerTask head;
	TimerTask tail;
	d_time last;
	long count;

	void add(TimerTask task, TimerTask start) {
		d_time now = getFastUTCtime();

		if (start !is null)
			assert(start.owner is this);

		task.owner = this;
		task.prev = null;
		task.next = null;
		task.remaining = task.timeout;

		// The Timer's reference time hasn't changed,
		// so extra time will pass for this task the
		// next time prod() runs. Add the offset from
		// the last run to compensate.
		if (now > last)
			task.remaining += now - last;

		TimerTask tmp = start is null ? head : start;

		while (tmp !is null) {
			if (tmp.remaining > task.remaining) {
				task.next = tmp;
				task.prev = tmp.prev;
				if (tmp.prev)
					tmp.prev.next = task;
				tmp.prev = task;
				break;
			}
			tmp = tmp.next;
		}

		if (tmp is null) {
			if (head !is null) {
				tail.next = task;
				task.prev = tail;
				tail = task;
			} else {
				head = task;
				tail = task;
			}
		} else if (tmp is head)
			head = task;

		assert(head is null || head.prev is null);
		assert(tail is null || tail.next is null);
		count++;
	}

public:
	this() {
		debug (REFCOUNT) refcount("Timing/Timer",1);

		last = getFastUTCtime();
	}

	~this() {
		debug (REFCOUNT) refcount("Timing/Timer",0);
	}

	void prod() {
		d_time now = getFastUTCtime();
		d_time diff = now - last;
		last = now;
		if (diff < 0) {
			writefln("%d: Time went backward %d tick%s!", now, -diff, -diff==1?"":"s");
		} else if (diff > 0) {
			debug (TIMER_VERBOSE) writefln("%d: Time went forward %d tick%s for %d task%s.", now, diff, diff==1?"":"s", count, count==1?"":"s");
			if (head !is null) {
				for (TimerTask task = head; task !is null; task = task.next)
					task.remaining -= diff;

				while (head !is null && head.remaining <= 0) {
					TimerTask task = head;
					remove(head);
					debug (TIMER) writefln("%d: Firing a task that waited for %d of %d tick%s.", now, task.timeout - task.remaining, task.timeout, task.timeout==1?"":"s");
					if (task.handleTask)
						task.handleTask(this, task);
				}

				debug (TIMER_VERBOSE) if (head !is null) writefln("Current task is waiting for %d tick%s, %d remaining.", head.timeout, head.timeout==1?"":"s", head.remaining);
			}
		}
	}

	void add(TimerTask task) {
		debug (TIMER_VERBOSE) writefln("Adding a task which waits for %d tick%s.", task.timeout, task.timeout==1?"":"s");
		assert(task.owner is null);
		add(task, null);
		assert(task.owner is this);
		assert(head !is null);
	}

	void restart(TimerTask task) {
		TimerTask tmp;

		assert(task.owner is this);
		debug (TIMER_VERBOSE) writefln("Restarting a task which waits for %d tick%s and had %d remaining.", task.timeout, task.timeout==1?"":"s", task.remaining);

		// Store current position, as the new position must be after it
		tmp = task.next !is null ? task.next : task.prev;

		remove(task);
		assert(task.owner is null);

		add(task, tmp);
		assert(task.owner is this);
	}

	void remove(TimerTask task) {
		debug (TIMER_VERBOSE) writefln("Removing a task which waits for %d tick%s.", task.timeout, task.timeout==1?"":"s");
		assert(task.owner is this);
		if (task is head) {
			if (head.next) {
				head = head.next;
				head.prev = null;
				debug (TIMER_VERBOSE) writefln("Removed current task, next task is waiting for %d tick%s, %d remaining.", head.timeout, head.timeout==1?"":"s", head.remaining);
			} else {
				debug (TIMER_VERBOSE) writefln("Removed last task.");
				assert(tail is task);
				head = tail = null;
			}
		} else if (task is tail) {
			tail = task.prev;
			if (tail)
				tail.next = null;
		} else {
			TimerTask tmp = task.prev;
			if (task.prev)
				task.prev.next = task.next;
			if (task.next) {
				task.next.prev = task.prev;
				task.next = tmp;
			}
		}
		task.owner = null;
		task.next = task.prev = null;
		count--;
	}

	d_time nextEvent() {
		if (head is null)
			return -1;

		assert(head.remaining >= 0);
		d_time now = getFastUTCtime();
		if (now > last)
			return max(0, head.remaining - (now - last));
		else
			return head.remaining;
	}

	debug invariant
	{
		if (head is null)
		{
			assert(tail is null);
			assert(count == 0);
		}
		else
		{
			TimerTask t = head;
			assert(t.prev is null);
			int n=1;
			while (t.next)
			{
				assert(t.owner is this);
				auto next = t.next;
				assert(t is next.prev);
				assert(t.remaining <= next.remaining);
				t = next;
				n++;
			}
			assert(t.owner is this);
			assert(t is tail);
			assert(count == n);
		}
	}
}

class TimerTask {
private:
	Timer owner;
	TimerTask prev;
	TimerTask next;

	d_time remaining;
	d_time timeout;

public:
	this(d_time delay) {
		debug (REFCOUNT) refcount("Timing/TimerTask",1);

		assert(delay > 0);
		timeout = delay;
	}

	~this() {
		debug (REFCOUNT) refcount("Timing/TimerTask",0);
	}

	bool isWaiting() {
		return owner !is null;
	}

	d_time getDelay() {
		return timeout;
	}

	void setDelay(d_time delay) {
		assert(delay > 0);
		assert(owner is null);
		timeout = delay;
	}

	void delegate(Timer timer, TimerTask task) handleTask;
}

final class BackgroundTimer {
private:
	d_time processingDuration;

public:
	IncrementalTask[] tasks;

	this(d_time processingDuration) {
		debug (REFCOUNT) refcount("Timing/BackgroundTimer",1);

		assert(processingDuration > 0);
		this.processingDuration = processingDuration;
	}

	~this() {
		debug (REFCOUNT) refcount("Timing/BackgroundTimer",0);
	}

	bool prod(d_time maxDuration) {
		if (maxDuration >= 0 && maxDuration < processingDuration)
			return false;

		if (tasks.length > 0)
			tasks[0].run(processingDuration);

		if (tasks.length > 1) {
			if (tasks[0].finished) {
				tasks = tasks[1..$];
				debug (TIMER) writefln("Incremental task completed; %d task%s waiting.", tasks.length, tasks.length==1?"":"s");
			} else
				tasks = tasks[1..$] ~ tasks[0];
		} else if (tasks[0].finished) {
			tasks = [];
			debug (TIMER) writefln("Incremental task completed; %d task%s waiting.", tasks.length, tasks.length==1?"":"s");
		}

		return true;
	}

	void add(IncrementalTask task) {
		debug (TIMER) writefln("Adding an incremental task; %d task%s waiting.", tasks.length, tasks.length==1?"":"s");

		foreach(existingTask;tasks)
			assert(task !is existingTask);

		tasks ~= task;
	}

	void remove(IncrementalTask task) {
		debug (TIMER) writefln("Removing an incremental task; %d task%s waiting.", tasks.length, tasks.length==1?"":"s");

		IncrementalTask[] tmp;
		foreach(existingTask;tasks)
			if (task !is existingTask)
				tmp ~= existingTask;

		assert(tasks.length == tmp.length+1);
		tasks = tmp;
	}

	bool waiting() {
		return tasks.length > 0;
	}
}

interface IncrementalTask {
	void run(d_time maxDuration=-1);
	bool finished();
}

/// The default timer
Timer mainTimer;

/// The background timer
BackgroundTimer bgTimer;

static this() {
	mainTimer = new Timer();
	bgTimer = new BackgroundTimer(BACKGROUND_TASK_RESOLUTION);
}

struct TimeOut
{
	private	d_time last;
	public bool opCall(int seconds)
	{
		d_time now = getFastUTCtime();
		if((now-last) / TicksPerSecond >= seconds)
		{
			last = now;
			return true;
		}
		else
			return false;
	}
}

/// Shorthand to creating a timer task with a delay
void setTimeout(void delegate() fn, d_time delay)
{
	auto task = new TimerTask(delay);
	task.handleTask = bind((Timer timer, TimerTask task, void delegate() fn) { fn(); }, _0, _1, fn).ptr;
	mainTimer.add(task);
}

/// Utility class to prevent executing several duplicate actions within the same time span.
class Throttle
{
	final bool opCall(string id, d_time span)
	{
		d_time now = getUTCtime();
		if (id in ids && now-ids[id] < span)
			return false;
		ids[id] = now;
		return true;
	}

	private d_time[string] ids;
}
