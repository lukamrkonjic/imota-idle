# Imota — Placeholders & Tune-Later TODO

> Running list of everything introduced as a **placeholder, stub, or deferred
> hook** during the Imota redesign (Phases 0–6). The systems are in place; the
> *content and numbers* are temporary and meant to be replaced/tuned later. Add
> to this as we go. (Architecture debt lives in `docs/TECH_DEBT.md`.)

## Content — replace placeholder names/data

- **Rename map** (`data/rename_map.json`) — placeholder original names set the tone,
  not the final list: ore tiers (Azurite/Hemalite/Zephite/…), Elderlog, Lumabird,
  and the boss renames (Solheim, Taurok, Vorlach, …). Refine for quality/consistency.
- **Un-renamed Bloobs flavor names** — distinctive forage/herb/mushroom names
  (Sunsnap, Thornfoot, Sporecap, Starshroom, Glowstalk, Emberplume, …) were left
  as-is. Decide which still need renaming for IP and add tokens.
- **"Gold" enemy drop** — a dangling currency-as-item drop reference; should resolve
  to **Coins** once the economy/drop system handles currency drops (Phase 7).
- **~200 dangling content refs** — export-gap warnings in `validate_content.gd`
  (recipes/drops referencing items that weren't exported). Triage later.

## Numbers — tune knobs

- **XP slowdown** `S = 1.25` (`tools/gen_xp_table.gd` → `data/xp_table.json`).
- **Per-hit combat XP** `XP_PER_DAMAGE = 4.0`, `HP_XP_PER_DAMAGE = 1.33`
  (`scripts/combat/combat_styles.gd`).
- **Weapon attack speed** — NO item has an `attackSpeed` field yet, so everything
  uses the 3 s default. Author per-weapon speeds (daggers fast, mauls slow).
- **Drop tiers / rare table** — `data/rare_drop_table.json` is empty (`chance: 0`);
  tertiary (pets/clues) hooks in `DropRoller` are unused. Populate later.
- **High Alchemy** — level 55, rate 0.6, 65 XP (`game_state.gd` consts). Placeholder.
- **Prayer bone XP** — `scripts/skills/prayer_lore.gd` per-bone values are guesses.
- **Farming** (`data/farming.json`) — placeholder crops (Cotton/Amberleaf/…), grow
  times, XP, yields; `plot_count = 3`; **`GROW_INTERVAL = 1 s` is test-fast** — slow
  it down (minutes per growth tick) for real play.
- **Run energy** — `RUN_REGEN_PER_SEC = 0.5`, +1%/Agility level. Placeholder.
- **Auto-eat threshold** — default 0.5 (`GameSettings`).

## Systems in place but stubbed / not wired

- **ActivityManager** (single intent + stop-reason coordinator, spec §21) — NOT
  built yet; Tick/Combat/Recipe/Farming sims still coordinate ad-hoc. Build when
  loadout/intent-switching needs it (Phase 7).
- **Modifiers** (timed buff stack for potions / Rested XP / diary perks) — NOT
  built; needed by Phases 7 & 10.
- **Prayer** — burying bones works, but prayers can't be toggled in combat from the
  UI (`active_prayers` is code-only); Protect-Item negation works. Prayer "points"
  on the minimap orb are just the Prayer **level** (no point pool / drain yet).
- **Magic** — the spellbook tab is a static placeholder list; no real spell casting,
  no spellbook combat. Magic style currently uses the generic combat path.
- **Hunter** — not built (no data, no loop). Deferred.
- **Agility** — `run_energy` exists but there's no auto-course activity and it is
  **not yet wired to movement/auto-nav speed** or drained by walking.
- **Combat styles** — only single-skill styles; the melee "controlled" split is a
  reserved placeholder in `CombatStyles`.
- **Slayer** — the minimap/dialog browses & fights monsters by type, but there's no
  task assignment, Slayer points, or Slayer-master NPC in the world.
- **Special attacks / pets / clues / achievement diaries** — hooks only.

## UI / presentation

- **Equipment tab** is still a text list, not the OSRS positioned-silhouette layout.
- **Minimap orbs** (Prayer, Run) show placeholder values; "Slayer" button opens the
  dialog but there's no Slayer-master location to path to.
- **Legacy `scenes/main.tscn` / `scripts/ui/main_ui.gd`** still in the tree (only
  smoke-tested); delete once nothing depends on it.
- Tab-icon glyphs and orb layout were not visually verified on-device — eyeball and
  nudge coordinates/sizes.

## World / map (far from finished — per direction)

- **Fixed per-type spawn zones** for every node & monster are not in place yet
  (Phase 8); auto-"nearest of type" relies on current procedural site spawns.
- No **region gating**, **fast-travel hubs**, or **world-map discovered state** yet.
- **Farming / Prayer / Hunter / Agility have no world stations or locations** — the
  loops run abstractly; place real stations when the map firms up.
- Player world position isn't persisted (respawns at `spawn_position()` each launch).
