#!/usr/bin/env python3
"""M6 Firemaking: generate one 'Burn <Log>' recipe per log (log -> Ashes + Firemaking XP).
Firemaking level for each log is derived from the woodcutting node that yields it (so you can
burn what you can chop). Reuses RecipeSim; no station needed (handled in world auto_station).

Idempotent — removes any prior fm_* recipes first. Dry-run by default; --apply writes.
"""
import json, os, sys, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DATA = os.path.join(ROOT, "data")
APPLY = "--apply" in sys.argv


def load(n):
    with open(os.path.join(DATA, n)) as f:
        return json.load(f)


def main():
    items = load("items.json")
    logs = sorted(k for k in items if k.lower() == "logs" or k.lower().endswith(" logs"))

    # log -> woodcutting level from the node that drops it (fallback by simple tier guess).
    nodes = load("gather_nodes.json")
    wc = nodes.get("woodcutting", []) if isinstance(nodes.get("woodcutting"), list) else []
    log_level = {}
    for n in wc:
        for it in n.get("items", []):
            if it in logs:
                log_level[it] = min(log_level.get(it, 999), int(n.get("level", 1)))
    DEFAULT = {"Logs": 1, "Oak Logs": 15, "Willow Logs": 30, "Teak Logs": 35,
               "Maple Logs": 45, "Yew Logs": 60, "Magic Logs": 75}
    for lg in logs:
        if lg not in log_level:
            log_level[lg] = DEFAULT.get(lg, 1)

    recipes = load("recipes.json")
    # drop any previously generated firemaking recipes (idempotent re-run). Recipes are
    # keyed "skill/name" and resolved by that key, so key ours the same way.
    for k in [k for k, r in recipes.items()
              if r.get("skill") == "firemaking" or k.startswith("recipe.fm_")]:
        recipes.pop(k)

    made = 0
    for lg in logs:
        lvl = log_level[lg]
        name = f"Burn {lg}"
        recipes[f"firemaking/{name}"] = {
            "skill": "firemaking",
            "name": name,
            "displayName": f"Burn {lg}",
            "levelReq": float(lvl),
            "time": round(2.6 + lvl * 0.02, 2),
            "inputs": [{"item": lg, "qty": 1.0}],
            "output": {"item": "Ashes", "qty": 1.0},
            "xp": float(round(20 + lvl * 4.5)),
            "hpValue": 0.0,
            "unburnable": True,
            "balanceStatus": "provisional",
        }
        made += 1

    print(f"firemaking recipes generated: {made} (logs found: {len(logs)})")
    if not APPLY:
        print("DRY RUN — re-run with --apply to write recipes.json")
        return
    with open(os.path.join(DATA, "recipes.json"), "w") as f:
        json.dump(recipes, f, ensure_ascii=False, separators=(",", ":"))
    print(f"APPLIED — recipes.json now has {len(recipes)} recipes.")


if __name__ == "__main__":
    main()
