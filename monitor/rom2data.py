#!/usr/bin/env python3
"""Puts monitor.bin into mini6502.bas as DATA lines (between the
"' --- BEGIN MONITOR ROM ---" and "' --- END MONITOR ROM ---" markers).

usage: python3 rom2data.py [monitor.bin] [../mini6502.bas]

Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

The ROM is placed so that it ends at $FFFF. Each DATA line holds 32 bytes as
"ADDR:HEX..."; lines that are all $FF (unused ROM) are left out, since the
loader fills the ROM with $FF first."""
import sys

rom_file = sys.argv[1] if len(sys.argv) > 1 else "monitor.bin"
bas_file = sys.argv[2] if len(sys.argv) > 2 else "../mini6502.bas"
BEGIN, END = "' --- BEGIN MONITOR ROM ---", "' --- END MONITOR ROM ---"

rom = open(rom_file, "rb").read()
if not 0 < len(rom) <= 4096:
    sys.exit(f"{rom_file}: {len(rom)} bytes, expected 1 to 4096")
base = 0x10000 - len(rom)

lines = []
for off in range(0, len(rom), 32):
    chunk = rom[off:off + 32]
    if chunk.count(0xFF) == len(chunk):
        continue
    lines.append(f'DATA "{base + off:04X}:{chunk.hex().upper()}"')

src = open(bas_file, newline="").read()
nl = "\r\n" if "\r\n" in src else "\n"
a, b = src.index(BEGIN), src.index(END)
src = src[:a] + BEGIN + nl + nl.join(lines) + nl + src[b:]
open(bas_file, "w", newline="").write(src)
print(f"{len(lines)} DATA lines from {rom_file} ({len(rom)} bytes at ${base:04X}) written to {bas_file}")
