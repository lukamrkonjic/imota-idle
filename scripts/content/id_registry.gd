extends RefCounted
class_name IdRegistry
## Persistent map from a content's *legacy slug id* (e.g. "item.acadia_logs") to
## an opaque, stable, OSRS-style numeric id (e.g. "item.1001").
##
## The slug id is derived once, from the original (pre-rename) display name, and
## is what live Early-Access saves and `content_aliases.json` key on. The numeric
## id is the permanent on-disk contract: assigned exactly once, never reused, and
## never derived from a name — so renaming content (display name only) is safe.
##
## Both `tools/stamp_ids.gd` (one-shot) and `tools/import_bloobs_data.gd` mint
## through this registry, so re-imports preserve every existing assignment and
## only mint ids for genuinely new content.

const ContentId := preload("res://scripts/content/content_id.gd")

const KINDS := ["items", "enemies", "nodes", "recipes"]
const PREFIX := {
	"items": ContentId.PREFIX_ITEM,
	"enemies": ContentId.PREFIX_ENEMY,
	"nodes": ContentId.PREFIX_NODE,
	"recipes": ContentId.PREFIX_RECIPE,
}
# Numeric ids start here per kind; the prefix already disambiguates the type.
const FIRST_ID := 1001

var path: String = "res://data/id_registry.json"
var data: Dictionary = {}


static func load_or_new(p: String = "res://data/id_registry.json") -> IdRegistry:
	var reg := IdRegistry.new()
	reg.path = p
	if FileAccess.file_exists(p):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			reg.data = parsed
	reg._ensure_shape()
	return reg


func _ensure_shape() -> void:
	if not data.has("next"):
		data["next"] = {}
	for kind: String in KINDS:
		if not data.has(kind):
			data[kind] = {}
		if not data["next"].has(kind):
			data["next"][kind] = FIRST_ID


## Returns the frozen numeric id for `legacy_slug`, minting (and recording) a new
## one if this is the first time we have seen this content.
func mint(kind: String, legacy_slug: String) -> String:
	assert(KINDS.has(kind), "unknown id kind: %s" % kind)
	var table: Dictionary = data[kind]
	if table.has(legacy_slug):
		return str(table[legacy_slug])
	var n := int(data["next"][kind])
	data["next"][kind] = n + 1
	var numeric: String = str(PREFIX[kind]) + str(n)
	table[legacy_slug] = numeric
	return numeric


func has(kind: String, legacy_slug: String) -> bool:
	return data.get(kind, {}).has(legacy_slug)


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()


## Builds the slug-id -> numeric-id maps for `content_aliases.json`, so live saves
## holding the old slug ids resolve to the new numeric ids on load.
func to_aliases() -> Dictionary:
	return {
		"items": data["items"].duplicate(),
		"nodes": data["nodes"].duplicate(),
		"recipes": data["recipes"].duplicate(),
		"enemies": data["enemies"].duplicate(),
	}
