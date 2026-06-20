extends RefCounted
class_name GatherNodeDef
## Typed view over a data/gather_nodes.json entry. `items` is the array of yielded item
## names. See docs/content/SCHEMA.md.

var raw: Dictionary = {}
var id: String = ""
var name: String = ""
var display_name: String = ""
var skill: String = ""
var level: int = 0
var xp: float = 0.0
var items: Array = []           # item names this node yields


static func from_dict(d: Dictionary) -> GatherNodeDef:
	var n := GatherNodeDef.new()
	if d.is_empty():
		return n
	n.raw = d
	n.id = str(d.get("id", ""))
	n.name = str(d.get("name", ""))
	n.display_name = str(d.get("displayName", n.name))
	n.skill = str(d.get("skill", ""))
	n.level = int(d.get("level", 0))
	n.xp = float(d.get("xp", 0.0))
	n.items = d.get("items", [])
	return n


func is_empty() -> bool:
	return id.is_empty()
