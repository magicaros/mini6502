#!/bin/sh
# Builds PAINT (for a bank, $E000) and PAINT2 (main RAM, $0800) from
# paint.asm (+ paint2.inc, paint3.inc). Needs cc65 (ca65, ld65) and python3.
set -e
cd "$(dirname "$0")"
python3 icons.py
python3 ovaltab.py
ca65 -g -I ../hw -I ../toolkit paint.asm -o paint.o -l paint.lst
ld65 -C paint.cfg paint.o -m paint.map -Ln paint.lbl
rm -f paint.o
python3 -c "
for f, n, a in (('paint.bin', 'PAINT', 0xE000), ('paint2.bin', 'PAINT2', 0x0800)):
    d = open(f, 'rb').read()
    open(n, 'wb').write(bytes([a & 255, a >> 8]) + d)
    print(n, len(d), 'bytes')
"
