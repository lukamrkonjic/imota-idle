# Imota — Content Plan (Phase 5: implementation backlog & pre-build specs)

The prioritized, task-by-task plan that turns `CONTENT_ARCHITECTURE.md` into data/code.
**Planning only — nothing here is implemented yet.** This is the last artifact before build.

Conventions used below per task: **Reason · Files · Deps · Risk · Impact**.
Risk = Low / Med / High (gameplay or save risk). Impact = rough record/system count.

Branch: `content/audit-and-architecture`. After every task: run `validate.tscn`
("ALL TESTS PASSED"), re-run `tools/content/audit.py`, and (for render/gameplay) a manual run.

---

## 0. Pre-build specs (decide once, before any records)

### 0.1 Item schema extension (additive, backward-compatible)
Add these optional fields to `data/items.json` records (absent = legacy default):

| Field | Type | Default if absent | Purpose |
|-------|------|-------------------|---------|
| `category` | string | inferred | `material`/`equipment`/`consumable`/`tool`/`currency`/`key`/`quest`/`cosmetic` |
| `slot` | string | name-inferred (current) | equipment slot; replaces name inference |
| `combatStyle` | string | stat/name-inferred | `melee`/`ranged`/`magic` |
| `tier` | int | 0 | material/equipment tier (1–8) |
| `levelBand` | string | from `reqs` | `"40-49"` etc. for band validation |
| `tags` | string[] | `[]` | `["dragon","scale","crafting_component"]` |
| `rarity` | string | `common` | common…boss-exclusive |
| `stackable` | bool | true for materials | inventory behaviour |
| `balanceStatus` | string | absent | `"provisional"` for un-tuned numbers |
| `deprecated` | bool | false | hidden legacy record kept for save compat |

Rule: never encode balance in display text; these structured fields are authoritative.
`game_state.slot_for_item` / `weapon_combat_style` already prefer data fields (done earlier),
so populating `slot`/`combatStyle` is the activation, not a code change.

### 0.2 Reference direction & generated indexes
Canonical (hand-authored): `monster.drops`, `recipe.inputs/output`, `node.items`,
`item.slot/tier/tags`. **Generated** (never hand-stored): `item.dropSources`,
`item.usedInRecipes`, `item.skillSources`. Generator = extend `tools/content/audit.py`
(already builds these) to optionally emit a `data/generated/reverse_index.json` the game can
load read-only. Keeps one source of truth.

### 0.3 name→id migration approach (save-safe)
Today drops/recipes/nodes reference **display names**. Migrate canonical refs to **stable ids**
in two safe steps so nothing breaks mid-way:
1. **Backfill ids alongside names** — add `itemId` next to `item` in each drop/input/output/node
   (script-generated from `resolve_item_id`). Runtime keeps reading `item` (name) → zero behaviour
   change; the new `itemId` is validated to match.
2. **Flip readers to `itemId`**, keep `item` as a comment/fallback for one release, then drop it.
Renames thereafter only touch the item's `displayName`; ids are stable forever.

### 0.4 Deprecation / removal strategy (the 673 replace + 199 deprecate)
No destructive deletion. For each removed/replaced id:
- **Orphan, never in a save-relevant slot** → mark `deprecated:true`, hide from UI/spawns, keep
  the record so old saves load. Validator allowlists deprecated ids.
- **IP-derivative but referenced** (in a drop/recipe) → re-originate the *concept* into a new id,
  add old→new mapping in `rename_map.json`/`content_aliases.json` (the alias layer already exists),
  so saves holding the old item resolve to the new one.
- **Soul/Golden bulk dumps** (591+279, almost all orphans) → batch `deprecated:true`; if any are
  in saves, alias to nearest generic or to a small "legacy collectible" stub.
Document every non-trivial mapping in `CONTENT_AUDIT.md` appendix.

### 0.5 Vertical-slice template (prove once, then scale)
Before mass-authoring, build ONE complete cross-skill loop end-to-end and validate it:
**Metal slice** — mining node(s) → ore → smithing bar → melee weapon+armour tier → a creature
that drops a secondary smithing ingredient → an alchemy flux that upgrades the top piece.
This exercises every system (gather, refine, recipe, drop, upgrade, reverse-index, validator)
on a small set, so the pattern is proven before the other families copy it.

### 0.6 ID & naming finalization
snake_case ids; reserve numeric ranges per family for expansion (e.g. `item.metal.*`).
Generics stay plain ("Iron Bar", "Boar Hide"); proper names reserved for bosses only.
Style guide lives in `CONTENT_ARCHITECTURE.md §13`.

---

## 1. Implementation backlog (prioritized milestones)

### M1 — Foundation (critical, no gameplay change)
- **T1.1 Add schema fields + populate `category`/`slot`/`combatStyle`/`stackable` for KEEP items.**
  Reason: unlock data-driven slot/style/validation. Files: `items.json`, `validate_content.gd`,
  `audit.py`. Deps: 0.1. Risk: Low. Impact: ~766 items annotated.
- **T1.2 name→id backfill (`itemId` beside `item`).** Reason: stable refs. Files: drops in
  `enemies.json`, `recipes.json`, `gather_nodes.json` + a one-shot migration script + validator
  match-check. Deps: 0.3. Risk: Med (data format). Impact: all refs.
- **T1.3 Reverse-index generator → `data/generated/reverse_index.json` + loader.** Reason:
  bidirectional queries. Files: `audit.py`, a tiny GDScript loader. Deps: T1.2. Risk: Low.
- **T1.4 Promote economy checks toward errors as backlog clears; add allowlists** (currency/keys/
  cosmetics/deprecated). Files: `validate_content.gd`. Deps: M2. Risk: Low.

### M2 — Prune & re-originate (high impact, save-safe)
- **T2.1 Batch-deprecate the 199 orphans + 591 souls + 279 goldens.** Reason: kill bloat/IP.
  Files: `items.json`, `rename_map.json`. Deps: 0.4. Risk: Med (save compat — mitigated by alias).
  Impact: ~1000 records hidden.
- **T2.2 Re-originate referenced IP items + named bosses** (incl. literal `Giant Mole`). Reason:
  originality. Files: `items.json`, `enemies.json`, alias map. Deps: 0.4, architecture §7/§13.
  Risk: Med. Impact: ~35 bosses reviewed, IP items remapped.
- **T2.3 Remove the unwired beastmastery/soul mechanic fields** from enemies (or repurpose for
  slayer). Files: `enemies.json`. Deps: M5 slayer decision. Risk: Low.

### M3 — Vertical slice (proof)
- **T3.1 Build the Metal slice end-to-end** (0.5). Reason: validate the whole pattern small.
  Files: items/recipes/nodes/enemies (metal subset). Deps: M1. Risk: Med. Impact: ~25 records.
- **T3.2 Tune + validate the slice** (kill-time, XP/hr, recipe cost) → lock the template numbers
  as `balanceStatus:"provisional"`. Deps: T3.1. Risk: Low.

### M4 — Economy build-out (the bulk, in passes)
Each as its own commit, following the slice template; validate after each.
- **T4.1 Material families** (wood, leather/hide, cloth, gem, herb, essence). Risk: Med. ~90 mats.
- **T4.2 Gathering + refining actions/nodes** across the bands, with spatial+regrow scarcity
  wired via `skill_sites.json`/`pois.json` (commons plentiful/fast; premium few/slow). Risk: Med.
- **T4.3 Recipes** per production skill across bands (cooking/smithing/fletching/crafting/alchemy).
  Risk: Med. ~200–280 recipes.
- **T4.4 Equipment progression** per style/slot incl. sidegrades + 2–4 set bonuses. Risk: Med.
  ~120–150 pieces.
- **T4.5 Normal monsters + thematic drop tables** across bands; no two identical tables. Risk: Med.
  ~90–110 monsters.
- **T4.6 Elites/minibosses.** ~12–18. Risk: Low.

### M5 — New skill SYSTEMS (code milestones, each shippable alone)
Sequenced after the economy exists so they have things to interact with. Each is design+code+data.
- **T5.1 Prayer activation** (Devotion resource, toggle groups, `combat_sim` hooks, `active_prayers`).
  Files: `game_state.gd`, `combat_sim.gd`, HUD prayer tab, `data/prayers.json` (new). Risk: High.
  Impact: system + ~18–24 prayers.
- **T5.2 Slayer task system** (task-giver, gates premium kills/drops). Files: new sim + UI +
  `enemies.json` gates. Risk: High.
- **T5.3 Firemaking** (burn logs → embers/ash; light-gated nodes). Risk: Med.
- **T5.4 Hunter** (trap loop → hides/feathers). Risk: Med.
- **T5.5 Thieving** (steal from humanoid POIs → coins/cloth/keys). Risk: Med.
- **T5.6 Agility** (map shortcuts + run-energy/efficiency). Risk: Med.

### M6 — Bosses & chase content
- **T6.1 Re-originated bosses** with entry gates, a mechanical trait, economy-linked uniques
  (cores finished by non-combat skills). ~16–20. Risk: Med.
- **T6.2 Rarity + pity/fragment systems** for mandatory boss components. Files: drop logic +
  `data`. Risk: Med.
- **T6.3 Chase items** (very-rare/exceptional sidegrades, prestige, collectibles). Risk: Low.

### M7 — Economy validation, migrations, docs
- **T7.1 Promote all economy checks to errors**; full green with allowlists. Risk: Low.
- **T7.2 Save migration pass** — verify alias map covers every removed/renamed id; add a
  validate phase asserting no save-referenced id is dangling. Risk: Med.
- **T7.3 Generated reports refresh + finalize the 3 docs.** Risk: Low.

### M8 — Future expansion (not now)
Region packs (biome + nodes + monsters + boss + material family + recipes), additive only.

---

## 2. Critical path & dependencies
`0.x specs → M1 foundation → M2 prune (parallel-ish) → M3 slice → M4 economy → M5 systems →
M6 bosses → M7 validation/migrations`. M5 systems can interleave with M4 once their target
economy items exist. OSRS reference cross-check folds into M3/M4 once the path is fixed.

## 3. Risk register (top)
- **Save compatibility** (M2/M7): mitigated by deprecation+alias, never destructive delete.
- **New systems scope** (M5): 6 new mechanics = the bulk of the effort; each is its own milestone
  and individually shippable so the project never half-breaks.
- **Balance** (all): every authored number tagged `provisional`, tuned in M3/M7 against measured
  kill-time/XP — no offline to model (Imota has none).
- **Name→id migration** (T1.2): staged (backfill → flip → drop) so no flag-day breakage.

## 4. What I still need from you before M1
- Sign-off on the **schema fields (0.1)** and **deprecation strategy (0.4)**.
- Confirm **M5 sequencing** — do all 6 new systems land in this effort, or stage some (e.g.
  prayer+slayer now, hunter/thieving/firemaking/agility as a later milestone)?
- Fix the **OSRS reference path** if you want that cross-check in M3/M4.
