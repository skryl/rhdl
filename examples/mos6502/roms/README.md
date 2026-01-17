# Apple II ROM Images

## appleiigo.rom (Public Domain)

This is a **public domain** Apple II replacement ROM written by Marc Ressl in 2006
specifically for use with emulators. It can run most Apple II software that doesn't
require Applesoft BASIC.

- **Size**: 12KB (12288 bytes)
- **Load Address**: $D000-$FFFF
- **License**: Public Domain
- **Source**: [AppleIIGo ROMs](https://a2go.applearchives.com/roms/)

### Usage

```bash
# Run with the AppleIIGo ROM
bin/apple2 -r examples/mos6502/roms/appleiigo.rom --rom-address D000

# Or use the rake task
rake apple2:run
```

## mini_monitor.asm (Custom)

A simple monitor ROM written for this project that provides basic keyboard echo
functionality. Useful for testing the emulator without needing external ROMs.

- **Size**: 2KB assembled
- **Load Address**: $F800-$FFFF
- **License**: Same as RHDL project

### Building

```bash
rake apple2:build
```

## Legal Note

The `appleiigo.rom` file is public domain software created specifically for
emulation purposes. It is not copyrighted Apple software.

If you need full Apple II compatibility (including Applesoft BASIC), you would
need actual Apple II ROM images, which are copyrighted by Apple Inc.
