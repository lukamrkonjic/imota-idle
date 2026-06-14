# Agent instructions (Imota / bloobs-godot)

## After finishing work

When you complete a feature, bug fix, or refactor that touches game code or data:

1. Run the headless test suite and confirm it passes:
   ```powershell
   & "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\bloobs-godot" res://tools/validate.tscn
   ```
2. Fix any failing tests before marking the task done.
3. Launch the game for a quick smoke test:
   ```powershell
   & "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" --path "C:\Dev\bloobs-godot"
   ```

Skip verify/play only for documentation-only edits or when the user asks not to.

## Project paths

- Project root: `C:\Dev\bloobs-godot`
- Godot editor: `C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe`
- Godot headless: `C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe`
- Tests: `res://tools/validate.tscn`

See `README.md` for architecture and data import commands.

## Design & decisions — read before building

`docs/DESIGN.md` is the entry point: the game's pillars (OSRS-style skills on the
Bloobs content lineage, a stronger idle layer, one-sim/dumb-UI, a living
expandable world) and an index to every decision doc. Before working in an area,
read its doc so new work reinforces the existing decisions:

- **World shape / geography / expansion** → `docs/WORLD_DESIGN.md` (tile-built,
  living non-circular continent, radial progression, seamless content growth).
- **Drawing/adding props, houses, structures, decor** → `docs/ART_GUIDE.md`
  (origin at the foot, 2:1 `iso_block` solids, upper-right sun, shared palette,
  shadow helpers, registration chain). The ruin pillar
  (`scripts/world/art/structures/ruin_pillar_art.gd`) is the reference example.
- **World generation internals** → `docs/WORLDGEN_GUIDE.md`; **shadows** →
  `docs/SHADOWS.md`; **content/data** → `docs/CONTENT_GUIDE.md`.

When you make a load-bearing decision in one of these areas, record it in the
relevant doc (decision → why → consequence), the way the existing entries are.
