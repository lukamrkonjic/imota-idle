#!/usr/bin/env python3
"""Re-author the top-right island (comp 2) from a flat all-wildflower field into a NATURAL,
MOUNTAINOUS island: a peak in the middle with biomes mixed by elevation —

  peak / high   -> tundra cap + rocky_hills (bare cold rock)
  upper slopes  -> boreal_forest (pine flanks)
  mid slopes    -> forest (broadleaf woods)
  lowland       -> wildflower_meadow + plains, mixed by a noise field (the flowers stay the
                   island's lowland signature, but no longer cover the whole island)

Noise perturbs the band edges so nothing reads as concentric rings, and the coast is flattened
so the island still meets the sea at a gentle shore. Only comp 2 is touched. Re-bake afterwards.
"""
import json, math, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASKS = os.path.join(ROOT, "data/world/masks")

pal = json.load(open(f"{MASKS}/aldreth_mask.json"))["biomePalette"]
IDX = {b: i for i, b in enumerate(pal)}


def vnoise(x, y, scale, seed):
    """Deterministic bilinear value-noise in [0,1] on a coarse grid of period `scale`."""
    xs, ys = x / scale, y / scale
    x0, y0 = math.floor(xs), math.floor(ys)
    fx, fy = xs - x0, ys - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)

    def h(a, b):
        n = (a * 374761393 + b * 668265263 + seed * 1013904223) & 0xFFFFFFFF
        n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0

    v00, v10 = h(x0, y0), h(x0 + 1, y0)
    v01, v11 = h(x0, y0 + 1), h(x0 + 1, y0 + 1)
    return (v00 * (1 - fx) + v10 * fx) * (1 - fy) + (v01 * (1 - fx) + v11 * fx) * fy


# ── label land, find comp 2 (nearest centroid to the top-right target) ────────
land = Image.open(f"{MASKS}/aldreth_land.png").convert("L")
W, H = land.size
lp = land.load()
lab = [[0] * W for _ in range(H)]
comps = {}
cid = 0
for sy in range(H):
    for sx in range(W):
        if lp[sx, sy] > 127 and lab[sy][sx] == 0:
            cid += 1
            st = [(sx, sy)]; lab[sy][sx] = cid; pix = []; cx = cy = 0
            while st:
                x, y = st.pop(); pix.append((x, y)); cx += x; cy += y
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and lp[nx, ny] > 127 and lab[ny][nx] == 0:
                        lab[ny][nx] = cid; st.append((nx, ny))
            comps[cid] = {"pix": pix, "c": (cx // len(pix), cy // len(pix)), "n": len(pix)}


def comp_at(tx, ty):
    best, bd = None, 1e9
    for c in comps.values():
        d = (c["c"][0] - tx) ** 2 + (c["c"][1] - ty) ** 2
        if c["n"] > 600 and d < bd:
            bd, best = d, c
    return best


isle = comp_at(1504, 129)
icx, icy = isle["c"]
maxr = max(1.0, max(((x - icx) ** 2 + (y - icy) ** 2) ** 0.5 for (x, y) in isle["pix"]))
print("island comp n=%d c=%s maxr=%.1f" % (isle["n"], isle["c"], maxr))

# ── paint elevation (central mountain) + biome (mixed by height) ──────────────
biome = Image.open(f"{MASKS}/aldreth_biomes.png").convert("L")
elev = Image.open(f"{MASKS}/aldreth_elev.png").convert("L")
bpx, epx = biome.load(), elev.load()

PEAK = 208.0
counts = {}
for (x, y) in isle["pix"]:
    d = (((x - icx) ** 2 + (y - icy) ** 2) ** 0.5) / maxr      # 0 centre .. 1 edge
    # off-centre the summit a touch and add ridge noise so the mountain isn't a perfect cone
    dd = min(1.0, d * (0.86 + 0.28 * vnoise(x, y, 60, 7)))
    ridge = (vnoise(x, y, 34, 11) - 0.5) * 70.0 + (vnoise(x, y, 14, 13) - 0.5) * 30.0
    e = PEAK * (1.0 - dd) ** 1.55 + ridge * (1.0 - dd)
    if d > 0.80:                                                # flatten toward the shore
        e *= max(0.0, 1.0 - (d - 0.80) / 0.20)
    e = max(0.0, min(232.0, e))
    epx[x, y] = int(e)

    # height band -> biome, with a noisy edge so bands aren't clean rings
    h = e / PEAK + (vnoise(x, y, 26, 23) - 0.5) * 0.13
    if h > 0.82:
        bid = "tundra"
    elif h > 0.56:
        bid = "rocky_hills"
    elif h > 0.36:
        bid = "boreal_forest"
    elif h > 0.19:
        bid = "forest"
    else:
        # lowland: wildflower meadow vs plains, in soft patches (flowers stay a feature)
        bid = "wildflower_meadow" if vnoise(x, y, 22, 31) > 0.46 else "plains"
    bpx[x, y] = IDX[bid]
    counts[bid] = counts.get(bid, 0) + 1

biome.save(f"{MASKS}/aldreth_biomes.png")
elev.save(f"{MASKS}/aldreth_elev.png")
print("repainted comp2 as mountainous mixed island:")
for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
    print("  %-18s %5d px (%.0f%%)" % (k, v, 100.0 * v / isle["n"]))
