# Imota — Remaining Work to Steam (Early Access)

Living plan. Effort: **S** ≈ <½ day · **M** ≈ 1–3 days · **L** ≈ 1–2 weeks. EA-crit = needed
before an Early-Access store build. Foundation hardening (Tiers A–E) is **done** — see
TECH_DEBT.md / SCHEMA.md / the `refactor(A..E)` commits. What's below is everything left.

---

## Track 1 — Finish the foundation (do alongside features, low risk)

These are the deferred remainders of the Tier A–E audit. None block EA, but each makes later
work cheaper and is best done when you're next in that area.

| # | Item | Size | Notes |
|---|------|------|-------|
| F1 | **Finish render decomposition** — extract `MoverRig` (5 pose fns + secondary motion + death), `WorldFx3D` (fire/prayer FX), `FXDirector` + a shared `PixelAnim.pulse()` | M | `TerrainStyle` already out. Line ranges + coupling in TECH_DEBT. **Verify per body type + per FX** (trigger firemaking, a prayer, walk each enemy type) — not a blind cut. |
| F2 | **Typed shapes for Recipe / Enemy / GatherNode** (+ migrate remaining Item dict sites) | M | `ItemDef` set the pattern; combat_sim reads enemy dicts heavily — biggest typo-risk left. |
| F3 | **ActivitySim base + real ActivityManager** | M | Unify the 5 divergent sim loops (tick/recipe/combat/farming/prayer) so they share one lifecycle and each owns its save serialization (kills per-skill save special-casing in game_state). Prereq for clean loadout/intent switching (Stage 5). |
| F4 | **Split `biome_classifier.gd`** into terrain-fields / hydrology / orography | M | Currently one file does classification + rivers + lakes + shore + mountain elevation. Makes "rework the map" tractable. |
| F5 | **`prop_meshes.gd` data-driven equip/rig**, and **`osrs_hud.gd` per-tab split** | L | The other two monoliths (~1.8k each). Quality-of-life; defer until they bite. |

---

## Track 2 — The release path (ordered; Stages 0–4 are the EA must-haves)

### Stage 0 — Make the current game *real* (tuning/bugs; cheap, high-impact) — **EA-crit**
Do first; these are why it "feels unfinished," and they're mostly data.
- **S** Author **weapon `attackSpeed`** — no item has one, so every weapon swings at the 4-tick default (daggers = mauls).
- **S** Populate **`data/rare_drop_table.json`** (currently 0% → no uniques ever drop) + wire the tertiary pet/clue hooks in `DropRoller`.
- **S** Fix **`farming GROW_INTERVAL`** (a 1s test value → real minutes-per-tick) and `plot_count`.
- **M** **Tune placeholder numbers**: the 39 new Tier-A items' values, High-Alch (lvl/rate/xp), prayer bone XP, run-energy. (`docs/IMOTA_PLACEHOLDERS_TODO.md`.)
- *(Done already: player world position is persisted — removed from this list.)*

### Stage 1 — Buildable & shippable shell — **EA-crit**
- **M** **`export_presets.cfg`** — Windows 64 first, then Linux + macOS; verify an exported build runs.
- **S** **Project hygiene** — real app icon (Godot default now), `config/version`, gate the debug HUD/flags (`--crisp`, tile/biome debug, perf log) behind `OS.is_debug_build()`, exclude `tools/` from export.
- **M** **Main menu** (New Game / Continue / Settings / Quit) + Quit-to-Menu; save **backups + a couple of slots** (EA saves are precious).

### Stage 2 — First-run experience (drives your reviews) — **EA-crit**
- **M** **Onboarding / tutorial** — guided first session. #1 cause of bad idle-game reviews is "I don't know what to do."
- **S–M** **Level-up & milestone feedback** — confetti + jingle + unlock dialog (slots into F1's `FXDirector`).

### Stage 3 — Audio (your single biggest content gap, currently 0/10) — **EA-crit**
- **L** Audio manager + bus layout; **music** (route via the existing `biome_changed` signal), ambience, UI/combat/gather SFX, rare-drop sting. The volume slider currently controls nothing.

### Stage 4 — Goals & retention (what makes EA worth playing past hour 1) — **EA-crit**
- **L** **Quests + Quest Points** (idle-friendly, spoiler-safe log).
- **M** **Collection Log + Achievements/Milestones** and **Statistics** (XP/hr, kills, drops).
- **M** **AFK → Rested XP** buff — your idle-session safety/UX mechanic.

### Stage 5 — Economy & world depth (iterate *during* EA)
- **M** **Shops/vendors** (sell-back + High-Alch UI; wire the **"Gold" drop → Coins** here), **loadout presets**, **bank tabs/search/deposit-all** (bank exists in state, no real UI).
- **M** **Fixed spawn zones, region gating, fast-travel hubs, world-map discovered state.**
- **M** **Finish Magic** (spellbook is a static placeholder — no real casting) + confirm Agility energy drives movement.
- **S** **Equipment tab** → OSRS positioned-silhouette layout (still a text list).

### Stage 6 — Steam integration
- **M** **GodotSteam** plugin + app ID + **Steam Cloud saves** (get this in early enough to test on Steam).
- **M** **Achievements** wired to Stage-4 milestones; **Rich Presence** ("Woodcutting Lvl 42").

### Stage 7 — Platform & launch polish
- **M** **Gamepad / Steam Input + Steam Deck verification** (keyboard/mouse only today — blocks Deck), min-spec profiling.
- **M** **Window modes** (borderless/resolution/ultrawide), **accessibility** (colourblind, text scale), final balance + QA.
- **M** **Store-page assets** — capsule art, trailer, screenshots. → **Launch EA.**

### Stage 8 — Post-launch (design now, build later)
Achievement Diaries, pets & skill capes, special attacks, optional Hardcore/Ironman.

---

## Suggested sequencing
1. **Stage 0** (days) — makes the game you have genuinely good; pairs naturally with **F2**.
2. **Stage 1 → 2 → 3 → 4** in order — the EA must-haves. Do **F1 (`FXDirector`)** as the front of Stage 2/3 (confetti + rare-drop banner live there). Kick off **Stage 6's GodotSteam + Cloud** in parallel once Stage 1 lands.
3. **Stage 5** + remaining **F3/F4** — iterate during EA.
4. **Stage 7** → **Launch**. **Stage 8** post-launch.

**Critical path to a *good* EA:** Stages 0–4 + Stage 1's shell + Steam plumbing. Everything
else is legitimately EA-iteration.
