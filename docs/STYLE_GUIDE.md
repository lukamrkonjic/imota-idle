# Imota — Code Style Guide

Conventions for keeping the codebase modular, typed, and data-driven as it grows.
These are the rules the refactor in `docs/REFACTOR_ROADMAP.md` moves the code toward;
follow them for all new code so we don't re-accrue the debt.

## 1. Static typing, always

GDScript is statically typed here. Annotate every variable, parameter, and return.

```gdscript
# Good
func damage_for(level: int, weapon: ItemDef) -> int:
    var base: float = weapon.damage
    ...

# Bad — untyped, infers Variant, no editor checks
func damage_for(level, weapon):
    var base = weapon.damage
```

Enable "untyped declaration" / "unsafe" warnings in the editor and keep them at zero.

## 2. Typed structures over string-key dictionaries

Dictionaries with magic string keys (`d.get("type")`, `stack["qty"]`) are the #1 source
of silent bugs. At any boundary that crosses files or gets saved, use a typed shape:

- A `class_name` / inner class with typed fields, **or**
- A small `RefCounted` data object with a `from_dict()` / `to_dict()` pair at the
  serialization edge (JSON has no typed objects, so normalize there — see the
  serialization invariant in `TECH_DEBT.md`).

```gdscript
# Good
class ItemStack:
    var id: String
    var qty: int

# Bad — typo-prone, no autocomplete, no validation
var stack := {"id": "item.logs", "qty": 4}   # was it "qty" or "count"?
```

Raw dicts are fine for *local*, short-lived, single-file data. They are not fine for
inventory entries, entity `action` payloads, save blobs, or content definitions.

## 3. Content and tuning live in `data/`, not in code

No new hardcoded content maps or balance constants in `.gd` files. If a designer might
ever want to tweak it, it belongs in `data/*.json`:

- Skill verbs, station labels, biome lists/densities → data.
- Combat coefficients, damage variance, crit, AI speeds/leash → `data/combat_*.json`.
- World-gen noise seeds/thresholds, dressing layouts → `data/world/*.json`.

Load once at startup (DataRegistry / WorldRegistry pattern) into typed structs.

## 4. Communicate through EventBus; don't reach across layers

UI and world subsystems talk via `EventBus` signals. **No new `world.call("...")` or
`hud.call("...")`** — emit an intent signal and let the owner react.

```gdscript
# Good
EventBus.bank_requested.emit()

# Bad — UI hardcodes the world's method surface
world.call("auto_bank")
```

Layer rule: UI never mutates sim state directly; it goes through autoload APIs
(GameState/TickSim/…) or EventBus. Sim layer never imports UI.

## 5. File and function size budgets

- **Soft cap ~600 lines per file.** Past that, split by responsibility. (The current
  god-objects — `world_render_3d.gd`, `osrs_hud.gd`, `prop_meshes.gd` — are the debt we
  are paying down, not a precedent.)
- **Functions: one job.** If you need section comments inside a function, those sections
  are probably separate functions.
- One `class_name` per file. Extract inner UI/component classes into their own files.

## 6. Magic numbers get a name and a reason

Every non-obvious literal becomes a named `const` with a comment explaining *why that
value* (units, what it was tuned against), not just *what* it is.

```gdscript
const CAM_SIZE_BASE := 19.5   # ortho half-height at 1.0 zoom; tuned for 16:9 @ 640x360 internal
```

## 7. Naming

- `snake_case` for vars/functions, `PascalCase` for classes/`class_name`,
  `SCREAMING_SNAKE` for consts.
- `_` prefix for private members and methods; be consistent (no public `inv_grid`
  next to private `_side_tabs`).
- Boolean names read as predicates: `is_active`, `has_target`, `can_equip`.

## 8. Determinism & saves

- World generation must stay deterministic from `(seed, layer, cx, cy)`. Don't introduce
  `randf()` without a seeded `RandomNumberGenerator`.
- Anything persisted round-trips through JSON: normalize `Vector2i`/`Color`/etc. at the
  `world_store.gd` serialize boundary, and add a `validate.gd` round-trip check.
- Content keys in saves are **stable ids** (`item.logs`), never display names.

## 9. Tests

- Keep `tools/validate.tscn` green on every change (`godot --headless --path .
  res://tools/validate.tscn` → "ALL TESTS PASSED").
- New systems get a focused phase/test. Prefer testing the simulation layer directly
  (no UI scene) so tests stay fast and decoupled.

## 10. Comments

- Comment the *why*, not the *what*. Document invariants, units, and non-obvious
  ordering. Delete commented-out code (git remembers it).
