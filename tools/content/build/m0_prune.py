#!/usr/bin/env python3
"""M0 cleanup: hard-delete every item the audit marked `replace` or `deprecate`, and scrub
every reference to it (enemy drops, recipe inputs/outputs, gather-node items, alias/registry
maps). items.json is keyed by item NAME and all refs use that same key, so deletion is
unambiguous. Dry-run by default; pass --apply to write.

Usage:
  python3 tools/content/build/m0_prune.py            # dry-run report
  python3 tools/content/build/m0_prune.py --apply    # write changes
"""
import json, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DATA = os.path.join(ROOT, "data")
APPLY = "--apply" in sys.argv


def load(name):
    with open(os.path.join(DATA, name)) as f:
        return json.load(f)


def save(name, obj):
    with open(os.path.join(DATA, name), "w") as f:
        json.dump(obj, f, ensure_ascii=False, separators=(",", ":"))


def main():
    audit = load(os.path.join("..", "docs", "content", "content-audit.json")) if False else \
        json.load(open(os.path.join(ROOT, "docs", "content", "content-audit.json")))
    items = load("items.json")

    # Protect item names referenced by system files we DON'T scrub (the audit didn't scan
    # these, so it wrongly flagged some used items as deprecate). Never delete a used item.
    protected = set()
    farming = load("farming.json")
    for seed, c in farming.get("crops", {}).items():
        protected.add(seed)
        if c.get("crop"):
            protected.add(c["crop"])
    protected |= set(load("tools.json").keys())            # tools ARE items, keyed by name
    for d in load("rare_drop_table.json").get("drops", []):
        if d.get("item"):
            protected.add(d["item"])

    # ids to delete -> their items.json keys (names), minus anything protected.
    del_ids = {a["id"] for a in audit["items"] if a["status"] in ("replace", "deprecate")}
    name_by_id = {rec["id"]: key for key, rec in items.items()}
    del_keys = {name_by_id[i] for i in del_ids if i in name_by_id} - protected
    del_ids = {items[k]["id"] for k in del_keys}           # re-derive ids after protection
    print(f"items: {len(items)} total; protected {len(protected & set(items))} used items; "
          f"deleting {len(del_keys)}; {len(items) - len(del_keys)} survive")

    # --- items.json ---
    for k in del_keys:
        items.pop(k, None)

    # --- enemies.json drops ---
    enemies = load("enemies.json")
    drops_removed = 0
    for rec in enemies.values():
        ds = rec.get("drops")
        if not ds:
            continue
        kept = [d for d in ds if d.get("item") not in del_keys]
        drops_removed += len(ds) - len(kept)
        rec["drops"] = kept
    print(f"enemy drops removed: {drops_removed}")

    # --- recipes.json: drop a recipe if its output or any input is deleted ---
    recipes = load("recipes.json")
    rec_del = []
    for rid, rec in recipes.items():
        out = (rec.get("output") or {}).get("item")
        ins = [i.get("item") for i in rec.get("inputs", [])]
        if out in del_keys or any(i in del_keys for i in ins):
            rec_del.append(rid)
    for rid in rec_del:
        recipes.pop(rid)
    print(f"recipes removed: {len(rec_del)} (of {len(rec_del) + len(recipes)})")

    # --- gather_nodes.json: strip deleted items; drop nodes left with none ---
    nodes = load("gather_nodes.json")
    node_items_removed = 0
    nodes_emptied = 0

    def scrub_node(n):
        nonlocal node_items_removed, nodes_emptied
        its = n.get("items", [])
        kept = [it for it in its if it not in del_keys]
        node_items_removed += len(its) - len(kept)
        n["items"] = kept
        return len(kept) > 0  # keep node only if it still yields something

    if isinstance(nodes, dict):
        # {category: [node,...]} or {id: node}
        sample = next(iter(nodes.values())) if nodes else None
        if isinstance(sample, list):
            for cat, arr in nodes.items():
                new = [n for n in arr if scrub_node(n)]
                nodes_emptied += len(arr) - len(new)
                nodes[cat] = new
        else:
            for nid in list(nodes):
                if not scrub_node(nodes[nid]):
                    nodes.pop(nid); nodes_emptied += 1
    print(f"node item-refs removed: {node_items_removed}; nodes emptied/removed: {nodes_emptied}")

    # --- alias / registry maps: drop entries pointing at deleted numeric ids ---
    aliases = load("content_aliases.json")
    alias_removed = 0
    if isinstance(aliases.get("items"), dict):
        for k in [k for k, v in aliases["items"].items() if v in del_ids]:
            aliases["items"].pop(k); alias_removed += 1
    registry = load("id_registry.json")
    reg_removed = 0
    if isinstance(registry, dict):
        # registry maps snake_id -> numeric id (or nested under a key)
        target = registry.get("items", registry)
        if isinstance(target, dict):
            for k in [k for k, v in target.items() if v in del_ids]:
                target.pop(k); reg_removed += 1
    print(f"alias entries removed: {alias_removed}; registry entries removed: {reg_removed}")

    if not APPLY:
        print("\nDRY RUN — no files written. Re-run with --apply to commit these deletions.")
        return
    save("items.json", items)
    save("enemies.json", enemies)
    save("recipes.json", recipes)
    save("gather_nodes.json", nodes)
    save("content_aliases.json", aliases)
    save("id_registry.json", registry)
    print("\nAPPLIED — wrote items/enemies/recipes/gather_nodes/aliases/registry.")


if __name__ == "__main__":
    main()
