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
var sub_biomes: Array = []              # sub-biome placement rules from biomes.json
var parent_biome_ids: PackedStringArray = []  # ids that can be macro parent regions
var biome_neighbors: Dictionary = {}    # parent id -> allowed neighbor ids
var biome_transitions: Dictionary = {}  # "a:b" -> {width, tiles resolved}
# Deprecation maps (biomes.json "deprecatedBiomes"/"deprecatedTiles"): removed-id ->
# ordered fallback ids. A baked world keeps a permanent index->id table; on load a
# removed id resolves through these so REMOVING a biome/tile never rerolls or
# corrupts the map — it just shows its fallback. Values may be a bare ["a","b"]
# array or {"fallbacks":["a","b"]}.
var deprecated_biomes: Dictionary = {}  # old biome id -> [fallback ids]
var deprecated_tiles: Dictionary = {}   # old tile id  -> [fallback ids]

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

# --- authored world layer (AI World Director / Compiler) ---
const WorldSpec := preload("res://scripts/worldgen/world_spec.gd")
var spec: RefCounted = WorldSpec.new()  # see docs/AI_WORLD_AUTHORING.md


func load_all() -> void:
	var biome_doc := _read("biomes.json")
	_parse_tiles(biome_doc.get("tiles", {}))
	_parse_biomes(biome_doc.get("biomes", []))
	_parse_sub_biomes(biome_doc.get("subBiomes", []))
	_parse_transitions(biome_doc.get("transitions", {}))
	deprecated_biomes = _parse_deprecations(biome_doc.get("deprecatedBiomes", {}))
	deprecated_tiles = _parse_deprecations(biome_doc.get("deprecatedTiles", {}))

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

	# Authored layer loads last so it can override procedural defaults.
	spec.load_active()


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
		if not bool(biomes[i].get("isSubBiome", false)):
			parent_biome_ids.append(str(biomes[i]["id"]))
			var nbrs: Array = biomes[i].get("neighbors", [])
			if nbrs.is_empty():
				nbrs = parent_biome_ids.duplicate()
			biome_neighbors[str(biomes[i]["id"])] = nbrs


func _parse_transitions(raw: Dictionary) -> void:
	biome_transitions.clear()
	for key: String in raw:
		var def: Dictionary = raw[key]
		var tw: Dictionary = def.get("tiles", {})
		var resolved: Array = []
		for tid: String in tw:
			if tile_index.has(tid):
				resolved.append([int(tile_index[tid]), float(tw[tid])])
		biome_transitions[key] = {
			"width": int(def.get("width", 3)),
			"tiles": resolved,
		}


func transition_key(a: String, b: String) -> String:
	if a == b:
		return ""
	return (a + ":" + b) if a < b else (b + ":" + a)


func transition_def(a: String, b: String) -> Dictionary:
	var key := transition_key(a, b)
	return biome_transitions.get(key, {})


func ground_decor(biome_id: String) -> Dictionary:
	return biome_by_id(biome_id).get("groundDecor", {})


## Ambient forest/large-vegetation layer for a biome: {density, kinds:[{kind,weight}]}.
## Empty = no canopy (open biome). Scattered at runtime like groundDecor; see
## world_entity_spawner._spawn_canopy.
func canopy(biome_id: String) -> Dictionary:
	return biome_by_id(biome_id).get("canopy", {})


func _parse_sub_biomes(raw: Array) -> void:
	sub_biomes.clear()
	var salt := 0
	for entry: Dictionary in raw:
		var def := entry.duplicate(true)
		def["_salt"] = salt
		salt += 1
		sub_biomes.append(def)


func parent_biome_id(idx: int) -> String:
	if idx < 0 or idx >= biomes.size():
		return "plains"
	var b: Dictionary = biomes[idx]
	if bool(b.get("isSubBiome", false)) and b.has("parentBiome"):
		return str(b["parentBiome"])
	return str(b["id"])


func biome(idx: int) -> Dictionary:
	return biomes[idx]


func biome_by_id(id: String) -> Dictionary:
	return biomes[int(biome_index.get(id, biomes.size() - 1))]


## Normalize a deprecation doc into {oldId: PackedStringArray(fallbacks)}.
static func _parse_deprecations(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for old_id: String in raw:
		var v: Variant = raw[old_id]
		var fbs: Array = v if v is Array else (v as Dictionary).get("fallbacks", []) if v is Dictionary else []
		var clean: PackedStringArray = []
		for fb: Variant in fbs:
			clean.append(str(fb))
		out[old_id] = clean
	return out


## Current biome id for a (possibly removed) id: the id itself if it still exists,
## else the first existing fallback (one transitive hop), else "".
func resolve_biome_id(id: String) -> String:
	return _resolve_id(id, biome_index, deprecated_biomes)


func resolve_tile_id(id: String) -> String:
	return _resolve_id(id, tile_index, deprecated_tiles)


func _resolve_id(id: String, index: Dictionary, deprecated: Dictionary) -> String:
	if index.has(id):
		return id
	for fb: String in deprecated.get(id, PackedStringArray()):
		if index.has(fb):
			return fb
		# one transitive hop: a fallback that is itself deprecated
		for fb2: String in deprecated.get(fb, PackedStringArray()):
			if index.has(fb2):
				return fb2
	return ""


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
			"forbiddenBiomes": rule.get("forbiddenBiomes", []),
		})
	monster_cfg["_rules"] = compiled


func _build_monster_table() -> void:
	var aggro_re: RegEx = monster_cfg["_aggressive"]
	var passive_re: RegEx = monster_cfg["_passive"]
	for name: String in DataRegistry.enemies:
		var e: Dictionary = DataRegistry.enemies[name]
		var m_biomes: Array = monster_cfg.get("defaultBiomes", [])
		var m_caves: Array = []
		var m_forbidden: Array = []
		for rule: Dictionary in monster_cfg["_rules"]:
			var re: RegEx = rule["_re"]
			if re != null and re.search(name) != null:
				m_biomes = rule["biomes"]
				m_caves = rule["caveLayers"]
				m_forbidden = rule.get("forbiddenBiomes", [])
				break
		var is_passive := passive_re != null and passive_re.search(name) != null
		var entry := {
			"name": name, "level": int(e["level"]), "boss": bool(e["isBoss"]),
			"biomes": m_biomes, "cave_layers": m_caves,
			"forbiddenBiomes": m_forbidden,
			"aggressive": (not is_passive) and aggro_re != null and aggro_re.search(name) != null,
		}
		monster_table[name] = entry
		if entry["boss"]:
			boss_list.append(entry)
	boss_list.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
