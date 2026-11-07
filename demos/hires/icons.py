#!/usr/bin/env python3
"""Writes icons.inc: hires icons for STAMP (16x16, one byte per pixel:
0 = PAPER, 1 = INK, $80 = see-through).
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
"""
ICONS = {
 "disk": [
  "1111111111111110",
  "1000100000010011",
  "1000100000010001",
  "1000100000010001",
  "1000111111110001",
  "1000000000000001",
  "1000000000000001",
  "1011111111111101",
  "1010000000000101",
  "1010111111110101",
  "1010000000000101",
  "1010111111110101",
  "1010000000000101",
  "1010000000000101",
  "1111111111111111",
  "................"],
 "doc": [
  "..1111111111....",
  "..1000000001100.",
  "..10000000010100",
  "..10111110011110",
  "..10000000000010",
  "..10111111110010",
  "..10000000000010",
  "..10111111110010",
  "..10000000000010",
  "..10111111110010",
  "..10000000000010",
  "..10111110000010",
  "..10000000000010",
  "..11111111111110",
  "................",
  "................"],
}
with open("icons.inc", "w") as f:
    f.write("; made by icons.py: 0 paper, 1 ink, $80 see-through\n")
    for name, rows in ICONS.items():
        f.write(f"; {name}\n")
        for r in rows:
            f.write("        .byte " + ",".join("$80" if c == "." else f"${int(c):02X}" for c in r) + "\n")
