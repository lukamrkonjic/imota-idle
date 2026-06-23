#!/usr/bin/env python3
"""Place + validate Aldreth POIs against the real terrain masks.

Takes the reference-map arrangement (same 46 named POIs) and SNAPS each anchor
to a chunk that actually holds flat, walkable, non-water land in OUR world —
so nothing lands on ocean, river or mountain. Preserves the layout, fits the
elevation. Writes validated anchors into data/world/worldspec/aldreth.json and
renders an overlay for review.

Masks (1670x941, grayscale):
  land   : 255 = land,   0 = ocean
  biomes : index (0=ocean,1=beach,2=plains,3=forest,...,11=tundra,12=volcanic)
  elev   : 0 = flat,      >0 = raised rock/mountain (settlements forbidden)
  rivers : 0 = dry,       >0 = river / lake water
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MASKS = os.path.join(ROOT, "data/world/masks")
SPEC = os.path.join(ROOT, "data/world/worldspec/aldreth.json")
BAKED_MAP = os.path.join(ROOT, "data/world/baked/aldreth_map.png")

CHUNK = 16
MIN_TX, MIN_TY = -82 * CHUNK, -43 * CHUNK          # -1312, -688
MASK_W, MASK_H = 1670, 941
TILE_W, TILE_H = 161 * CHUNK, 91 * CHUNK            # 2576, 1456

# --- reference arrangement: (id, label, poi_type, cx, cy, tier) ---------------
# tier drives how much flat land the spot must hold (city > town > village > poi)
POIS = [
    ("spawn",            "Home Camp",        "player_spawn",   0,   0,  "town"),
    # villages / settlements
    ("imota",            "Imota",            "village",       -8,  13,  "town"),
    ("vodamere",         "Vodamere",         "village",      -15, -19,  "village"),
    ("kamenwick",        "Kamenwick",        "village",      -40, -12,  "town"),
    ("kelmere",          "Kelmere",          "village",        0,  -4,  "village"),
    ("varenhold",        "Varenhold",        "village",       20,   1,  "town"),
    ("sumarrow",         "Sumarrow",         "village",       22,  -9,  "village"),
    ("rookstead",        "Rookstead",        "village",        6,  15,  "village"),
    ("morhaven",         "Morhaven",         "village",      -26,  17,  "village"),
    ("dravemere",        "Dravemere",        "village",       16,  25,  "village"),
    ("duurak",           "Duurak",           "village",       38,   3,  "city"),
    ("brackhaven",       "Brackhaven",       "village",       56,   5,  "town"),
    ("reedspire",        "Reedspire",        "village",       64,  14,  "village"),
    ("trovik",           "Trovik",           "village",      -71,   4,  "village"),
    ("karsum",           "Karsum",           "village",      -32,  28,  "town"),
    ("dunmere",          "Dunmere",          "village",       59, -24,  "village"),
    ("halmwick",         "Halmwick",         "village",      -67,  36,  "village"),
    ("odrin_lodge",      "Odrin Lodge",      "village",      -28,  37,  "village"),
    # camp
    ("raven_camp",       "Raven Camp",       "campsite",     -27,  -5,  "poi"),
    # caves
    ("wolfrest_cave",    "Wolfrest Cave",    "cave_entrance", -46, -17, "poi"),
    ("gloam_cavern",     "Gloam Cavern",     "cave_entrance",  34, -27, "poi"),
    ("kamen_den",        "Kamen Den",        "cave_entrance", -53, -18, "poi"),
    # altars / shrines
    ("windmere_shrine_a","Windmere Shrine",  "altar",         -8, -32,  "poi"),
    ("windmere_shrine_b","Windmere Shrine",  "altar",        -13, -24,  "poi"),
    ("mirecross_shrine", "Mirecross Shrine", "altar",          0,  19,  "poi"),
    # watchtowers / outposts
    ("greywatch",        "Greywatch",        "old_watchtower",-60, -22, "poi"),
    ("whitepine_outpost","Whitepine Outpost","old_watchtower",-39, -41, "poi"),
    ("sable_tower",      "Sable Tower",      "old_watchtower", -5, -18, "poi"),
    ("ironthorn_post",   "Ironthorn Post",   "old_watchtower",-20, -11, "poi"),
    ("ashen_gate",       "Ashen Gate",       "old_watchtower", 29,  -6, "poi"),
    ("bela_watch",       "Bela Watch",       "old_watchtower",-15,   6, "poi"),
    ("southwatch",       "Southwatch",       "old_watchtower", 27,  27, "poi"),
    ("brine_beacon",     "Brine Beacon",     "old_watchtower", 62, -34, "poi"),
    ("cliffward_watch",  "Cliffward Watch",  "old_watchtower",-53,  26, "poi"),
    ("sea_lookout_a",    "Sea Lookout",      "old_watchtower",-39,  21, "poi"),
    ("sea_lookout_b",    "Sea Lookout",      "old_watchtower",-41,  30, "poi"),
    ("crag_lantern",     "Crag Lantern",     "old_watchtower", -4,  33, "poi"),
    ("serpent_ford",     "Serpent Ford",     "old_watchtower",  1,  40, "poi"),
    # fishing
    ("voda_wharf",       "Voda Wharf",       "fishing_hotspot", -6, -11,"poi"),
    # landmarks
    ("moinmere_stand_a", "Moinmere Stand",   "landmark",        7, -10, "poi"),
    ("moinmere_stand_b", "Moinmere Stand",   "landmark",        9,   4, "poi"),
    ("hollow_yews",      "Hollow Yews",      "landmark",       21, -20, "poi"),
    ("stag_hollow",      "Stag Hollow",      "landmark",       17, -27, "poi"),
    ("yewmere_grove",    "Yewmere Grove",    "landmark",      -70, -10, "poi"),
    ("oaken_steps",      "Oaken Steps",      "landmark",      -65,  28, "poi"),
    # ruins / boss
    ("old_varo_ruins",   "Old Varo Ruins",   "haunted_ruins", -21,  29, "poi"),
    ("blackmere_pit",    "Blackmere Pit",    "boss_lair",      51,  -9, "poi"),
]

# minimum count of valid tiles a chunk must hold for this tier (out of 256)
TIER_MIN = {"city": 48, "town": 26, "village": 14, "poi": 5}
# fishing wants to sit ON the coast, so it is allowed to keep less flat land
COAST_TYPES = {"fishing_hotspot"}

# --- load masks ---------------------------------------------------------------
land = Image.open(f"{MASKS}/aldreth_land.png").convert("L").load()
biome = Image.open(f"{MASKS}/aldreth_biomes.png").convert("L").load()
elev = Image.open(f"{MASKS}/aldreth_elev.png").convert("L").load()
river = Image.open(f"{MASKS}/aldreth_rivers.png").convert("L").load()


def mask_px(tx, ty):
    u = (tx - MIN_TX) / TILE_W
    v = (ty - MIN_TY) / TILE_H
    if u < 0 or u >= 1 or v < 0 or v >= 1:
        return None
    return (min(int(u * MASK_W), MASK_W - 1), min(int(v * MASK_H), MASK_H - 1))


def tile_valid(tx, ty):
    """Flat, walkable, non-water land (mirrors _footprint_ok at mask res)."""
    mp = mask_px(tx, ty)
    if mp is None:
        return False
    px, py = mp
    return (land[px, py] > 127 and elev[px, py] < 16
            and river[px, py] < 40 and biome[px, py] >= 1)


def chunk_valid_count(cx, cy):
    n = 0
    for ty in range(cy * CHUNK, cy * CHUNK + CHUNK):
        for tx in range(cx * CHUNK, cx * CHUNK + CHUNK):
            if tile_valid(tx, ty):
                n += 1
    return n


def chunk_adjacent_water(cx, cy):
    for ty in range(cy * CHUNK, cy * CHUNK + CHUNK):
        for tx in range(cx * CHUNK, cx * CHUNK + CHUNK):
            mp = mask_px(tx, ty)
            if mp and (land[mp[0], mp[1]] <= 127 or river[mp[0], mp[1]] >= 40):
                return True
    return False


def snap(cx, cy, tier, ptype):
    """Return (cx, cy, count, moved) — nearest chunk holding enough flat land."""
    need = TIER_MIN[tier]
    coast = ptype in COAST_TYPES
    best = None
    for ring in range(0, 14):
        ring_best = None
        for dy in range(-ring, ring + 1):
            for dx in range(-ring, ring + 1):
                if max(abs(dx), abs(dy)) != ring:
                    continue
                nx, ny = cx + dx, cy + dy
                cnt = chunk_valid_count(nx, ny)
                ok = cnt >= need and (not coast or chunk_adjacent_water(nx, ny))
                if ok and (ring_best is None or cnt > ring_best[2]):
                    ring_best = (nx, ny, cnt)
        if ring_best:
            return (ring_best[0], ring_best[1], ring_best[2], ring != 0)
    return (cx, cy, chunk_valid_count(cx, cy), False)  # gave up; keep original


# --- run ----------------------------------------------------------------------
anchors = []
report = []
seen = {}
for pid, label, ptype, cx, cy, tier in POIS:
    nx, ny, cnt, moved = snap(cx, cy, tier, ptype)
    # avoid two anchors landing on the exact same chunk
    while (nx, ny) in seen:
        ny += 1
        cnt = chunk_valid_count(nx, ny)
    seen[(nx, ny)] = pid
    a = {"id": pid, "chunk": [nx, ny], "label": label, "poi": ptype}
    if pid == "spawn":
        a.update({"region": "heartland", "teleport": False, "locked": False})
    anchors.append(a)
    dist = ((nx - cx) ** 2 + (ny - cy) ** 2) ** 0.5
    report.append((pid, tier, (cx, cy), (nx, ny), cnt, dist))

moved_n = sum(1 for r in report if r[5] > 0.1)
print(f"placed {len(anchors)} anchors  |  snapped {moved_n} onto valid land\n")
for pid, tier, o, n, cnt, dist in report:
    flag = "" if dist < 0.1 else f"  MOVED {dist:.0f}ch {o}->{n}"
    print(f"  {pid:20} {tier:8} chunk={n}  flat_tiles={cnt:3d}{flag}")

# --- write anchors into the worldspec -----------------------------------------
spec = json.load(open(SPEC))
spec["anchors"] = anchors
json.dump(spec, open(SPEC, "w"), indent=1)
print(f"\nwrote {len(anchors)} anchors -> {os.path.relpath(SPEC, ROOT)}")

# --- overlay for review -------------------------------------------------------
img = Image.open(BAKED_MAP).convert("RGB")
img = Image.blend(img, Image.new("RGB", img.size, (255, 255, 255)), 0.12)
dr = ImageDraw.Draw(img)
try:
    fnt = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 13)
except Exception:
    fnt = ImageFont.load_default()
TIER_COL = {"city": (222, 40, 40), "town": (255, 150, 46),
            "village": (255, 214, 64), "poi": (84, 178, 236)}
for (pid, label, ptype, cx, cy, tier), a in zip(POIS, anchors):
    nx, ny = a["chunk"]
    tx, ty = nx * CHUNK + 8, ny * CHUNK + 8
    px, py = tx - MIN_TX, ty - MIN_TY
    col = TIER_COL[tier]
    r = 8 if tier in ("city", "town") else 6
    dr.ellipse([px - r, py - r, px + r, py + r], fill=col, outline=(20, 20, 20), width=2)
    for ox, oy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        dr.text((px + r + 3 + ox, py - 8 + oy), label, font=fnt, fill=(0, 0, 0))
    dr.text((px + r + 3, py - 8), label, font=fnt, fill=(255, 255, 255))
out = "/tmp/poi_placement.png"
img.save(out)
print(f"overlay -> {out}")
