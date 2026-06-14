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

## Authoring world art

Before drawing or adding any prop / house / structure / decor, read
`docs/ART_GUIDE.md` — the procedural isometric pixel-art conventions (origin at
the foot, 2:1 `iso_block` solids, upper-right sun, shared palette, shadow
helpers) and the end-to-end steps to register a new placeable. The ruin pillar
(`scripts/world/art/structures/ruin_pillar_art.gd`) is the reference example.
