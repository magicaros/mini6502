#!/bin/sh
# Builds the lullaby demo: song.inc (from song.py), lullaby.bin, lullaby.hex,
# and LULLABY (a disk file: 2-byte address + code). Needs cc65 and python3.
set -e
cd "$(dirname "$0")"
python3 song.py
ca65 -I ../../hw lullaby.asm -o lullaby.o -l lullaby.lst
ld65 -C lullaby.cfg lullaby.o -o lullaby.bin -m lullaby.map
python3 ../../basic/bin2hex.py lullaby.bin E000 > lullaby.hex
python3 -c "import sys; d=open('lullaby.bin','rb').read(); open('LULLABY','wb').write(bytes([0,0xE0])+d)"
echo "Done. Copy LULLABY into the disk folder, then in the monitor: L LULLABY E000 02 / D020: 02 / E000R"
