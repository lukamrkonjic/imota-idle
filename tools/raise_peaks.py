#!/usr/bin/env python3
"""Make the TOP-LEFT mountain massif huge: amplify the already-elevated land there toward the
(now raised) elevation ceiling, with a smooth radial falloff + ridge noise so it reads as a big
craggy range rather than a flat block. Only land already above a threshold is lifted, so valleys
and coastlines keep their shape. The global ceiling/gamma change (in code) handles overall
variation; this just makes the top-left peaks the dramatic centrepiece. Re-bake after running.
"""
import math, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M = os.path.join(ROOT, "data/world/masks")


def vnoise(x, y, scale, seed):
    xs, ys = x / scale, y / scale
    x0, y0 = math.floor(xs), math.floor(ys)
    fx, fy = xs - x0, ys - y0
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)

    def h(a, b):
        n = (a * 374761393 + b * 668265263 + seed * 1013904223) & 0xFFFFFFFF
        n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0

    v00, v10 = h(x0, y0), h(x0 + 1, y0)
    v01, v11 = h(x0, y0 + 1), h(x0 + 1, y0 + 1)
    return (v00 * (1 - fx) + v10 * fx) * (1 - fy) + (v01 * (1 - fx) + v11 * fx) * fy


elev = Image.open(f"{M}/aldreth_elev.png").convert("L")
land = Image.open(f"{M}/aldreth_land.png").convert("L")
W, H = elev.size
ep, lp = elev.load(), land.load()

CX, CY, RAD = 400, 140, 380      # top-left massif centre + influence radius (mask px)
THRESH = 95                       # only lift land already this high (keeps valleys/coast intact)
raised = peak = 0
for y in range(H):
    for x in range(W):
        if lp[x, y] <= 127:
            continue
        v = ep[x, y]
        d = math.hypot(x - CX, y - CY) / RAD
        w = max(0.0, 1.0 - d)
        w = w * w * (3 - 2 * w)                      # smoothstep falloff
        if w > 0.0 and v > THRESH:
            ridge = (vnoise(x, y, 46, 5) - 0.5) * 46 + (vnoise(x, y, 18, 7) - 0.5) * 22
            boosted = v + (v - THRESH) * 1.7 * w + ridge * w
            nv = int(max(0, min(255, max(v, boosted))))
            if nv > v:
                ep[x, y] = nv
                raised += 1
                if nv >= 248:
                    peak += 1

elev.save(f"{M}/aldreth_elev.png")
print(f"top-left massif: raised {raised} px, {peak} pushed to near-max (huge summit cores)")
