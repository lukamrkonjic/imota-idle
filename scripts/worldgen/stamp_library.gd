extends RefCounted
class_name StampLibrary
## Reusable natural-map stamps (data/world/stamps.json). A stamp is a small
## multi-tile piece — pond, grove, outcrop, cove… — that the editor paints to
## build a hybrid world. build() returns offset cells (tile + biome) and gather
## sites for a given variant/rotation/flip, so repeated stamps vary deterministically.

const WG := preload("res://scripts/worldgen/wg.gd")
const PATH := "res://data/world/stamps.json"

static var _stamps: Array = []


static func all() -> Array:
	if _stamps.is_empty():
		_load()
	return _stamps


static func get_stamp(id: String) -> Dictionary:
	for s: Dictionary in all():
		if str(s["id"]) == id:
			return s
	return {}


static func _load() -> void:
	_stamps = JsonIO.read_dict(PATH).get("stamps", [])


## Returns { "cells": [ {dx,dy, tile:String, biome:String} ], "sites": [ {dx,dy, skill:String} ] }.
## dx/dy are tile offsets from the stamp centre, after rotation/flip.
static func build(stamp: Dictionary, variant: int, rot: int, flip: bool) -> Dictionary:
	var raw: Dictionary
	match str(stamp.get("kind", "patch")):
		"blob": raw = _blob(stamp, variant)
		_: raw = _patch(stamp, variant)
	var out := {"cells": [], "sites": []}
	for c: Dictionary in raw["cells"]:
		var p := _xf(int(c["dx"]), int(c["dy"]), rot, flip)
		out["cells"].append({"dx": p.x, "dy": p.y, "tile": c["tile"], "biome": c.get("biome", "")})
	for s: Dictionary in raw["sites"]:
		var p := _xf(int(s["dx"]), int(s["dy"]), rot, flip)
		out["sites"].append({"dx": p.x, "dy": p.y, "skill": s["skill"]})
	return out


static func _xf(dx: int, dy: int, rot: int, flip: bool) -> Vector2i:
	var x := -dx if flip else dx
	var y := dy
	match posmod(rot, 4):
		1: return Vector2i(-y, x)
		2: return Vector2i(-x, -y)
		3: return Vector2i(y, -x)
		_: return Vector2i(x, y)


static func _jit(variant: int, a: int, b: int) -> float:
	return WG.r01(variant * 1009 + 7, a, b, 41)


# Round water/terrain piece: core inside, ring around it, edge rim. The radius
# wobbles per-angle so the outline isn't a perfect circle.
static func _blob(stamp: Dictionary, variant: int) -> Dictionary:
	var r: int = int(stamp.get("radius", 3))
	var core := str(stamp.get("core", "water"))
	var ring := str(stamp.get("ring", "shallow"))
	var edge := str(stamp.get("edge", ""))
	var biome := str(stamp.get("biome", ""))
	var cells: Array = []
	var rim: Array = []
	for dy: int in range(-r - 1, r + 2):
		for dx: int in range(-r - 1, r + 2):
			var wob := (_jit(variant, dx, dy) - 0.5) * 1.4
			var d := sqrt(float(dx * dx + dy * dy)) + wob
			if d <= float(r) - 1.0:
				cells.append({"dx": dx, "dy": dy, "tile": core, "biome": biome})
			elif d <= float(r):
				cells.append({"dx": dx, "dy": dy, "tile": ring, "biome": biome})
			elif d <= float(r) + 1.0 and not edge.is_empty():
				cells.append({"dx": dx, "dy": dy, "tile": edge, "biome": biome})
				rim.append(Vector2i(dx, dy))
	var sites: Array = _scatter_sites(stamp, rim, variant)
	return {"cells": cells, "sites": sites}


# Filled area + biome, with scattered gather sites.
static func _patch(stamp: Dictionary, variant: int) -> Dictionary:
	var r: int = int(stamp.get("radius", 3))
	var fill := str(stamp.get("fill", "grass"))
	var biome := str(stamp.get("biome", ""))
	var cells: Array = []
	var inside: Array = []
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var wob := (_jit(variant, dx, dy) - 0.5) * 1.2
			if sqrt(float(dx * dx + dy * dy)) + wob <= float(r):
				cells.append({"dx": dx, "dy": dy, "tile": fill, "biome": biome})
				inside.append(Vector2i(dx, dy))
	var sites: Array = _scatter_sites(stamp, inside, variant)
	return {"cells": cells, "sites": sites}


static func _scatter_sites(stamp: Dictionary, slots: Array, variant: int) -> Array:
	var sites: Array = []
	if slots.is_empty():
		return sites
	for skill: String in ["woodcutting", "mining", "fishing", "foraging"]:
		var n: int = int(stamp.get(skill, 0))
		for i: int in n:
			var idx: int = int(WG.r01(variant + i * 13, skill.hash(), i, 51) * float(slots.size())) % slots.size()
			var p: Vector2i = slots[idx]
			sites.append({"dx": p.x, "dy": p.y, "skill": skill})
	return sites
