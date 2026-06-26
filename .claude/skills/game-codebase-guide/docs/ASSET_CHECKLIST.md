# Asset checklist (pointer)

The full, maintained asset checklist lives at the repo root: **[`docs/ASSET_CHECKLIST.md`](../../../../docs/ASSET_CHECKLIST.md)**
(relative to this wiki: `<repo>/docs/ASSET_CHECKLIST.md`).

It is the **single source of truth** for required and existing 3D models, GLB assets, item/skill/UI
icons, animations, VFX, materials/textures, and audio — kept there to avoid a duplicate that drifts.

## What you must know before touching any asset
- **Imota is a procedural-art game.** Almost all 3D models and item icons are generated in code, not
  loaded from files:
  - Props/buildings/decor → `scripts/render/prop_meshes.gd`
  - Player/enemy bodies, worn gear, held weapons/tools → `scripts/render/mover_meshes.gd` + `equip_loadout.gd`
  - Item icons → `scripts/ui/item_icon.gd`
  - Animations → `scripts/render/mover_rig.gd` (code poses, not sprite sheets)
  - VFX → `scripts/render/world_fx_3d.gd`, `fishing_decor_3d.gd`
- The only file-based art: **22 skill-icon PNGs** (`assets/skill_icons/`), **one GLB**
  (`models/smithy.glb`), worldgen mask PNGs (`data/world/...`), and dev baker output
  (`generated/props/*.png`, not runtime).
- **No audio ships** — `autoload/audio.gd` is fully wired but `data/audio.json` paths are empty.
  Intended folder: `assets/audio/{music,sfx}/`.

## Rule for agents
Before adding, changing, renaming, or generating ANY model, sprite, icon, UI art, animation,
material, texture, or VFX: **read `docs/ASSET_CHECKLIST.md` first**, reuse what exists, and **update
it** (tick `[x]` with the path) once the asset is added or verified. For file-based 3D, follow
`docs/GLB_IMPORT_GUIDE.md` (keep roofs/leaves/doors/ore-veins/tool-heads as separate meshes). See
also `ANIMATION_AND_SPRITES.md` (how the render layer works) and
`INVENTORY_ITEMS_AND_RESOURCES.md` (item icon system).
