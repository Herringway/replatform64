# Replatform64, the console game porting framework

## Summary

Replatform64 is a collection of libraries designed to simplify porting games for old consoles to modern systems.

Currently supported systems include:

- SNES
- NES (Untested)
- Gameboy

Planned systems include:

- Gameboy Advance
- Sega Genesis

## Features

### Compatibility with modern OSes and hardware

Runs on all CPU architectures D and the backends support (pretty much anything SDL, LLVM and/or GCC support at this time)

#### Available backends

- SDL 2

#### OS Support

- Windows
- Linux
- FreeBSD
- MacOS (Not frequently tested, but no known problems)

#### Input support

- Keyboard
- Gamepad
- Touchscreen (WIP)

### Advanced debug UI support

An advanced debugging UI for viewing and editing game state, hardware state, and more in real time.

![Debug UI](debug%20ui.png)

### Asset packing and replacement

Replatform64 supports extracting assets from ROMs on its own and repacks them into archives that are easy to modify.

### Automatic crash and hang detection

When a crash or hang occurs, Replatform64 can dump handy information like the screen contents and last executed code to disk for later examination.

### Unit Testing Framework

Easy support for unit testing using a null backend, so you can start testing early on.

### Higher resolution rendering

Replatform64 supports rendering at non-native resolutions, offering the possibility of widescreen games.
