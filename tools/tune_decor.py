#!/usr/bin/env python3
"""Decor tuning pass over biomes.json (idempotent):
  1. GREATLY reduce rock clutter in ALL biomes — scale down pebble/rubble/stone/boulder
     weights, and halve groundDecor density on biomes that are still rock-dominated.
  2. Add RARE tree stumps to forest/woodland/wasteland biomes' ground decor.
  3. Add RARE dead trees (canopy_deadtree) to the canopy of cold/dead/spooky woods.
Re-bake is NOT needed (decor is runtime), but reload the editor to see it.
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BP = os.path.join(ROOT, "data/world/biomes.json")
d = json.load(open(BP))

ROCK = {"pebble": 0.4, "rubble": 0.4, "stone": 0.4, "boulder": 0.4}  # kind -> weight scale
STUMP_BIOMES = {
    "forest", "dense_forest", "boreal_forest", "dead_forest", "swamp", "taiga",
    "badlands", "haunted_moor", "graveyard", "ancient_ruins", "misty_pine_woods",
    "sunlit_glade", "thorn_waste", "highland_meadow",
}
DEADTREE_CANOPY = {  # biome -> canopy weight for canopy_deadtree
    "dead_forest": 0.5, "boreal_forest": 0.05, "forest": 0.03, "haunted_moor": 0.4,
    "swamp": 0.08, "tundra": 0.06, "taiga": 0.06, "misty_pine_woods": 0.05,
    "thorn_waste": 0.1, "badlands": 0.05,
}


def kinds_of(block):
    return block.get("kinds", []) if isinstance(block, dict) else []


rock_trimmed = stump_added = dead_added = 0
for b in d["biomes"]:
    gd = b.get("groundDecor")
    if isinstance(gd, dict):
        ks = kinds_of(gd)
        # 1a. scale rock weights down
        for k in ks:
            if k["kind"] in ROCK:
                k["weight"] = round(float(k.get("weight", 1)) * ROCK[k["kind"]], 3)
        # 1b. if still rock-dominated, halve density so rocky biomes aren't a boulder field
        tot = sum(float(k.get("weight", 1)) for k in ks) or 1.0
        rsum = sum(float(k.get("weight", 1)) for k in ks if k["kind"] in ROCK)
        if rsum / tot >= 0.45:
            gd["density"] = round(float(gd.get("density", 0.05)) * 0.5, 3)
            rock_trimmed += 1
        # 2. rare stumps in fitting biomes
        if b["id"] in STUMP_BIOMES and not any(k["kind"] == "stump" for k in ks):
            ks.append({"kind": "stump", "weight": 0.05})
            stump_added += 1

    # 3. rare dead trees in cold/dead/spooky canopies
    if b["id"] in DEADTREE_CANOPY:
        cap = b.get("canopy")
        if isinstance(cap, dict):
            cks = kinds_of(cap)
            if not any(k["kind"] == "canopy_deadtree" for k in cks):
                cks.append({"kind": "canopy_deadtree", "weight": DEADTREE_CANOPY[b["id"]]})
                cap["kinds"] = cks
                dead_added += 1

json.dump(d, open(BP, "w"), indent=1)
print(f"rock weights scaled in all biomes; density halved on {rock_trimmed} rock-dominated biomes")
print(f"stumps added to {stump_added} biomes; dead trees added to {dead_added} canopies")
