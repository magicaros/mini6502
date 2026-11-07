#!/bin/sh
# Builds TRACKER (for a bank, $E000) and TRACKER2 (main RAM, $0800) from
# tracker.asm. Needs cc65 (ca65, ld65) and python3.
set -e
cd "$(dirname "$0")"
ca65 -I ../hw -I ../toolkit tracker.asm -o tracker.o -l tracker.lst
ld65 -C tracker.cfg tracker.o -m tracker.map
rm -f tracker.o
python3 -c "
for f, n, a in (('tracker.bin', 'TRACKER', 0xE000), ('tracker2.bin', 'TRACKER2', 0x0800)):
    d = open(f, 'rb').read()
    open(n, 'wb').write(bytes([a & 255, a >> 8]) + d)
    print(n, len(d), 'bytes')
"
