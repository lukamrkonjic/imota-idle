extends RefCounted
class_name RecipeDef
## Typed view over a data/recipes.json entry. `inputs` stay as [{item, qty}] dicts (still
## iterated raw); the scalar fields are typed. See docs/content/SCHEMA.md.

var raw: Dictionary = {}
var id: String = ""
var name: String = ""
var display_name: String = ""
var skill: String = ""
var level_req: int = 0
var xp: float = 0.0
var time: float = 0.0
var inputs: Array = []          # [{item: String, qty: float}]
var output: Dictionary = {}     # {item: String, qty: float}
var hp_value: int = 0
var unburnable: bool = false


static func from_dict(d: Dictionary) -> RecipeDef:
	var r := RecipeDef.new()
	if d.is_empty():
		return r
	r.raw = d
	r.id = str(d.get("id", ""))
	r.name = str(d.get("name", ""))
	r.display_name = str(d.get("displayName", r.name))
	r.skill = str(d.get("skill", ""))
	r.level_req = int(d.get("levelReq", 0))
	r.xp = float(d.get("xp", 0.0))
	r.time = float(d.get("time", 0.0))
	r.inputs = d.get("inputs", [])
	r.output = d.get("output", {})
	r.hp_value = int(d.get("hpValue", 0))
	r.unburnable = bool(d.get("unburnable", false))
	return r


func is_empty() -> bool:
	return id.is_empty()
