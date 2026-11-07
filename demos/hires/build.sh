#!/bin/sh
# Builds the graphics demo: hidemo.bin, hidemo.hex and HIDEMO (disk file,
# 2-byte load address $E000 first). Needs cc65 (ca65, ld65) and python3.
set -e
cd "$(dirname "$0")"
python3 icons.py
ca65 -I ../../hw hidemo.asm -o hidemo.o -l hidemo.lst
ld65 -C hidemo.cfg hidemo.o -o hidemo.bin -m hidemo.map
python3 ../../basic/bin2hex.py hidemo.bin E000 > hidemo.hex
python3 -c "import sys; d=open('hidemo.bin','rb').read(); open('HIDEMO','wb').write(bytes([0,0xE0])+d)"
echo "Done: hidemo.bin / hidemo.hex / HIDEMO ($(wc -c < hidemo.bin) bytes)"
