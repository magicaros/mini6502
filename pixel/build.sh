#!/bin/sh
# Builds PIXEL (the loader, for a bank: $E000) and PIXEL2 (main RAM,
# $0800) from pixel.asm. Needs cc65 (ca65, ld65)
# and python3 (the oval table comes from ../paint/ovaltab.py).
set -e
cd "$(dirname "$0")"
(cd ../paint && python3 ovaltab.py)
ca65 -g -I ../hw pixel.asm -o pixel.o -l pixel.lst
ld65 -C pixel.cfg pixel.o -m pixel.map -Ln pixel.lbl
rm -f pixel.o
python3 -c "
for f, n, a in (('pixel.bin', 'PIXEL', 0xE000), ('pixel2.bin', 'PIXEL2', 0x0800)):
    d = open(f, 'rb').read()
    open(n, 'wb').write(bytes([a & 255, a >> 8]) + d)
    print(n, len(d), 'bytes')
"
