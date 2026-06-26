# Agent instructions (Imota)

## ⚠️ Save-game safety — NON-NEGOTIABLE (Steam Early Access)

Imota is shipping in Steam Early Access. **Real players have real save files.** Any
change to content (items, enemies, nodes, recipes, equipment, drops, skills) MUST NOT
corrupt or silently delete an existing player's save. Treat a broken save as a release
blocker, not a bug.

**The one load-bearing rule: stable `id` is permanent; everything else is free to change.**

Saves store only **stable ids + quantities** (`{"id": "item.x", "qty": n}`, bank keyed by
id, equipment slot→id). Stats are always re-read from `data/*.json` at load — they are
never baked into the save. Therefore:

| Action | Rule |
|---|---|
| **Rename** (display name) | ✅ Change `displayName` only. **Never** change the `id`. |
| **Rebalance** (stats, value, drops, recipe I/O, XP, yields) | ✅ Always safe — saves don't store these. |
| **Add** new content | ✅ Safe. Give it an explicit, final `id` from day one. |
| **Change an `id`** | ⚠️ Only with BOTH: an `old_id → new_id` entry in `data/content_aliases.json`, AND a bump + rewrite step in `autoload/save_migration.gd`. Never rename an id bare. |
| **Remove** content | ⚠️ Never delete an id players may hold. Alias it to a replacement, or convert it (e.g. to Coins) in a `save_migration.gd` step. A bare removal silently drops the item from inventories/banks. |

**Hard requirements for any content PR:**
1. Every item/enemy/node/recipe carries an explicit, **opaque stable `id`** (a frozen
   number behind the type prefix, e.g. `item.1001` — OSRS-style numeric ids, NOT a
   name-slug). Ids are assigned **once via a persistent id registry**, **never** derived
   from the display name, **never** edited once shipped, and **never reused** after a
   content removal. The importer must preserve existing id assignments and only mint new
   ids for genuinely new content. Display names and name-based authoring cross-references
   (recipes/drops/nodes referencing items by name) stay on top and resolve to ids at load.
2. Any id change or removal ships with a `content_aliases.json` mapping **and** a
   `save_migration.gd` migration (bump `CURRENT_SCHEMA`), with the older→newer path tested.
3. Loading a save from the previous released version must succeed with **zero** "unknown
   item / dropped from inventory" warnings. Add/extend a save-migration check in
   `res://tools/validate.tscn` to prove it.
4. If you are even unsure whether a change is save-safe, STOP and flag it — do not guess.

See `docs/IMOTA_REDESIGN_SPEC.md` (§ Content & save stability) for the full rationale.

## After finishing work

When you complete a feature, bug fix, or refactor that touches game code or data:

1. Run the headless test suite and confirm it passes:
   ```powershell
   & "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\imota-idle" res://tools/validate.tscn
   ```
2. Fix any failing tests before marking the task done.
3. Launch the game for a quick smoke test:
   ```powershell
   & "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" --path "C:\Dev\imota-idle"
   ```

Skip verify/play only for documentation-only edits or when the user asks not to.

## Project paths

- Project root: `C:\Dev\imota-idle`
- Godot editor: `C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe`
- Godot headless: `C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe`
- Tests: `res://tools/validate.tscn`

See `README.md` for architecture and data import commands.

## Windows: run the game (and the cold-cache gotcha)

`.godot/` (the class cache) is gitignored, so a **fresh clone has no cache**. Running the
game before the cache exists fails to resolve global `class_name`s, which nulls out the
autoloads (you'll see `GameState`-is-Nil / `prayer_sim.gd` errors spamming every frame).
macOS rebuilds it via `dev.sh`; on Windows use the committed batch scripts:

- **`run.bat`** — launches the game. If `.godot/` is missing it rebuilds the cache once
  first, then plays. This is the normal way to run on Windows.
- **`import.bat`** — just rebuilds the cache (`--import`). Re-run it after adding a new
  `class_name` or a new `.glb`.

Both default to the engine paths above; override with the `GODOT` / `GODOT_CONSOLE` env
vars. (The autoloads are also hardened with path-based `preload()`s instead of bare
`class_name` refs, so a cold cache degrades more gracefully — but the cache should still
be built.)

## World build tools

The fixed overworld is **authored, then compiled** — it never generates at runtime.
Two tools own that pipeline (both run via the editor binary with `--path .`):

- **World editor** — `res://tools/world_editor.tscn` (the production designer for the
  finite world). Top-down 1px/tile view of the baked world with hand-authoring brushes:
  biome, terrain, structures, erase, set-spawn. Edits are undoable; "Generate World"
  rebuilds the continent via the shared `FiniteWorldGenerator`; Save writes
  `data/world/baked/<id>.world` (+ map + spawn). A "🧊 3D View" button docks the real
  game renderer for live in-game preview.
  ```powershell
  & "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" --path "C:\Dev\imota-idle" res://tools/world_editor.tscn
  ```
- **World baker** — `res://tools/world_bake.tscn` (offline world compiler). Regenerates
  the finite world from the active worldspec and rewrites
  `res://data/world/baked/<id>.world` + `<id>_map.png`. Headless is fine (tiles are
  CPU-only). **Re-run this after any worldspec edit** — the overworld is fixed/baked.
  ```powershell
  & "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path "C:\Dev\imota-idle" res://tools/world_bake.tscn
  ```

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
