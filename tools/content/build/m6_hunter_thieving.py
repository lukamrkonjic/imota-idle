#!/usr/bin/env python3
"""M6 Hunter + Thieving: two new GATHER skills reusing the existing gather pipeline
(TickSim + worldgen site spawner). Per the skill_sites.json doc, a new gather skill needs:
gather_nodes entries + a skill_sites 'skills' entry + biome skillWeights. This writes all
three. (Code side: tool_progress + GATHER_VERB handle the rest.)

Idempotent. Dry-run by default; --apply writes gather_nodes.json, skill_sites.json, biomes.json.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DATA = os.path.join(ROOT, "data")
APPLY = "--apply" in sys.argv

# Hunter trap nodes (kind=burrow) -> hides / feathers / meat. Thieving stalls (kind=stall)
# -> cloth / gems / keys. Outputs use items that survived the M0 prune.
HUNTER = [
    ("Bird Snare", 1, 24, ["Feathers", "Raw Bird Meat"]),
    ("Rabbit Trap", 12, 38, ["Raw Bird Meat", "Brindle Pelt"]),
    ("Boar Trap", 27, 60, ["Boar Meat", "Brindle Pelt"]),
    ("Wolf Trap", 43, 90, ["Wolf Tooth", "Brindle Pelt"]),
    ("Polar Trap", 60, 130, ["Polar Pelt", "Wolf Tooth"]),
]
THIEVING = [
    ("Fruit Stall", 1, 22, ["Wool"]),
    ("Silk Stall", 20, 48, ["Silk"]),
    ("Gem Stall", 40, 85, ["Crushed Gem"]),
    ("Locked Chest", 55, 120, ["Crushed Gem", "Goblin Key"]),
]
SKILL_SITES = {
    "hunter": {"kind": "burrow", "defaultBiomes": ["forest", "plains", "tundra", "savanna"],
               "resources": 6, "respawnSec": 30.0},
    "thieving": {"kind": "stall", "defaultBiomes": ["plains", "savanna", "forest"],
                 "resources": 6, "respawnSec": 28.0},
}
# Where each skill spawns, and how strongly, layered onto existing biome weights.
BIOME_WEIGHTS = {
    "hunter": {"forest": 0.8, "plains": 0.7, "tundra": 0.9, "savanna": 1.0, "dense_forest": 0.6},
    "thieving": {"plains": 0.6, "savanna": 0.7},
}


def load(n):
    with open(os.path.join(DATA, n)) as f:
        return json.load(f)


def nodes_for(rows):
    out = []
    for name, lvl, xp, items in rows:
        out.append({"name": name, "displayName": name, "level": float(lvl),
                    "xp": float(xp), "items": items})
    return out


def main():
    gn = load("gather_nodes.json")
    gn["hunter"] = nodes_for(HUNTER)
    gn["thieving"] = nodes_for(THIEVING)
    print("gather nodes: hunter=%d, thieving=%d" % (len(gn["hunter"]), len(gn["thieving"])))

    sites = load(os.path.join("world", "skill_sites.json"))
    sites.setdefault("skills", {})
    sites["skills"]["hunter"] = SKILL_SITES["hunter"]
    sites["skills"]["thieving"] = SKILL_SITES["thieving"]

    biomes = load(os.path.join("world", "biomes.json"))
    touched = 0
    for b in biomes.get("biomes", []):
        bid = b.get("id", "")
        sw = b.setdefault("skillWeights", {})
        for skill, perbiome in BIOME_WEIGHTS.items():
            if bid in perbiome:
                sw[skill] = perbiome[bid]
                touched += 1
    print("biome skillWeight entries set: %d" % touched)

    if not APPLY:
        print("DRY RUN — re-run with --apply to write.")
        return
    with open(os.path.join(DATA, "gather_nodes.json"), "w") as f:
        json.dump(gn, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(DATA, "world", "skill_sites.json"), "w") as f:
        json.dump(sites, f, indent=2)   # match original 2-space, ASCII-escaped
    with open(os.path.join(DATA, "world", "biomes.json"), "w") as f:
        json.dump(biomes, f, indent=2)
    print("APPLIED — gather_nodes/skill_sites/biomes updated.")


if __name__ == "__main__":
    main()
