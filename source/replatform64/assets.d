module replatform64.assets;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.array;
import std.exception;
import std.meta;
import std.path;
import std.range;
import std.traits;

import replatform64.backend.common.interfaces;
import replatform64.ui;
import replatform64.util;

import justimages.png;
import tilemagic;
import squiz_box;

alias ProgressUpdateFunction = void delegate(scope const Progress);
alias AddFileFunction = void delegate(string, const ubyte[]);
alias ExtractFunction = void function(scope AddFileFunction, scope ProgressUpdateFunction, immutable(ubyte)[]);
alias LoadFunction = void function(const scope char[], const scope ubyte[], scope PlatformBackend);

enum DataType {
	raw,
	structured,
	bpp1,
	bpp2Intertwined,
	bpp2Linear,
	bpp4Intertwined,
}

struct ROMSource {
	uint offset;
	uint length;
}

struct Asset {
	string name;
	DataType type;
	bool forceMultipleFiles;
}

private enum isROMLoadable(alias sym) = (Filter!(typeMatches!ROMSource, __traits(getAttributes, sym)).length == 1) || (Filter!(typeMatches!(ROMSource[]), __traits(getAttributes, sym)).length == 1);
private enum isAsset(alias sym) = Filter!(typeMatches!Asset, __traits(getAttributes, sym)).length == 1;

struct SymbolDataItem(alias Sym) {
	alias data = Sym;
	SymbolMetadata metadata;
	template ReadableElementType() {
		//pragma(msg, __traits(identifier, Sym), ", ", typeof(Sym));
		static if (is(typeof(Sym) == S[], S)) {
			static if (is(S == T[], T)) {
				alias ReadableElementType = T[];
			} else {
				alias ReadableElementType = S[];
			}
		} else {
			alias ReadableElementType = ubyte[];
		}
		static assert(is(ReadableElementType == X[], X));
	}
}

string defaultExtension(DataType type) {
	final switch(type) {
		case DataType.raw: return "bin";
		case DataType.structured: return "yaml";
		case DataType.bpp1: return "png";
		case DataType.bpp2Linear: return "png";
		case DataType.bpp2Intertwined: return "png";
		case DataType.bpp4Intertwined: return "png";
	}
}
struct SymbolMetadata {
	ROMSource[] sources;
	string name;
	string extension = "bin";
	bool array;
	DataType type;
	size_t originalLength;
	bool requiresExtraction() const @safe pure {
		return (sources.length != 0) && (type == DataType.structured);
	}
}

string assetPath(const scope SymbolMetadata symbol, size_t i) @safe pure {
	import std.math : ceil, log10;
	import std.format;
	if (!symbol.array) {
		return symbol.name;
	} else {
		return format!"%s/%0*d%s%s"(symbol.name, cast(int)ceil(log10(cast(float)symbol.sources.length)), i, symbol.extension != "" ? "." : "", symbol.extension);
	}
}

@safe pure unittest {
	assert(SymbolMetadata(name: "sample").assetPath(0) == "sample");
}

bool matches(const scope string path, const scope SymbolMetadata symbol) @safe pure {
	//import std.stdio; debug writeln(path, ", ", symbol);
	if (path == symbol.name) {
		return true;
	}
	if (path.equal(symbol.name.withExtension(symbol.extension))) {
		return true;
	}
	if (symbol.array) {
		string pathCopy = path;
		if (pathCopy.skipOver(symbol.name.chain(only('/')))) {
			// everything in the root of this subdirectory matches
			if (!pathCopy.canFind('/') && (pathCopy.extension.empty || pathCopy.extension.equal(only('.').chain(symbol.extension)))) {
				return true;
			}
		}
	}
	return false;
}

unittest {
	assert("sample".matches(SymbolMetadata(name: "sample")));
	assert("sample.bin".matches(SymbolMetadata(name: "sample")));
	assert(!"saple".matches(SymbolMetadata(name: "sample")));
	assert("sample/001".matches(SymbolMetadata(name: "sample", array: true)));
	assert(!"sample/somethingelse/001".matches(SymbolMetadata(name: "sample", array: true)));
	assert("sample/001.gfx".matches(SymbolMetadata(name: "sample", extension: "gfx", array: true)));
	assert("test/bytes2/3".matches(SymbolMetadata(name: "test/bytes2", array: true)));
}

private template useMultipleFiles(T) {
	static if (is(T : K[], K)) {
		enum useMultipleFiles = !isBasicType!K;
	} else {
		enum useMultipleFiles = false;
	}
}

unittest {
	static assert(!useMultipleFiles!(int));
	static assert(!useMultipleFiles!(int[]));
	static struct SomeStruct {
		int a;
	}
	static assert(useMultipleFiles!(SomeStruct[]));
	static assert(useMultipleFiles!(ubyte[0x40][]));
}

private template SymbolAssetName(alias Sym) {
	static if (isAsset!Sym) {
		enum SymbolAssetName = Filter!(typeMatches!Asset, __traits(getAttributes, Sym))[0].name;
	} else {
		enum SymbolAssetName = __traits(identifier, Sym);
	}
}
@safe pure unittest {
	static immutable foo = 3;
	assert(SymbolAssetName!foo == "foo");
	@Asset("whatever")
	static immutable bar = 5;
	assert(SymbolAssetName!bar == "whatever");
}
private template SymbolDataSingle(alias Sym) {
	static if (isROMLoadable!Sym || isAsset!Sym) {
		alias SymbolDataSingle = AliasSeq!(SymbolDataItem!Sym(SymbolMetadataFor!Sym));
	} else {
		alias SymbolDataSingle = AliasSeq!();
	}
}
private template SymbolMetadataFor(alias Sym) {
	alias AssetDefs = Filter!(typeMatches!Asset, __traits(getAttributes, Sym));
	alias SingleSource = Filter!(typeMatches!ROMSource, __traits(getAttributes, Sym));
	alias MultiSources = Filter!(typeMatches!(ROMSource[]), __traits(getAttributes, Sym));
	static if (AssetDefs.length == 1) {
		enum ThisAsset = () { auto asset = AssetDefs[0]; asset.forceMultipleFiles = MultiSources.length == 1; return asset; } ();
	} else {
		enum ThisAsset = Asset(name: __traits(identifier, Sym), type: DataType.raw, forceMultipleFiles: MultiSources.length == 1);
	}
	static if (isROMLoadable!Sym) {
		static if (SingleSource.length == 1) { // single source
			enum SymbolMetadataFor = SymbolMetadata([SingleSource], SymbolAssetName!Sym, defaultExtension(ThisAsset.type), useMultipleFiles!(typeof(Sym)) || ThisAsset.forceMultipleFiles, ThisAsset.type);
		} else static if (MultiSources.length == 1) { // array of sources
			enum SymbolMetadataFor = SymbolMetadata(MultiSources, SymbolAssetName!Sym, defaultExtension(ThisAsset.type), useMultipleFiles!(typeof(Sym)) || ThisAsset.forceMultipleFiles, ThisAsset.type);
		}
	} else static if (isAsset!Sym) { // not extracted, but expected to exist
		enum SymbolMetadataFor = SymbolMetadata([], SymbolAssetName!Sym, defaultExtension(ThisAsset.type), useMultipleFiles!(typeof(Sym)) || ThisAsset.forceMultipleFiles, ThisAsset.type);
	} else {
		static assert(0);
	}
}

@safe pure unittest {
	static int nothing;
	assert(SymbolDataSingle!nothing.length == 0);
	@Asset("foo")
	static immutable foo = 3;
	with(SymbolDataSingle!foo[0]) {
		assert(metadata.name == "foo");
		assert(metadata.sources == []);
		assert(!metadata.array);
		assert(metadata.type == DataType.raw);
		assert(metadata.assetPath(0) == "foo");
	}
	@Asset("foo2", DataType.bpp2Intertwined)
	static immutable foo2 = 3;
	with(SymbolDataSingle!foo2[0]) {
		assert(data == 3);
		assert(metadata.sources == []);
		assert(metadata.name == "foo2");
		assert(!metadata.array);
		assert(metadata.type == DataType.bpp2Intertwined);
		assert(metadata.assetPath(0) == "foo2");
	}
	// array is ignored, no elements can be added to this
	@Asset("foo3", DataType.bpp2Intertwined, forceMultipleFiles: true)
	static immutable int[4] foo3;
	with(SymbolDataSingle!foo3[0]) {
		assert(metadata.name == "foo3");
		assert(metadata.sources == []);
		assert(!metadata.array);
		assert(metadata.type == DataType.bpp2Intertwined);
		assert(metadata.assetPath(0) == "foo3");
	}
	@ROMSource(123, 0x456)
	@Asset("foo4")
	static immutable int[4] foo4;
	with(SymbolDataSingle!foo4[0]) {
		assert(metadata.name == "foo4");
		assert(metadata.sources[0].offset == 123);
		assert(metadata.sources[0].length == 0x456);
		assert(!metadata.array);
		assert(metadata.type == DataType.raw);
		assert(metadata.assetPath(0) == "foo4");
	}
	@([ROMSource(123, 2), ROMSource(1234, 6)])
	@Asset("foo5")
	static immutable int[4] foo5;
	with(SymbolDataSingle!foo5[0]) {
		assert(metadata.name == "foo5");
		assert(metadata.sources[0].offset == 123);
		assert(metadata.sources[0].length == 2);
		assert(metadata.sources[1].offset == 1234);
		assert(metadata.sources[1].length == 6);
		assert(metadata.array);
		assert(metadata.type == DataType.raw);
		assert(metadata.assetPath(0) == "foo5/0.bin");
		assert(metadata.assetPath(0).matches(metadata));
		assert(metadata.assetPath(1) == "foo5/1.bin");
		assert(metadata.assetPath(1).matches(metadata));
	}
	@([ROMSource(0x0, 0x1), ROMSource(0x1, 0x1), ROMSource(0x2, 0x1), ROMSource(0x3, 0x1)])
	@Asset("test/bytes2", DataType.raw)
	static ubyte[] sample2;
	with(SymbolDataSingle!sample2[0]) {
		assert(metadata.name == "test/bytes2");
		assert(metadata.sources[0].offset == 0);
		assert(metadata.sources[0].length == 1);
		assert(metadata.array);
		assert(metadata.type == DataType.raw);
		assert(metadata.assetPath(0) == "test/bytes2/0.bin");
		assert(metadata.assetPath(0).matches(metadata));
		assert(metadata.assetPath(1) == "test/bytes2/1.bin");
		assert(metadata.assetPath(1).matches(metadata));
	}
	@ROMSource(0, 0x40 * 16)
	@Asset("test/directory", DataType.bpp2Intertwined)
	static immutable(ubyte[0x40])[] graphicsIcons;
	with (SymbolDataSingle!graphicsIcons[0]) {
		assert(metadata.name == "test/directory");
		assert(metadata.sources[0].offset == 0);
		assert(metadata.sources[0].length == 1024);
		assert(metadata.array);
		assert(metadata.extension == "png");
		assert(metadata.type == DataType.bpp2Intertwined);
		assert(metadata.assetPath(0) == "test/directory/0.png");
		assert(metadata.assetPath(0).matches(metadata));
		assert(metadata.assetPath(1) == "test/directory/1.png");
		assert(metadata.assetPath(1).matches(metadata));
	}
	@ROMSource(0, 16)
	static immutable(ushort[2])[] sample3;
	with(SymbolDataSingle!sample3[0]) {
		assert(metadata.name == "sample3");
		assert(metadata.sources[0].offset == 0);
		assert(metadata.sources[0].length == 16);
		assert(metadata.array);
		assert(metadata.type == DataType.raw);
		assert(metadata.assetPath(0) == "sample3/0.bin");
		assert(metadata.assetPath(0).matches(metadata));
		assert(metadata.assetPath(1) == "sample3/1.bin");
		assert(metadata.assetPath(1).matches(metadata));
	}
}
template SymbolData(mods...) {
	alias SymbolData = AliasSeq!();
	static foreach (mod; mods) {
		static foreach (member; __traits(allMembers, mod)) { // look for loadable things in module
			static if (!is(typeof(__traits(getMember, mod, member)) == function)) {
				SymbolData = AliasSeq!(SymbolData, SymbolDataSingle!(__traits(getMember, mod, member)));
			}
		}
	}
}
struct Progress {
	string title;
	uint completedItems = 0;
	uint totalItems = 1;
}


struct PlanetArchive {
	private UnboxEntry[] loaded;
	private InfoBoxEntry[] files;
	void addFile(scope const(char)[] name, const(ubyte)[] data)
		in(!files.map!(x => x.path).canFind(name), name~" already exists in archive!")
	{
		files ~= infoEntry(BoxEntryInfo(name.idup), only(data));
	}
	void write(OutputRange)(OutputRange range) {
		import std.algorithm.mutation : copy;
		if (files.length > 0) {
			copy(files.boxZip(), range);
		}
	}
	static PlanetArchive read(ubyte[] buffer) {
		return PlanetArchive(buffer.unboxZip.array);
	}
	private struct Entry {
		string name;
		ubyte[] data;
	}
	auto entries() {
		return loaded.map!(x => Entry(x.path, x.readContent));
	}
	bool empty() const @safe pure {
		return files.length == 0;
	}
}

private const(ubyte)[] readTilesFromImage(T)(const(ubyte)[] data) {
	if (auto img = cast(IndexedImage)readPngFromBytes(data)) {
		auto pixelArray = img.data;
		auto tiles = Array2D!T(img.width / 8, img.height / 8);
		foreach (x, y, pixel; pixelArray) {
			enforce(pixel < 2 ^^ T.bpp, "Source image colour out of range!");
			tiles[x / 8, y / 8][x % 8, y % 8] = pixel;
		}
		return cast(ubyte[])(tiles[]);
	} else { // not an indexed PNG?
		throw new Exception("Invalid PNG");
	}
}
private const(ubyte)[] saveTilesToImage(T)(const(T)[] tiles) {
	const w = min(tiles.length * 8, 16 * 8);
	const h = max(1, cast(int)((tiles.length + 15) / 16)) * 8;
	auto img = new IndexedImage(w, h);
	auto pixelArray = img.data;
	const colours = 1 << T.bpp;
	foreach (i; 0 .. colours) {
		ubyte g = cast(ubyte)((255 / colours) * (colours - i));
		img.addColor(RGBA32(red: g, green: g, blue: g, alpha: i == 0 ? 0 : 255));
	}
	foreach (tileID, tile; tiles) {
		foreach (colIdx; 0 .. 8) {
			foreach (rowIdx; 0 .. 8) {
				pixelArray[(tileID % (w / 8)) * 8 + colIdx, (tileID / (w / 8)) * 8 + rowIdx] = tile[colIdx, rowIdx];
			}
		}
	}
	return writePngToArray(img);
}
const(ubyte)[] loadROMAsset(const(ubyte)[] data, SymbolMetadata asset) {
	final switch (asset.type) {
		case DataType.raw:
		case DataType.structured: // array of characters, array of bytes. same thing
			return data;
		case DataType.bpp1:
			return readTilesFromImage!Simple1BPP(data);
		case DataType.bpp2Linear:
			return readTilesFromImage!Linear2BPP(data);
		case DataType.bpp2Intertwined:
			return readTilesFromImage!Intertwined2BPP(data);
		case DataType.bpp4Intertwined:
			return readTilesFromImage!Intertwined4BPP(data);
	}
}
const(ubyte)[] saveROMAsset(const(ubyte)[] data, SymbolMetadata asset) {
	final switch (asset.type) {
		case DataType.raw:
			return data;
		case DataType.bpp2Linear:
			return saveTilesToImage(cast(const(Linear2BPP)[])data);
		case DataType.bpp1:
			return saveTilesToImage(cast(const(Simple1BPP)[])data);
		case DataType.bpp2Intertwined:
			return saveTilesToImage(cast(const(Intertwined2BPP)[])data);
		case DataType.bpp4Intertwined:
			return saveTilesToImage(cast(const(Intertwined4BPP)[])data);
		case DataType.structured:
			assert(0);
	}
}
