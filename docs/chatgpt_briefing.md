# Imota — Adapt-a-World Briefing for ChatGPT (EA beginner region)

Paste this whole file into ChatGPT **together with a world map image** (any existing
fantasy/continent map). Your job is NOT to invent a world from scratch — it is to **take
that existing map and adapt it into the first playable beginner region of Imota**:
re-assign its land to our biomes, populate it with our skills/enemies/POIs, and **redraw
it as a clean, traceable top-down map** I can import.

If no map is attached, first invent a simple organic landmass (irregular coastline, a few
lakes and a river), then do everything below to it.

---

## 1. What Imota is (context)

A semi-idle OSRS-inspired incremental RPG. The world is a **finite, hand-authored
continent** explored on foot, rendered in-game as isometric pixel art. We are shipping
ONE complete **low-level beginner region** for Early Access; the rest of the continent
comes later and must be sealed off naturally (see §7).

## 2. Hard rules (do not violate)

- **Beginner region only.** Low level **~1–20**. Calm, welcoming, temperate.
- **Stay inside our vocabulary.** Use only the biome IDs, skills, enemies and POI types
  below. Do NOT invent biomes/skills. You MAY invent named places, NPCs/traders, and
  quests built from that vocabulary.
- **You do not need all biomes** — pick **3–6** from the beginner set that suit a starter
  area, and assign the existing map's regions to them sensibly.
- **Irregular coastline**, and **clear water**: at least one lake and one river in
  addition to the coast (Fishing must be trainable).

## 3. Beginner biomes — pick 3–6 of these (ignore the rest)

`id | name | primary gather skill`

```
plains          | Grassland       | foraging
forest          | Forest          | woodcutting
dense_forest    | Deepwood        | woodcutting
boreal_forest   | Boreal Forest   | woodcutting
wheatfield      | Wheatfields     | foraging
flower_meadow   | Flower Meadow   | foraging
grove           | Sunlit Grove    | foraging
heather_moor    | Heather Moor    | foraging
rocky_clearing  | Rocky Clearing  | mining
rocky_hills     | Highlands       | mining
beach           | Coast           | fishing
marsh_pool      | Marsh Pool      | fishing
```
(Imota has 24 more biomes — swamp, jungle, desert, tundra, volcanic, etc. — but those are
higher-level / far from the centre. **Do not use them in this beginner region.**)

## 4. Skills (22 — reference in quests / traders / gather nodes)

Attack, Strength, Defence, Hitpoints, Ranged, Magic, Prayer, Slayer, Woodcutting,
Mining, Fishing, Foraging, Thieving, Hunter, Farming, Cooking, Smithing, Firemaking,
Fletching, Crafting, Alchemy, Agility.

Make sure the chosen biomes let a new player train at least **Woodcutting, Mining,
Fishing and Foraging** early.

## 5. POI types — place a sensible spread

campsite, village, capital_city, cave_entrance, altar, soul_shrine, resource_depot,
fishing_hotspot, obelisk, boss_lair, trap_site, landmark, old_watchtower,
abandoned_farmstead, haunted_ruins, great_ruins, mole_dungeon.

The region needs **one town hub** (a village or small capital_city) with traders, a bank,
and quest NPCs — plus campsites, gather hotspots, **one cave/dungeon entrance**, and a few
landmarks/ruins.

## 6. Enemies — use the level 1–20 band only

`level | name | style | (BOSS)`
```
 1 Chickens (Melee)    2 Cows (Melee)         3 Crabs (Melee)        4 Bats (Range)
 4 Goblins (Melee)     4 Hobgoblins (Melee)   5 Goats (Melee)        6 Pigs (Melee)
 6 Sheeps (Melee)      6 Wolves (Melee)       8 Mole (Melee)         9 Goblin Wolf Riders (Range)
 9 Hobgoblin Brawlers (Melee)  11 Goblin Mage (Mage)  12 Boars (Melee)  12 Gnolls (Melee)
13 Skittering Hands (Melee)  14 Goblin Rangers (Range)  16 Goblin Fighter (Melee)
17 Black Wolves (Melee)  17 Skeletons (Melee)  17 Toxic Hounds (Melee)  20 Sludge Elemental (Mage)
— low bosses —
 5 Matron Hen   7 Skullsmasher   8 Matron Aurochs   9 Matron Hog   9 Matron Ewe
11 Direhowl   16 Grokk the Brawler   18 Gnoll Chief   20 Duskfang
```
Ramp difficulty **outward from the town** (level 1–5 nearest, up to ~20 at the edges).
Place 1–2 low bosses. (Imota has 100 more enemies up to level 300 — they live *beyond*
the mountain barrier and are out of scope here.)

## 7. World expansion barrier — a mountain range with a natural pass

The beginner region is sealed off from the rest of the (unbuilt) continent **not by a
wall**, but by a **large, organically-shaped mountain range** running along the region's
inland border. Through it is **one naturally-shaped passage** (a valley / gorge) that is
currently impassable (blocked by rockfall, fog, or a closed gate) and will open later.
The player can see the mountains and the pass on the horizon but cannot leave yet. Draw
the range as an irregular ridge line — never straight — with the single winding pass clearly
visible.

---

## ✅ WHAT TO PRODUCE

### A. A written region spec (markdown)
1. Region name + one-paragraph fiction.
2. Sub-zones: for each, the **biome id**, a short name, level range, gather skills it
   serves, and which level-1–20 enemies live there.
3. Town hub: name, traders/shops, bank, 1–3 named quest NPCs.
4. POI placements (which POI types, roughly where).
5. 1–2 starter quest outlines (giver → steps → reward).
6. Where the mountain range runs and where the natural pass is.

### B. IMAGE 1 — a clean BLACK-AND-WHITE TRACEABLE map (required)
A flat, **top-down orthographic** map of the region with **no decoration, no text, no
labels, no shading, no gradients**. This is a tracing source, so it must be crisp:
- **Land = solid white. Water = solid black.** Hard, clean edges only (no anti-aliasing
  fuzz, no texture).
- **Lakes and rivers** are black shapes/lines cut into the white land. Rivers should be
  continuous lines of a few pixels wide, connecting to the coast or a lake.
- Coastline irregular and organic.
- Output it large and high-contrast so a coastline tracer can read it directly.

### C. IMAGE 2 — a flat-colour LABELLED biome map (required)
The **same landmass and coastline** as Image 1, but as a planning map:
- Each zone **flat-filled with a distinct solid colour**, **no painterly art / no props /
  no texture** — just clean colour blocks with thin borders.
- A small **text label per zone naming its biome id** (e.g. "forest", "rocky_hills").
- Mark the **town hub**, the **POIs**, the **mountain range** (as a clear ridge band) and
  its **natural pass**, a **compass**, and a **"START HERE"** marker on the town.
- Water stays clearly readable (lakes, rivers, coast) in a single blue.

Keep both images **purely top-down 2D** — no isometric, no perspective, no decorative
illustration. Image 1 is for tracing; Image 2 is the human-readable plan.

---

*(After you send the results back, I'll map every zone / enemy / POI to Imota's real data
IDs, trace Image 1 into the land mask, and build the region from Image 2 + the spec.)*
