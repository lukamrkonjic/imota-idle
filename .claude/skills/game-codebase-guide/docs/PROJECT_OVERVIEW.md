# Project overview

## What it is
**Imota** — an OSRS-inspired, semi-idle incremental RPG. Data/formulas were recreated from a
"Bloobs Adventure Idle" export (see `project.godot` header + `docs/` design notes). You explore a
procedurally-generated + partly hand-authored world, train 22 skills (gathering, combat, production,
utility), fight monsters, and manage inventory/bank/equipment. Rendered as a 3D pixel-art world
through a low-res viewport with a cozy "A Short Hike"-style look.

## Engine & config (`project.godot`)
- Godot **4.6** (`config/features=PackedStringArray("4.6")`), `forward_plus` renderer.
- Main scene: `run/main_scene="res://scenes/world.tscn"`.
- 15 autoloads (see `AUTOLOADS_AND_GLOBALS.md`).
- Shader globals: `wind_mul`, `dawn_mist`.
- GDScript warnings are not errors (`[debug] gdscript/warnings/treat_warnings_as_errors=false`).
- No `[input]` InputMap section — input is handled in code (see `INPUT_ACTIONS.md`).

## Top-level directories
- `autoload/` — 15 singleton scripts (the backbone).
- `scripts/` — gameplay/render/UI code:
  - `world/` (89 .gd) — the world scene, controllers, entities, sims/NPCs, art helpers.
  - `worldgen/` (27) — chunk generation, baked world, skill-site spawner, paths.
  - `render/` (22, + `render/terrain/`) — the 3D renderer subsystems.
  - `ui/` (21, + `ui/tabs/`, `ui/widgets/`) — HUD, tabs, widgets, popups.
  - `content/` (8) — typed wrappers (`ItemDef`, `GatherNodeDef`, `RecipeDef`, `EnemyDef`,
    `ContentId`, `IdRegistry`, `SkillRemap`) + id/rename helpers.
  - `combat/` (5) — combat math (`CombatCalc`, `DropRoller`, styles, constants).
  - `state/` (3) — GameState sub-states (`prayer_state`, `run_energy_state`, `slayer_state`).
  - `skills/`, `util/`.
- `data/` — all content JSON (items, enemies, recipes, gather_nodes, skills, prayers, farming,
  tools, npcs, xp_table, id_registry, rename_map, content_aliases) + `data/world/*` (biomes, pois,
  skill_sites, monsters, stamps, tree_species, …) + `data/sim_players/*` (names, looks, dialogue) +
  `data/world/baked/<id>.world` (authored finite world).
- `shaders/` — `toon_ground`, `toon_water`, `toon_world`, `palette_snap`, `outline`, `dawn_mist`, …
- `models/` — `.glb` assets (currently `smithy.glb`). See repo-root `docs/GLB_IMPORT_GUIDE.md`.
- `tools/` — ~30 headless/windowed dev tools + the test suite (`validate.tscn`) + the world editor
  (`world_editor.tscn`).
- `docs/` — human design docs (background; may lag code).
- `assets/` — `skill_icons/` PNGs.

## How to run
- Play: open the project in Godot 4.6 and run, or
  `<godot> --path . res://scenes/world.tscn` (a window opens; rendering needs a real GPU/display).
- The repo `AGENTS.md` documents a Windows Godot path; on macOS this session used
  `/Applications/Godot.app/Contents/MacOS/Godot`.

## How to test (the gate)
- `<godot> --headless --path . res://tools/validate.tscn` → prints per-phase `ok` lines and ends with
  `ALL TESTS PASSED`. This is THE check to run after any gameplay edit (`tools/validate.gd`).
- 3D render smoke test (headless wiring only, no visible output):
  `<godot> --headless --path . res://tools/validate.tscn -- --force3d`.
- After adding/importing a `.glb` or new `class_name`, run `<godot> --headless --path . --import`
  once so Godot regenerates the import/class cache (a new `class_name` is otherwise "not declared").
- Visual evaluation tools (windowed, save PNGs): `tools/world_shoot.tscn`, `tools/fish_shot.tscn`,
  `tools/smithy_preview.tscn`, etc.

## Mental model
Gameplay state + logic = the **2D layer** (`GameState`, sims, `scripts/world/`). The **3D layer**
(`scripts/render/`) is a cosmetic mirror that reads that state and draws it. Content = **data**.
The HUD reflects state via **EventBus** signals. Saves are **forward-compatible by contract**.
