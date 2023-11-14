module librehome.snes.bsnes.renderer;

import librehome.snes.hardware;

import bindbc.loader;

public enum ImgW = 512;
public enum ImgH = 448;

public struct SnesDrawFrameData {
align:
	ubyte INIDISP;
	ubyte OBSEL;
	ushort OAMADDR;
	ubyte BGMODE;
	ubyte MOSAIC;
	ubyte BG1SC;
	ubyte BG2SC;
	ubyte BG3SC;
	ubyte BG4SC;
	ubyte BG12NBA;
	ubyte BG34NBA;
	ushort BG1HOFS;
	ushort BG1VOFS;
	ushort BG2HOFS;
	ushort BG2VOFS;
	ushort BG3HOFS;
	ushort BG3VOFS;
	ushort BG4HOFS;
	ushort BG4VOFS;
	ubyte M7SEL;
	ushort M7A;
	ushort M7B;
	ushort M7C;
	ushort M7D;
	ushort M7X;
	ushort M7Y;
	ubyte W12SEL;
	ubyte W34SEL;
	ubyte WOBJSEL;
	ubyte WH0;
	ubyte WH1;
	ubyte WH2;
	ubyte WH3;
	ubyte WBGLOG;
	ubyte WOBJLOG;
	ubyte TM;
	ubyte TS;
	ubyte TMW;
	ubyte TSW;
	ubyte CGWSEL;
	ubyte CGADSUB;
	ubyte FIXED_COLOUR_DATA_R;
	ubyte FIXED_COLOUR_DATA_G;
	ubyte FIXED_COLOUR_DATA_B;
	ubyte SETINI;

	ushort[0x8000] vram;
	ushort[0x100] cgram;
	OAMEntry[128] oam1;
	ubyte[32] oam2;

	ushort numHdmaWrites;
	HDMAWrite[4*8*240] hdmaData;
	const(ubyte[]) getRegistersConst() const {
		const ubyte* first = cast(const ubyte*)(&INIDISP);
		const ubyte* last  = cast(const ubyte*)(&SETINI);
		return first[0..(last-first+1)];
	}
}


extern(C) @nogc nothrow {
	alias plibsfcppu_init = bool function();
	alias plibsfcppu_drawFrame = ushort * function(const(SnesDrawFrameData)* d);
}

__gshared {
	plibsfcppu_init libsfcppu_init;
	plibsfcppu_drawFrame libsfcppu_drawFrame;
}

private {
	SharedLib lib;
}

public bool loadSnesDrawFrame() {
	version(Windows) {
		const(char)[][1] libNames = [
			"libsfcppu.dll",
		];
	} else version(OSX) {
		const(char)[][1] libNames = [
			"libsfcppu.dylib",
		];
	} else version(Posix) {
		const(char)[][1] libNames = [
			"libsfcppu.so",
		];
	} else static assert(0, "libsfcppu is not yet supported on this platform.");

	bool ret;
	foreach(name; libNames) {
		ret = loadDynamicLibrary(name);
		if(ret) break;
	}
	return ret;
}

bool loadDynamicLibrary(const(char)[] libName) {
	lib = load(libName.ptr);
	if(lib == invalidHandle) {
		return false;
	}

	auto errCount = errorCount();
	lib.bindSymbol(cast(void**)&libsfcppu_init, "libsfcppu_init");
	lib.bindSymbol(cast(void**)&libsfcppu_drawFrame, "libsfcppu_drawFrame");
	if(errorCount() != errCount) return false;
	return true;
}


public bool initSnesDrawFrame() {
	assert(libsfcppu_init, "libsfcppu not loaded?");
	return libsfcppu_init();
}

public void drawFrame(ushort[] buffer, int pitch, const(SnesDrawFrameData)* d)
	in(buffer.length == ImgW * ImgH)
{
	assert(pitch == 1024);
	assert(libsfcppu_drawFrame, "libsfcppu not loaded?");
	buffer[] = getFrameData(d);
}
ushort[] getFrameData(const(SnesDrawFrameData)* d) {
	ushort * rawdata = libsfcppu_drawFrame(d);
	return rawdata[ImgW * 16 .. ImgW * (ImgH + 16)];
}
