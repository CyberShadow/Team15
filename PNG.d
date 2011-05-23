/**
 * Simple PNG chunk manipulation.
 *
 * http://www.libpng.org/pub/png/spec/1.2/PNG-Structure.html
 *
 * Copyright 2007-2009  Simon Arlott
 * Copyright 2008       Stéphan Kochen <stephan@kochen.nl>
 * Copyright 2007-2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module Team15.PNG;

import std.string;
import std.date:d_time;
import std.date:getUTCtime;
static import zlib = Team15.Zlib;
debug (PNG) import std.stdio;

public import Team15.Utils;
private import crc32;
import Team15.Timing;
import Team15.Data;

struct PNGChunk
{
	char[4] type;
	Data data;

	uint crc32()
	{
		uint crc = strcrc32(type);
		foreach(v;cast(ubyte[])data.contents)
			crc = update_crc32(v, crc);
		return ~crc;
	}

	static PNGChunk opCall(string type, Data data)
	{
		PNGChunk c;
		c.type[] = type;
		c.data = data;
		return c;
	}
}

enum PNGColourType : ubyte { G, RGB=2, PLTE, GA, RGBA=6 }
enum PNGCompressionMethod : ubyte { DEFLATE }
enum PNGFilterMethod : ubyte { ADAPTIVE }
enum PNGInterlaceMethod : ubyte { NONE, ADAM7 }

enum PNGFilterAdaptive : ubyte { NONE, SUB, UP, AVERAGE, PAETH }

struct PNGHeader
{
align(1):
	uint width, height;
	ubyte colourDepth;
	PNGColourType colourType;
	PNGCompressionMethod compressionMethod;
	PNGFilterMethod filterMethod;
	PNGInterlaceMethod interlaceMethod;
	static assert(PNGHeader.sizeof == 13);
}

ubyte paethPredictor(ubyte a, ubyte b, ubyte c) {
	// a = left, b = above, c = upper left
	int p = a + b - c; // initial estimate
	int pa = abs(p - a); // distances to a, b, c
	int pb = abs(p - b);
	int pc = abs(p - c);
	// return nearest of a,b,c,
	// breaking ties in order a,b,c.
	if (pa <= pb && pa <= pc) return a;
	else if (pb <= pc) return b;
	else return c;
}

class PNG
{
	final static const ulong signature = 0x0a1a0a0d474e5089;

	PNGChunk[] chunks;
	uint width;
	uint height;
	ubyte colourDepth, planes;
	PNGColourType colourType;
	PNGCompressionMethod compressionMethod;
	PNGFilterMethod filterMethod;
	PNGInterlaceMethod interlaceMethod;

	/// Bytes per pixel
	int bpp() {
		return ((colourDepth >> 3) + (colourDepth % 8 == 0 ? 0 : 1)) * planes;
	}

	ulong bpsl() {
		ulong bpsl = cast(ulong)width*colourDepth*planes;
		return (bpsl >> 3) + 1 + (bpsl % 8 == 0 ? 0 : 1);
	}

	this(Data data)
	{
		debug (REFCOUNT) refcount("PNG/PNG",1);

		enforce(8 <= data.length, "Not enough data in PNG");
		enforce(*cast(ulong*)data.ptr == signature, "Invalid PNG signature"); // \211   P   N   G  \r  \n \032 \n
		int i = 8;
		while (i < data.length)
		{
			enforce(i+8 < data.length, "Not enough data in chunk header");
			uint len = reverse(*cast(uint*)(data.ptr+i));
			assert(i+12+len <= data.length, "Not enough data for chunk contents");
			PNGChunk chunk = PNGChunk(cast(string)data[i+4 .. i+8].contents, data[i+8 .. i+8+len]);
			chunks ~= chunk;
			/+PNGChunk chunk;
			chunk.type[] = cast(string)data[i+4 .. i+8];
			chunk.data = data[i+8 .. i+8+len];
			enforce(chunk.crc32() == reverse(*cast(uint*)(data.ptr+i+8+len)), "Bad chunk CRC");
			chunks ~= chunk;+/
			i += 12+len;

			switch (chunk.type) {
				case "IHDR":
					enforce(chunks.length == 1, "An IHDR chunk exists which is not the first chunk");
					enforce(chunk.data.length == 13, "Invalid IHDR chunk length");
					auto header = cast(PNGHeader*)chunk.data.ptr;
					width = fromBE(header.width);
					height = fromBE(header.height);
					colourDepth = header.colourDepth;
					colourType = header.colourType;
					compressionMethod = header.compressionMethod;
					filterMethod = header.filterMethod;
					interlaceMethod = header.interlaceMethod;
					enforce(width > 0, "Width is 0");
					enforce(height > 0, "Height is 0");
					switch (colourType) {
						case PNGColourType.G:
							enforce(colourDepth == 1 || colourDepth == 2 || colourDepth == 4 || colourDepth == 8 || colourDepth == 16, "Invalid colour depth for Greyscale");
							planes = 1;
							break;
						case PNGColourType.PLTE:
							enforce(colourDepth == 1 || colourDepth == 2 || colourDepth == 4 || colourDepth == 8, "Invalid colour depth for Paletted");
							planes = 1;
							break;
						case PNGColourType.RGB:
							enforce(colourDepth == 8 || colourDepth == 16, "Invalid colour depth for RGB");
							planes = 3;
							break;
						case PNGColourType.GA:
							enforce(colourDepth == 8 || colourDepth == 16, "Invalid colour depth for Greyscale+Alpha");
							planes = 2;
							break;
						case PNGColourType.RGBA:
							enforce(colourDepth == 8 || colourDepth == 16, "Invalid colour depth for RGB+Alpha");
							planes = 4;
							break;
						default:
							enforce(false, format("Invalid colour type %d", colourType));
					}
					enforce(compressionMethod == PNGCompressionMethod.DEFLATE, format("Invalid compression method %d", compressionMethod));
					enforce(filterMethod == PNGFilterMethod.ADAPTIVE, format("Invalid filter method %d", filterMethod));
					enforce(interlaceMethod == PNGInterlaceMethod.NONE || interlaceMethod == PNGInterlaceMethod.ADAM7, format("Invalid interlace method %d", interlaceMethod));
					break;
				case "IEND":
					enforce(i == data.length, format("%d byte%s of data after IEND chunk", data.length-i, data.length-i==1?"":"s"));
					break;
				default:
			}
		}

		enforce(chunks.length >= 2, "Less than 2 chunks exist");
		enforce(chunks[0].type == "IHDR", "No IHDR chunk");
		enforce(chunks[$-1].type == "IEND", "No IEND chunk");
	}

	~this()
	{
		debug (REFCOUNT) refcount("PNG/PNG",0);
	}

	Data compile()
	{
		// VP 2009.10.08: calculate total size and allocate exact amount of memory
		uint totalSize = 8;
		foreach(chunk;chunks)
			totalSize += 8 + chunk.data.length + 4;
		Data container = new Data(totalSize);
		ubyte[] data = cast(ubyte[])container.contents;
		*cast(ulong*)data.ptr = signature;
		uint pos = 8;
		foreach(chunk;chunks)
		{
			uint i = pos;
			pos += 12 + chunk.data.length;
			*cast(uint*)&data[i] = reverse(chunk.data.length);
			(cast(string)data[i+4 .. i+8])[] = chunk.type;
			data[i+8 .. i+8+chunk.data.length] = cast(ubyte[])chunk.data.contents;
			*cast(uint*)&data[i+8+chunk.data.length] = reverse(chunk.crc32());
			assert(pos == i+12+chunk.data.length);
		}
		return container;
	}
}

class PNGProcessor : IncrementalTask
{
	final static const uint INFLATE_BLOCK_SIZE = 16*256;
	final static const uint PROCESS_BLOCK_SIZE = 16*128;
	final static const uint DEFLATE_BLOCK_SIZE = 16*1024;

private:
	PNG png;
	bool readonly;
	PNGProcess[] processes;
	bool broken;

	enum State { INIT, INFLATE, READLINES, PROCESS, DEFLATE, FINAL, DONE, ERROR }
	State state;

	// chunk state
	Data idat;
	uint dataPos;
	uint dataCount;
	ulong size;
	bool endOfData;

	// compression state
	zlib.Compress comp;
	zlib.StreamUnCompress ucomp;
	Data ubuf, ubufcont;
	Data cbuf;

	// scanline state
	uint line;
	Data prev;
	Data curr;
	uint bufPos;

	// processing state
	uint processPos;
	uint linePos;

	void cleanup() {
		try { delete comp; } catch (zlib.ZlibException e) { /* ... */ }
		try { delete ucomp; } catch (zlib.ZlibException e) { /* ... */ }
		comp = null;
		ucomp = null;
		ubuf = ubufcont = null;
		cbuf = null;
		prev = null;
		curr = null;
	}

public:
	this(PNG png, bool readonly=false) {
		debug (REFCOUNT) refcount("PNG/PNGProcessor",1);

		enforce(png.compressionMethod == PNGCompressionMethod.DEFLATE, format("Invalid compression method %d", png.compressionMethod));
		this.png = png;
		this.readonly = readonly;
		if (!readonly)
			comp = new zlib.Compress();
		enforce(png.bpsl <= uint.max, "PNG too wide");
		curr = new Data;
		prev = new Data(cast(size_t)png.bpsl);
		cbuf = new Data;
		ubufcont = new Data(INFLATE_BLOCK_SIZE);
	}

	~this() {
		debug (REFCOUNT) refcount("PNG/PNGProcessor",0);
	}

	void add(PNGProcess process) {
		assert(state == State.INIT);
		assert(!broken || process.safe);
		processes ~= process;
		if (process.last)
			broken = true;
	}

	void run(d_time maxDuration=-1) {
		assert(maxDuration >= -1);
		assert(state < State.DONE);
		d_time start;
		d_time now;

		if (maxDuration > 0)
			start = getUTCtime();

		try {
			do {
				switch(state) {
				case State.INIT:
					size_t idatSize;
					foreach(ref chunk;png.chunks)
						if (chunk.type == "IDAT")
							idatSize += chunk.data.length;
					if (idatSize == 0)
						state = State.FINAL;
					else {
						idat = new Data(idatSize);
						idatSize = 0;
						foreach(ref chunk;png.chunks)
							if (chunk.type == "IDAT")
							{
								idat.contents[idatSize..idatSize+chunk.data.length] = chunk.data.contents;
								idatSize += chunk.data.length;
								debug (PNG) writefln("INIT: Added IDAT chunk (%d bytes)", chunk.data.length);
							}
						ucomp = new zlib.StreamUnCompress(idat);
						state = State.INFLATE;
					}
					break;
				case State.INFLATE:
					// inflate some of the chunk data
					ubuf = ubufcont[];
					endOfData = ucomp.uncompress(ubuf);
					assert(ubuf.length);
					size += ubuf.length;

					// flush uncompressor at end of zlib stream
					if (endOfData) {
						if (size != png.bpsl*png.height)
							throw new Exception(format("Invalid PNG data size: %d != %d (%d/%d scanlines read).", size, png.bpsl*png.height, line+1, png.height));
					}

					debug (PNG) writefln("INFLATE: Uncompressed to %d-%d/%d (%d)", size-ubuf.length+1, size, png.bpsl*png.height, ubuf.length);
					bufPos = 0;
					state = State.READLINES;
					break;
				case State.READLINES:
					// read in a scanline
					uint remaining;
					while (bufPos < ubuf.length) {
						// get more data from buffer
						remaining = cast(uint)(png.bpsl-curr.length);
						assert(remaining > 0);
						if (remaining > ubuf.length - bufPos)
							remaining = ubuf.length - bufPos;
						curr ~= ubuf[bufPos..bufPos+remaining];
						bufPos += remaining;

						assert(curr.length <= png.bpsl);
						debug (PNG) writefln("READLINES: Read %d-%d/%d, line data %d-%d/%d", dataCount+1, dataCount+bufPos, dataCount+ubuf.length, png.bpsl-remaining+1, curr.length, png.bpsl);
						if (curr.length == png.bpsl)
							break;
					}
					dataCount += ubuf.length;
					if (curr.length == png.bpsl) {
						debug (PNG) writefln("READLINES: Read line %d/%d", line+1, png.height);
						processPos = 0;
						linePos = 1;
						state = State.PROCESS;
					} else if (bufPos == ubuf.length) {
						assert(dataPos < idat.length, "End of data on unfinished line");
						state = State.INFLATE;
					}
					break;
				case State.PROCESS:
					// process a scanline with each process
					if (processes.length == 0)
						linePos = curr.length;
					else if (linePos < curr.length) {
						uint blockSize = PROCESS_BLOCK_SIZE - (PROCESS_BLOCK_SIZE % png.planes);
						uint remaining = linePos+blockSize <= curr.length
							? blockSize : curr.length-linePos;
						assert(remaining > 0);
						uint oldLength = curr.length;
						processes[processPos].doProcessScanline(line, prev, curr, linePos, linePos+remaining-1);
						debug (PNG) writefln("PROCESS: Processed %d-%d/%d of line %d/%d with %d/%d", linePos+1, linePos+(curr.length-oldLength)+remaining, curr.length, line+1, png.height, processPos+1, processes.length);
						linePos += remaining;
						linePos += curr.length - oldLength;
					}
					assert(linePos <= curr.length);
					if (linePos == curr.length) {
						if (processes.length > 0)
							processPos++;

						assert(processPos <= processes.length);
						if (processPos == processes.length) {
							if (!readonly) {
								linePos = 0;
								state = State.DEFLATE;
							} else {
								line++;
								prev = curr[];
								curr.clear;

								if (maxDuration > 0)
									if (handleLine)
										handleLine(this, line);

								assert(dataPos <= idat.length);
								if (bufPos < ubuf.length)
									state = State.READLINES;
								else if (endOfData) {
									processPos = 0;
									state = State.FINAL;
								} else
									state = State.INFLATE;
							}
						} else
							linePos = 1;
					}
					break;
				case State.DEFLATE:
					// deflate some of the scanline data
					uint clen;
					uint remaining = linePos+DEFLATE_BLOCK_SIZE <= curr.length
						? DEFLATE_BLOCK_SIZE : curr.length-linePos;
					if (remaining)
					{
						clen = cbuf.length;
						cbuf ~= comp.compress(curr[linePos..linePos+remaining]);
						debug (PNG) writefln("DEFLATE: Compressed %d-%d/%d of line %d/%d%s", linePos+1, linePos+remaining, curr.length, line+1, png.height, cbuf.length-clen==0 ? "" : format(" as %d-%d (%d)", clen+1, cbuf.length+1, cbuf.length-clen));
						linePos += remaining;
					}

					assert(linePos <= curr.length);
					if (linePos == curr.length) {
						line++;
						prev = curr[];
						curr.clear;

						if (maxDuration > 0)
							if (handleLine)
								handleLine(this, line);

						assert(dataPos <= idat.length);
						if (bufPos < ubuf.length)
							state = State.READLINES;
						else if (endOfData) {
							clen = cbuf.length;
							cbuf ~= comp.flush(zlib.Z_FINISH);
							processPos = 0;
							debug (PNG) writefln("DEFLATE: Flushed as %d-%d/%d (%d)", clen+1, cbuf.length, cbuf.length, cbuf.length-clen);
							idat = cbuf[];
							cbuf.clear;
							state = State.FINAL;
						} else
							state = State.INFLATE;
					}
					break;
				case State.FINAL:
					if (processes.length > processPos) {
						debug (PNG) writefln("FINAL: Processing with %d/%d", processPos+1, processes.length);
						processes[processPos].processPNG(png, readonly);
						processPos++;
					}
					assert(processPos <= processes.length);
					if (processPos == processes.length)
					{
						// replace all IDAT chunks with a new one containing idat
					findIDAT:
						foreach(i, ref chunk;png.chunks)
							if (chunk.type == "IDAT")
								foreach(j, ref chunk2;png.chunks[i..$])
									if (chunk2.type != "IDAT")
									{
										png.chunks = png.chunks[0..i] ~ PNGChunk("IDAT", idat) ~ png.chunks[i+j..$];
										cleanup();
										state = State.DONE;
										break findIDAT;
									}
						assert(state == State.DONE);
					}
					else
						break;
				case State.DONE:
					if (maxDuration > 0)
						if (handleDone)
							handleDone(this, true);
					return;
				default:
					assert(false);
				}

				if (maxDuration > 0)
					now = getUTCtime();
			} while(maxDuration == -1 || (maxDuration > 0 && (now < start || now - start < maxDuration)));
		} catch (Exception e) {
			state = State.ERROR;
			cleanup();
			if (maxDuration > 0) {
				if (handleDone)
					handleDone(this, false, e.msg);
			} else
				throw e;
		}
	}

	bool finished() {
		return state >= State.DONE;
	}

	bool successful() {
		assert(finished);
		return state != State.ERROR;
	}

	void stop() {
		assert(!finished);
		state = State.ERROR;
		cleanup();
	}

	uint linesCompleted() {
		return line;
	}

	double percentageComplete() {
		return (100.0*cast(double)line)/cast(double)png.height;
	}

	override string toString() {
		string stateStr;
		switch(state) {
			case State.INIT     : stateStr = "INIT     "; break;
			case State.INFLATE  : stateStr = "INFLATE  "; break;
			case State.READLINES: stateStr = "READLINES"; break;
			case State.PROCESS  : stateStr = "PROCESS  "; break;
			case State.DEFLATE  : stateStr = "DEFLATE  "; break;
			case State.FINAL    : stateStr = "FINAL    "; break;
			case State.DONE     : stateStr = "DONE     "; break;
			case State.ERROR    : stateStr = "ERROR    "; break;
			default: assert(0);
		}
		return stateStr ~ " (" ~ .toString(line) ~ " / " ~ (png ? .toString(png.height) : "null") ~ ")";
	}

	void delegate(PNGProcessor process, uint line) handleLine;
	void delegate(PNGProcessor process, bool success, string error=null) handleDone;
}

abstract class PNGProcess {
protected:
	// treat this as READ ONLY
	PNG png;

private:
	bool privateScanline;
	Data prev;

	void doProcessScanline(uint line, ref Data prev, ref Data curr, uint from, uint to) {
		if(privateScanline)
		{
			processScanline(line, this.prev, curr, from, to);
			if(to+1==png.bpsl)
				this.prev = curr.dup;
		}
		else
			processScanline(line, prev, curr, from, to);
	}

public:
	/**
	 * Request a private scan line to avoid working with modified data.
	 */
	this(PNG png, bool privateScanline) {
		debug (REFCOUNT) refcount("PNG/PNGProcess",1);

		this.png = png;
		this.privateScanline = privateScanline;
	}

	~this() {
		debug (REFCOUNT) refcount("PNG/PNGProcess",0);
	}

	/**
	 * Called for every scan line; in order:
	 * - Process only byte 0 and/or the specified byte range (which will not include 0)
	 * - The previous scan line will be available in full (except on line 0)
	 */
	void processScanline(uint line, ref Data prev, ref Data curr, uint from, uint to) {}

	/**
	 * Called at the end of processing to allow settings to be changed.
	 */
	void processPNG(PNG png, bool readonly) {}

	/**
	 * True if this process is safe to use after a previous processor has done something odd.
	 */
	bool safe() {
		return false;
	}

	/**
	 * True if this process will cause problems with a future processor.
	 */
	bool last() {
		return false;
	}
}

/**
 * Converts scanlines to have no filtering.
 */
class PNGDecodeAdaptiveFilter : PNGProcess {
protected:
	// track the filter type (since it's changed at the start)
	uint line;
	PNGFilterAdaptive type;

public:
	this(PNG png) {
		debug (REFCOUNT) refcount("PNG/PNGDecodeAdaptiveFilter",1);
		super(png, true);
	}

	~this() {
		debug (REFCOUNT) refcount("PNG/PNGDecodeAdaptiveFilter",0);
	}

	override void processScanline(uint line, ref Data prevdata, ref Data currdata, uint from, uint to) {
		ubyte[] prev = prevdata ? cast(ubyte[])prevdata.contents : null, curr = cast(ubyte[])currdata.contents;
		if(from == 1 && (line == 0 || line != this.line))
		{
			debug (PNG) writefln("Adaptive Filter type for %08x: %02x", line, curr[0]);
			this.line = line;
			type = cast(PNGFilterAdaptive)curr[0];
			curr[0] = PNGFilterAdaptive.NONE;
		}

		switch (type) {
			int i;
			case PNGFilterAdaptive.NONE:
				// yay.
				break;
			case PNGFilterAdaptive.SUB:
				for (i = from; i <= to; i++)
					curr[i] = cast(ubyte)((curr[i] + (i-png.bpp < 1 ? 0 : curr[i-png.bpp]))%256);
				break;
			case PNGFilterAdaptive.UP:
				for (i = from; i <= to; i++)
					curr[i] = cast(ubyte)((curr[i] + (line == 0 ? 0 : prev[i]))%256);
				break;
			case PNGFilterAdaptive.AVERAGE:
				for (i = from; i <= to; i++)
					curr[i] = cast(ubyte)((curr[i] + (
							((i-png.bpp < 1 ? 0 : curr[i-png.bpp]) + (line == 0 ? 0 : prev[i])) >> 1
						))%256);
				break;
			case PNGFilterAdaptive.PAETH:
				for (i = from; i <= to; i++)
					curr[i] = cast(ubyte)((curr[i] + paethPredictor(
						cast(ubyte)((i-png.bpp < 1) ? 0 : curr[i-png.bpp]),
						cast(ubyte)(line == 0 ? 0 : prev[i]),
						cast(ubyte)(line == 0 ? 0 : ((i-png.bpp < 1) ? 0 : prev[i-png.bpp]))
					))%256);
				break;
			default:
				throw new Exception(format("Invalid PNG adaptive filter %d for scanline %d/%d.", type, line+1, png.height));
		}
	}
}

class PNGRewritePalette : PNGProcess {
private:
	ubyte[] pixelMap;
	ubyte[] paletteMap;

public:
	/**
	 * Pixel map is an array of 2^depth bytes which have the new pixel values.
	 * Palette map is an array of up to 2^depth bytes is the new palette pointing to the old palette values.
	 */
	this(PNG png, ubyte[] pixelMap, ubyte[] paletteMap) {
		debug (REFCOUNT) refcount("PNG/PNGRewritePalette",1);

		enforce(png.colourType == PNGColourType.PLTE);
		enforce(png.colourDepth == 1 || png.colourDepth == 4 || png.colourDepth == 8);
		enforce(png.colourDepth != 1 || pixelMap.length == 1 << 1);
		enforce(png.colourDepth != 4 || pixelMap.length == 1 << 4);
		enforce(png.colourDepth != 8 || pixelMap.length == 1 << 8);
		enforce(png.colourDepth != 1 || paletteMap.length <= 1 << 1);
		enforce(png.colourDepth != 4 || paletteMap.length <= 1 << 4);
		enforce(png.colourDepth != 8 || paletteMap.length <= 1 << 8);
		super(png, false);

		bool foundPalette;
		uint paletteLength;
		foreach(ref chunk;png.chunks)
			if (chunk.type == "PLTE") {
				foundPalette = true;
				auto palette = cast(ubyte[3][])chunk.data.contents;
				enforce(palette.length <= 256);
				enforce(palette.length >= paletteMap.length);
				paletteLength = palette.length;
				break;
			}
		enforce(foundPalette);

		for(uint i = 0; i < pixelMap.length; i++)
			enforce(pixelMap[i] < paletteMap.length);
		for(uint i = 0; i < paletteMap.length; i++)
			enforce(paletteMap[i] < paletteLength);

		this.pixelMap = pixelMap;
		this.paletteMap = paletteMap;
	}

	/**
	 * Swap two palette entries.
	 */
	this(PNG png, ubyte index1, ubyte index2) {
		debug (REFCOUNT) refcount("PNG/PNGRewritePalette",1);

		ubyte[] pixelMap;
		ubyte[] paletteMap;
		bool foundPalette;
		pixelMap.length = 1 << 8;
		foreach(ref chunk;png.chunks)
			if (chunk.type == "PLTE") {
				foundPalette = true;
				auto palette = cast(ubyte[3][])chunk.data.contents;
				enforce(palette.length <= 256);

				paletteMap.length = palette.length;
				for(uint i = 0; i < palette.length; i++)
					pixelMap[i] = paletteMap[i] = cast(ubyte)i;
				break;
			}
		enforce(foundPalette, "No palette");

		assert(index1 < paletteMap.length);
		assert(index2 < paletteMap.length);
		pixelMap[index1] = paletteMap[index1] = index2;
		pixelMap[index2] = paletteMap[index2] = index1;
		this(png, pixelMap, paletteMap);
	}

	~this() {
		debug (REFCOUNT) refcount("PNG/PNGRewritePalette",0);
	}

	override void processScanline(uint line, ref Data prevdata, ref Data currdata, uint from, uint to) {
		ubyte[] curr = cast(ubyte[])currdata.contents;
		assert(cast(PNGFilterAdaptive)curr[0] == PNGFilterAdaptive.NONE);
		switch(png.colourDepth) {
			case 1:
				for(uint i = from; i <= to; i++)
					curr[i] = cast(ubyte)
						(  (pixelMap[ curr[i] & 0x01]             & 0x01) | ((pixelMap[(curr[i] & 0x02) >> 1] << 1) & 0x02)
						| ((pixelMap[(curr[i] & 0x04) >> 2] << 2) & 0x04) | ((pixelMap[(curr[i] & 0x08) >> 3] << 3) & 0x08)
						| ((pixelMap[(curr[i] & 0x10) >> 4] << 4) & 0x10) | ((pixelMap[(curr[i] & 0x20) >> 5] << 5) & 0x20)
						| ((pixelMap[(curr[i] & 0x40) >> 6] << 6) & 0x40) | ((pixelMap[(curr[i] & 0x80) >> 7] << 7) & 0x80));
				break;
			case 4:
				for(uint i = from; i <= to; i++)
					curr[i] = cast(ubyte)
						(  (pixelMap[ curr[i] & 0x0F]             & 0x0F)
						| ((pixelMap[(curr[i] & 0xF0) >> 4] << 4) & 0xF0));
				break;
			case 8:
				for(uint i = from; i <= to; i++)
					curr[i] = pixelMap[curr[i]];
				break;
			default:
				assert(false);
		}
	}

	override void processPNG(PNG png, bool readonly) {
		if(readonly)
			return;
		foreach(ref chunk;png.chunks)
			if (chunk.type == "PLTE") {
				auto palette = cast(ubyte[3][])chunk.data.contents;
				enforce(palette.length <= 256);
				auto origPalette = palette.dup;
				assert(palette.length >= paletteMap.length);
				palette = palette.ptr[0..paletteMap.length];
				for(uint i = 0; i < palette.length; i++) {
					palette[i][0] = origPalette[paletteMap[i]][0];
					palette[i][1] = origPalette[paletteMap[i]][1];
					palette[i][2] = origPalette[paletteMap[i]][2];
				}
				chunk.data = new Data(palette);
				break;
			}
	}
}

class PNGCyclePalette : PNGRewritePalette {
public:
	this(PNG png) {
		debug (REFCOUNT) refcount("PNG/PNGCyclePalette",1);

		enforce(png.colourType == PNGColourType.PLTE);
		enforce(png.colourDepth == 8);
		ubyte[] pixelMap;
		ubyte[] paletteMap;
		bool foundPalette;
		pixelMap.length = 1 << 8;
		foreach(ref chunk;png.chunks)
			if (chunk.type == "PLTE") {
				foundPalette = true;
				auto palette = cast(ubyte[3][])chunk.data.contents;
				enforce(palette.length <= 256);

				paletteMap.length = palette.length;
				for(uint i = 0; i < palette.length; i++) {
					pixelMap[i] = cast(ubyte)((i + 1) % palette.length);
					paletteMap[i] = cast(ubyte)i;
				}
				break;
			}
		enforce(foundPalette, "No palette");
		super(png, pixelMap, paletteMap);
	}

	~this() {
		debug (REFCOUNT) refcount("PNG/PNGCyclePalette",0);
	}
}

class PNGDepthConvert : PNGProcess {
private:
	ubyte depth;
	ulong bpsl;

public:
	this(PNG png, ubyte depth) {
		debug (REFCOUNT) refcount("PNG/PNGDepthConvert",1);

		enforce(png.colourType == PNGColourType.PLTE);
		enforce(png.colourDepth == 1 || png.colourDepth == 4);
		assert(depth == 4 || depth == 8);
		assert(depth > png.colourDepth);
		super(png, false);
		this.depth = depth;
		bpsl = cast(ulong)png.width*depth;
		bpsl = (bpsl >> 3) + 1 + (bpsl % 8 == 0 ? 0 : 1);
	}

	~this() {
		debug (REFCOUNT) refcount("PNG/PNGDepthConvert",0);
	}

	override void processScanline(uint line, ref Data prevdata, ref Data currdata, uint from, uint to) {
		ubyte[] curr = cast(ubyte[])currdata.contents;
		assert(cast(PNGFilterAdaptive)curr[0] == PNGFilterAdaptive.NONE);
		if (png.colourDepth == depth) return;
		uint append = to+1 < curr.length ? curr.length - (to+1) : 0;
		Data tmp = currdata[0..from].dup;
		switch(png.colourDepth) {
			case 1:
				switch(depth) {
					case 4:
						for(uint i = from; i <= to; i++) {
							if (tmp.length + append < bpsl) {
								tmp ~= cast(ubyte)(((curr[i] & 0x80) >> 3) | ((curr[i] & 0x40) >> 6));
								if (tmp.length + append < bpsl) {
									tmp ~= cast(ubyte)(((curr[i] & 0x20) >> 1) | ((curr[i] & 0x10) >> 4));
									if (tmp.length + append < bpsl) {
										tmp ~= cast(ubyte)(((curr[i] & 0x08) << 1) | ((curr[i] & 0x04) >> 2));
										if (tmp.length + append < bpsl)
											tmp ~= cast(ubyte)(((curr[i] & 0x02) << 3) | ((curr[i] & 0x01)     ));
									}
								}
							}
						}
						break;
					case 8:
						for(uint i = from; i <= to; i++)
							for(int j = 7; j >= 0; j--)
								if (tmp.length + append < bpsl)
									tmp ~= cast(ubyte)((curr[i] & (1 << j)) >> j);
						break;
					default:
						assert(false);
				}
				break;
			case 4:
				switch(depth) {
					case 8:
						for(uint i = from; i <= to; i++)
							for(int j = 1; j >= 0; j--)
								if (tmp.length + append < bpsl)
									tmp ~= cast(ubyte)((curr[i] & (0xF << j)) >> j*4);
						break;
					default:
						assert(false);
				}
				break;
			default:
				assert(false);
		}
		if (to+1 < curr.length)
			tmp ~= curr[to+1..$];
		assert(tmp.length == curr.length + ((to-from+1) * (depth-png.colourDepth)));
		currdata = tmp;
	}

	override void processPNG(PNG png, bool readonly) {
		assert(!readonly);
		assert(png.chunks[0].type == "IHDR");
		auto header = cast(PNGHeader*)png.chunks[0].data.ptr;
		header.colourDepth = png.colourDepth = depth;
	}

	bool last() {
		return true;
	}
}

class PNGPaletteAnalyser : PNGProcess {
private:
	bool[] paletteUsage;
	ulong maxbpsl;

public:
	this(PNG png) {
		debug (REFCOUNT) refcount("PNG/PNGPaletteAnalyser",1);

		assert(png.colourType == PNGColourType.PLTE);
		assert(png.colourDepth == 1 || png.colourDepth == 4 || png.colourDepth == 8);
		super(png, false);
		paletteUsage.length = 1 << png.colourDepth;
		maxbpsl = cast(ulong)png.width*png.colourDepth;
	}

	~this() {
		debug (REFCOUNT) refcount("PNG/PNGPaletteAnalyser",0);
	}

	override void processScanline(uint line, ref Data prevdata, ref Data currdata, uint from, uint to) {
		ubyte[] curr = cast(ubyte[])currdata.contents;
		assert(cast(PNGFilterAdaptive)curr[0] == PNGFilterAdaptive.NONE);
		switch(png.colourDepth) {
			case 1:
				for(uint i = from; i <= to; i++)
					for(int j = 7; j >= 0; j--)
						if ((i-1)*8 + (8-j) <= maxbpsl)
							paletteUsage[(curr[i] & (1 << j)) >> j] = true;
				break;
			case 4:
				for(uint i = from; i <= to; i++)
					for(int j = 1; j >= 0; j--)
						if ((i-1)*8 + (2-j)*4 <= maxbpsl)
							paletteUsage[(curr[i] & (0xF << j)) >> j*4] = true;
				break;
			case 8:
				for(uint i = from; i <= to; i++)
					paletteUsage[curr[i]] = true;
				break;
			default:
				assert(false);
		}
	}

	override void processPNG(PNG png, bool readonly) {
		bool foundPalette;
		uint paletteSize;
		foreach(ref chunk;png.chunks)
			if (chunk.type == "PLTE") {
				foundPalette = true;
				auto palette = cast(ubyte[3][])chunk.data.contents;
				assert(palette.length <= 256);
				paletteSize = palette.length;
				break;
			}
		enforce(foundPalette, "No palette");

		if (handlePaletteInfo)
			handlePaletteInfo(this, paletteSize, paletteUsage);
	}

	void delegate(PNGPaletteAnalyser pa, uint paletteSize, bool[] paletteUsage) handlePaletteInfo;
}

class PNGDownscale : PNGProcess {
private:
	uint factor;
	uint[] ar, ag, ab;
	ubyte[3][] palette;
	uint x;

public:
	this(PNG png, uint factor) {
		debug (REFCOUNT) refcount("PNG/PNGDownscale",1);

		if (png.interlaceMethod != PNGInterlaceMethod.NONE)
			throw new Exception("Interlaced PNGs not supported");
		assert(factor > 0);
		super(png, false);
		this.factor = factor;
		ar.length = ag.length = ab.length = png.width / factor;

		if (png.colourType == PNGColourType.PLTE) {
			bool foundPalette;
			foreach(ref chunk;png.chunks)
				if (chunk.type == "PLTE") {
					foundPalette = true;
					palette = cast(ubyte[3][])chunk.data.contents;
					assert(palette.length <= 256);
					break;
				}
			enforce(foundPalette, "No palette");
		}
	}

	~this() {
		debug (REFCOUNT) refcount("PNG/PNGDownscale",0);
	}

	override void processScanline(uint line, ref Data prevdata, ref Data currdata, uint from, uint to) {
		ubyte[] curr = cast(ubyte[])currdata.contents;
		if (from == 1)
			assert(cast(PNGFilterAdaptive)curr[0] == PNGFilterAdaptive.NONE);
		bool writing = line % factor == factor-1;
		Data tmp;
		if (writing)
			tmp = currdata[0..from].dup;

		void handlePixel(ubyte r, ubyte g, ubyte b)
		{
			uint fx = x / factor;
			if (fx < ar.length)
			{
				ar[fx] += r;
				ag[fx] += g;
				ab[fx] += b;
				if (x % factor == factor-1 && writing)
				{
					uint factor2 = factor * factor;
					tmp ~= [
						cast(ubyte)(ar[fx] / factor2),
						cast(ubyte)(ag[fx] / factor2),
						cast(ubyte)(ab[fx] / factor2)
					][];
					ar[fx] = ag[fx] = ab[fx] = 0;
				}
			}
			x++;

			if (x==png.width)
				x = 0;
		}

		switch (png.colourType) {
			case PNGColourType.PLTE:
				switch (png.colourDepth) {
					case 1:
						for(uint i = from; i <= to; i++)
							for(int j = 7; j >= 0; j--)
							{
								ubyte c = cast(ubyte)((curr[i] & (1 << j)) >> j);
								handlePixel(palette[c][0], palette[c][1], palette[c][2]);
							}
						break;
					case 4:
						for(uint i = from; i <= to; i++)
							for(int j = 1; j >= 0; j--)
							{
								ubyte c = cast(ubyte)((curr[i] & (0xF << j)) >> j*4);
								handlePixel(palette[c][0], palette[c][1], palette[c][2]);
							}
						break;
					case 8:
						for(uint i = from; i <= to; i++)
						{
							ubyte c = curr[i];
							handlePixel(palette[c][0], palette[c][1], palette[c][2]);
						}
						break;
					default:
						assert(false);
				}
				break;
			case PNGColourType.RGB:
				switch (png.colourDepth) {
					case 8:
						for(uint i = from; i <= to; i+=3)
							handlePixel(curr[i], curr[i+1], curr[i+2]);
						break;
					default:
						assert(false);
				}
				break;
			case PNGColourType.RGBA:
				switch (png.colourDepth) {
					case 8:
						for(uint i = from; i <= to; i+=4)
							handlePixel(curr[i], curr[i+1], curr[i+2]);
						break;
					default:
						assert(false);
				}
				break;
			default:
				assert(false);
		}

		if (writing)
		{
			if (to+1 < curr.length)
				tmp ~= curr[to+1..$];
			currdata = tmp;
		}
		else
			currdata = currdata[to+1..currdata.length];
	}

	override void processPNG(PNG png, bool readonly) {
		assert(!readonly);
		assert(png.chunks[0].type == "IHDR");
		auto header = cast(PNGHeader*)png.chunks[0].data.ptr;
		header.colourDepth = png.colourDepth = 8;
		header.colourType  = png.colourType  = PNGColourType.RGB;
		uint newWidth = png.width/factor, newHeight = png.height/factor;
		png.width = newWidth;
		header.width  = toBE(newWidth);
		png.height = newHeight;
		header.height = toBE(newHeight);

		for (int i=0; i<png.chunks.length; i++)
			if (png.chunks[i].type == "PLTE")
				png.chunks = png.chunks[0..i] ~ png.chunks[i+1..$];
	}

	bool last() {
		return true;
	}
}

class PNGMonochromize : PNGProcess {
private:
	ubyte[3][] palette;
	ubyte bits;
	uint x;

public:
	this(PNG png) {
		if (png.interlaceMethod != PNGInterlaceMethod.NONE)
			throw new Exception("Interlaced PNGs not supported");
		super(png, false);

		if (png.colourType == PNGColourType.PLTE) {
			bool foundPalette;
			foreach(ref chunk;png.chunks)
				if (chunk.type == "PLTE") {
					foundPalette = true;
					palette = cast(ubyte[3][])chunk.data.contents;
					assert(palette.length <= 256);
					break;
				}
			enforce(foundPalette, "No palette");
		}
	}

	override void processScanline(uint line, ref Data prevdata, ref Data currdata, uint from, uint to) {
		ubyte[] curr = cast(ubyte[])currdata.contents;
		if (from == 1)
			assert(cast(PNGFilterAdaptive)curr[0] == PNGFilterAdaptive.NONE);
		Data tmp = currdata[0..from].dup;

		void handlePixel(ubyte r, ubyte g, ubyte b)
		{
			ubyte bit = cast(ubyte)((r || g || b) ? 1 : 0);
			bits = (bits<<1) | bit;
			x++;
			if (x % 8 == 0 || x == png.width)
			{
				tmp ~= [bits][];
				bits = 0;
			}

			if (x==png.width)
				x = 0;
		}

		switch (png.colourType) {
			case PNGColourType.PLTE:
				switch (png.colourDepth) {
					case 1:
						for(uint i = from; i <= to; i++)
							for(int j = 7; j >= 0; j--)
							{
								ubyte c = cast(ubyte)((curr[i] & (1 << j)) >> j);
								handlePixel(palette[c][0], palette[c][1], palette[c][2]);
							}
						break;
					case 4:
						for(uint i = from; i <= to; i++)
							for(int j = 1; j >= 0; j--)
							{
								ubyte c = cast(ubyte)((curr[i] & (0xF << j)) >> j*4);
								handlePixel(palette[c][0], palette[c][1], palette[c][2]);
							}
						break;
					case 8:
						for(uint i = from; i <= to; i++)
						{
							ubyte c = curr[i];
							handlePixel(palette[c][0], palette[c][1], palette[c][2]);
						}
						break;
					default:
						assert(false);
				}
				break;
			case PNGColourType.RGB:
				switch (png.colourDepth) {
					case 8:
						for(uint i = from; i <= to; i+=3)
							handlePixel(curr[i], curr[i+1], curr[i+2]);
						break;
					default:
						assert(false);
				}
				break;
			case PNGColourType.RGBA:
				switch (png.colourDepth) {
					case 8:
						for(uint i = from; i <= to; i+=4)
							handlePixel(curr[i], curr[i+1], curr[i+2]);
						break;
					default:
						assert(false);
				}
				break;
			default:
				assert(false);
		}

		if (to+1 < curr.length)
			tmp ~= curr[to+1..$];
		currdata = tmp;
	}

	override void processPNG(PNG png, bool readonly) {
		assert(!readonly);
		assert(png.chunks[0].type == "IHDR");
		auto header = cast(PNGHeader*)png.chunks[0].data.ptr;
		header.colourDepth = png.colourDepth = 1;
		header.colourType  = png.colourType  = PNGColourType.G;

		for (int i=0; i<png.chunks.length; i++)
			if (png.chunks[i].type == "PLTE")
				png.chunks = png.chunks[0..i] ~ png.chunks[i+1..$];
	}

	bool last() {
		return true;
	}
}

class PNGChromatize : PNGProcess {
private:
	ubyte[3][] palette;
	ubyte lastColor;
	ubyte black = 255;

public:
	this(PNG png) {
		if (png.interlaceMethod != PNGInterlaceMethod.NONE)
			throw new Exception("Interlaced PNGs not supported");
		super(png, false);

		enforce(png.colourType == PNGColourType.PLTE);

		bool foundPalette;
		foreach(ref chunk;png.chunks)
			if (chunk.type == "PLTE") {
				foundPalette = true;
				palette = cast(ubyte[3][])chunk.data.contents;
				assert(palette.length <= 256);
				break;
			}
		enforce(foundPalette, "No palette");

		foreach (ubyte i, entry; palette)
			if (entry[0]==0 && entry[1]==0 && entry[2]==0)
			{
				black = i;
				break;
			}
	}

	override void processScanline(uint line, ref Data prevdata, ref Data currdata, uint from, uint to) {
		ubyte[] curr = cast(ubyte[])currdata.contents;
		if (from == 1)
			assert(cast(PNGFilterAdaptive)curr[0] == PNGFilterAdaptive.NONE);

		switch (png.colourType) {
			case PNGColourType.PLTE:
				switch (png.colourDepth) {
					case 8:
						for(uint i = from; i <= to; i++)
							if (curr[i] == black)
								curr[i] = lastColor;
							else
								lastColor = curr[i];
						break;
					default:
						assert(false);
				}
				break;
			default:
				assert(false);
		}
	}

	override void processPNG(PNG png, bool readonly) {
		assert(!readonly);
	}

	bool last() {
		return true;
	}
}
