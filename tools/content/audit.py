#!/usr/bin/env python3
"""Imota content audit + report generator (Phase 3, read-only).

Loads data/*.json, builds reverse indexes (item -> drop sources / recipe uses /
skill sources), classifies every item, runs economy checks, and writes:
  docs/content/content-audit.json   (per-item status: keep/refine/deprecate/replace)
  docs/content/reports/*.txt|json   (items without source/use, by band, skill links, IP risk)

This is the analysis engine. The in-engine gate (tools/validate_content.gd, run via
godot --headless res://tools/validate.tscn) enforces the hard checks at build time.

Run:  python3 tools/content/audit.py
"""
import json, os, re
from collections import Counter, defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(ROOT, "docs", "content")
REPORTS = os.path.join(OUT, "reports")


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)


def band(level):
    if not level or level <= 0:
        return "none"
    lo = (min(int(level), 99) - 1) // 10 * 10 + 1
    return f"{lo}-{lo + 9}"


def main():
    os.makedirs(REPORTS, exist_ok=True)
    items = load("items.json")          # name -> item
    enemies = load("enemies.json")
    recipes = load("recipes.json")
    nodes = load("gather_nodes.json")   # skill -> [node]
    tools = load("tools.json")

    # name<->id maps (drops/recipes/nodes reference display names today)
    name_to_id = {}
    for v in items.values():
        for key in (v.get("displayName"), v.get("name")):
            if key:
                name_to_id.setdefault(key, v.get("id", ""))

    # ---- reverse indexes (canonical: monster.drops / recipe.io / node.items) ----
    drop_sources = defaultdict(list)   # item name -> [enemy displayName]
    used_in_recipes = defaultdict(list)
    produced_by = defaultdict(list)
    skill_sources = defaultdict(set)   # item name -> {skill}

    for e in enemies.values():
        for d in e.get("drops", []):
            drop_sources[str(d.get("item", ""))].append(e.get("displayName", e.get("name", "")))
    for r in recipes.values():
        sk = r.get("skill", "?")
        for i in r.get("inputs", []):
            used_in_recipes[str(i.get("item", ""))].append(r.get("name", ""))
        out = r.get("output", {})
        if out:
            produced_by[str(out.get("item", ""))].append(r.get("name", ""))
            skill_sources[str(out.get("item", ""))].add(sk)
    for skill, arr in nodes.items():
        for n in arr:
            for it in n.get("items", []):
                skill_sources[str(it)].add(skill)
    tool_names = {str(t.get("name", t)) if isinstance(t, dict) else str(t) for t in (tools.values() if isinstance(tools, dict) else tools)}

    IP_NAME = re.compile(r"\bsoul\b|^golden ", re.I)
    # crude named-proper-noun boss detector: "X the Y" cadence
    PROPER = re.compile(r"\bthe\b.+(born|bound|hoof|titan|smasher|warlord|chief)", re.I)

    def names_of(v):
        return [n for n in (v.get("displayName"), v.get("name")) if n]

    audit = []
    counts = Counter()
    for v in items.values():
        nm = v.get("displayName") or v.get("name") or ""
        id = v.get("id", "")
        has_source = any(n in drop_sources or n in produced_by or n in skill_sources for n in names_of(v))
        has_use = any(n in used_in_recipes for n in names_of(v)) or any(
            float(v.get(f, 0) or 0) != 0 for f in
            ("accuracy", "damage", "rangeDamage", "magicDamage", "damageReduction", "progress")
        ) or nm in tool_names
        ip = bool(IP_NAME.search(nm)) or bool(PROPER.search(nm))

        reasons, changes, status = [], [], "keep"
        if ip:
            status = "replace"
            reasons.append("IP-derivative name/mechanic (soul/golden/named import)")
            changes.append("Remove or re-originate; deprecate via alias if referenced")
        elif not has_source and not has_use:
            status = "deprecate"
            reasons.append("Orphan: no source and no use")
            changes.append("Deprecate via alias layer (save-safe) unless given a role")
        elif not has_use:
            status = "refine"
            reasons.append("No use (sourced but consumed by nothing)")
            changes.append("Add as a recipe input / give a consumable or upgrade role")
        elif not has_source:
            status = "refine"
            reasons.append("No source (used but produced by nothing)")
            changes.append("Add a gather node / drop / recipe output")
        counts[status] += 1
        audit.append({
            "id": id, "name": nm, "status": status,
            "reasons": reasons, "recommendedChanges": changes,
            "hasSource": has_source, "hasUse": has_use, "ipRisk": ip,
            "levelBand": band(max([int(x) for x in (v.get("reqs", {}) or {}).values()] + [0])),
        })

    with open(os.path.join(OUT, "content-audit.json"), "w", encoding="utf-8") as f:
        json.dump({"summary": dict(counts), "items": audit}, f, indent=2)

    # ---- reports ----
    def write(name, lines):
        with open(os.path.join(REPORTS, name), "w", encoding="utf-8") as f:
            f.write("\n".join(str(x) for x in lines) + "\n")

    write("items_without_source.txt", [a["name"] for a in audit if not a["hasSource"]])
    write("items_without_use.txt", [a["name"] for a in audit if not a["hasUse"]])
    write("ip_risk_items.txt", [a["name"] for a in audit if a["ipRisk"]])

    by_band = Counter(a["levelBand"] for a in audit)
    write("items_by_band.txt", [f"{k}: {v}" for k, v in sorted(by_band.items())])

    # skill interaction counts: produces (outputs/nodes) vs consumes (inputs) per skill
    produces, consumes = Counter(), Counter()
    for r in recipes.values():
        produces[r.get("skill", "?")] += 1
        # consumes counts the skills whose recipes eat items that ANOTHER skill produces — approx
    for skill, arr in nodes.items():
        produces[skill] += len(arr)
    write("skill_interaction_counts.txt",
          [f"{s}: produces~{produces.get(s,0)}" for s in sorted(set(produces) | set(consumes))])

    enemy_band = Counter(band(int(e.get("level", 0))) for e in enemies.values())
    boss_band = Counter(band(int(e.get("level", 0))) for e in enemies.values() if e.get("isBoss"))
    write("monsters_by_band.txt", [f"{k}: {v}" for k, v in sorted(enemy_band.items())])
    write("bosses_by_band.txt", [f"{k}: {v}" for k, v in sorted(boss_band.items())])

    print("=== CONTENT AUDIT SUMMARY ===")
    for k, v in counts.most_common():
        print(f"  {k:10} {v}")
    print(f"  TOTAL      {sum(counts.values())} items")
    print(f"orphans(no src+use): {sum(1 for a in audit if not a['hasSource'] and not a['hasUse'])}")
    print(f"ip-risk: {sum(1 for a in audit if a['ipRisk'])}")
    print(f"wrote content-audit.json + {len(os.listdir(REPORTS))} reports under docs/content/")


if __name__ == "__main__":
    main()
