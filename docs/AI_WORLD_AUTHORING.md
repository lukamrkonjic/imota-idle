# AI World Authoring — Director, WorldSpec & Compiler

This document evaluates and specifies an **AI-first world-authoring system** for Imota,
mapped onto the project's **existing** deterministic, data-driven world generator.

> TL;DR — We do **not** build a visual map editor. We add a thin **authored layer**
> (`WorldSpec`) that the existing seeded passes consult *first* and fall back to
> procedural generation when absent. An AI writes the brief → a compiler emits the
> WorldSpec → the existing Godot pipeline builds it deterministically → headless
> validators + screenshot tooling produce machine-readable evidence → AI critics
> emit structured issues → only the affected region/layer is rebuilt.

---

## 0. Findings — how the current generator works

The investigation (see also `docs/WORLDGEN_GUIDE.md`, `docs/ARCHITECTURE.md`) found a
system that is already **80% of the desired "deterministic World Compiler"**:

| Question | Finding |
|----------|---------|
| 1. World generator | `WorldGen` autoload → `WorldGenerator.generate(layer,cx,cy)`. Per-chunk passes: terrain fields → biome → elevation → tiles → roads → POIs → skill sites → monsters. |
| 2. Terrain & biomes | `BiomeClassifier`: layered `FastNoiseLite` height/moisture/temp ∈ [0,1]; data-driven biome `when` ranges (`data/world/biomes.json`). `ElevationMap`: discrete levels 0..7. |
| 3. Reusable parts | **Almost everything.** Registry pattern, deterministic hashing, chunk model, snapshots, anchors/roads, POI/site/monster placement are all reusable as compiler passes. |
| 4. Asset/data org | `data/world/*.json` (biomes, pois, anchors, skill_sites, monsters, cave_layers, zone_names, generation_rules). Art = **procedural `_draw()`** sprite "kinds", not `.tscn`/`.tres` assets. |
| 5. Services spawned | POI "parts" with a `station` id (`bank`, `anvil`, `range`, …) → clickable `WorldEntity`. Skill sites from bestiary/gather-node tables. |
| 6. Save/load/chunks | `CHUNK_TILES=16`, `TILE=48px`, `ZONE_CELL=6`. In-memory cache keyed `layer:cx:cy`; explored chunks frozen in `chunkSnapshots`; only player deltas persisted. |
| 7. Navigation/collision | **No physics.** `AStarGrid2D` over loaded chunks (`PathFinder`). Walkability from tile flags. No `NavigationRegion`. |
| 8. Determinism | **Yes — strong.** `WG.hash_i/r01` (splitmix) + seeded noise. Same seed ⇒ identical chunk; `GENERATOR_VERSION` invalidates stale snapshots. |
| 9. Screenshots / eval | Headless **ASCII** tool (`tools/world_debug.tscn`) + headless test harness (`tools/validate.tscn`). **No viewport capture yet.** |
| 10. Restrictions | `--headless` uses the dummy renderer → **no PNG capture headless**; screenshots need a (hidden) window. Biomes are global noise (no native region masks). Boss names shown = real bestiary names. Art is code, not assets. |

**Conclusion:** the right move is *not* to rewrite the generator, but to (a) add an
**authored override layer**, (b) add **screenshot + metrics emission**, and (c) wrap the
existing headless harness in an AI-operable **CLI**.

---

## 1. Recommended architecture

```
 Human brief (natural language)
        │
        ▼
 ┌──────────────┐   writes    ┌────────────────────────────┐
 │ AI World     │ ──────────▶ │ WorldSpec (JSON, versioned) │  data/world/worldspec/*.json
 │ Director     │             └────────────────────────────┘
 └──────────────┘                         │ loaded by
        ▲                                 ▼
        │ structured issues     ┌────────────────────┐
 ┌──────────────┐               │ WorldRegistry.spec │  scripts/worldgen/world_spec.gd
 │ AI Critics   │               └────────────────────┘
 └──────────────┘                         │ consulted (override-first) by
        ▲                                 ▼
        │ metrics + images      ┌──────────────────────────────────────────────┐
 ┌──────────────┐               │ Deterministic compiler passes (existing+new): │
 │ Validators / │ ◀──────────── │ zone_map · biome_classifier · elevation ·     │
 │ Reporters    │   emit        │ anchor_planner · poi_placement · skill_sites · │
 └──────────────┘               │ monster_spawner · cave_generator · renderer    │
        ▲                       └──────────────────────────────────────────────┘
        │                                 │
        └──────────── CLI: tools/worldc.gd (compile · validate · explain · shoot)
```

Key principle: **authored-first, procedural-fallback.** Each pass asks `reg.spec`
"do you own this cell/chunk/tile?" If yes, it uses the authored decision; if no (or no
spec is active), behaviour is byte-identical to today. This keeps the infinite
procedural world working and makes authored regions *islands of intent* inside it.

---

## 2. Proposed WorldSpec schema

A WorldSpec is a single JSON document (one active spec at a time, selected by
`data/world/worldspec/index.json`). It describes **semantics**, never individual trees.

```jsonc
{
  "id": "medieval", "version": 1, "seed": 7, "generatorVersion": 3,
  "name": "The Eastvale Realm",
  "defaults": { "biome": "", "danger": "safe" },

  "regions": [{
    "id": "eastvale", "name": "Eastvale Commons",
    "shape": { "type": "disc", "center": [0, 0], "radius": 2 },  // chunk space
    "biome": "plains",            // forces biome (memorable, separated regions)
    "req": 1,                      // entry level → danger gate + monster band
    "tier": "Beginner",
    "danger": "safe",
    "motif": "rolling green commons, low fences, a guidepost",
    "material": "grass+timber", "silhouette": "open",
    "locked": false,              // authored & protected from regen
    "regen": ["vegetation", "decals"]  // layers that MAY be rebuilt
  }],

  "anchors": [{                    // fixed-placement settlements/landmarks/dungeons
    "id": "kingsreach", "poi": "capital_city", "label": "Kingsreach",
    "chunk": [4, 0], "region": "kingsreach",
    "boss": "", "teleport": true, "locked": true
  }],

  "routes": [                      // primary roads (limited, understandable)
    { "from": "spawn", "to": "kingsreach" },
    { "from": "spawn", "to": "grimwarden" }
  ],

  "relationships": [               // declarative, validated (not yet auto-solved)
    { "kind": "visible_from", "a": "bank@spawn", "b": "town_entrance@spawn" },
    { "kind": "travel_time", "a": "bank@spawn", "b": "mine@oakholt", "seconds": 120, "tolerance": 30 },
    { "kind": "max_entrances", "region": "dreadmoor", "count": 2 }
  ]
}
```

**WorldSpec responsibilities** map as follows:

| Responsibility | WorldSpec field | Compiled by |
|----------------|-----------------|-------------|
| Regions / regional identity | `regions[]` (motif/material/silhouette) | `zone_map`, `biome_classifier` |
| Biomes / contrast | `regions[].biome` | `biome_classifier` (force) |
| Settlements / services | `anchors[].poi` + `pois.json` parts | `anchor_planner`, `poi_placement` |
| Landmarks / dungeons | `anchors[].poi` (ruins, dungeon) | `poi_placement`, `cave_generator` |
| Roads / transport | `routes[]` | `anchor_planner.road_segments` |
| Skilling areas / resources | region biome `skillWeights` + `generation_rules` | `skill_site_spawner` |
| Danger progression | `regions[].req` | `monster_spawner` band + path gate |
| Expected travel times / sightlines | `relationships[]` | **validators** |
| Placement constraints | `shape`, `chunk`, biome whitelist | placement passes |
| Seeds | `seed`, per-region future `seed` | all (seed chain) |
| Locked / regenerable | `locked`, `regen[]` | selective-regen + snapshots |

---

## 3. Proposed asset-metadata schema

The project's "assets" are **procedural sprite kinds** + data definitions, not scene
files — so the registry is a **sidecar JSON** that augments the existing `pois.json`
parts and `biomes.json` tiles rather than a per-`.tscn` resource. (If/when real
`.tscn` props are added, the same schema becomes a Godot **custom Resource**
`AssetMeta.tres` referenced by scene `metadata`.)

```jsonc
// data/world/asset_registry.json  (sidecar; future-proof for .tscn assets)
{
  "campfire": {
    "category": "service", "role": "functional",
    "scene": "kind:campfire",            // procedural kind today; res:// path later
    "biomes": ["*"], "settlements": ["*"],
    "footprint": [1, 1], "entrances": [[0, 1]], "anchors": [[0,-1]],
    "requiredTerrain": ["land"], "maxSlope": 4, "minClearance": 1,
    "visualImportance": 0.4, "perfCost": 1, "frequency": "unique",
    "rotation": [0], "scale": [1.0], "blocksNav": false
  }
}
```

Recommendation: **sidecar JSON now** (zero engine coupling, AI-editable, validates in
the existing harness); migrate hot fields to **exported properties on a `WorldEntity`
scene** only if/when art moves from `_draw()` to instanced scenes. Do **not** use
scene `metadata{}` as the source of truth — it is invisible to the headless validator.

---

## 4. Compiler pass responsibilities

Existing passes are reused; new/extended passes are marked **(+)**. Each is
deterministic and independently rerunnable.

| # | Pass | Module | Authored input | Independence |
|---|------|--------|----------------|--------------|
| 1 | Semantic world graph | `world_spec.gd` **(+)** | regions/anchors/routes | builds once at load |
| 2 | Regional boundaries | `zone_map` (override **+**) | region `shape`+`req`+`name` | per-cell, cached |
| 3 | Macro terrain | `biome_classifier.fields` | seed | per-tile, pure |
| 4 | Biome mask | `biome_classifier` (override **+**) | region `biome` | per-chunk |
| 5 | Landmark placement | `poi_placement` (authored anchor **+**) | anchors | per-chunk |
| 6 | Settlement layout | `poi_placement` + `pois.json` parts | anchor `poi` | per-chunk |
| 7 | Roads & paths | `anchor_planner.road_segments` (authored **+**) | routes | global, cached |
| 8 | Gameplay services | `pois.json` part `station` | poi parts | per-chunk |
| 9 | Resources / skilling | `skill_site_spawner` | biome weights | per-chunk |
| 10 | Vegetation / props | `world_entity_spawner` ground decor | biome | per-tile (presentational) |
| 11 | Decals / micro-detail | `chunk_renderer` bake | tiles | per-chunk image |
| 12 | Collision | (tile walkability flags) | tiles | per-tile |
| 13 | Navigation bake | `path_finder` (`AStarGrid2D`) | loaded tiles | per-load |
| 14 | Runtime chunks | `chunk_manager` | streaming | per-load |
| 15 | Minimap / metadata | `worldc.gd` reporters **(+)** | chunk data | per-region |

**Isolation guarantee:** vegetation (pass 10) is regenerated from
`r01(seed, chunk, tile)` and never moves a POI (pass 5/6); regenerating a settlement
re-rolls only that chunk's POI placement while terrain (pass 3/4) is reused or
snapshot-frozen.

---

## 5. Validation rules

Run headless (`worldc --validate`). Each rule emits a **structured issue** (§6 format).

- **Reachability:** every authored anchor tile is on the `AStarGrid2D`-walkable set
  reachable from `spawn` (BFS over walkable tiles); else `inaccessible_location`.
- **Service presence:** spawn region has a reachable `bank`, `campfire`/respawn; each
  region declares the services it promises → `missing_service`.
- **Travel time:** `relationships.travel_time` measured as `A*` path length ÷
  walk speed; out of tolerance → `travel_time_violation`.
- **Sightline:** `visible_from` checks straight-line tile LOS (no `blocksNav` tile and
  ≤ a max distance) → `sightline_blocked`.
- **Entrance count:** `max_entrances` counts walkable border openings into a region's
  disc → `entrance_count`.
- **Danger monotonicity:** region `req` should not drop then spike along a primary
  route → `danger_discontinuity`.
- **Overlap/collision:** two POI parts on the same tile, or a part on water/hazard →
  `overlap` / `bad_terrain`.
- **Density / perf budget:** entities-per-chunk and decor-per-chunk under budget →
  `perf_budget`.
- **Determinism:** compile twice, diff chunk bytes → `nondeterminism` (should never fire).

The existing `tools/validate.gd` Phase 6 already encodes many of these as assertions;
the new validators generalise them to *any* WorldSpec and emit JSON.

---

## 6. AI critic responsibilities

Critics consume the metrics + images and return **arrays of structured issues** (never prose):

```json
{
  "region": "coastal_forest", "severity": "high",
  "problem": "The primary route cannot be visually distinguished from decorative clearings.",
  "suggested_action": "Increase road width, reduce vegetation near the route, add a landmark at the northern turn.",
  "affected_passes": ["road_generation", "vegetation_scattering"],
  "preserve": ["terrain", "village", "lighthouse"]
}
```

| Critic | Reads | Looks for |
|--------|-------|-----------|
| World-design | region map, motif metadata | identity, contrast, "one unusual trait" per region |
| Navigation & spatial-memory | road map, sightlines, entrances, travel times | legible routes, recognisable entrances, landmark visibility |
| Gameplay-distribution | service map, resource-density map | clustered/memorable service relationships, no uniform spread |
| Visual-identity | overview + ground screenshots, biome map | distinct silhouette/material/colour per region |
| Technical validator | validator JSON | reachability, overlaps, determinism |
| Performance | density stats, perf budget | entity/decor/draw budgets |

The `severity`, `affected_passes`, and `preserve` fields drive **selective
regeneration** directly: the Director re-runs only `affected_passes` for `region`
while locking everything in `preserve`.

---

## 7. Selective-regeneration strategy

Every generated element already carries enough metadata to localise a rebuild, and we
extend it with **provenance**:

```jsonc
// added to each POI/site/decor record
"_prov": { "region": "oakholt", "pass": "poi_placement", "seed": 7, "rule": "anchor:molehollow", "locked": false }
```

Regeneration is expressed as `(scope, passes, preserve)`:

| Command | scope | passes rerun | preserved |
|---------|-------|--------------|-----------|
| Compile world | all | 1–15 | locked anchors |
| Compile region | one region's chunks | 2–15 | other regions (snapshots) |
| Regen vegetation in region | region chunks | 10–11 | 1–9, 12–15 |
| Rebuild settlement, keep terrain | settlement chunk | 5–6 | 3–4 (terrain reused) |
| Recalc roads, keep landmarks | global | 7 | 5 (landmarks locked) |
| Validate only | all | 0 | everything |

Mechanism: bump a **per-region seed salt** (or `GENERATOR_VERSION`) for the affected
passes only, clear those chunks from the cache, and regenerate. Locked elements are
written to `chunkSnapshots` so no pass can move them. Because passes are pure functions
of `(seed, salt, coords, spec)`, rerunning one pass cannot perturb another.

---

## 8. Command-line interface design

Primary interface is the CLI (AI-operable). Implemented by `tools/worldc.gd`
(headless) + `tools/world_shoot.gd` (windowed, for PNGs):

```powershell
# Compile + validate a region, emit metrics JSON and ASCII maps
godot --headless --path . res://tools/worldc.tscn -- --spec=medieval --region=eastvale --validate --report=user://reports/

# Validate the whole world without regenerating
godot --headless --path . res://tools/worldc.tscn -- --spec=medieval --validate

# Explain why an element exists
godot --headless --path . res://tools/worldc.tscn -- --spec=medieval --explain=anchor:kingsreach

# Selective regen (vegetation only, one region)
godot --headless --path . res://tools/worldc.tscn -- --spec=medieval --regen=vegetation --region=oakholt

# Render evaluation screenshots from predefined camera positions (needs a window)
godot --path . res://tools/world_shoot.tscn -- --spec=medieval --shots=overview,ground --out=user://shots/
```

Every subcommand prints a machine-readable trailer: `=== WORLDC RESULT ===` followed by
one JSON object (issues, metrics, artifact paths) so an AI agent can parse it.

---

## 9. Minimal vertical slice (this change set)

Implemented here (see §12 reuse table). The slice proves the loop end-to-end:

- `data/world/worldspec/medieval.json` — one authored realm.
- Authored layer `world_spec.gd` consulted by zone/biome/anchor/poi passes.
- `worldc.gd` CLI: `--validate`, `--explain`, `--ascii`, `--metrics`.
- `world_shoot.gd`: overview + ground PNG capture.
- Structured validator issues + region report.
- Selective regen by region/pass (`--regen`).

The first authored region (Eastvale) satisfies the brief's slice checklist: a
settlement (spawn camp + Kingsreach capital), a bank, a skilling area (Oakholt woods),
a dominant landmark (Grimwarden Ruins), two connected routes, two contrasting biomes
(plains vs forest/deepwood), procedural vegetation/decals, valid navigation, and
automated screenshots + validation.

---

## 10. Phased implementation plan

1. **Phase A (this PR): authored layer + slice.** WorldSpec runtime, override hooks,
   medieval spec, CLI validate/explain, screenshots, structured issues. *Done.*
2. **Phase B: provenance + selective regen.** `_prov` on every record; `--regen` by
   pass with locking; per-region seed salts.
3. **Phase C: relationship solver.** Turn `visible_from` / `travel_time` from
   *validated* into *satisfied* (placement search honouring constraints).
4. **Phase D: critic harness.** Wire metrics+images to AI critics; round-trip issues →
   spec edits → targeted recompile in CI.
5. **Phase E: editor plugin (optional).** Read-only WorldSpec visualiser, constraint
   overlays, lock toggles, regen buttons — *supporting* the AI workflow, not replacing it.
6. **Phase F: per-region palettes + real assets.** Region-scoped tile palettes and
   optional `.tscn` props with `AssetMeta` resources.

---

## 11. Risks and trade-offs

- **Headless screenshots:** `--headless` cannot render. Mitigation: `world_shoot.gd`
  runs a real (small/hidden) window and captures the viewport; CI must allow a GPU/SW
  rasteriser. ASCII + metrics remain fully headless for fast loops.
- **Hard biome seams:** forcing a biome per chunk creates crisp region borders.
  Trade-off: great for memorability, but can look blocky. Phase F adds boundary noise.
- **Boss naming:** combat entities display the real bestiary name. To get a literal
  "Giant Mole" we extend `enemies.json` (safe — import is manual). Flavour beyond the
  bestiary needs data, not code.
- **Zone granularity vs. announcements:** region overrides make zone names as fine as
  authored discs, so names pop precisely on entry — at the cost of small overlap seams
  (resolved by nearest-center).
- **Snapshot staleness:** authored edits must bump `GENERATOR_VERSION` (or a per-region
  salt) or explored chunks keep old layouts. Handled by the regen strategy.
- **Determinism coupling:** content (bestiary/gather nodes) lives in `DataRegistry`;
  authored references must stay valid — validated by the content schema check.

---

## 12. Existing systems: reuse / modify / replace

| System | Verdict | Notes |
|--------|---------|-------|
| `WG` hashing, chunk model, seed chain | **Reuse** | Already the deterministic backbone. |
| `WorldRegistry` data loading | **Modify (additive)** | Also load `reg.spec` (WorldSpec). |
| `BiomeClassifier` | **Modify (additive)** | Region biome override; procedural fallback. |
| `ZoneMap` | **Modify (additive)** | Authored region name/req/biome override. |
| `AnchorPlanner` | **Modify (additive)** | Authored fixed anchors + authored routes. |
| `PoiPlacement` | **Modify (additive)** | Authored anchor POIs + pinned boss names. |
| `SkillSiteSpawner`, `MonsterSpawner`, `CaveGenerator` | **Reuse** | Driven by region biome/req — no change. |
| `ChunkRenderer`, `WorldEntitySpawner`, `PathFinder` | **Reuse** | Presentation/nav consume chunk data unchanged. |
| `tools/validate.gd`, `world_debug.gd` | **Reuse + extend** | New `worldc.gd` wraps them for AI ops. |
| Viewport screenshot capture | **New** | `world_shoot.gd`. |
| Visual map editor | **Replace with CLI** | Optional read-only plugin later (Phase E). |
| `data/world/*.json` | **Reuse** | Extend with `worldspec/` + `asset_registry.json`. |
```

