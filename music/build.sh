#!/bin/sh
# Builds the music engine (music.bin / .hex, MUSIC: disk file for bank $12)
# and the demo song (DEMO.MUS from demo.txt). Needs cc65 and python3.
set -e
cd "$(dirname "$0")"
ca65 -I ../hw music.asm -o music.o -l music.lst
ld65 -C music.cfg music.o -o music.bin -m music.map
rm -f music.o
python3 ../basic/bin2hex.py music.bin E000 > music.hex
python3 -c "d=open('music.bin','rb').read(); open('MUSIC','wb').write(bytes([0,0xE0])+d); print('MUSIC', len(d), 'bytes')"
python3 mus.py demo.txt DEMO.MUS
