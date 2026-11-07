#!/usr/bin/env python3
# PAINT's oval table -> paint_oval.inc: how much narrower than the radius an
# oval is t/256 of the way from its middle row to its top, in 255ths.
# Copyright (C) 2026 Benoit Colson. With the help of Claude AI. GPL-3.0+.
import math
v = [min(255, round(255 * (1 - math.sqrt(max(0.0, 1 - (t / 256) ** 2)))))
     for t in range(256)]
lines = ["; made by ovaltab.py: 255 * (1 - sqrt(1 - (t/256)^2)), t = 0-255",
         "shrink:"]
for i in range(0, 256, 16):
    lines.append("        .byte " + ",".join(str(x) for x in v[i:i + 16]))
open("paint_oval.inc", "w").write("\n".join(lines) + "\n")
