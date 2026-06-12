extends RefCounted
## Loads and indexes res://data/world/*.json — the registry pattern behind the
## whole generator. Generator code consumes these tables and never hard-codes
## biome/tile/site/monster/POI lists, so new content is data-only.
##
## Also precomputes, against DataRegistry (the Bloobs export):
##   node_table[skill]  -> Array of {node, level, biomes, cave_layers}
##   monster_table[name]-> {level, boss, biomes, cave_layers, aggressive, passive}

# --- tiles ---
var tiles: Dictionary = {}              # id -> {colors:[Color,Color], walkable, water, hazard}
var tile_order: PackedStringArray = []  # byte id -> tile id
var tile_index: Dictionary = {}         # tile id -> byte id

# --- biomes (sorted by priority desc) ---
var biomes: Array = []                  # parsed biome dicts
var biome_index: Dictionary = {}        # biome id -> index in biomes

# --- skill sites / stations ---
var site_defaults: Dictionary = {}
var skill_rules: Dictionary = {}        # skill -> parsed config (with compiled RegEx)
var stations: Dictionary = {}           # production skill -> [station part ids]
var node_table: Dictionary = {}         # skill -> Array of node placement entries

# --- monsters ---
var monster_cfg: Dictionary = {}
var monster_table: Dictionary = {}      # enemy name -> placement entry
var boss_list: Array = []               # [{name, level, biomes}]

# --- POIs / caves / names ---
var pois: Dictionary = {}               # poi type -> def
var cave_layers: Dictionary = {}        # int layer -> def
var zone_words: Dictionary = {}


func load_all() -> void:
	var biome_doc := _read("biomes.json")
	_parse_tiles(biome_doc.get("tiles", {}))
	_parse_biomes(biome_doc.get("biomes", []))

	var sites_doc := _read("skill_sites.json")
	site_defaults = sites_doc.get("defaults", {"resources": 8, "respawnSec": 25.0})
	stations = sites_doc.get("stations", {})
	_parse_skill_rules(sites_doc.get("skills", {}))
	_build_node_table()

	monster_cfg = _read("monsters.json")
	_compile_monster_rules()
	_build_monster_table()

	pois = _read("pois.json").get("pois", {})
	var cave_doc: Dictionary = _read("cave_layers.json").get("layers", {})
	for k: String in cave_doc:
		cave_layers[int(k)] = cave_doc[k]
	zone_words = _read("zone_names.json")
	zone_words.erase("_doc")


func _read(name: String) -> Dictionary:
	var path := "res://data/world/" + name
	if not FileAccess.file_exists(path):
		push_error("Missing world data file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _hex(h: String) -> Color:
	return Color.from_string("#" + h, Color.MAGENTA)


# ------------------------------------------------------------------ tiles ----

func _parse_tiles(raw: Dictionary) -> void:
	for id: String in raw:
		var t: Dictionary = raw[id]
		var cols: Array = t.get("colors", ["ff00ff", "ff00ff"])
		tile_index[id] = tile_order.size()
		tile_order.append(id)
		tiles[id] = {
			"colors": [_hex(str(cols[0])), _hex(str(cols[1]))],
			"walkable": bool(t.get("walkable", true)),
			"water": bool(t.get("water", false)),
			"hazard": bool(t.get("hazard", false)),
		}


func tile_def(byte_id: int) -> Dictionary:
	return tiles[tile_order[byte_id]]


# ----------------------------------------------------------------- biomes ----

func _parse_biomes(raw: Array) -> void:
	biomes = raw.duplicate(true)
	biomes.sort_custom(func(a, b): return int(a.get("priority", 0)) > int(b.get("priority", 0)))
	for i: int in biomes.size():
		biome_index[str(biomes[i]["id"])] = i
		# Pre-resolve tile weights to byte ids for the hot path.
		var tw: Dictionary = biomes[i].get("tiles", {})
		var resolved: Array = []
		for tid: String in tw:
			resolved.append([int(tile_index[tid]), float(tw[tid])])
		biomes[i]["_tile_weights"] = resolved


func biome(idx: int) -> Dictionary:
	return biomes[idx]


func biome_by_id(id: String) -> Dictionary:
	return biomes[int(biome_index.get(id, biomes.size() - 1))]


# ------------------------------------------------------------ skill sites ----

static func _regex(pattern: String) -> RegEx:
	if pattern.is_empty():
		return null
	var r := RegEx.new()
	if r.compile(pattern) != OK:
		push_error("Bad regex in world data: %s" % pattern)
		return null
	return r


func _parse_skill_rules(raw: Dictionary) -> void:
	for skill: String in raw:
		var cfg: Dictionary = raw[skill].duplicate(true)
		cfg["_include"] = _regex(str(cfg.get("includeMatch", "")))
		cfg["_cave_match"] = _regex(str(cfg.get("caveMatch", "")))
		var compiled: Array = []
		for rule: Dictionary in cfg.get("rules", []):
			compiled.append({
				"_re": _regex(str(rule.get("match", ""))),
				"biomes": rule.get("biomes", []),
				"caveLayers": rule.get("caveLayers", []),
			})
		cfg["_rules"] = compiled
		skill_rules[skill] = cfg


## Resolve every gather node from DataRegistry into a placement entry.
func _build_node_table() -> void:
	for skill: String in skill_rules:
		var cfg: Dictionary = skill_rules[skill]
		var entries: Array = []
		for n: Dictionary in DataRegistry.gather_nodes.get(skill, []):
			var name := str(n["name"])
			var inc: RegEx = cfg["_include"]
			if inc != null and inc.search(name) == null:
				continue  # e.g. foraging entries mixed into the fishing list
			var node_biomes: Array = cfg.get("defaultBiomes", [])
			var node_caves: Array = cfg.get("caveLayers", []) if not cfg.has("caveMatch") else []
			for rule: Dictionary in cfg["_rules"]:
				var re: RegEx = rule["_re"]
				if re != null and re.search(name) != null:
					node_biomes = rule["biomes"]
					if not rule["caveLayers"].is_empty():
						node_caves = rule["caveLayers"]
					break
			var cave_re: RegEx = cfg["_cave_match"]
			if cave_re != null and cave_re.search(name) != null:
				node_caves = cfg.get("caveLayers", [])
			entries.append({
				"node": n, "name": name, "level": int(n["level"]),
				"biomes": node_biomes, "cave_layers": node_caves,
			})
		node_table[skill] = entries


func skill_cfg(skill: String) -> Dictionary:
	return skill_rules.get(skill, {})


# --------------------------------------------------------------- monsters ----

func _compile_monster_rules() -> void:
	monster_cfg["_aggressive"] = _regex(str(monster_cfg.get("aggressive", "")))
	monster_cfg["_passive"] = _regex(str(monster_cfg.get("passive", "")))
	var compiled: Array = []
	for rule: Dictionary in monster_cfg.get("rules", []):
		compiled.append({
			"_re": _regex(str(rule.get("match", ""))),
			"biomes": rule.get("biomes", []),
			"caveLayers": rule.get("caveLayers", []),
		})
	monster_cfg["_rules"] = compiled


func _build_monster_table() -> void:
	var aggro_re: RegEx = monster_cfg["_aggressive"]
	var passive_re: RegEx = monster_cfg["_passive"]
	for name: String in DataRegistry.enemies:
		var e: Dictionary = DataRegistry.enemies[name]
		var m_biomes: Array = monster_cfg.get("defaultBiomes", [])
		var m_caves: Array = []
		for rule: Dictionary in monster_cfg["_rules"]:
			var re: RegEx = rule["_re"]
			if re != null and re.search(name) != null:
				m_biomes = rule["biomes"]
				m_caves = rule["caveLayers"]
				break
		var is_passive := passive_re != null and passive_re.search(name) != null
		var entry := {
			"name": name, "level": int(e["level"]), "boss": bool(e["isBoss"]),
			"biomes": m_biomes, "cave_layers": m_caves,
			"aggressive": (not is_passive) and aggro_re != null and aggro_re.search(name) != null,
		}
		monster_table[name] = entry
		if entry["boss"]:
			boss_list.append(entry)
	boss_list.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
