#!/bin/sh
# Builds the graphics demo: gfxdemo.bin, gfxdemo.hex and GFXDEMO (disk file,
# 2-byte load address $E000 first). Needs cc65 (ca65, ld65) and python3.
set -e
cd "$(dirname "$0")"
python3 images.py
ca65 -I ../../hw gfxdemo.asm -o gfxdemo.o -l gfxdemo.lst
ld65 -C gfxdemo.cfg gfxdemo.o -o gfxdemo.bin -m gfxdemo.map
python3 ../../basic/bin2hex.py gfxdemo.bin E000 > gfxdemo.hex
python3 -c "import sys; d=open('gfxdemo.bin','rb').read(); open('GFXDEMO','wb').write(bytes([0,0xE0])+d)"
echo "Done: gfxdemo.bin / gfxdemo.hex / GFXDEMO ($(wc -c < gfxdemo.bin) bytes)"
