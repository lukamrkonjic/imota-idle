#!/usr/bin/env python3
"""M0 schema: add the structured fields (category/slot/combatStyle/tier/levelBand/tags/
rarity/stackable/deprecated) to every surviving item, mirroring the runtime inference in
game_state.gd so behaviour is unchanged — just now data-driven and validatable.

Idempotent. Dry-run by default; --apply writes items.json + data/generated/reverse_index.json.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DATA = os.path.join(ROOT, "data")
APPLY = "--apply" in sys.argv


def load(n):
    with open(os.path.join(DATA, n)) as f:
        return json.load(f)


# slot inference mirrors game_state.slot_for_item (name fallback order matters).
SLOT_RULES = [
    ("helm", "Helm"), ("hat", "Helm"), ("coif", "Helm"),
    ("body", "Body"), ("tunic", "Body"), ("robe", "Body"),
    ("legs", "Legs"), ("chaps", "Legs"), ("platelegs", "Legs"), ("skirt", "Legs"),
    ("boots", "Boots"), ("slippers", "Boots"), ("moccasins", "Boots"),
    ("sword", "Weapon"), ("dagger", "Weapon"), ("scimitar", "Weapon"), ("reaver", "Weapon"),
    ("shortbow", "Weapon"), ("longbow", "Weapon"), ("bow", "Weapon"), ("staff", "Weapon"),
    ("wand", "Weapon"), ("mace", "Weapon"), ("spear", "Weapon"), ("battleaxe", "Weapon"),
    ("warhammer", "Weapon"),
    ("shield", "Shield"), ("ring", "Ring"),
    ("gloves", "Gloves"), ("mitts", "Gloves"), ("wraps", "Gloves"),
    ("cape", "Cape"), ("cloak", "Cape"), ("necklace", "Amulet"), ("amulet", "Amulet"),
    ("arrows", "Ammunition"), ("bolts", "Ammunition"), ("dart", "Ammunition"),
    ("pickaxe", "Pickaxe"), ("axe", "Axe"), ("rod", "Rod"), ("lens", "Lens"),
    ("potion", "Potion"), ("lockpick", "Lockpick"), ("slate", "Slate"),
]
WORN = {"Helm", "Body", "Legs", "Boots", "Weapon", "Shield", "Ring", "Gloves", "Cape",
        "Amulet", "Ammunition"}
TOOL_SLOTS = {"Pickaxe", "Axe", "Rod", "Lens"}


def infer_slot(rec):
    if rec.get("slot"):
        return rec["slot"]
    n = (rec.get("name") or "").lower()
    for key, slot in SLOT_RULES:
        if key in n:
            return slot
    return ""


def infer_combat_style(rec, slot):
    if slot != "Weapon":
        return ""
    n = (rec.get("name") or "").lower()
    if rec.get("rangeDamage", 0) > 0 or any(k in n for k in ("bow", "crossbow", "dart", "knife")):
        return "ranged"
    if rec.get("magicDamage", 0) > 0 or "staff" in n or "wand" in n:
        return "magic"
    return "melee"


def req_level(rec):
    return max([int(v) for v in (rec.get("reqs") or {}).values()] + [0])


def main():
    items = load("items.json")
    tool_names = set(load("tools.json").keys())
    currency = {"Gold", "Coins"}

    for rec in items.values():
        slot = infer_slot(rec)
        style = infer_combat_style(rec, slot)
        name = rec.get("name", "")
        lvl = req_level(rec)
        # category
        if name in currency:
            cat = "currency"
        elif name in tool_names or slot in TOOL_SLOTS:
            cat = "tool"
        elif slot in WORN:
            cat = "equipment"
        elif slot in ("Food", "Potion") or rec.get("hpValue", 0) > 0:
            cat = "consumable"
        else:
            cat = "material"
        rec["category"] = cat
        if slot:
            rec["slot"] = slot
        if style:
            rec["combatStyle"] = style
        rec["tier"] = min(8, 1 + lvl // 10) if lvl > 0 else 0
        rec["levelBand"] = f"{(lvl // 10) * 10}-{(lvl // 10) * 10 + 9}" if lvl > 0 else "none"
        rec.setdefault("tags", [])
        rec.setdefault("rarity", "common")
        rec["stackable"] = cat in ("material", "currency", "consumable") or slot == "Ammunition"
        rec.setdefault("deprecated", False)

    # Reverse index (generated, read-only): item -> who drops/makes/gathers it.
    rev = {}

    def add(item, key, src):
        rev.setdefault(item, {"dropSources": [], "usedInRecipes": [], "skillSources": []})[key].append(src)

    for eid, e in load("enemies.json").items():
        for d in e.get("drops", []):
            if d.get("item"):
                add(d["item"], "dropSources", eid)
    for rid, r in load("recipes.json").items():
        out = (r.get("output") or {}).get("item")
        if out:
            add(out, "skillSources", {"recipe": rid, "skill": r.get("skill")})
        for i in r.get("inputs", []):
            if i.get("item"):
                add(i["item"], "usedInRecipes", rid)
    nodes = load("gather_nodes.json")
    arrs = nodes.values() if isinstance(next(iter(nodes.values()), None), list) else [list(nodes.values())]
    for arr in arrs:
        for nrec in arr:
            for it in nrec.get("items", []):
                add(it, "skillSources", {"node": nrec.get("id")})

    counts = {}
    for rec in items.values():
        counts[rec["category"]] = counts.get(rec["category"], 0) + 1
    print("categories:", counts)
    print(f"reverse index entries: {len(rev)}")

    if not APPLY:
        print("DRY RUN — re-run with --apply to write items.json + reverse_index.json")
        return
    with open(os.path.join(DATA, "items.json"), "w") as f:
        json.dump(items, f, ensure_ascii=False, separators=(",", ":"))
    os.makedirs(os.path.join(DATA, "generated"), exist_ok=True)
    with open(os.path.join(DATA, "generated", "reverse_index.json"), "w") as f:
        json.dump(rev, f, ensure_ascii=False, separators=(",", ":"))
    print("APPLIED — items.json annotated; data/generated/reverse_index.json written.")


if __name__ == "__main__":
    main()
