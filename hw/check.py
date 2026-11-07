und#!/usr/bin/env python3
"""check.py - checks that mini6502.bas (IORead / IOWrite) and the simulator
(monitor/simtest.py) decode exactly the registers in hw/mini6502.def: every
register is read and/or written where the table says, and nothing is decoded
that the table does not list.  usage: python3 hw/check.py
Copyright (C) 2026 Benoit Colson. With the help of Claude AI.
Free software under the GNU General Public License, version 3 or
(at your option) any later version, WITHOUT ANY WARRANTY; see COPYING.
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen import parse, TOP

IO = range(0xD000, 0xE000)


def bas_cases(src, func):
    """addresses of the top-level CASEs of SELECT CASE reg in func"""
    m = re.search(rf"^(SUB|FUNCTION) {re.escape(func)}[ (].*?^END (SUB|FUNCTION)", src, re.S | re.M)
    out, depth = set(), 0
    for line in m.group(0).split("\n"):
        t = line.split("'")[0].strip()
        if t.upper().startswith("SELECT CASE"):
            depth += 1
        elif t.upper().startswith("END SELECT"):
            depth -= 1
        elif depth == 1 and t.upper().startswith("CASE ") and not t.upper().startswith("CASE ELSE"):
            expr = t[5:].split(":")[0]
            for item in expr.split(","):
                v = [int(x.strip()[2:], 16) for x in item.split(" TO ")]
                out |= set(range(0xD000 + v[0], 0xD000 + v[-1] + 1))
    return out


class Any:
    def __getattr__(self, k): return Any()
    def __call__(self, *a, **k): return Any()
    def __bool__(self): return False
    def __getitem__(self, k): return Any()
    def __and__(self, o): return 0
    __rand__ = __and__


def sim_cases(src, meth):
    m = re.search(rf"    def {meth}\(s, addr(, v)?\):\n(.*?)\n    def ", src, re.S)
    body = m.group(2).split("\n")
    out = set()
    for i, line in enumerate(body):
        mm = re.match(r"(\s*)if (.*?):(.*)$", line)
        if not mm or "addr" not in mm.group(2):
            continue
        ind = len(mm.group(1))
        block = mm.group(3)
        for nxt in body[i + 1:]:
            if len(nxt) - len(nxt.lstrip()) <= ind:
                break
            block += nxt
        if "return" not in block:
            continue
        hits = set()
        for a in IO:
            for v in (0, 1, 2, 3, 255):
                try:
                    if eval(mm.group(2), {"addr": a, "s": Any(), "os": Any(), "SCRIPT": [], "v": v}):
                        hits.add(a)
                except Exception:
                    pass
        if len(hits) < 0x800:               # not the catch-all "I/O reads 0"
            out |= hits
    return out


def main():
    d = parse()
    bas = open(os.path.join(TOP, "mini6502.bas")).read()
    sim = open(os.path.join(TOP, "monitor", "simtest.py")).read()
    dec = {"host read": bas_cases(bas, "IORead&"), "host write": bas_cases(bas, "IOWrite"),
           "sim read": sim_cases(sim, "__getitem__"), "sim write": sim_cases(sim, "__setitem__")}
    need = {k: set() for k in dec}
    known = set()
    for a, size, txt in d["spare"]:
        known |= set(range(a, a + size))
    for nm, a, acc, size in d["reg"]:
        for x in range(a, a + size):
            known.add(x)
            if "r" in acc:
                need["host read"].add(x); need["sim read"].add(x)
            if "w" in acc:
                need["host write"].add(x); need["sim write"].add(x)
    bad = 0

    def ranges(xs):
        xs = sorted(xs); out = []
        for x in xs:
            if out and x == out[-1][1] + 1:
                out[-1][1] = x
            else:
                out.append([x, x])
        return ", ".join(f"${a:04X}" if a == b else f"${a:04X}-${b:04X}" for a, b in out)
    for k in dec:
        miss = need[k] - dec[k]
        extra = dec[k] - known
        if miss:
            print(f"{k}: not decoded but in the table: {ranges(miss)}"); bad += 1
        if extra:
            print(f"{k}: decoded but not in the table: {ranges(extra)}"); bad += 1
    print("check: ok" if not bad else f"check: {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
