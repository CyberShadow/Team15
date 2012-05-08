/**
 * Asynchronous socket abstraction.
 *
 * Copyright 2006       Stéphan Kochen <stephan@kochen.nl>
 * Copyright 2006-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
 * Copyright 2007       Vincent Povirk <madewokherd@gmail.com>
 * Copyright 2007-2010  Simon Arlott
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

module Team15.ASockets;

import Team15.Timing;
import Team15.Data;

import std.string;
import Team15.std_socket;
import std.date;
debug import std.stdio;
public import Team15.Utils;  // for "buffer"
version (Windows) // IPv6 support requires OS-level access since Phobos support is non-existent
	import Team15.std_c_windows_winsock;
else
	import std.c.linux.socket;
//debug import Team15.cn.kuehne.flectioned;
import std.c.stdlib : getErrno;

public import Team15.std_socket : InternetAddress, InternetHost, Socket;
alias std.string.toString toString;

enum { NI_MAXHOST = 1025, NI_MAXSERV = 32 }
version (Windows)
	enum { NI_NUMERICHOST = 0x02, NI_NUMERICSERV = 0x08 }
else
version (linux)
	enum { NI_NUMERICHOST = 0x01, NI_NUMERICSERV = 0x02 }
else
	static assert(0, "Platform unsupported");

version(Win32) import Team15.std_c_windows_winsock : FD_SETSIZE;
version(linux) import std.c.linux.linux     : FD_SETSIZE;

version (Win32)
{
	pragma(lib, "ws2_32.lib");
	pragma(lib, "Team15\\ws2_32x.lib"); // local library for missing IPv6 functions

	import std.c.windows.windows;
	alias OVERLAPPED* LPWSAOVERLAPPED;
	alias void function(DWORD, DWORD, LPWSAOVERLAPPED, DWORD) LPWSAOVERLAPPED_COMPLETION_ROUTINE;
	extern(Windows) int WSAIoctl(socket_t, DWORD, LPVOID, DWORD, LPVOID, DWORD, LPDWORD, LPWSAOVERLAPPED, LPWSAOVERLAPPED_COMPLETION_ROUTINE);
	const int IOC_VENDOR = 0x18000000;
	const int SIO_KEEPALIVE_VALS = IOC_IN | IOC_VENDOR | 4;
	struct tcp_keepalive {
		ULONG onoff;
		ULONG keepalivetime;
		ULONG keepaliveinterval;
	}
}

version (linux)
{
	const SO_KEEPALIVE  = cast(SocketOption) 9;

	const TCP_KEEPIDLE  = cast(SocketOption) 4;        /* Start keeplives after this period */
	const TCP_KEEPINTVL = cast(SocketOption) 5;        /* Interval between keepalives */
	const TCP_KEEPCNT   = cast(SocketOption) 6;        /* Number of keepalives before death */
}

//debug = Valgrind;

/// Flags that determine socket wake-up events.
private struct PollFlags
{
	/// Wake up when socket is readable.
	bool read;
	/// Wake up when socket is writable.
	bool write;
	/// Wake up when an error occurs on the socket.
	bool error;
}

int eventCounter;

private final class SocketManager
{
private:
	/// List of all sockets to poll.
	GenericSocket[] sockets;

private:
	/// Register a socket with the manager.
	void register(GenericSocket conn)
	{
		if (sockets.length == FD_SETSIZE)
		{
			conn.conn.close();
			throw new Exception("Too many sockets"); // FIXME (somehow)
		}
		sockets ~= conn;
	}

	/// Unregister a socket with the manager.
	void unregister(GenericSocket conn)
	{
		foreach (size_t i, GenericSocket j; sockets)
			if (j is conn)
			{
				sockets = sockets[0 .. i] ~ sockets[i + 1 .. sockets.length];
				break;
			}
	}

public:
	this()
	{
		debug (REFCOUNT) refcount("ASockets/SocketManager",1);
	}

	~this()
	{
		debug (REFCOUNT) refcount("ASockets/SocketManager",0);
	}

	int size()
	{
		return sockets.length;
	}

	/// Loop continuously until no sockets are left.
	void loop()
	{
		SocketSet readset, writeset, errorset;
		size_t sockcount;
		readset = new SocketSet();
		writeset = new SocketSet();
		errorset = new SocketSet();
		while (true)
		{
			static long getWait()
			{
				long waitMain = mainTimer.nextEvent();
				long waitIdle = idleTimer.nextEvent();
				long wait = -1;

				if (waitMain >= 0 && waitIdle >= 0)
					wait = min(waitMain, waitIdle);
				else if (waitMain >= 0)
					wait = waitMain;
				else if (waitIdle >= 0)
					wait = waitIdle;

				return wait;
			}

			long wait = getWait();

			// if bg task is waiting, try and do something in the time available
			if (bgTimer.waiting)
				if (bgTimer.prod(wait))
					// if anything happened, adjust wait time appropriately
					if (bgTimer.waiting)
						wait = 0;
					else
						wait = getWait();

			assert(wait >= -1);
			if (wait > 0) {
				wait *= 1000000 / TicksPerSecond;
				if (wait < 0 || wait > int.max)
					wait = int.max;
			}

			// SocketSet.add() doesn't have an overflow check, so we need to do it manually
			// this is just a debug check, the actual check is done when registering sockets
			if (sockets.length > readset.max || sockets.length > writeset.max || sockets.length > errorset.max)
			{
				/*
				readset  = new SocketSet(sockets.length*2);
				writeset = new SocketSet(sockets.length*2);
				errorset = new SocketSet(sockets.length*2);
				*/ // VP 2009.02.21: does not work, sadly - we are still bounded by the OS FD_SETSIZE
				assert(0, "Too many sockets");
			}
			else
			{
				readset.reset();
				writeset.reset();
				errorset.reset();
			}

			sockcount = 0;
			debug (VERBOSE) writefln("Populating sets");
			foreach (GenericSocket conn; sockets)
			{
				if (!conn.socket)
					continue;
				sockcount++;

				debug (VERBOSE) writef("\t%s:", cast(void*)conn);
				PollFlags flags = conn.pollFlags();
				if (flags.read)
				{
					readset.add(conn.socket);
					debug (VERBOSE) writef(" READ");
				}
				if (flags.write)
				{
					writeset.add(conn.socket);
					debug (VERBOSE) writef(" WRITE");
				}
				if (flags.error)
				{
					errorset.add(conn.socket);
					debug (VERBOSE) writef(" ERROR");
				}
				debug (VERBOSE) writefln();
			}
			debug (VERBOSE) { writefln("Waiting..."); fflush(stdout); }
			if (sockcount == 0 && wait == -1)
				break;

			int events;
			if (wait == -1)
				events = Socket.select(readset, writeset, errorset);
			else
				events = Socket.select(readset, writeset, errorset, cast(int) wait);

			mainTimer.prod();

			if (events > 0)
			{
				foreach (GenericSocket conn; sockets)
				{
					if (!conn.socket)
						continue;
					if (readset.isSet(conn.socket))
					{
						debug (VERBOSE) writefln("\t%s is readable", cast(void*)conn);
						conn.onReadable();
					}

					if (!conn.socket)
						continue;
					if (writeset.isSet(conn.socket))
					{
						debug (VERBOSE) writefln("\t%s is writable", cast(void*)conn);
						conn.onWritable();
					}

					if (!conn.socket)
						continue;
					if (errorset.isSet(conn.socket))
					{
						debug (VERBOSE) writefln("\t%s is errored", cast(void*)conn);
						conn.onError("select() error");
					}
				}
			}

			idleTimer.prod();
			eventCounter++;
		}
	}
}

enum DisconnectType
{
	Requested, // initiated by the application
	Graceful,  // peer gracefully closed the connection
	Error      // abnormal network condition
}

/// General methods for an asynchronous socket
private abstract class GenericSocket
{
protected:
	/// The socket this class wraps.
	Socket conn;

protected:
	/// Retrieve the socket class this class wraps.
	final Socket socket()
	{
		return conn;
	}

	/// Retrieve the poll flags for this socket.
	PollFlags pollFlags()
	{
		PollFlags flags;
		flags.read = flags.write = flags.error = false;
		return flags;
	}

	void onReadable()
	{
	}

	void onWritable()
	{
	}

	void onError(string reason)
	{
	}

public:
	/// allow getting the address of connections that are already disconnected
	private string cachedAddress = null;

	this()
	{
		debug (REFCOUNT) refcount("ASockets/GenericSocket",1);
	}

	~this()
	{
		debug (REFCOUNT) refcount("ASockets/GenericSocket",0);
	}

	final string remoteAddress()
	{
		if(cachedAddress !is null)
			return cachedAddress;
		else
		if(conn is null)
			return "(null)";
		else
		try
		{
			char[NI_MAXHOST] hbuf;
			char[NI_MAXSERV] sbuf;
			ubyte[1024] sa;
			int length = sa.length;
			sa[] = 0;

			if (getpeername(conn.handle, cast(sockaddr*)sa.ptr, &length) != 0)
				throw new Exception("getpeername-error-" ~ .toString(getErrno));

			int ret = getnameinfo(cast(sockaddr*)sa.ptr, length, hbuf.ptr, hbuf.sizeof, sbuf.ptr, sbuf.sizeof, NI_NUMERICHOST|NI_NUMERICSERV);
			if (ret != 0)
				throw new Exception("getnameinfo-error-" ~ .toString(ret));
			else
				return cachedAddress=.toString(hbuf.ptr) ~ ":" ~ .toString(sbuf.ptr);
		}
		catch(Exception e)
			return e.msg;
	}

	final string remoteIP()
	{
		string addr = remoteAddress();
		int pos=addr.rfind(':');
		if(pos<0)
			return addr;
		else
			return addr[0..pos];
	}

	final void setKeepAlive(bool enabled=true, int time=10, int interval=5)
	{
		assert(conn);
		version(Windows)
		{
			tcp_keepalive options;
			options.onoff = enabled?1:0;
			options.keepalivetime = time * 1000;
			options.keepaliveinterval = interval * 1000;
			uint cbBytesReturned;
			if (WSAIoctl(conn.handle, SIO_KEEPALIVE_VALS, &options, options.sizeof, null, 0, &cbBytesReturned, null, null))
				throw new Exception("WSAIoctl error: " ~ .toString(WSAGetLastError));
			//debug writefln("Keepalive set");
		}
		else
		version(linux)
		{
			conn.setOption(SocketOptionLevel.TCP, TCP_KEEPIDLE, time);
			conn.setOption(SocketOptionLevel.TCP, TCP_KEEPINTVL, interval);
			conn.setOption(SocketOptionLevel.SOCKET, SO_KEEPALIVE, true);
		}
		else
			assert(0, "Not supported");
	}

	final void setNagle(bool enabled=false)
	{
		assert(conn);
		conn.setOption(SocketOptionLevel.TCP, SocketOption.TCP_NODELAY, enabled);
	}
}


/// An asynchronous client socket.
class ClientSocket : GenericSocket
{
private:
	TimerTask idleTask;

public:
	/// Whether the socket is connected.
	bool connected;

protected:
	/// The send buffer.
	Data outBuffer;
	/// Queue indices (for low-priority data)
	int[] queueIndices;
	/// Whether a disconnect as pending after all data is sent
	bool disconnecting;

protected:
	/// Constructor used by a ServerSocket for new connections
	this(Socket conn)
	{
		this();
		this.conn = conn;
		connected = !(conn is null);
		if(connected)
			socketManager.register(this);
	}

protected:
	/// Retrieve the poll flags for this socket.
	override PollFlags pollFlags()
	{
		PollFlags flags;

		flags.error = true;

		if (!connected || outBuffer.length > 0)
			flags.write = true;

		if (connected && handleReadData)
			flags.read = true;

		return flags;
	}

	/// Called when a socket is readable.
	override void onReadable()
	{
		static ubyte[0x10000] inBuffer;
		int received = conn.receive(inBuffer);
		debug (VERBOSE) writefln("\t\t%s: %d bytes received", cast(void*)this, received);

		if (received == 0)
		{
			outBuffer.clear;
			disconnect("Connection closed", DisconnectType.Graceful);
			return;
		}

		if (received == Socket.ERROR)
			onError(getSocketException("Read error").msg);
		else
			if (!disconnecting && handleReadData)
				handleReadData(this, inBuffer[0 .. received]);
	}

	/// Called when a socket is writable.
	override void onWritable()
	{
		if (!connected)
		{
			connected = true;
			//debug writefln("[%s] Connected", remoteAddress);
			try
				setKeepAlive(),
				setNagle();
			catch(Exception e)
				return disconnect(e.msg, DisconnectType.Error);
			if (idleTask !is null)
				idleTimer.add(idleTask);
			if (handleConnect)
				handleConnect(this);
			return;
		}
		//debug writefln(remoteAddress(), ": Writable - handler ", handleBufferFlushed?"OK":"not set", ", outBuffer.length=", outBuffer.length);


		debug (VERBOSE) writefln("\t\t%s: %d bytes to send", cast(void*)this, outBuffer.length);
		while(outBuffer.length>0)
		{
			int amount = queueIndices.length?queueIndices[0]?queueIndices[0]:queueIndices.length>1?queueIndices[1]:outBuffer.length:outBuffer.length;
			int sent = conn.send(outBuffer.contents[0..amount]);
			//debug writefln(remoteAddress(), ": Sent ", sent, "/", amount, "/", outBuffer.length);
			debug (VERBOSE) writefln("\t\t%s: sent %d/%d bytes", cast(void*)this, sent, amount);
			if (sent == Socket.ERROR)
			{
				if (wouldBlock()) // why would this happen?
					return;
				else
					onError(getSocketException("Write error").msg);
			}
			else
			if (sent == 0)
				return;
			else
			{
				//debug writefln("[%s] Sent data:", remoteAddress);
				//debug writefln("%s", hexDump(outBuffer[0..sent]));
				outBuffer = outBuffer[sent .. outBuffer.length];
				if (outBuffer.length == 0)
					outBuffer.clear;
				foreach(ref index;queueIndices)
					index -= sent;
				while(queueIndices.length>0 && queueIndices[0]<0)
					queueIndices = queueIndices[1..$];
			}
		}

		if (outBuffer.length == 0)
		{
			if (handleBufferFlushed)
				handleBufferFlushed(this);
			if (disconnecting)
				disconnect("Delayed disconnect - buffer flushed", DisconnectType.Requested);
		}
	}

	/// Called when an error occurs on the socket.
	override void onError(string reason)
	{
		outBuffer.clear;
		disconnect("Socket error: " ~ reason, DisconnectType.Error);
	}

	final void onTask_Idle(Timer timer, TimerTask task)
	{
		if(!connected)
			return;

		if(disconnecting)
		{
			outBuffer.clear;
			disconnect("Delayed disconnect - time-out", DisconnectType.Error);
			return;
		}

		if(handleIdleTimeout)
		{
			handleIdleTimeout(this);
			if (connected && !disconnecting)
			{
				assert(!idleTask.isWaiting());
				idleTimer.add(idleTask);
			}
		}
		else
			disconnect("Time-out", DisconnectType.Error);
	}

public:
	/// Default constructor
	this()
	{
		debug (VERBOSE) writefln("New ClientSocket @ %s", cast(void*)this);
		outBuffer = new Data;
		debug (REFCOUNT) refcount("ASockets/ClientSocket",1);
	}

	~this()
	{
		debug (REFCOUNT) refcount("ASockets/ClientSocket",0);
	}

	/// Start establishing a connection.
	final void connect(string host, ushort port)
	{
		if(conn || connected)
			throw new Exception("Socket object is already connected");

		conn = new Socket(cast(AddressFamily)AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
		conn.blocking = false;

		try
		{
			InternetAddress address = new InternetAddress(host, port);
			conn.connect(address);
		}
		catch(Object o)
		{
			onError("Connect error: " ~ o.toString());
			return;
		}

		socketManager.register(this);
	}

	const DefaultDisconnectReason = "Software closed the connection";

	/// Close a connection. If there is queued data waiting to be sent, wait until it is sent before disconnecting.
	void disconnect(string reason = DefaultDisconnectReason, DisconnectType type = DisconnectType.Requested)
	{
		assert(conn);

		if (outBuffer.length && type==DisconnectType.Requested)
		{
			// queue disconnect after all data is sent
			//debug writefln("[%s] Queueing disconnect: ", remoteAddress, reason);
			disconnecting = true;
			setIdleTimeout(30 * TicksPerSecond);
			if (handleDisconnect)
				handleDisconnect(this, reason, type);
			return;
		}

		//debug writefln("[%s] Disconnecting: %s", remoteAddress, reason);
		socketManager.unregister(this);
		conn.close();
		conn = null;
		outBuffer.clear;
		connected = false;
		if (idleTask !is null && idleTask.isWaiting())
			idleTimer.remove(idleTask);
		if (handleDisconnect && !disconnecting)
			handleDisconnect(this, reason, type);
	}

	/// Append data to the send buffer, before the low-priority data.
	final void send(void[] data)
	{
		//assert(connected);
		if(!connected || disconnecting)
		{
			//debug writefln("Not connected when trying to send buffer to " ~ remoteAddress() ~ ":" ~ hexDump(data));
			return;
		}
		//debug(Valgrind) validate(data);
		if(queueIndices.length==0)
			outBuffer ~= data;
		else
		{
			//debug writefln(remoteAddress(), ": Inserting ", data.length, " bytes into the queue");
			int pos = queueIndices[0];
			//outBuffer = outBuffer[0..pos] ~ data ~ outBuffer[pos..outBuffer.length];
			outBuffer.splice(pos, data);
			foreach(ref index;queueIndices)
				index += data.length;
		}
	}

	/// Append data to the send buffer, in a low-priority queue.
	final void queue(void[] data)
	{
		assert(connected);
		if(data.length==0) return;
		//debug writefln(remoteAddress(), ": Queuing ", data.length, " bytes");
		//debug(Valgrind) validate(data);
		queueIndices ~= outBuffer.length;
		outBuffer ~= data;
	}

	final void clearQueue()
	{
		if(queueIndices.length>0)
		{
			outBuffer = outBuffer[0..queueIndices[0]];
			queueIndices = null;
		}
	}

	final bool queuePresent()
	{
		return queueIndices.length>0;
	}

	void cancelIdleTimeout()
	{
		assert(idleTask !is null);
		assert(idleTask.isWaiting());
		idleTimer.remove(idleTask);
	}

	void resumeIdleTimeout()
	{
		assert(connected);
		assert(idleTask !is null);
		assert(!idleTask.isWaiting());
		idleTimer.add(idleTask);
	}

	final void setIdleTimeout(d_time duration)
	{
		assert(duration > 0);
		if (idleTask is null)
		{
			idleTask = new TimerTask(duration);
			idleTask.handleTask = &onTask_Idle;
		}
		else
		{
			if (idleTask.isWaiting())
				idleTimer.remove(idleTask);
			idleTask.setDelay(duration);
		}
		if (connected)
			idleTimer.add(idleTask);
	}

	void markNonIdle()
	{
		assert(idleTask !is null);
		if (idleTask.isWaiting())
			idleTimer.restart(idleTask);
	}

	final bool isConnected()
	{
		return connected;
	}

public:
	/// Callback for when a connection has been established.
	void delegate(ClientSocket sender) handleConnect;
	/// Callback for when a connection was closed.
	void delegate(ClientSocket sender, string reason, DisconnectType type) handleDisconnect;
	/// Callback for when a connection has stopped responding.
	void delegate(ClientSocket sender) handleIdleTimeout;
	/// Callback for incoming data.
	void delegate(ClientSocket sender, void[] data) handleReadData;
	/// Callback for when the send buffer has been flushed.
	void delegate(ClientSocket sender) handleBufferFlushed;
}

/// An asynchronous server socket.
final class GenericServerSocket(T : ClientSocket)
{
private:
	/// Class that actually performs listening on a certain address family
	final class Listener : GenericSocket
	{
		this(Socket conn)
		{
			debug (VERBOSE) writefln("New Listener @ %s", cast(void*)this);
			this.conn = conn;
			socketManager.register(this);
		}

		/// Retrieve the poll flags for this socket.
		override PollFlags pollFlags()
		{
			PollFlags flags;

			flags.error = true;
			flags.read = handleAccept !is null;

			return flags;
		}

		/// Called when a socket is readable.
		override void onReadable()
		{
			Socket acceptSocket = conn.accept();
			acceptSocket.blocking = false;
			if (handleAccept)
			{
				T connection = new T(acceptSocket);
				connection.setKeepAlive();
				connection.setNagle();
				//assert(connection.connected);
				//connection.connected = true;
				handleAccept(connection);
			}
			else
				acceptSocket.close();
		}

		/// Called when a socket is writable.
		override void onWritable()
		{
		}

		/// Called when an error occurs on the socket.
		override void onError(string reason)
		{
			close(); // call parent
		}

		void closeListener()
		{
			assert(conn);
			socketManager.unregister(this);
			conn.close();
			conn = null;
		}
	}

	/// Whether the socket is listening.
	bool listening;
	/// Listener instances
	Listener[] listeners;

public:
	/// Debugging aids
	ushort port;
	string addr;

	this()
	{
		debug (REFCOUNT) refcount("ASockets/GenericServerSocket",1);
	}

	~this()
	{
		debug (REFCOUNT) refcount("ASockets/GenericServerSocket",0);
	}

	/// Start listening on this socket.
	ushort listen(ushort port, string addr = null)
	{
		//debug writefln("Listening on %s:%d", addr, port);
		assert(!listening);

		addrinfo hints;
		addrinfo* res, cur;
		int status, ret, i;
		char* service = toStringz(.toString(port));

		hints.ai_flags = AI_PASSIVE;
		hints.ai_family = AF_UNSPEC;
		hints.ai_socktype = SOCK_STREAM;
		hints.ai_protocol = IPPROTO_TCP;

		ret = getaddrinfo(addr ? toStringz(addr) : null, service, &hints, &res);
		if (ret != 0)
			throw new Exception("getaddrinfo failed");
		scope(exit) freeaddrinfo(res);

		for (cur = res; cur != null; cur = cur.ai_next)
		{
			if (cur.ai_family != AF_INET && port == 0)
				continue;  // listen on random ports only on IPv4 for now

			version(Windows) enum { IPV6_V6ONLY = 27 }

			char[NI_MAXHOST] hbuf;
			char[NI_MAXSERV] sbuf;
			int one = 1;
			int flags;
			Socket conn;

			ret = getnameinfo(cur.ai_addr, cur.ai_addrlen, hbuf.ptr, hbuf.sizeof, sbuf.ptr, sbuf.sizeof, NI_NUMERICHOST|NI_NUMERICSERV);
			if (ret != 0) {
				hbuf[0] = 0;
				sbuf[0] = 0;
			}

			try
			{
				conn = new Socket(cast(AddressFamily)cur.ai_family, cast(SocketType)cur.ai_socktype, cast(ProtocolType)cur.ai_protocol);
				conn.blocking = false;
				if (cur.ai_family == AF_INET6)
					conn.setOption(SocketOptionLevel.IPV6, cast(SocketOption)IPV6_V6ONLY, 1);
				conn.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);

				ret = bind(conn.handle, cur.ai_addr, cur.ai_addrlen);
				if (ret != 0)
					throw new Exception("Bind failed");

				conn.listen(8);
				if (cur.ai_family == AF_INET)
					port = (cast(InternetAddress)conn.localAddress).port;

				listeners ~= new Listener(conn);
			}
			catch(Object o)
			{
				if (hbuf[0] != 0 && sbuf[0] != 0)
					debug writefln("Unable to listen node \"%s\" service \"%s\"", .toString(hbuf.ptr), .toString(sbuf.ptr));
				debug writefln(o.toString);
			}
		}

		if (listeners.length==0)
			throw new Exception("Unable to bind service");

		this.port = port;
		this.addr = addr;

		return port;
	}

	/// Stop listening on this socket.
	void close()
	{
		foreach(listener;listeners)
			listener.closeListener();
		listeners = null;
		listening = false;
		if (handleClose)
			handleClose();
	}

public:
	/// Callback for when the socket was closed.
	void delegate() handleClose;
	/// Callback for an incoming connection.
	void delegate(T incoming) handleAccept;
}

/// Server socket type for ordinary sockets.
alias GenericServerSocket!(ClientSocket) ServerSocket;

/// Asynchronous class for client sockets with a line-based protocol.
class LineBufferedSocket : ClientSocket
{
private:
	/// The receive buffer.
	string inBuffer;

public:
	/// The protocol's line delimiter.
	string delimiter = "\r\n";

private:
	/// Called when data has been received.
	final void onReadData(ClientSocket sender, void[] data)
	{
		inBuffer ~= cast(string) data;
		string[] lines = split(inBuffer, delimiter);
		inBuffer = lines[lines.length - 1];

		if (handleReadLine)
			foreach (string line; lines[0 .. lines.length - 1])
				if (line.length > 0)
				{
					handleReadLine(this, line);
					if (!connected || disconnecting)
						break;
				}

		if (lines.length > 0)
			markNonIdle();
	}

public:
	override void cancelIdleTimeout() { assert(false); }
	override void resumeIdleTimeout() { assert(false); }
	//override void setIdleTimeout(d_time duration) { assert(false); }
	//override void markNonIdle() { assert(false); }

	this(d_time idleTimeout)
	{
		handleReadData = &onReadData;
		super.setIdleTimeout(idleTimeout);

		debug (REFCOUNT) refcount("ASockets/LineBufferedSocket",1);
	}

	this(Socket conn)
	{
		handleReadData = &onReadData;
		super.setIdleTimeout(TicksPerMinute);
		super(conn);
		debug (REFCOUNT) refcount("ASockets/LineBufferedSocket",1);
	}

	~this()
	{
		debug (REFCOUNT) refcount("ASockets/LineBufferedSocket",0);
	}

	/// Cancel a connection.
	override final void disconnect(string reason = DefaultDisconnectReason, DisconnectType type = DisconnectType.Requested)
	{
		super.disconnect(reason, type);
		inBuffer = null;
	}

	/// Append a line to the send buffer.
	final void send(string line)
	{
		super.send(line ~ "\r\n");
	}

public:
	/// Callback for an incoming line.
	void delegate(LineBufferedSocket sender, string line) handleReadLine;
}

string getHostByName(string addr)
{
	uint uiaddr = ntohl(inet_addr(std.string.toStringz(addr)));
	if (InternetAddress.ADDR_NONE == uiaddr)
	{
		InternetHost ih = new InternetHost;
		if (!ih.getHostByName(addr))
			//throw new AddressException("Invalid internet address");
						throw new AddressException(
								"Unable to resolve host '" ~ addr ~ "'");
		uiaddr = ih.addrList[0];
	}
	in_addr ia;
	ia.s_addr = htonl(uiaddr);
	return toString(inet_ntoa(ia)).dup;
}

/// The default socket manager.
SocketManager socketManager;
private Timer idleTimer;

static this()
{
	socketManager = new SocketManager();
	idleTimer = new Timer();
}
