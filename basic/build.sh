#!/bin/sh
# Assembles EhBASIC for mini6502 into basic.bin and basic.hex (load at $A000).
# Needs the cc65 suite (ca65, ld65): e.g. "sudo apt install cc65".
set -e
cd "$(dirname "$0")"
ca65 -I ../hw --feature labels_without_colons mini6502_basic.asm -o basic.o -l basic.lst
ld65 -C basic.cfg basic.o -o basic.bin -m basic.map
python3 bin2hex.py basic.bin A000 > basic.hex
echo "Done: basic.hex. Run:  mini6502 basic/basic.hex basic/basic.txt"
