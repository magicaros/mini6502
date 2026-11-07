#!/usr/bin/env python3
"""Writes a binary as a monitor hex dump ("ADDR: BB BB ...", 8 bytes a line),
the format mini6502 loads from the command line or with F5.
usage: python3 bin2hex.py file.bin LOADADDR(hex) > file.hex
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING."""
import sys
data = open(sys.argv[1], "rb").read(); addr = int(sys.argv[2], 16)
for off in range(0, len(data), 8):
    print(f"{addr + off:04X}: " + " ".join(f"{b:02X}" for b in data[off:off + 8]))
