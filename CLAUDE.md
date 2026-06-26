# CLAUDE.md — Imota

Imota is an OSRS-inspired semi-idle RPG in **Godot 4.6** (GDScript). This file tells every Claude
session how to work in this repo safely.

## Required: use the codebase guide skill before gameplay work

This project has a **required codebase guide skill** at
`.claude/skills/game-codebase-guide/SKILL.md`, with an AI-facing wiki at
`.claude/skills/game-codebase-guide/docs/`.

**Before adding, changing, or debugging ANY gameplay functionality**, read
`.claude/skills/game-codebase-guide/SKILL.md` and follow its required workflow. Treat
`.claude/skills/game-codebase-guide/docs/` as the codebase wiki (start at `INDEX.md` →
`FEATURE_MAP.md`). Gameplay = items, tools, inventory, skills, gathering/mining/fishing/foraging,
combat, stations/recipes, prayer, farming, movement, camera, world/chunks, NPCs/sims, UI/HUD,
save/load, animation, the world editor, and 3D rendering.

You may skip the skill only for trivial, non-gameplay edits (a comment/typo, this file).

## The rules (full detail in the skill's `SAFE_EDITING_RULES.md`)

1. **Follow the existing architecture; reuse existing systems.** There is exactly one of each core
   system (`GameState`, `EventBus`, `DataRegistry`, `TickSim`/`CombatSim`/`RecipeSim`, `WorldGen`, the
   HUD `osrs_hud.gd`, the 3D coordinator `world_render_3d.gd`, the controllers on `world.gd`). **Do
   not create duplicate/parallel systems.** Find the owner in `docs/FILE_OWNERSHIP_MAP.md`.
2. **Content is data.** Add items/nodes/enemies/recipes/prayers/crops via `data/*.json`, not new code.
   Items keep a frozen `name` + stable `id`; rename only `displayName` (via `data/rename_map.json`).
   Never change an `id`/`name`/skill key/save key without a migration.
3. **Don't rename load-bearing names** (scene nodes in `world.tscn`/`world.gd`, autoloads, `class_name`s,
   `EventBus` signals, save keys) unless you update every reference (and add a save migration).
4. **Saves must never break.** New saved field → `GameState.to_save_dict` + defaulted `from_save_dict`
   (+ migration only if needed) + a `tools/validate.gd` round-trip. Honor `suppress` flags.
5. **UI updates via `EventBus` signals**, not polling. **Gameplay logic lives in the 2D layer**;
   `scripts/render/` is cosmetic.
6. **Update the wiki** whenever you change architecture, file ownership, signals, save fields, or
   feature behavior (`FEATURE_MAP.md`, `FILE_OWNERSHIP_MAP.md`, the system doc, `OPEN_QUESTIONS.md`).
7. **Assets:** Before adding, changing, renaming, or generating any model, sprite, icon, UI art,
   animation, material, texture, or VFX asset, check **`docs/ASSET_CHECKLIST.md`** and update it after
   the asset is added or verified (tick `[x]` with the exact path). Note: most art is **procedural**
   (in `scripts/render/` + `scripts/ui/item_icon.gd`), so reuse/extend the existing generator rather
   than adding duplicate files; for file-based 3D follow `docs/GLB_IMPORT_GUIDE.md`.

## Validate every change

Run the headless test suite and make sure it passes:
```
<godot> --headless --path . res://tools/validate.tscn      # must print "ALL TESTS PASSED"
```
For 3D/visual edits also smoke-test wiring with `-- --force3d`, and after adding a new `class_name`
or `.glb` run `<godot> --headless --path . --import` once. If you cannot run a check, say so in your
report and list what you would have run.

## Other docs
- `AGENTS.md` — environment/build notes (Godot path, project root, tests). Still valid; this file
  doesn't replace it.
- `docs/` (repo root) — human design docs (`ARCHITECTURE.md`, `COMBAT.md`, `SAVE_FORMAT.md`,
  `WORLDGEN_GUIDE.md`, `GLB_IMPORT_GUIDE.md`, `SHADOWS.md`, `ART_GUIDE.md`). Useful background; may lag
  the code. The `.claude/.../docs/` wiki is the AI-facing source of truth — keep it current.

## Git
- Commit/push only when asked. If on `main`, branch first. End commit messages with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
