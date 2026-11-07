#!/bin/sh
# Assembles the editor into edit.bin and edit.hex (for bank RAM at $E000).
# Needs the cc65 suite (ca65, ld65): e.g. "sudo apt install cc65".
set -e
cd "$(dirname "$0")"
ca65 -I ../hw edit.asm -o edit.o -l edit.lst
ld65 -C edit.cfg edit.o -o edit.bin -m edit.map
python3 ../basic/bin2hex.py edit.bin E000 > edit.hex
echo "Done: edit.bin / edit.hex. In the monitor: D020: 01, then L EDIT E000 01 (after saving it) or load edit.hex"
