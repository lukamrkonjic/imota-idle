#!/usr/bin/env python3
"""Author two themed islands into Aldreth's masks:
  • top-right island (comp 2)  -> wildflower_meadow (dense coloured flowers, ~no trees, flat)
  • islet beside it (comp 8)   -> rocky_hills + raised, uneven elevation
  • center-bottom island (39)  -> jungle (fully tropical)

Adds the wildflower_meadow biome to biomes.json and registers wildflower_meadow + jungle
in aldreth_mask.json's biomePalette (so the painted mask indices resolve), then paints the
biome mask (parent index per pixel) and the elevation mask. Re-bake after running.
"""
import json, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASKS = os.path.join(ROOT, "data/world/masks")
from PIL import Image

# ── 1. wildflower_meadow biome (a paintable PARENT) ───────────────────────────
BP = os.path.join(ROOT, "data/world/biomes.json")
bd = json.load(open(BP))
if not any(b["id"] == "wildflower_meadow" for b in bd["biomes"]):
    bd["biomes"].append({
        "id": "wildflower_meadow", "name": "Wildflower Meadow", "priority": 36,
        "neighbors": ["plains", "forest", "beach", "rocky_hills"],
        "tiles": {"grass": 0.72, "grass_dark": 0.12, "dirt": 0.16},
        "tint": "c8d878", "music": "plains",
        "skillWeights": {"foraging": 2.6, "woodcutting": 0.3, "hunter": 0.6},
        "siteDensity": 0.8, "monsterDensity": 0.25,
        "canopy": {"density": 0.006, "kinds": [
            {"kind": "canopy_birch", "weight": 0.7}, {"kind": "canopy_maple", "weight": 0.3}]},
        "groundDecor": {"density": 0.30, "kinds": [
            {"kind": "flower_purple", "weight": 0.30}, {"kind": "flower_yellow", "weight": 0.28},
            {"kind": "flower_white", "weight": 0.20}, {"kind": "flower_pink", "weight": 0.12},
            {"kind": "grass", "weight": 0.34}, {"kind": "shrub", "weight": 0.08}]},
    })
    json.dump(bd, open(BP, "w"), indent=1)
    print("added wildflower_meadow biome")

# ── 2. register wildflower_meadow + jungle in the mask palette ─────────────────
MP = os.path.join(MASKS, "aldreth_mask.json")
mj = json.load(open(MP))
pal = mj["biomePalette"]
for b in ("wildflower_meadow", "jungle"):
    if b not in pal:
        pal.append(b)
mj["biomePalette"] = pal
json.dump(mj, open(MP, "w"), indent=1)
IDX = {b: i for i, b in enumerate(pal)}
print("palette:", pal)

# ── 3. label land, collect target island pixels ───────────────────────────────
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


def comp_at(tx, ty):  # the component whose centroid is nearest the target
    best, bd_ = None, 1e9
    for c in comps.values():
        d = (c["c"][0] - tx) ** 2 + (c["c"][1] - ty) ** 2
        if c["n"] > 600 and d < bd_:
            bd_, best = d, c
    return best


flower = comp_at(1504, 129)   # comp 2  top-right
islet = comp_at(1421, 188)    # comp 8  rocky islet
tropic = comp_at(536, 761)    # comp 39 center-bottom (ringed by islets)
print("flower n=%d c=%s | islet n=%d c=%s | tropic n=%d c=%s" % (
    flower["n"], flower["c"], islet["n"], islet["c"], tropic["n"], tropic["c"]))

# ── 4. paint biome mask + elevation mask ──────────────────────────────────────
biome = Image.open(f"{MASKS}/aldreth_biomes.png").convert("L")
elev = Image.open(f"{MASKS}/aldreth_elev.png").convert("L")
bpx, epx = biome.load(), elev.load()

for (x, y) in flower["pix"]:
    bpx[x, y] = IDX["wildflower_meadow"]
    epx[x, y] = 0                                   # flat meadow
for (x, y) in tropic["pix"]:
    bpx[x, y] = IDX["jungle"]
    epx[x, y] = 0                                   # flatten -> tropical lowland (not grey rock)

# rocky islet: raised, uneven (radial bump + noise), walkable rocky_hills
icx, icy = islet["c"]
imaxr = max(1.0, max(((x - icx) ** 2 + (y - icy) ** 2) ** 0.5 for (x, y) in islet["pix"]))
for (x, y) in islet["pix"]:
    bpx[x, y] = IDX["rocky_hills"]
    d = (((x - icx) ** 2 + (y - icy) ** 2) ** 0.5) / imaxr      # 0 centre .. 1 edge
    base = 150.0 * (1.0 - d * 0.7)
    noise = 38.0 * math.sin(x * 0.32) * math.cos(y * 0.27) + 22.0 * math.sin(x * 0.71 + y * 0.5)
    epx[x, y] = int(max(0, min(190, base + noise)))

biome.save(f"{MASKS}/aldreth_biomes.png")
elev.save(f"{MASKS}/aldreth_elev.png")
print("painted: flower(wildflower_meadow) + islet(rocky_hills+elev) + tropic(jungle)")
