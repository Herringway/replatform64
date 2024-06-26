module replatform64.assets;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.array;
import std.exception;
import std.meta;
import std.range;

import replatform64.backend.common.interfaces;
import replatform64.ui;
import replatform64.util;

import arsd.png;
import pixelatrix;
import squiz_box;

alias ProgressUpdateFunction = void delegate(scope const Progress);
alias AddFileFunction = void delegate(string, const ubyte[]);
alias ExtractFunction = void function(scope AddFileFunction, scope ProgressUpdateFunction, immutable(ubyte)[]);
alias LoadFunction = void function(const scope char[], const scope ubyte[], scope PlatformBackend);

enum DataType {
	raw,
	structured,
	bpp2Intertwined,
	bpp4Intertwined,
}

struct ROMSource {
	uint offset;
	uint length;
}

struct Asset {
	string name;
	DataType type;
	bool array;
}

private enum isROMLoadable(alias sym) = (Filter!(typeMatches!ROMSource, __traits(getAttributes, sym)).length == 1) || (Filter!(typeMatches!(ROMSource[]), __traits(getAttributes, sym)).length == 1);
private enum isAsset(alias sym) = Filter!(typeMatches!Asset, __traits(getAttributes, sym)).length == 1;

template typeMatches(T) {
	enum typeMatches(alias t) = is(typeof(t) == T);
}

struct SymbolDataItem(alias Sym) {
	ROMSource[] sources;
	string name;
	bool array;
	DataType type;
	alias data = Sym;
	bool requiresExtraction() const @safe pure {
		return (sources.length != 0) && (type == DataType.structured);
	}
}

private template SymbolAssetName(alias Sym) {
	static if (isAsset!Sym) {
		enum SymbolAssetName = Filter!(typeMatches!Asset, __traits(getAttributes, Sym))[0].name;
	} else {
		enum SymbolAssetName = __traits(identifier, Sym);
	}
}
private template SymbolDataSingle(alias Sym) {
	alias SymbolDataSingle = AliasSeq!();
	alias AssetDefs = Filter!(typeMatches!Asset, __traits(getAttributes, Sym));
	alias SingleSource = Filter!(typeMatches!ROMSource, __traits(getAttributes, Sym));
	alias MultiSources = Filter!(typeMatches!(ROMSource[]), __traits(getAttributes, Sym));
	static if (AssetDefs.length == 1) {
		enum ThisAsset = AssetDefs[0];
	} else {
		enum ThisAsset = Asset(name: __traits(identifier, Sym), type: DataType.raw, MultiSources.length == 1);
	}
	static if (isROMLoadable!Sym) {
		static if (SingleSource.length == 1) { // single source
			SymbolDataSingle = AliasSeq!(SymbolDataItem!Sym([SingleSource], SymbolAssetName!Sym, ThisAsset.array, ThisAsset.type));
		} else static if (MultiSources.length == 1) { // array of sources
			SymbolDataSingle = AliasSeq!(SymbolDataItem!Sym(MultiSources, SymbolAssetName!Sym, ThisAsset.array, ThisAsset.type));
		}
	} else static if (isAsset!Sym) { // not extracted, but expected to exist
		SymbolDataSingle = AliasSeq!(SymbolDataItem!Sym([], SymbolAssetName!Sym, ThisAsset.array, ThisAsset.type));
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
		copy(files.boxZip(), range);
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
}

private const(ubyte)[] readTilesFromImage(T)(const(ubyte)[] data) {
	if (auto img = cast(IndexedImage)readPngFromBytes(data)) {
		auto pixelArray = Array2D!ubyte(img.width, img.height, img.width, img.data);
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
	auto pixelArray = Array2D!ubyte(w, h, img.data);
	const colours = 1 << T.bpp;
	foreach (i; 0 .. colours) {
		ubyte g = cast(ubyte)((255 / colours) * (colours - i));
		img.addColor(Color(g, g, g, i == 0 ? 0 : 255));
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
const(ubyte)[] loadROMAsset(const(ubyte)[] data, DataType type) {
	final switch (type) {
		case DataType.raw:
			return data;
		case DataType.bpp2Intertwined:
			return readTilesFromImage!Intertwined2BPP(data);
		case DataType.bpp4Intertwined:
			return readTilesFromImage!Intertwined4BPP(data);
		case DataType.structured:
			assert(0);
	}
}
const(ubyte)[] saveROMAsset(const(ubyte)[] data, DataType type) {
	final switch (type) {
		case DataType.raw:
			return data;
		case DataType.bpp2Intertwined:
			return saveTilesToImage(cast(const(Intertwined2BPP)[])data);
		case DataType.bpp4Intertwined:
			return saveTilesToImage(cast(const(Intertwined4BPP)[])data);
		case DataType.structured:
			assert(0);
	}
}
