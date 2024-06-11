module replatform64.assets;

import std.meta;

enum DataType {
    raw,
    bpp2intertwined
}

struct ROMSource {
	uint offset;
	uint length;
    DataType type;
}

private enum isROMLoadable(alias sym) = (Filter!(typeMatches!ROMSource, __traits(getAttributes, sym)).length == 1) || (Filter!(typeMatches!(ROMSource[]), __traits(getAttributes, sym)).length == 1);

template typeMatches(T) {
	enum typeMatches(alias t) = is(typeof(t) == T);
}

struct SymbolDataItem(alias Sym) {
    ROMSource[] sources;
    string name;
    bool array;
    alias data = Sym;
}

template SymbolData(mods...) {
    alias SymbolData = AliasSeq!();
    static foreach (mod; mods) {
        static foreach (member; __traits(allMembers, mod)) { // look for loadable things in module
            static if (!is(typeof(__traits(getMember, mod, member)) == function) && isROMLoadable!(__traits(getMember, mod, member))) {
                static if (Filter!(typeMatches!ROMSource, __traits(getAttributes, __traits(getMember, mod, member))).length == 1) { // single source
                    SymbolData = AliasSeq!(SymbolData, SymbolDataItem!(__traits(getMember, mod, member))([Filter!(typeMatches!ROMSource, __traits(getAttributes, __traits(getMember, mod, member)))[0]], member, false));
                } else static if (Filter!(typeMatches!(ROMSource[]), __traits(getAttributes, __traits(getMember, mod, member))).length == 1) { // array of sources
                    SymbolData = AliasSeq!(SymbolData, SymbolDataItem!(__traits(getMember, mod, member))(Filter!(typeMatches!(ROMSource[]), __traits(getAttributes, __traits(getMember, mod, member)))[0], member, true));
                }
            }
        }
    }
}