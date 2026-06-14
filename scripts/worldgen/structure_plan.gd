extends RefCounted
class_name StructurePlan
## Deterministic, multi-chunk layout for a megastructure — a sprawling city or a
## ruined-city field — centred on a global tile. Every chunk that overlaps the
## plan stamps its own slice independently (tiles + entities), so the structure
## is identical regardless of the order chunks stream in. Built once and cached;
## queried per chunk via tile_id_at() and parts_in_chunk().

const WG := preload("res://scripts/worldgen/wg.gd")
const Chunk := preload("res://scripts/worldgen/chunk.gd")

const K_NONE := 0
const K_COBBLE := 1
const K_ROAD := 2
const K_PLAZA := 3
const K_BFLOOR := 4   # building interior — walkable
const K_BWALL := 5    # building perimeter — solid (non-walkable)
const K_WALL := 6     # rampart base
const K_GRAVEL := 7   # worn paving patch (breaks up the grey)

const WALL_SEGMENT := 0
const WALL_GATE := 1
const WALL_TOWER := 2

const ROOF_COLORS := ["7a4630", "8a6848", "705038", "6a4030", "5f5142",
	"7a5a30", "8a7558", "5a4840", "6a5846", "7a6040", "5a4a3c", "8a6848"]
const PROPS := ["lamp", "crate", "barrel", "well", "flowerbox", "hay", "cart", "lamp", "crate"]

var kind := "city"
var center := Vector2i.ZERO
var radius := 40
var seed := 0
var min_t := Vector2i.ZERO
var w := 0
var grid := PackedByteArray()
var parts: Array = []
var _occ: Dictionary = {}   # tile key -> true, for prop/landmark spacing


func _h(a: int, b: int, salt: int) -> int:
	return WG.hash_i(seed, a, b, salt)


func _r(a: int, b: int, salt: int) -> float:
	return WG.r01(seed, a, b, salt)


func _in(gtx: int, gty: int) -> bool:
	return gtx >= min_t.x and gty >= min_t.y and gtx < min_t.x + w and gty < min_t.y + w


func _idx(gtx: int, gty: int) -> int:
	return (gty - min_t.y) * w + (gtx - min_t.x)


func _at(gtx: int, gty: int) -> int:
	if not _in(gtx, gty):
		return K_NONE
	return grid[_idx(gtx, gty)]


func _put(gtx: int, gty: int, k: int) -> void:
	if _in(gtx, gty):
		grid[_idx(gtx, gty)] = k


## Tile id to paint at (gtx,gty), or -1 to leave the natural terrain.
func tile_id_at(gtx: int, gty: int, reg: RefCounted) -> int:
	match _at(gtx, gty):
		K_NONE:
			return -1
		K_ROAD:
			return int(reg.tile_index.get("dirt", -1))
		K_GRAVEL:
			return int(reg.tile_index.get("gravel", -1))
		K_PLAZA:
			return int(reg.tile_index.get("plaza", reg.tile_index.get("cobble", -1)))
		K_BFLOOR:
			return int(reg.tile_index.get("plank_floor", reg.tile_index.get("cobble", -1)))
		K_BWALL:
			return int(reg.tile_index.get("building_wall", reg.tile_index.get("cobble", -1)))
		_:
			return int(reg.tile_index.get("cobble", -1))


func is_city() -> bool:
	return kind == "city"


func parts_in_chunk(cx: int, cy: int) -> Array:
	var out: Array = []
	var bx := cx * WG.CHUNK_TILES
	var by := cy * WG.CHUNK_TILES
	for p: Dictionary in parts:
		var tx: int = p["tx"]
		var ty: int = p["ty"]
		if tx >= bx and ty >= by and tx < bx + WG.CHUNK_TILES and ty < by + WG.CHUNK_TILES:
			out.append(p)
	return out


# --------------------------------------------------------------- build ----

func build(p_kind: String, p_center: Vector2i, p_radius: int, p_seed: int,
		def: Dictionary, is_water: Callable) -> void:
	kind = p_kind
	center = p_center
	radius = p_radius
	seed = p_seed
	var pad := radius + 4
	min_t = Vector2i(center.x - pad, center.y - pad)
	w = pad * 2 + 1
	grid.resize(w * w)
	grid.fill(K_NONE)
	if kind == "city":
		_build_city(def, is_water)
	else:
		_build_ruins(def, is_water)


func _boundary_radius(gtx: int, gty: int) -> float:
	var ang := atan2(float(gty - center.y), float(gtx - center.x))
	return float(radius) - 3.0 + sin(ang * 5.0 + float(seed % 17)) * (float(radius) * 0.07) \
		+ sin(ang * 2.0 - float(seed % 11)) * (float(radius) * 0.05)


func _build_city(def: Dictionary, is_water: Callable) -> void:
	var plaza_r := 12
	# 1) organic footprint, paved with cobble/gravel patches (worn gradient look)
	for gy: int in range(min_t.y, min_t.y + w):
		for gx: int in range(min_t.x, min_t.x + w):
			var dx := gx - center.x
			var dy := gy - center.y
			if sqrt(float(dx * dx + dy * dy)) <= _boundary_radius(gx, gy):
				var worn := _r(int(floor(gx / 4.0)), int(floor(gy / 4.0)), 60) < 0.32
				_put(gx, gy, K_GRAVEL if worn else K_COBBLE)
	# 2) winding avenues + ring roads
	var avenues := 7
	for i: int in avenues:
		_stroke_avenue(TAU * float(i) / float(avenues) + _r(i, 0, 70) * 0.4)
	_stroke_ring(int(float(radius) * 0.62))
	_stroke_ring(int(float(radius) * 0.34))
	# 3) plaza + fountain
	for gy: int in range(center.y - plaza_r, center.y + plaza_r + 1):
		for gx: int in range(center.x - plaza_r, center.x + plaza_r + 1):
			if _at(gx, gy) != K_NONE and Vector2(gx - center.x, gy - center.y).length() <= float(plaza_r):
				_put(gx, gy, K_PLAZA)
	parts.append({"kind": "fountain", "tx": center.x, "ty": center.y + 4, "label": str(def.get("label", "City"))})
	_mark_occ(center.x, center.y + 4)
	# 4) big halls lining the streets, 5) rampart, 6) street clutter
	_place_buildings(def, is_water, plaza_r)
	_place_walls()
	_scatter_city_props()


func _stroke_avenue(ang: float) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	for s: int in range(2, radius + 3):
		var wob := sin(float(s) * 0.16 + ang * 3.0) * 3.2 * clampf(float(s) / float(radius), 0.0, 1.0)
		var p := Vector2(center) + dir * float(s) + perp * wob
		var tx := int(round(p.x))
		var ty := int(round(p.y))
		for ox: int in [-1, 0, 1]:
			for oy: int in [-1, 0, 1]:
				if absi(ox) + absi(oy) <= 1 and _at(tx + ox, ty + oy) in [K_COBBLE, K_GRAVEL]:
					_put(tx + ox, ty + oy, K_ROAD)


func _stroke_ring(rr: int) -> void:
	if rr < 4:
		return
	var n := maxi(24, rr * 6)
	for i: int in n:
		var ang := TAU * float(i) / float(n)
		var wob := sin(ang * 4.0 + float(seed % 13)) * 2.5
		var p := Vector2(center) + Vector2(cos(ang), sin(ang)) * (float(rr) + wob)
		if _at(int(round(p.x)), int(round(p.y))) in [K_COBBLE, K_GRAVEL]:
			_put(int(round(p.x)), int(round(p.y)), K_ROAD)


func _place_buildings(def: Dictionary, is_water: Callable, plaza_r: int) -> void:
	var services: Array = def.get("services", [])
	var svc_i := 0
	var max_b := int(def.get("maxBuildings", 40))
	var count := 0
	var step := 20
	var lo := -radius + 14
	var hi := radius - 14
	var gy := lo
	while gy <= hi and count < max_b:
		var gx := lo
		while gx <= hi and count < max_b:
			var jx := int(_r(gx, gy, 71) * 6.0) - 3
			var jy := int(_r(gx, gy, 72) * 6.0) - 3
			var bx := center.x + gx + jx
			var by := center.y + gy + jy
			var foot := 11 + int(_r(bx, by, 73) * 6.0)  # 11..16 tiles
			if _can_place_building(bx, by, foot, plaza_r, is_water):
				_stamp_building(bx, by, foot)
				var roof: String = ROOF_COLORS[_h(bx, by, 74) % ROOF_COLORS.size()]
				parts.append({"kind": "building", "tx": bx, "ty": by, "foot": foot, "color": roof})
				if svc_i < services.size():
					_place_station(bx, by, foot, services[svc_i])
					svc_i += 1
				count += 1
			gx += step
		gy += step


func _can_place_building(bx: int, by: int, foot: int, plaza_r: int, is_water: Callable) -> bool:
	var half := foot / 2
	if Vector2(bx - center.x, by - center.y).length() < float(plaza_r + 5):
		return false
	# cheap water check at a few sample points only
	for s: Array in [[0, 0], [half, half], [-half, -half], [half, -half], [-half, half]]:
		if is_water.is_valid() and is_water.call(bx + int(s[0]), by + int(s[1])):
			return false
	var near_road := false
	for ty: int in range(by - half - 1, by + half + 2):
		for tx: int in range(bx - half - 1, bx + half + 2):
			var k := _at(tx, ty)
			if k == K_NONE or k == K_BWALL or k == K_BFLOOR:
				return false
			if k == K_ROAD:
				near_road = true
	return near_road


func _stamp_building(bx: int, by: int, foot: int) -> void:
	var half := foot / 2
	for ty: int in range(by - half, by + half + 1):
		for tx: int in range(bx - half, bx + half + 1):
			var edge := tx == bx - half or tx == bx + half or ty == by - half or ty == by + half
			_put(tx, ty, K_BWALL if edge else K_BFLOOR)
	# side doorway on the long south-west face — visually matches the hall art.
	var door_x := bx - maxi(1, half / 2)
	for i: int in range(-1, 2):
		_put(door_x + i, by + half, K_BFLOOR)
		_put(door_x + i, by + half - 1, K_BFLOOR)
	_put(door_x, by + half - 2, K_BFLOOR)


func _place_station(bx: int, by: int, foot: int, svc: Dictionary) -> void:
	var half := foot / 2
	var tx := bx + half - 2   # just inside, near the south door
	var ty := by + half - 2
	var station := str(svc.get("station", ""))
	parts.append({
		"kind": _station_kind(station), "tx": tx, "ty": ty,
		"station": station, "label": str(svc.get("label", station.capitalize())),
	})


func _station_kind(station: String) -> String:
	match station:
		"bank": return "chest"
		"anvil": return "anvil"
		"range": return "campfire"
		_: return "stall"


func _place_walls() -> void:
	for gy: int in range(min_t.y, min_t.y + w):
		for gx: int in range(min_t.x, min_t.x + w):
			var k := _at(gx, gy)
			if k != K_COBBLE and k != K_ROAD and k != K_PLAZA and k != K_GRAVEL:
				continue
			if not (_at(gx + 1, gy) == K_NONE or _at(gx - 1, gy) == K_NONE \
					or _at(gx, gy + 1) == K_NONE or _at(gx, gy - 1) == K_NONE):
				continue
			var piece := WALL_SEGMENT
			if k == K_ROAD:
				piece = WALL_GATE
			elif _h(gx, gy, 75) % 11 == 0:
				piece = WALL_TOWER
			_put(gx, gy, K_WALL)
			parts.append({"kind": "city_wall", "tx": gx, "ty": gy, "piece": piece})


func _scatter_city_props() -> void:
	var step := 4
	var lo := -radius + 3
	var hi := radius - 3
	var gy := lo
	while gy <= hi:
		var gx := lo
		while gx <= hi:
			var tx := center.x + gx + int(_r(gx, gy, 91) * 3.0) - 1
			var ty := center.y + gy + int(_r(gx, gy, 92) * 3.0) - 1
			var k := _at(tx, ty)
			if (k == K_COBBLE or k == K_GRAVEL or k == K_PLAZA) and not _occupied_part(tx, ty):
				# props cluster near roads and the plaza edge; lamps line the streets
				var road_adj := _at(tx + 1, ty) == K_ROAD or _at(tx - 1, ty) == K_ROAD \
					or _at(tx, ty + 1) == K_ROAD or _at(tx, ty - 1) == K_ROAD
				var chance := 0.10 + (0.22 if road_adj else 0.0)
				if _r(tx, ty, 93) < chance:
					var prop: String = "lamp" if road_adj and _r(tx, ty, 94) < 0.5 else PROPS[_h(tx, ty, 95) % PROPS.size()]
					parts.append({"kind": "city_prop", "prop": prop, "tx": tx, "ty": ty})
					_mark_occ(tx, ty)
			gx += step
		gy += step


# --------------------------------------------------------------- ruins ----

const RUIN_KINDS := ["ruin_pillar", "broken_wall", "rubble_pile", "broken_statue",
	"ruin_pillar", "rubble_pile", "broken_wall"]


func _build_ruins(def: Dictionary, is_water: Callable) -> void:
	var heart := maxi(8, radius / 4)
	for gy: int in range(center.y - heart, center.y + heart + 1):
		for gx: int in range(center.x - heart, center.x + heart + 1):
			if Vector2(gx - center.x, gy - center.y).length() <= float(heart) \
					and not (is_water.is_valid() and is_water.call(gx, gy)):
				_put(gx, gy, K_COBBLE if _r(gx, gy, 61) > 0.4 else K_GRAVEL)
	parts.append({"kind": "ruin_arch", "tx": center.x, "ty": center.y, "label": str(def.get("label", "Ancient Ruins"))})
	parts.append({"kind": "enemy", "tx": center.x + 3, "ty": center.y + 2, "boss": true})
	parts.append({"kind": "sign", "tx": center.x, "ty": center.y + heart + 1, "label": str(def.get("label", "Ancient Ruins"))})
	_mark_occ(center.x, center.y)
	_mark_occ(center.x + 3, center.y + 2)
	var step := 4
	var lo := -radius + 2
	var hi := radius - 2
	var gy := lo
	while gy <= hi:
		var gx := lo
		while gx <= hi:
			var tx := center.x + gx + int(_r(gx, gy, 81) * 3.0) - 1
			var ty := center.y + gy + int(_r(gx, gy, 82) * 3.0) - 1
			var dist := Vector2(tx - center.x, ty - center.y).length()
			if dist <= float(radius) and not (is_water.is_valid() and is_water.call(tx, ty)):
				var density := 1.0 - dist / float(radius)
				if _r(tx, ty, 83) < 0.18 + density * 0.4 and not _occupied_part(tx, ty):
					var rk: String = RUIN_KINDS[_h(tx, ty, 84) % RUIN_KINDS.size()]
					parts.append({"kind": rk, "tx": tx, "ty": ty})
					_mark_occ(tx, ty)
			gx += step
		gy += step


func _mark_occ(tx: int, ty: int) -> void:
	_occ[ty * 100003 + tx] = true


func _occupied_part(tx: int, ty: int) -> bool:
	for oy: int in [-1, 0, 1]:
		for ox: int in [-1, 0, 1]:
			if _occ.has((ty + oy) * 100003 + (tx + ox)):
				return true
	return false
