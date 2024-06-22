module replatform64.assets;

import std.meta;

enum DataType {
    raw,
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