#!/bin/sh
# Builds Breakout: breakout.bin / .hex and BREAKOUT (disk file, load address
# $0800 first). Needs cc65 (ca65, ld65) and python3.
set -e
cd "$(dirname "$0")"
ca65 -I ../../hw breakout.asm -o breakout.o -l breakout.lst
ld65 -C breakout.cfg breakout.o -o breakout.bin -m breakout.map
rm -f breakout.o
python3 ../../basic/bin2hex.py breakout.bin 0800 > breakout.hex
python3 -c "d=open('breakout.bin','rb').read(); open('BREAKOUT','wb').write(bytes([0,8])+d); print('BREAKOUT', len(d), 'bytes')"
