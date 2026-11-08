#!/bin/sh
# Native assembler application and its on-demand fixed-RAM core.
# Usage: sh asm/build.sh [output-directory]; requires ca65, ld65, python3.
set -eu
cd "$(dirname "$0")"
out=${1:-build}
mkdir -p "$out"
out=$(cd "$out" && pwd)
ca65 -g -I ../hw -I . asm.asm -o "$out/asm.o"
ld65 -C ../edit/edit.cfg "$out/asm.o" -o "$out/asm.bin" -Ln "$out/asm.labels"
ca65 -g -I ../hw -I . core.asm -o "$out/core.o"
ld65 -C core.cfg "$out/core.o" -o "$out/core.bin" -Ln "$out/core.labels"
python3 ../basic/bin2hex.py "$out/asm.bin" E000 > "$out/asm.hex"
python3 - "$out" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
for source, name, address in [('asm.bin', 'ASM', 0xe000), ('core.bin', 'ASMCORE', 0x8400)]:
    body = (p / source).read_bytes()
    (p / name).write_bytes(address.to_bytes(2, 'little') + body)
    print(f'{name}: {len(body)} bytes at ${address:04X}')
(p / 'HELLO.ASM').write_bytes(b'\x00\x04' + Path('hello.asm').read_text().replace('\n', '\r').encode('ascii'))
PY
