#!/bin/sh
# Assembles the monitor and builds it into ../mini6502.bas.
# Needs the cc65 suite (ca65, ld65): e.g. "sudo apt install cc65".
set -e
cd "$(dirname "$0")"
ca65 -I ../hw monitor.asm -o monitor.o -l monitor.lst
ld65 -C monitor.cfg monitor.o -o monitor.bin -m monitor.map
python3 rom2data.py monitor.bin ../mini6502.bas
echo "Done. Recompile mini6502.bas, or copy monitor.bin next to the program to try it without recompiling."
