#!/usr/bin/env python3
"""Re-map the woodcutting tree ladder to OSRS-exact levels/XP for the core trees, add an
Elven tree, and write a VISUAL-SPECIES -> NODE map (data/world/tree_species.json) so the world's
canopy species resolve to a choppable woodcutting node. Idempotent.
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GN = os.path.join(ROOT, "data/gather_nodes.json")
d = json.load(open(GN))

# name -> (level, xp) OSRS-exact for the core ladder; fantasy trees keep their slots.
OSRS = {
    "Regular Tree": (1, 25), "Oak Tree": (15, 38), "Willow Tree": (30, 68),
    "Teak Tree": (35, 85), "Maple Tree": (45, 100), "Acadia Tree": (50, 125),
    "Eucalyptus Tree": (54, 92), "Yew Tree": (60, 175), "Magic Tree": (75, 250),
    "Red Maple Tree": (85, 210), "Rubra Tree": (90, 380),
}
for n in d["woodcutting"]:
    if n["name"] in OSRS:
        n["level"], n["xp"] = float(OSRS[n["name"]][0]), float(OSRS[n["name"]][1])

# Add an Elven tree at 80 (between Magic 75 and Red Maple 85) if missing.
if not any(n["name"] == "Elven Tree" for n in d["woodcutting"]):
    d["woodcutting"].append({
        "displayName": "Elven Tree", "id": "node.1180", "items": ["Elven Logs"],
        "level": 80.0, "name": "Elven Tree", "xp": 230.0,
    })
d["woodcutting"].sort(key=lambda n: n["level"])
json.dump(d, open(GN, "w"), indent=1)

# Visual canopy species -> woodcutting node. Most conifers/broadleaves are Regular (L1); the
# rest map to their species' node. New species (willow/yew/magic/elven) await meshes.
SPECIES = {
    "canopy_fir": "Regular Tree", "canopy_spruce": "Regular Tree", "canopy_pine": "Regular Tree",
    "canopy_snow_fir": "Regular Tree", "canopy_snow_spruce": "Regular Tree",
    "canopy_birch": "Regular Tree", "canopy_broadleaf": "Regular Tree", "canopy_deadtree": "Regular Tree",
    "canopy_oak": "Oak Tree",
    "canopy_maple": "Maple Tree",
    "canopy_acacia": "Acadia Tree",
    "canopy_palm": "Teak Tree",
    # --- species that still need meshes (placeholders so the data is ready) ---
    "canopy_willow": "Willow Tree", "canopy_yew": "Yew Tree",
    "canopy_magic": "Magic Tree", "canopy_elven": "Elven Tree",
}
sp_path = os.path.join(ROOT, "data/world/tree_species.json")
json.dump({
    "_doc": "Maps a world canopy species (prop_meshes canopy_* kind) to a woodcutting gather "
            "node in gather_nodes.json. Used to make ambient trees choppable, gated by level.",
    "speciesToNode": SPECIES,
}, open(sp_path, "w"), indent=1)

print("woodcutting ladder (OSRS-exact core + Elven):")
for n in sorted(d["woodcutting"], key=lambda n: n["level"]):
    if n["level"] <= 100:
        print(f"  L{int(n['level']):3d}  {n['name']:20s} {n['xp']:5.0f}xp  {n['items']}")
print(f"\nspecies map -> {sp_path}  ({len(SPECIES)} species)")
