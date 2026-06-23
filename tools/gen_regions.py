#!/usr/bin/env python3
"""Initial Aldreth region-layout generator (Phase 2).

Expands a compact region table into the verbose worldspec `regions` array and
patches anchors / macroRegions / islandGroups in data/world/worldspec/aldreth.json.
Run ONCE to lay regions onto the traced coastline; after that the JSON is the
canonical, hand-editable source (re-running overwrites manual region edits).

    python3 tools/gen_regions.py

Coordinates are CHUNK space; bounds are x[-67,67] y[-45,44] (origin ~ map centre).
Verify placement with tools/region_preview.tscn (centers_in_sea) + coast_preview.
"""
import json, os, zlib

SPEC = os.path.join(os.path.dirname(__file__), "..", "data", "world", "worldspec", "aldreth.json")

# id, name, biome, req, cx, cy, rx, ry, rot, macro, role, fixed
R = [
    # --- central heartlands (hub) ---
    ("greenhollow", "Greenhollow Vale", "plains",        1,  -2,  -2,  8.0, 5.5, -10, "central_heartlands", "hub",   True),
    ("aldspire",    "Aldspire",          "plains",        2, -12,  -7,  5.1, 3.3, -75, "central_heartlands", "micro", True),
    ("larkmeadow",  "Larkmeadow",        "flower_meadow", 4,  -7, -13,  6.4, 4.1, -50, "central_heartlands", "micro", True),
    ("brightfields","Brightfields",      "wheatfield",    3,   6,   2,  7.0, 4.5, -82, "central_heartlands", "major", True),
    ("saltcove",    "Salt Cove",         "beach",         7,   3, -11,  4.6, 3.0, -88, "central_heartlands", "micro", True),
    ("stonereach",  "Stonereach",        "rocky_hills",  14, -15,   3,  6.4, 4.1, -41, "central_heartlands", "major", True),
    # --- western marches (main-continent forests) ---
    ("mosswood",    "Mosswood",          "forest",        6, -31,  -7,  7.7, 4.9, -68, "western_marches", "major", True),
    ("oakshade",    "Oakshade Forest",   "forest",        9, -36,  -1,  7.7, 4.9,  33, "western_marches", "major", True),
    ("deepwood",    "The Deepwood",      "dense_forest", 13, -26, -13,  7.7, 4.9,  72, "western_marches", "major", True),
    ("wolfden",     "Wolfden",           "boreal_forest",22, -38, -17,  7.7, 4.9,   6, "western_marches", "major", True),
    # --- frostlands (NW lobe) ---
    ("frostspire",  "The Frostspire",    "snowdrift",    60, -28, -39,  7.7, 4.9,  78, "frostlands", "major", True),
    ("helcarn",     "Helcarn",           "snowdrift",    62, -19, -35,  7.7, 4.9,  88, "frostlands", "major", True),
    ("frostmere",   "Frostmere",         "tundra",       30, -27, -30,  7.7, 4.9, -32, "frostlands", "major", True),
    ("frostwood",   "Frostwood",         "boreal_forest",28, -34, -29,  9.0, 5.7,  26, "frostlands", "major", True),
    ("graymarch",   "Graymarch",         "rocky_hills",  33, -15, -31,  6.4, 4.1,  47, "frostlands", "micro", True),
    # --- northern calamity (NE lobe) ---
    ("northwatch",  "Northwatch",        "rocky_hills",  35,  -2, -37,  6.4, 4.1,  29, "northern_calamity", "major", True),
    ("riftlands",   "The Riftlands",     "rocky_hills",  57,  16, -33,  6.4, 4.1, -66, "northern_calamity", "micro", True),
    ("cinderpeak",  "Cinderpeak",        "volcanic",     55,   8, -29,  7.7, 4.9, -75, "northern_calamity", "major", True),
    ("ashfall",     "Ashfall",           "badlands",     49,  16, -25,  6.4, 4.1, -48, "northern_calamity", "micro", True),
    ("thegeysers",  "The Geysers",       "geyser_field", 52,   3, -24,  5.1, 3.3,  82, "northern_calamity", "micro", True),
    ("blightmoor",  "Blightmoor",        "dead_forest",  53,  18, -23,  7.7, 4.9,   8, "northern_calamity", "major", True),
    # --- eastern transition -> sunspear ---
    ("eastreach",   "Eastreach",         "savanna",      15,  19,  -2,  8.0, 5.0,  65, "sunspear_peninsula", "major", True),
    ("duskreach",   "Duskreach",         "badlands",     31,  26,   5,  7.0, 4.6, -11, "sunspear_peninsula", "major", True),
    ("emberscrub",  "Emberscrub",        "savanna_scrub",34,  33,   9,  6.4, 4.1,  13, "sunspear_peninsula", "micro", True),
    ("scorchplain", "Scorchplain",       "cactus_plain", 37,  41,  15,  6.4, 4.1, -47, "sunspear_peninsula", "major", True),
    ("sunspear",    "Sunspear Dunes",    "desert",       41,  49,  21, 11.0, 7.0, -16, "sunspear_peninsula", "major", True),
    ("mirage",      "Mirage Oasis",      "oasis",        39,  44,  23,  5.1, 3.3,  80, "sunspear_peninsula", "micro", True),
    ("saltpan",     "The Salt Pan",      "salt_marsh",     43,  56,  28,  7.0, 4.5, -78, "sunspear_peninsula", "micro", True),
    # --- southern fens ---
    ("greywater",   "Greywater Mire",    "swamp",        23,  -8,  11, 13.0, 8.0, -10, "southern_fens", "major", True),
    ("mirewood",    "Mirewood",          "swamp",        24, -22,   9, 11.0, 7.0,  15, "southern_fens", "major", True),
    ("witchmere",   "Witchmere",         "swamp",        33,  -2,  15, 12.0, 7.0, -20, "southern_fens", "major", True),
    ("bogmire",     "Bogmire",           "bog",          27, -13,  18,  8.0, 5.0,  25, "southern_fens", "micro", True),
    ("blackfen",    "Blackfen",          "bog",          29,   6,  13,  8.0, 6.0, -15, "southern_fens", "micro", True),
    ("tanglewild",  "The Tanglewild",    "jungle",       46,  16,  11,  8.0, 5.0,  80, "southern_fens", "major", False),
    # --- islands ---
    ("westcape",    "Westcape",          "grove",        16, -55, -17,  6.4, 4.1,  -9, "greywood_isle", "micro", True),
    ("highmoor",    "Highmoor",          "heather_moor", 19, -52, -11,  7.7, 4.9, -46, "greywood_isle", "major", True),
    ("ironward",    "Ironward Isle",     "alpine",       58,  52, -26,  7.7, 5.0,  30, "ironward_isle", "major", True),
    ("verdant",     "Verdant Isle",      "grove",        17, -50,  13,  7.7, 4.9, -20, "verdant_isles", "major", True),
    ("sirensrest",  "Siren's Rest",      "grove",        20, -48,  34,  6.4, 4.1,  40, "verdant_isles", "micro", True),
    ("emberisle",   "Ember Isle",        "volcanic",     50, -13,  35,  6.4, 4.1,   0, "emberjungle_isles", "major", True),
    ("jungleisle",  "Jungle Isle",       "jungle",       44,  11,  35,  7.0, 4.5,  15, "emberjungle_isles", "major", True),
]

MACROS = [
    ("central_heartlands", "The Central Heartlands", "hub",    "lush temperate: forests, grasslands, wheatfarms"),
    ("western_marches",    "The Western Marches",    "major",  "broadleaf + spruce forest on the continent's west"),
    ("frostlands",         "The Frostlands",         "major",  "tundra, boreal, snow — the cold north-west"),
    ("northern_calamity",  "The Northern Calamity",  "major",  "volcanic, ash, geysers, dead land — the hostile north-east"),
    ("southern_fens",      "The Southern Fens",      "major",  "swamp, bog, witch country + jungle"),
    ("sunspear_peninsula", "Sunspear Peninsula",     "major",  "savanna -> badlands -> desert, the south-east cape"),
    ("greywood_isle",      "Greywood Isle",          "island", "temperate grove/moor island (west)"),
    ("ironward_isle",      "Ironward Isle",          "island", "cold alpine rock island (north-east)"),
    ("verdant_isles",      "The Verdant Isles",      "island", "green grove islands (south-west)"),
    ("emberjungle_isles",  "The Ember & Jungle Isles","island","volcanic + jungle islands (south)"),
]

ISLAND_GROUPS = [
    ("greywood_isle",  "Greywood Isle",  "continent_island", "greywood_isle",      ["westcape", "highmoor"]),
    ("ironward_isle",  "Ironward Isle",  "continent_island", "ironward_isle",      ["ironward"]),
    ("verdant_isles",  "The Verdant Isles", "island_group",  "verdant_isles",      ["verdant", "sirensrest"]),
    ("ember_isle",     "Ember Isle",     "island",           "emberjungle_isles",  ["emberisle"]),
    ("jungle_isle",    "Jungle Isle",    "island",           "emberjungle_isles",  ["jungleisle"]),
]

# anchor id -> region id whose centre the anchor pins to (keeps anchorsMustBeInsideRegion happy)
ANCHOR_REGION = {"spawn": "greenhollow", "aldspire_keep": "aldspire",
                 "graymarch_keep": "graymarch", "molehollow": "oakshade"}

# Roads: id, kind (major=cobble / minor=dirt), [region ids the polyline runs through].
# Points are the region centres in TILE space (chunk*16+8). The heartland is split by
# the central bay, so straight region-to-region lines cut across water — roads need
# either a land-following router or hand-authoring in the editor. Left EMPTY until
# then (finite_world_generator still rasterizes any roads added here). Verify with
# tools/region_preview.tscn (roads_crossing_sea) before enabling.
ROADS = []


def danger(req):
    if req < 10: return "safe"
    if req < 20: return "low"
    if req < 35: return "medium"
    if req < 50: return "high"
    if req < 60: return "elite"
    return "wilderness"


def main():
    path = os.path.normpath(SPEC)
    spec = json.load(open(path))

    centers = {}
    regions = []
    for (rid, name, biome, req, cx, cy, rx, ry, rot, macro, role, fixed) in R:
        centers[rid] = (cx, cy)
        gen = {"placement": "fixed", "terrain": "baked" if fixed else "procedural"}
        if not fixed:
            gen["persistGeneratedChunks"] = True
        reg = {
            "id": rid, "name": name, "biome": biome, "req": req, "danger": danger(req),
            "shape": {"type": "ellipse", "center": [cx, cy], "radius": [rx, ry],
                      "rotation": rot, "warp": {"seed": zlib.crc32(rid.encode()) % 1000, "strength": 0.32}},
            "fixed": fixed, "motif": "",
            "priority": 60 if role == "micro" else (50 if role == "hub" else 40),
            "blendWidth": 3, "macroRegion": macro, "role": role,
            "generation": gen,
        }
        if biome in ("snowdrift",) and req >= 60:
            reg["allowBoundsClipping"] = True
        regions.append(reg)
    spec["regions"] = regions

    # repoint anchors to their region centres (so they stay inside the region)
    for a in spec.get("anchors", []):
        rid = ANCHOR_REGION.get(a.get("id"))
        if rid and rid in centers:
            a["chunk"] = list(centers[rid])
            a["region"] = rid

    # roads: polylines through region centres (tile space = chunk*16 + 8)
    def center_tile(rid):
        cx, cy = centers[rid]
        return [cx * 16 + 8, cy * 16 + 8]
    roads = []
    for (rid, kind, through) in ROADS:
        pts = [center_tile(r) for r in through if r in centers]
        roads.append({"id": rid, "kind": kind, "width": 2 if kind == "major" else 1, "points": pts})
    spec["roads"] = roads

    spec["macroRegions"] = [{"id": i, "name": n, "role": r, "theme": t} for (i, n, r, t) in MACROS]
    spec["islandGroups"] = [{"id": i, "name": n, "kind": k, "macroRegion": m, "regions": regs}
                            for (i, n, k, m, regs) in ISLAND_GROUPS]

    json.dump(spec, open(path, "w"), indent="\t", ensure_ascii=False)
    print("wrote %d regions, %d roads, %d macroRegions, %d islandGroups to %s" %
          (len(regions), len(roads), len(MACROS), len(ISLAND_GROUPS), path))


if __name__ == "__main__":
    main()
