#!/bin/sh
# Builds the interrupt tune: irqtune.bin / .hex and IRQTUNE (disk file, load
# address $E000 first). Needs cc65 (ca65, ld65) and python3.
set -e
cd "$(dirname "$0")"
ca65 -I ../../hw irqtune.asm -o irqtune.o -l irqtune.lst
ld65 -C irqtune.cfg irqtune.o -o irqtune.bin -m irqtune.map
rm -f irqtune.o
python3 ../../basic/bin2hex.py irqtune.bin E000 > irqtune.hex
python3 -c "d=open('irqtune.bin','rb').read(); open('IRQTUNE','wb').write(bytes([0,0xE0])+d); print('IRQTUNE', len(d), 'bytes')"
