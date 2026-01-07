module replatform64._test;

version(unittest):

import replatform64.util;

mixin generateStateDumpFunctions;

@DumpableGameState __gshared:
int foo;
