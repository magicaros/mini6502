#!/usr/bin/env python3
"""gen.py - makes everything that comes from hw/mini6502.def.
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.

usage: python3 hw/gen.py          (from anywhere)
writes hw/mini6502.inc, hw/REGISTERS.txt, disk-ready hw/VECTORS, and the
description at the top of mini6502.bas (between "' Memory map" and
"' The keyboard and display registers"), then runs hw/check.py.
"""
import os, re, subprocess, sys, textwrap

HW = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(HW)


def num(s):
    s = s.strip()
    return int(s[1:], 16) if s.startswith("$") else int(s, 0)


def parse(path=os.path.join(HW, "mini6502.def")):
    d = {"doc": [], "reg": [], "const": [], "zone": [], "bank": [], "entry": [],
         "stub": [], "sys": [], "owner": [], "spare": []}
    in_doc = True
    for n, line in enumerate(open(path).read().split("\n"), 1):
        if line.startswith("#"):
            continue
        if line.startswith("@equates"):
            in_doc = False
            continue
        if line.startswith("@table"):
            d["doc"].append(("table", line.split()[1]))
            continue
        if not line.startswith("@"):
            if in_doc:
                d["doc"].append(("text", line))
            elif line.strip():
                sys.exit(f"mini6502.def line {n}: text after @equates")
            continue
        w = line.split()
        kind = w[0][1:]
        try:
            if kind == "reg":
                acc = w[3]
                if acc not in ("r", "w", "rw", "0"):
                    raise ValueError("access must be r, w, rw or 0")
                d["reg"].append((w[1], num(w[2]), acc, int(w[4]) if len(w) > 4 else 1))
            elif kind == "spare":
                d["spare"].append((num(w[1]), int(w[2]), " ".join(w[3:])))
            elif kind == "const":
                d["const"].append((w[1], num(w[2])))
            elif kind == "zone":
                d["zone"].append((num(w[1]), num(w[2]), w[3], " ".join(w[4:])))
            elif kind in ("bank", "stub"):
                cnt = 1
                rest = w[2:]
                if rest[0].isdigit():
                    cnt = int(rest[0])
                    rest = rest[1:]
                d[kind].append((num(w[1]), cnt, rest[0], " ".join(rest[1:])))
            elif kind == "entry":
                d["entry"].append((num(w[1]), w[2], num(w[3]), num(w[4]), " ".join(w[5:])))
            elif kind == "sys":
                d["sys"].append((num(w[1]), w[2], " ".join(w[3:])))
            elif kind == "owner":
                d["owner"].append((num(w[1]), w[2], " ".join(w[3:])))
            else:
                raise ValueError(f"unknown @{kind}")
        except (IndexError, ValueError) as e:
            sys.exit(f"mini6502.def line {n}: {e}")
    return d


def const(d, name):
    for n, v in d["const"]:
        if n == name:
            return v
    sys.exit(f"mini6502.def: no @const {name}")


def entry_addr(d, n):
    return const(d, "VTENTRY") + 8 * n


def wrap(first, text, width=78):
    """first is the start of the line (fixed width); text wraps under it"""
    ind = " " * len(first)
    lines = textwrap.wrap(text, width - len(first)) or [""]
    return [first + lines[0]] + [ind + l for l in lines[1:]]


def tables(d, name):
    out = []
    if name == "zones":
        out.append("   Banks: 256 of 4K at $E000-$EFFF (BANK), in zones:")
        for lo, hi, nm, txt in d["zone"]:
            out += wrap(f"     ${lo:02X}-${hi:02X}  {nm:<10}", txt)
    elif name == "banks":
        out.append("   Banks with a fixed use:")
        for b, cnt, nm, txt in d["bank"]:
            r = f"${b:02X}" if cnt == 1 else f"${b:02X}-${b + cnt - 1:02X}"
            out += wrap(f"     {r:<8} {nm:<10}", txt)
    elif name == "page":
        vt, names, bmap, vmax = const(d, "VTAB"), const(d, "VTNAMES"), const(d, "BANKMAP"), const(d, "VTMAX")
        out += [
            "   System page ($CC00-$CFFF, never swapped out):",
            f"     ${vt:04X}  \"VT\", then the number of entries in use, 5 bytes reserved",
            f"     ${entry_addr(d, 0):04X}  far-call entries $00-${vmax - 1:02X}, 8 bytes each: JSR $FFD0 / bank /",
            "            address / 2 spare bytes. Entry NN is at $CC08 + 8 * NN: JSR",
            "            there, or CALL 52232+8*NN in BASIC (V lists them, V NN BB",
            "            HHHH NAME sets one)",
            f"     ${names:04X}  their names, 8 bytes each (0 = none, else up to 8",
            f"            characters, 0 after shorter ones): VFIND looks them up",
            f"     ${names + 8 * vmax:04X}  the system calls' variables (8 bytes), then reserved",
            f"     ${bmap:04X}  BANK MAP: one byte per bank, its owner:",
        ]
        for v, nm, txt in d["owner"]:
            out += wrap(f"              ${v:02X} {nm:<7}", txt)
        out += wrap("              $01-$FC", "the bank of the program that owns it")
        out += [
            "            Set at power-on (zones $00-$1F and $C0-$FF reserved); the",
            "            monitor's B command lists it. Save the table (not the map)",
            f"            with S VECTORS CC00.{bmap - 1:04X}.",
        ]
    elif name == "entries":
        out.append("   Far-call entries:")
        rows = [(n, nm, f"bank ${b:02X} ${a:04X}  {txt}") for n, nm, b, a, txt in d["entry"]]
        rows += [(n, nm, txt + ("" if c == 1 else f" ({c} entries)")) for n, c, nm, txt in d["stub"]]
        for n, nm, txt in sorted(rows):
            out += wrap(f"     ${n:02X} ${entry_addr(d, n):04X} {nm:<8} ", txt)
    elif name == "syscalls":
        out.append("   System calls in the ROM (JSR, from anywhere; banks: see the bank map):")
        for a, nm, txt in d["sys"]:
            out += wrap(f"     ${a:04X} {nm:<9}", txt)
    else:
        sys.exit(f"mini6502.def: unknown @table {name}")
    return out


def doc_lines(d):
    out = []
    for kind, v in d["doc"]:
        out += tables(d, v) if kind == "table" else [v]
    while out and not out[-1].strip():
        out.pop()
    while out and not out[0].strip():
        out.pop(0)
    return out


def inc_text(d):
    o = ["; mini6502.inc - made by hw/gen.py from hw/mini6502.def: edit that, not this.",
         "; Copyright (C) 2026 Benoit Colson, with the help of Claude AI; GNU GPL 3 or later (COPYING).",
         "; The mini6502's registers, banks, far-call entries and system calls.",
         "; In a program: .include \"mini6502.inc\" (ca65 -I path/to/hw). Including it",
         "; twice is fine.", "", ".ifndef MINI6502_INC", "MINI6502_INC = 1", ""]

    def eq(name, v, cmt=""):
        o.append(f"{name:<12}= ${v:04X}" + (f"   ; {cmt}" if cmt else "") if v > 255 else
                 f"{name:<12}= ${v:02X}" + (f"     ; {cmt}" if cmt else "") if v > 9 else
                 f"{name:<12}= {v}" + (f"       ; {cmt}" if cmt else ""))
    o.append("; registers")
    for nm, a, acc, size in d["reg"]:
        eq(nm, a, {"r": "read", "w": "write", "rw": "read/write", "0": "reads 0"}[acc]
           + ("" if size == 1 else f", {size} bytes"))
    o.append("; numbers")
    for nm, v in d["const"]:
        eq(nm, v)
    o.append("; bank zones (first, last)")
    for lo, hi, nm, txt in d["zone"]:
        eq(f"Z_{nm}", lo, txt)
        eq(f"Z_{nm}_END", hi)
    o.append("; fixed banks")
    for b, cnt, nm, txt in d["bank"]:
        eq(f"B_{nm}", b, txt)
    o.append("; far-call entries: E_NAME = its address (JSR E_NAME), EN_NAME = its number")
    for n, nm, b, a, txt in d["entry"]:
        eq(f"E_{nm}", entry_addr(d, n), txt)
        eq(f"EN_{nm}", n)
    for n, c, nm, txt in d["stub"]:
        eq(f"E_{nm}", entry_addr(d, n), txt)
        eq(f"EN_{nm}", n)
    o.append("; bank map owners")
    for v, nm, txt in d["owner"]:
        eq(f"OWN_{nm}", v, txt)
    o.append("; system calls in the ROM")
    for a, nm, txt in d["sys"]:
        eq(nm, a, txt.split(":")[0][:60])
    o += ["", ".endif"]
    return "\n".join(o) + "\n"


def vectors(d):
    vt, names, vmax, bmap = const(d, "VTAB"), const(d, "VTNAMES"), const(d, "VTMAX"), const(d, "BANKMAP")
    page = bytearray(bmap - vt)
    page[0:2] = b"VT"
    used = [n for n, *_ in d["entry"]] + [n + i for n, c, *_ in d["stub"] for i in range(c)]
    page[2] = max(used) + 1
    for n, nm, b, a, txt in d["entry"]:
        if n >= vmax:
            sys.exit(f"entry ${n:02X}: the table has $00-${vmax - 1:02X}")
        e = entry_addr(d, n) - vt
        page[e:e + 6] = bytes([0x20, 0xD0, 0xFF, b, a & 255, a >> 8])
    for n, nm, *_ in d["entry"] + [(n, nm) for n, c, nm, t in d["stub"]]:
        if len(nm) > 8:
            sys.exit(f"name {nm}: 8 characters at most")
        o = names - vt + 8 * n
        page[o:o + len(nm)] = nm.encode()
    return bytes([vt & 255, vt >> 8]) + bytes(page)


def check_doc(d):
    """no two registers on one address with different access; zones cover 0-255"""
    cover = set()
    for lo, hi, *_ in d["zone"]:
        cover |= set(range(lo, hi + 1))
    if cover != set(range(256)):
        sys.exit("mini6502.def: the zones do not cover banks $00-$FF exactly")


def main():
    d = parse()
    check_doc(d)
    doc = doc_lines(d)
    open(os.path.join(HW, "mini6502.inc"), "w").write(inc_text(d))
    open(os.path.join(HW, "REGISTERS.txt"), "w").write(
        "mini6502 reference (made by hw/gen.py from hw/mini6502.def)\n"
        "Copyright (C) 2026 Benoit Colson, with the help of Claude AI; GNU GPL 3 or later (COPYING)\n\n" + "\n".join(doc) + "\n")
    open(os.path.join(HW, "VECTORS"), "wb").write(vectors(d))
    bas = os.path.join(TOP, "mini6502.bas")
    L = open(bas).read().split("\n")
    a = next(i for i, l in enumerate(L) if l.startswith("' Memory map"))
    b = next(i for i, l in enumerate(L) if l.startswith("' The keyboard and display registers sit"))
    new = ["'" + l if l else "'" for l in doc]
    new[0] = "' Memory map   (made by hw/gen.py from hw/mini6502.def: edit that, not this)" \
        if doc[0].strip() == "Memory map" else new[0]
    new.append("'")
    if L[a:b] != new:
        L[a:b] = new
        open(bas, "w").write("\n".join(L))
        print("mini6502.bas: description updated")
    for l in doc:
        if len(l) > 79:
            print("note: long line:", l)
    print("made hw/mini6502.inc, hw/REGISTERS.txt, hw/VECTORS")
    r = subprocess.run([sys.executable, os.path.join(HW, "check.py")])
    sys.exit(r.returncode)


if __name__ == "__main__":
    main()
