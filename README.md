# Imota

OSRS-inspired semi-idle incremental RPG in Godot 4, with systems and numbers
recreated from the Bloobs Adventure Idle data export.

## Run

```powershell
# Play
C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe --path C:\Dev\bloobs-godot

# Re-import game data from the export (writes res://data/*.json)
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\Dev\bloobs-godot --script res://tools/import_bloobs_data.gd

# Headless test suite (49 checks across data, gathering, combat, crafting, save, UI)
C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\Dev\bloobs-godot res://tools/validate.tscn
```

## Architecture

One simulation layer, dumb UI. Autoload singletons:

| Autoload | Role |
|----------|------|
| `EventBus` | Signals (XP, loot, combat log, activity) — the UI only listens |
| `DataRegistry` | Loads `res://data/*.json`; indexes 1,803 items, 118 enemies, 775 recipes, 167 gather nodes, XP table to level 1000 |
| `GameState` | Skill XP/levels, inventory (24 slots), bank, equipment, gold, HP |
| `TickSim` | Gathering loop (deltaTime timer; tool power damages node, award per 100) |
| `CombatSim` | Continuous combat (3s player attacks, enemy cooldowns from bestiary, drops, respawn) |
| `RecipeSim` | Production crafting (inputs → timer → output + XP, auto-repeat) |
| `SaveManager` | `user://save.json`, 30s autosave, offline progress (12h cap) |

`scenes/world.tscn` + `scripts/world/world.gd` + `scripts/ui/osrs_hud.gd` are the
playable 2D front-end in the **Aldenfall pixel-art style** (ported from
`C:\Dev\aldenfall\src\world\*.ts`): dithered shader terrain
(`shaders/terrain_ground.gdshader`), procedural sprites
(`scripts/world/iso_sprites.gd`, `tree_art.gd`, `pixel_draw.gd`,
`pixel_palette.gd`), tent-camp town, paper-doll player, OSRS-style HUD.
`scenes/main.tscn` + `scripts/ui/main_ui.gd` keep the Melvor-style screen for
comparison and headless UI tests.

**Start with [docs/DESIGN.md](docs/DESIGN.md)** — the game's design pillars and an
index to every decision doc: the [world vision](docs/WORLD_DESIGN.md) (tile-built,
living non-circular geography, seamless expansion), [world generation](docs/WORLDGEN_GUIDE.md),
the [isometric pixel-art conventions](docs/ART_GUIDE.md), and the [global shadow
sun](docs/SHADOWS.md). Formula provenance and the few unrecoverable values are
documented in [docs/DATA_GAPS.md](docs/DATA_GAPS.md).

## Status

- Phases 0–3 complete (data import, gathering, combat, crafting, full UI, save/load).
- Phase 4 mostly complete: all gather nodes / enemies / production recipes wired,
  tool shop, food eating, offline progress. Remaining: challenges, pets, crops,
  thieving, tracking panels.
- Phase 5 complete: 2D overworld in the Aldenfall art style with click-to-walk,
  sectored entity placement (camp plaza, gather sectors, enemies east, lake in
  the fishing sector), and OSRS-style HUD. Same sims as the Melvor UI —
  `scenes/main.tscn` remains for headless UI smoke tests.

Run the game: "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" --path C:\Dev\imota-idle
Run the editor: "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" --path C:\Dev\imota-idle res://tools/world_editor.tscn