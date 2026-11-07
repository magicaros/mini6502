#!/bin/sh
# Builds the BASIC extensions: GFX (bank $00) and DOS (bank $01), each as
# NAME.bin / name.hex and the disk file NAME (load address $E000 first).
# Needs cc65 (ca65, ld65) and python3.
set -e
cd "$(dirname "$0")"
for f in gfx dos; do
    ca65 -I ../hw $f.asm -o $f.o -l $f.lst
    ld65 -C gfx.cfg $f.o -o $f.bin -m $f.map
    rm -f $f.o
    python3 ../basic/bin2hex.py $f.bin E000 > $f.hex
    python3 -c "import sys; f=sys.argv[1]; d=open(f+'.bin','rb').read(); open(f.upper(),'wb').write(bytes([0,0xE0])+d); print(f.upper(), len(d), 'bytes')" $f
done
