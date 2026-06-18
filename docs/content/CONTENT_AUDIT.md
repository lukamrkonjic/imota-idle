# Imota — Content Audit (Phase 1: discovery)

Status: **Phase 1 only** — discovery + audit. No content/database changes made yet.
Branch: `content/audit-and-architecture`. Engine is **Godot 4.6 / GDScript**, content is
**`data/*.json`** loaded by `DataRegistry` (the brief's TypeScript/npm/offline assumptions
do not apply — see "Brief assumptions that don't fit Imota" at the end).

---

## 1. Detected skill list (authoritative, from `autoload/game_state.gd` `SKILLS`)

22 skills:

| Category | Skills |
|----------|--------|
| Combat | attack, strength, defence, hitpoints, ranged, magic |
| Combat-support | prayer, slayer |
| Gathering | woodcutting, mining, fishing, foraging, thieving, hunter, farming |
| Production | cooking, smithing, firemaking, fletching, crafting, alchemy |
| Utility | agility |

**Content coverage per skill (the critical finding):**

| Skill | Has content? | Source |
|-------|-------------|--------|
| attack/strength/defence/hitpoints/ranged/magic | ✅ | 120 enemies + ~390 equipment items, `combat_sim.gd` |
| woodcutting | ✅ | 19 gather nodes |
| mining | ✅ | 35 gather nodes |
| fishing | ✅ | 67 gather nodes |
| foraging | ✅ | 46 gather nodes |
| smithing | ✅ | 228 recipes |
| crafting | ✅ | 306 recipes |
| alchemy | ✅ | 118 recipes |
| fletching | ✅ | 51 recipes |
| cooking | ✅ | 46 recipes |
| farming | ⚠️ minimal | `data/farming.json` (2 records), `FarmingSim` |
| prayer | ⚠️ inert | 26 "prayer" recipes exist, but prayers are **display-only** — `GameState.active_prayers` is never populated; no toggle/effect path |
| slayer | ⚠️ inert | enemies carry `beastMasteryReq`/`slayerReq` but `combat_sim` defaults the gate OFF (no slayer task system) |
| **firemaking** | ❌ none | no recipes, no nodes |
| **thieving** | ❌ none | no nodes, no recipes |
| **hunter** | ❌ none | no nodes, no recipes |
| **agility** | ❌ none | exists only as the `run_energy` meta-stat (`game_state.gd`) |

> **6 of 22 skills are dead-end content islands** (firemaking, thieving, hunter, agility) or
> mechanically inert (prayer, slayer). This is the single biggest structural problem.

---

## 2. Schema map

### Item — `data/items.json` (dict keyed by display name; 1803 records)
Fields: `id`, `name`, `displayName`, `info`, `value`, `reqs` (dict `skill→level`),
combat stats (`accuracy`, `damage`, `rangeAccuracy`, `rangeDamage`, `magicAccuracy`,
`magicDamage`, `critChance`, `damageReduction`, `runSpeed`), `progress` (tool gather power),
`bonusXp`.
**Missing structured fields the brief wants:** `category`, `slot`, `tier`, `levelBand`,
`tags`, `rarity`, `tradeable`, `stackable`, `sources`, `uses`. Equipment slot is currently
**inferred from the display name** at runtime (`game_state.slot_for_item`, now data-first but
the data fields don't exist yet), and combat style is inferred from stats/name.

### Enemy — `data/enemies.json` (dict; 120 records, 35 flagged `isBoss`)
Fields: `id`, `name`, `displayName`, `level`, `maxHealth`, `style`, `accuracy`, `damage`,
`critChance`, `critMultiplier`, `damageReduction`, `cooldown`, `combatXp`, `hitpointsXp`,
`beastMasteryReq`, `beastMasteryXp`, `isBoss`, `drops`.
`drops`: `[{item, chance (0..1), min, max}]` — **references items by DISPLAY NAME, not id**.

### Recipe — `data/recipes.json` (dict keyed `skill/Name`; 775 records)
Fields: `id`, `name`, `displayName`, `skill`, `levelReq`, `time`, `xp`, `inputs`
`[{item, qty}]`, `output` `{item, qty}`, `hpValue`, etc. Inputs/outputs reference item names.

### Gather node — `data/gather_nodes.json` (dict `skill→[nodes]`; 167 nodes)
Fields per node: `id`, `name`, `displayName`, `level`, `xp`, `items` (list of names).

### Other: `tools.json` (60), `rare_drop_table.json` (3), `xp_table.json`,
`content_aliases.json` / `id_registry.json` / `rename_map.json` (stable-id + alias layer),
`data/world/*` (biomes 5, pois, skill_sites, zone_names 23, monsters [spawn config]).

### Stable IDs & loaders
`DataRegistry` assigns stable ids (`item.NNNN`, `node.NNNN`) and resolves aliases
(`resolve_item_id`). **But canonical cross-references in drops/recipes/nodes are stored by
DISPLAY NAME**, not id — fragile to renames. Combat formulas live in `combat_sim.gd`
(audited earlier: accuracy `0.3+0.01·lvl`, damage variance 0.6–1.2×, combat triangle ×1.25).

---

## 3. Content counts

| Type | Count | Brief target | Verdict |
|------|------:|-------------:|---------|
| Items (records) | 1803 | 150–300 | **~6–12× over** |
| — distinct item names | 2265 | | |
| — **orphans (no source AND no use)** | **1289 (~57%)** | | **severe bloat** |
| — equipment-ish (combat stats) | 390 | 80–180 | ~2× over |
| — "soul" items | 591 | — | imported beastmastery dump (orphaned/inert) |
| — "Golden …" variants | 279 | — | imported cosmetic/variant dump |
| Enemies | 120 (35 boss) | 80–140 normal / 12–25 boss | normal OK; **bosses ~40% over** |
| Recipes | 775 | "enough" | heavy; 280 pegged at lvl 99 |
| Gather nodes | 167 | "enough" | OK breadth, gathering-skill only |

**Level-band distribution** (content is *not* missing in high bands — the opposite problem):

| Band | Enemies | Recipes | Nodes | Equipment |
|------|--------:|--------:|------:|----------:|
| 1–10 | 19 | 95 | 28 | 43 |
| 11–50 | ~38 | ~222 | ~51 | ~81 |
| 51–90 | ~25 | ~175 | ~39 | ~86 |
| **91–100** | **38** | **280** | **49** | **111** |

> Every band has content, but there's a **huge pile-up at 99** (3–5× any other band) — the
> classic "import dumped everything at the level cap" pattern, not smooth 1→99 tiering.

---

## 4. Most serious problems (prioritized)

**P0 — Originality / IP risk.** Large swaths are direct Bloobs/OSRS imports, not "inspired by":
- `Giant Mole` (literal OSRS boss), proper-named bosses like *Solheim the Sunbound Pharaoh*,
  *Taurok the Crimsonhoof*, *Vorlach the Glacierborn*, *Drommok the Twin-Titan*, plus
  591 "Soul" items and 279 "Golden …" variants are Bloobs's distinctive content/mechanics.
  These must be removed or re-originated, not trivially renamed.

**P0 — Item bloat & orphans.** 1803 items / ~1289 orphans (57%) with no source and no use —
inventory/economy noise, much of it the imported soul/golden dumps. Target is 150–300.

**P1 — Dead/inert skills.** firemaking, thieving, hunter, agility have **zero** content;
prayer is display-only; slayer's gate is disabled. 6/22 skills don't participate in the economy.

**P1 — Name-keyed references.** drops/recipes/nodes reference items by **display name**, so any
rename silently breaks links (and makes the orphan/relationship analysis fragile). Canonical
refs should be stable ids with generated reverse indexes.

**P1 — Missing structured item metadata.** No `category/slot/tier/levelBand/tags/rarity/
tradeable/stackable` → slot & style are name-inferred; rarity/tiering is implicit. Blocks
clean drop-table, progression, and validation work.

**P2 — Boss over-supply / weak identity.** 35 bosses (≈30% of all enemies) flagged only by
`isBoss=true` + bigger stats; no mechanical traits, entry gates, or economy-linked unique
rewards encoded.

**P2 — 99-cluster progression.** ~280 recipes / 111 equipment pegged at the cap instead of
spread; little distinction between "late-game" (70–89) and "endgame chase" (90–99).

**P2 — No rarity model.** drop `chance` is a raw float with no rarity tiering, bad-luck
protection, or fragment/token systems — needed for meaningful chase items.

---

## 5. Copyright / derivation risk register (samples to purge or re-originate)
- Literal OSRS: `Giant Mole`. Audit all 35 bosses against OSRS/Bloobs boss lists.
- Proper-named Bloobs bosses (*…the Glacierborn*, *…the Sunbound Pharaoh*, etc.).
- 591 `* Soul` items + `beastMastery*` enemy fields = Bloobs's summoning/soul mechanic,
  imported but unwired (also orphaned).
- 279 `Golden *` items = Bloobs golden-variant collectible system.
- Generic-but-fine (keep, re-describe): chickens, cows, wolves, goblins, skeletons, dragons,
  bronze/iron/steel/mithril tiers, Logs/Bones/Hide families.

---

## Brief assumptions that DON'T fit Imota (flagged for your verification)
- **No offline progress.** Imota has no offline/idle-time fast-forward (confirmed: SaveManager
  has no offline apply). All "average offline time / offline balance" guidance is N/A — balance
  on active kill-time + automation only.
- **No TypeScript/npm.** It's GDScript + JSON; validators go in `tools/` (GDScript), run via
  `godot --headless res://tools/validate.tscn`, not `npm run validate:content`.
- **Trading / tradeable.** No player trading/GE in Imota (single-player). `tradeable` is
  meaningless unless it gates an alch/sell value — recommend dropping it or repurposing as
  "vendor-sellable".
- **Localization.** No separate localization layer; display names are the strings.
- **Pets/companions/cosmetics/quests.** Not confirmed in code — do **not** design rewards
  around them without adding the systems first.
- **OSRS reference DB empty.** `/Users/lukamrkonjic/Downloads/osrs db` contains no usable
  files (1 entry, no data). **Please verify the path** — Phase 3 OSRS pattern analysis can't
  run without it. (Bloobs export is present: 1723 wiki pages.)

## Design note you raised (will bake into Phase 4 architecture)
Node/boss **scarcity should be spatial + time-gated, not just drop-rate**: common nodes
(regular trees, copper/tin, shrimp) plentiful, everywhere, fast regrow; premium nodes (a
"magic"-tier tree, rare ore) few, in special biomes/POIs, slow regrow → not trivially farmable.
Same for bosses: gated by location/access + cooldown, not just rarity. This maps onto the
existing `data/world/skill_sites.json` + `pois.json` + depletion/respawn timers.
