# Imota — Full Content Build Plan ("build it all")

Goal: a complete, coherent, OSRS/bloobs-shaped content foundation across **all 22 skills** —
every material family, gathering node, refining/production recipe, equipment progression,
normal monster, miniboss and boss, plus the **inert/missing skill systems wired in code** —
authored data-first so it's regenerable and easy to customise into Imota's own identity later.

Single-player, **no save-compat constraint**: the bloat (replace + deprecate items) is
**hard-deleted**, all references scrubbed, and content rebuilt original from clean families.

Authoring is **generator-driven**: Python build scripts in `tools/content/build/` emit the
data from compact family/tier/band specs, so the whole economy is consistent and can be
regenerated/retuned in one pass. Hand-tuning happens on top, tagged `balanceStatus:"provisional"`.

After every milestone: run `tools/validate.tscn` (ALL TESTS PASSED) + `tools/content/audit.py`,
and a manual run for gameplay milestones.

---

## Design frame

- **Level bands:** 1–10, 10–20, 20–30, 30–40, 40–50, 50–60, 60–70, 70–80, 80–90, 90–99.
- **Tiers (materials/equipment):** 8 tiers mapped onto the bands (T1≈1–10 … T8≈80–99).
- **Combat styles:** melee / ranged / magic, each with a full slot+tier progression.
- **Reference direction (one source of truth):** canonical = `monster.drops`, `recipe.inputs/output`,
  `node.items`, `item.slot/tier/tags`. Generated (never hand-stored) = reverse indexes.
- **IDs:** stable `snake_case`/numeric within reserved per-family ranges; refs migrate name→id.

---

## Milestones

### M0 — Foundation & cleanup (this milestone first)
- **Hard-delete** every item with audit status `replace` (673) or `deprecate` (199) from
  `items.json`, and scrub all references (drops, recipe inputs/outputs, node items, alias/registry)
  by id AND display name. Drop now-empty recipes/drops; report everything removed.
- **Schema extension** (additive): `category, slot, combatStyle, tier, levelBand, tags, rarity,
  stackable, balanceStatus, deprecated`. Populate `category/slot/combatStyle/stackable/levelBand`
  for the surviving keep+refine items (~931).
- **name→id migration:** backfill `itemId` beside `item` in every drop/input/output/node, then flip
  readers to ids (with a one-release name fallback). Same for enemies/recipes/nodes.
- **Reverse-index generator:** extend `audit.py` to emit `data/generated/reverse_index.json`
  (`dropSources/usedInRecipes/skillSources`) + a read-only GDScript loader.
- **Validator:** promote economy checks (every item has a source + a use; every ref resolves).

### M1 — Material families (the economy's atoms)
Per family, T1–T8 across the bands, with raw → refined chains:
wood (logs→planks), ore→bar (metal), hide→leather, fibre→cloth, gem (rough→cut), herb→ (potions),
essence/rune (magic), fish (raw→cooked), crop/seed (farming), bone/ash (prayer/firemaking),
secondary reagents (feathers, threads, fletching, fluxes). ~120–160 material items.

### M2 — Gathering content (all gathering skills)
Nodes across every band with spatial + regrow scarcity (commons plentiful/fast, premium few/slow),
wired through `gather_nodes.json` + `skill_sites.json`/`pois.json`:
woodcutting, mining, fishing, foraging, farming patches, hunter traps, thieving targets.

### M3 — Production recipes (all production skills)
Band-scaled recipe chains: smithing (bars→tools/weapons/armour), crafting (leather/cloth/gem/jewellery),
fletching (bows/arrows/bolts), cooking (raw→cooked food, tiered heals), alchemy (herb→potions, tiers),
firemaking (logs→light/ash). ~300–400 recipes.

### M4 — Equipment progression (combat)
Full melee/ranged/magic ladders per slot (weapon, head, body, legs, hands, feet, cape, shield, ring,
amulet) per tier, with deliberate sidegrades and 2–4 set bonuses. ~150–200 pieces, stats from a
single tier curve so power scales predictably.

### M5 — Monsters & drop tables
Normal monsters per band/biome with thematic, non-duplicate drop tables (each ties to its biome's
materials + a small shared rare table). Elites/minibosses per band. ~110–140 monsters.

### M6 — New skill SYSTEMS (code, each shippable alone)
Sequenced after the economy gives them things to touch:
- **Prayer** — Devotion resource, toggle groups, `combat_sim` hooks, `data/prayers.json`.
- **Slayer** — task-giver, gates premium kills/drops.
- **Firemaking** — burn logs → light/ash, light-gated nodes.
- **Hunter** — trap loop → hides/feathers.
- **Thieving** — steal from humanoid POIs → coins/cloth/keys.
- **Agility** — shortcuts + run-energy/efficiency. **DEFERRED** (chilling on this one for now;
  re-pick up after the other five skill systems land).

### M7 — Bosses & chase content
~16–20 original bosses: entry gate, one mechanical trait, economy-linked uniques (cores finished by
non-combat skills), rarity + pity/fragment systems, prestige/chase sidegrades.

### M8 — Validation, balance, docs
Economy checks → errors (full green). Measured kill-time/XP-per-hour tuning passes off the
provisional numbers. Refresh generated reports + finalise the content docs.

---

## Critical path
`M0 foundation → M1 materials → M2 gathering → M3 recipes → M4 equipment → M5 monsters →
M6 systems (interleave once their items exist) → M7 bosses → M8 validation/balance`.

## Approach notes
- Each milestone = its own commit(s); validate after each; never leave the project half-broken.
- All authored numbers tagged `provisional`; balance is a dedicated later pass (no offline sim).
- Generators are idempotent and re-runnable so retuning a whole family is a spec edit + regen.
