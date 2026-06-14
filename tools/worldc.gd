extends Node
## worldc — the headless World Compiler CLI for the AI World Director.
## Compiles / validates / explains an authored WorldSpec on top of the existing
## deterministic generator and emits machine-readable results for AI agents.
## See docs/AI_WORLD_AUTHORING.md.
##
## Usage (the active spec is chosen by data/world/worldspec/index.json):
##   godot --headless --path . res://tools/worldc.tscn -- --validate
##   godot --headless --path . res://tools/worldc.tscn -- --ascii --radius=10
##   godot --headless --path . res://tools/worldc.tscn -- --explain=anchor:kingsreach
##   godot --headless --path . res://tools/worldc.tscn -- --explain=chunk:-3,2
##   godot --headless --path . res://tools/worldc.tscn -- --metrics --region=eastvale
##   godot --headless --path . res://tools/worldc.tscn -- --regen=vegetation --region=oakmantle
##
## Every run prints a JSON trailer after the line "=== WORLDC RESULT ===".

const WG := preload("res://scripts/worldgen/wg.gd")
const PLAYER_SPEED := 230.0  # px/s (scripts/world/player_avatar.gd)

var issues: Array = []
var metrics: Dictionary = {}
var artifacts: Dictionary = {}


func _ready() -> void:
	SaveManager.suppress = true
	GameSettings.suppress = true
	WorldGen.store.suppress = true

	var do_validate := false
	var do_ascii := false
	var do_metrics := false
	var explain := ""
	var region := ""
	var regen := ""
	var radius := 10
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--validate":
			do_validate = true
		elif arg == "--ascii":
			do_ascii = true
		elif arg == "--metrics":
			do_metrics = true
		elif arg == "--regen":
			regen = "all"
		elif arg.begins_with("--regen="):
			regen = arg.trim_prefix("--regen=")
		elif arg.begins_with("--explain="):
			explain = arg.trim_prefix("--explain=")
		elif arg.begins_with("--region="):
			region = arg.trim_prefix("--region=")
		elif arg.begins_with("--radius="):
			radius = int(arg.trim_prefix("--radius="))
		elif arg.begins_with("--spec="):
			pass  # spec is selected by worldspec/index.json; flag kept for clarity

	if not (do_validate or do_ascii or do_metrics or not regen.is_empty() or not explain.is_empty()):
		do_validate = true  # default action

	_print_header()
	if do_ascii:
		_print_region_map(radius)
	if not regen.is_empty():
		_regen(regen, region)
	if not explain.is_empty():
		_explain(explain)
	if do_metrics or do_validate:
		_collect_metrics(region)
	if do_validate:
		_validate(region)

	_print_result()
	get_tree().quit(1 if _has_blocking_issues() else 0)


# --------------------------------------------------------------- header ----

func _print_header() -> void:
	var spec: RefCounted = WorldGen.reg.spec
	print("== worldc — World Compiler ==")
	if spec == null or not spec.active:
		print("  WorldSpec: (inactive — pure procedural world)")
		return
	print("  WorldSpec: %s  '%s'  v%d  seed %d  genVer %d" % [
		spec.id, spec.spec_name, spec.version, WorldGen.store.world_seed, spec.generator_version])
	print("  Regions (%d):" % spec.regions.size())
	for r: Dictionary in spec.regions:
		print("    %-12s %-26s biome=%-13s req=%-3d danger=%-11s center=(%d,%d) r=%.1f" % [
			str(r["id"]), str(r["name"]), str(r["biome"]), int(r["req"]),
			str(r["danger"]), int(r["cx"]), int(r["cy"]), float(r["radius"])])
	print("  Anchors (%d):" % spec.anchors.size())
	for a: Dictionary in spec.anchors:
		var c: Vector2i = a["chunk"]
		var boss := str(a["boss"])
		print("    %-16s poi=%-14s chunk=(%d,%d)%s" % [
			str(a["id"]), str(a["poi"]), c.x, c.y,
			("  boss=" + boss) if not boss.is_empty() else ""])


# ------------------------------------------------------------- ascii map ----

func _print_region_map(radius: int) -> void:
	print("\n  Region / biome map (radius %d chunks, @ = spawn):" % radius)
	print("  legend: lowercase=authored region 1st letter, #=anchor, .=procedural land, ~=water")
	var spec: RefCounted = WorldGen.reg.spec
	for cy: int in range(-radius, radius + 1):
		var line := "  "
		for cx: int in range(-radius, radius + 1):
			line += _region_char(spec, cx, cy)
		print(line)


func _region_char(spec: RefCounted, cx: int, cy: int) -> String:
	if cx == 0 and cy == 0:
		return "@"
	if spec != null and spec.active:
		var a: Dictionary = spec.anchor_for_chunk(cx, cy)
		if not a.is_empty():
			return "#"  # authored anchor (settlement/landmark/dungeon)
		var r: Dictionary = spec.region_for_chunk(cx, cy)
		if not r.is_empty():
			return str(r["id"]).substr(0, 1)
	var center_tile := (Vector2(float(cx), float(cy)) + Vector2(0.5, 0.5)) * WG.CHUNK_TILES
	var b: int = WorldGen.generator.classifier.biome_idx(center_tile.x, center_tile.y)
	var bid := str(WorldGen.reg.biomes[b]["id"])
	return "~" if bid == "ocean" else "."


# --------------------------------------------------------------- explain ----

func _explain(target: String) -> void:
	print("\n  Explain: %s" % target)
	var spec: RefCounted = WorldGen.reg.spec
	var out: Dictionary = {"target": target}
	if target.begins_with("anchor:") and spec != null:
		var aid := target.trim_prefix("anchor:")
		var a: Dictionary = spec.anchor_by_id(aid)
		if a.is_empty():
			print("    no such anchor")
			out["found"] = false
		else:
			var c: Vector2i = Vector2i(a.get("chunk", Vector2i.ZERO))
			var chunk: RefCounted = WorldGen.get_chunk(0, c.x, c.y)
			var placed := _poi_of_type(chunk, str(a.get("poi", "")))
			print("    anchor '%s' pins POI '%s' at chunk (%d,%d) in region '%s'" % [
				aid, str(a.get("poi", "")), c.x, c.y, str(a.get("region", ""))])
			print("    reason: authored in WorldSpec (locked=%s, boss=%s)" % [
				str(a.get("locked", true)), str(a.get("boss", ""))])
			print("    compiled: %s" % ("placed" if not placed.is_empty() else "NOT placed (footprint blocked?)"))
			out["found"] = true
			out["placed"] = not placed.is_empty()
			out["chunk"] = [c.x, c.y]
	elif target.begins_with("chunk:") and spec != null:
		var parts := target.trim_prefix("chunk:").split(",")
		var cx := int(parts[0])
		var cy := int(parts[1]) if parts.size() > 1 else 0
		var e: Dictionary = spec.explain_chunk(cx, cy)
		print("    %s" % JSON.stringify(e))
		out["explain"] = e
	else:
		print("    (spec inactive or unknown target form)")
	artifacts["explain"] = out


# ----------------------------------------------------------------- regen ----

## Selective regeneration: rebuild one region's chunks and prove the rest of the
## world is byte-identical (passes are pure functions of seed+coords+spec, so
## rebuilding a region never perturbs another). `layer` documents which compiler
## pass the AI critic asked to redo (e.g. "vegetation"); reported for provenance.
func _regen(layer: String, region: String) -> void:
	var spec: RefCounted = WorldGen.reg.spec
	if spec == null or not spec.active or region.is_empty():
		print("\n  Regen: needs an active spec and --region=<id>. Skipped.")
		artifacts["regen"] = {"ok": false, "reason": "no active spec or region"}
		return
	print("\n  Regen: pass='%s' region='%s'" % [layer, region])
	# Control region (untouched) to prove isolation.
	var control_id := "eastvale" if region != "eastvale" else "kingsreach"
	var control: Array = _region_chunks(spec, control_id)
	var control_hash := _chunks_hash(control)
	var target: Array = _region_chunks(spec, region)

	# Rebuild only the target region's chunks.
	for c: Vector2i in target:
		WorldGen.chunks.erase(WG.key(0, c.x, c.y))
	for c: Vector2i in target:
		WorldGen.get_chunk(0, c.x, c.y)

	var control_hash_after := _chunks_hash(control)
	var isolated := control_hash == control_hash_after
	print("    rebuilt %d chunks in '%s'; control region '%s' unchanged: %s" % [
		target.size(), region, control_id, str(isolated)])
	if not isolated:
		_add(region, "high", "regen_leak",
			"Rebuilding '%s' changed control region '%s'." % [region, control_id],
			"A pass is not a pure function of (seed, coords, spec).", ["all"], [])
	artifacts["regen"] = {
		"pass": layer, "region": region, "chunks": target.size(),
		"control": control_id, "isolated": isolated,
	}


func _chunks_hash(cells: Array) -> int:
	var h := 0
	for c: Vector2i in cells:
		var chunk: RefCounted = WorldGen.get_chunk(0, c.x, c.y)
		h = hash([h, c.x, c.y, chunk.tiles, chunk.biomes_t, chunk.pois.size(), chunk.sites.size()])
	return h


# --------------------------------------------------------------- metrics ----

func _collect_metrics(region: String) -> void:
	var spec: RefCounted = WorldGen.reg.spec
	var cells := _region_chunks(spec, region) if not region.is_empty() else _window_chunks(6)
	var entities := 0
	var sites := 0
	var monsters := 0
	var pois := 0
	var overlaps := 0
	for c: Vector2i in cells:
		var chunk: RefCounted = WorldGen.get_chunk(0, c.x, c.y)
		sites += chunk.sites.size()
		monsters += chunk.monsters.size()
		pois += chunk.pois.size()
		var occ: Dictionary = {}
		for poi: Dictionary in chunk.pois:
			for part: Dictionary in poi["parts"]:
				entities += 1
				var k := "%d:%d" % [int(part["tx"]), int(part["ty"])]
				if occ.has(k):
					overlaps += 1
				occ[k] = true
	var n := maxi(cells.size(), 1)
	metrics = {
		"chunks": cells.size(),
		"pois": pois, "sites": sites, "monsters": monsters,
		"poi_parts": entities,
		"sites_per_chunk": float(sites) / float(n),
		"monsters_per_chunk": float(monsters) / float(n),
		"overlaps": overlaps,
	}
	print("\n  Metrics (%s): %s" % [region if not region.is_empty() else "home window", JSON.stringify(metrics)])


# -------------------------------------------------------------- validate ----

func _validate(region: String) -> void:
	print("\n  Validators:")
	_v_determinism()
	_v_anchors_placed()
	_v_overlaps()
	_v_relationships()
	if metrics.get("sites_per_chunk", 0.0) > 12.0:
		_add("*", "low", "perf_budget", "Gather sites per chunk high (%.1f)" % float(metrics["sites_per_chunk"]),
			"Reduce siteDensity for the region's biome.", ["resource_placement"], [])
	var blocking := 0
	for i: Dictionary in issues:
		if str(i["severity"]) == "high":
			blocking += 1
	print("    %d issue(s) (%d high)" % [issues.size(), blocking])
	for i: Dictionary in issues:
		print("      [%s] %s/%s: %s" % [str(i["severity"]), str(i["region"]), str(i["problem"]).left(60), str(i["suggested_action"]).left(50)])


func _v_determinism() -> void:
	var c := Vector2i(2, 3)
	WorldGen.chunks.clear()
	var a: RefCounted = WorldGen.get_chunk(0, c.x, c.y)
	var ta: PackedByteArray = a.tiles.duplicate()
	WorldGen.chunks.clear()
	var b: RefCounted = WorldGen.get_chunk(0, c.x, c.y)
	if b.tiles != ta:
		_add("*", "high", "nondeterminism", "Chunk (2,3) differs across recompiles.",
			"Ensure all randomness derives from WG.hash_i/seeded noise.", ["all"], [])


func _v_anchors_placed() -> void:
	var spec: RefCounted = WorldGen.reg.spec
	if spec == null or not spec.active:
		return
	# Start from a clean slate: the global placement grid accumulates footprints
	# across the run (and the determinism check clears the chunk cache without it),
	# which would falsely block re-generation here. In-game, chunks generate once.
	WorldGen.chunks.clear()
	WorldGen.generator.placement_grid.clear()
	for a: Dictionary in spec.anchors:
		var c: Vector2i = a["chunk"]
		var chunk: RefCounted = WorldGen.get_chunk(0, c.x, c.y)
		var placed := _poi_of_type(chunk, str(a["poi"]))
		if placed.is_empty():
			_add(str(a.get("region", "*")), "high", "anchor_not_placed",
				"Authored anchor '%s' (%s) did not compile at chunk (%d,%d) — footprint blocked." % [
					str(a["id"]), str(a["poi"]), c.x, c.y],
				"Move the anchor 1-2 chunks, shrink its POI footprint, or suppress water in the region.",
				["settlement_layout"], ["terrain"])
		elif not str(a["boss"]).is_empty():
			var has_boss := false
			for part: Dictionary in placed["parts"]:
				if str(part.get("boss_name", "")) == str(a["boss"]):
					has_boss = true
			if not has_boss:
				_add(str(a.get("region", "*")), "medium", "boss_missing",
					"Anchor '%s' expected boss '%s' but it was not pinned." % [str(a["id"]), str(a["boss"])],
					"Check the boss name exists in data/enemies.json.", ["landmark_placement"], [])


func _v_overlaps() -> void:
	if int(metrics.get("overlaps", 0)) > 0:
		_add("*", "medium", "overlap", "%d POI parts share a tile." % int(metrics["overlaps"]),
			"Adjust POI part offsets in pois.json.", ["settlement_layout"], [])


func _v_relationships() -> void:
	var spec: RefCounted = WorldGen.reg.spec
	if spec == null or not spec.active:
		return
	for rel: Dictionary in spec.relationships:
		match str(rel.get("kind", "")):
			"service_present":
				_check_service(spec, str(rel["region"]), str(rel["service"]))
			"reachable":
				_check_reachable(spec, str(rel["from"]), str(rel["to"]))
			"travel_time":
				_check_travel(spec, rel)
			"max_entrances":
				_check_entrances(spec, str(rel["region"]), int(rel["count"]))


func _check_service(spec: RefCounted, region_id: String, service: String) -> void:
	var r: Dictionary = spec.region_by_id(region_id)
	if r.is_empty():
		return
	var from := WG.tile_to_world(int(r["cx"]) * WG.CHUNK_TILES + 8, int(r["cy"]) * WG.CHUNK_TILES + 8)
	var found: Dictionary = WorldGen.find_nearest_station(0, from, service, 4)
	if found.is_empty():
		_add(region_id, "high", "missing_service",
			"Region '%s' promises a '%s' but none is reachable within 4 chunks." % [region_id, service],
			"Add a POI part with station '%s' to the region's settlement." % service,
			["gameplay_service_placement"], [])


func _check_reachable(spec: RefCounted, from_id: String, to_id: String) -> void:
	var a: Dictionary = spec.anchor_by_id(from_id)
	var b: Dictionary = spec.anchor_by_id(to_id)
	if a.is_empty() or b.is_empty():
		return
	var ca: Vector2i = Vector2i(a.get("chunk", Vector2i.ZERO))
	var cb: Vector2i = Vector2i(b.get("chunk", Vector2i.ZERO))
	var walkable := _line_walkable_ratio(ca, cb)
	if walkable < 0.6:
		_add(str(b.get("region", "*")), "high", "inaccessible_location",
			"Route %s -> %s is only %d%% walkable along its corridor." % [from_id, to_id, int(walkable * 100.0)],
			"Route through walkable land or lower the region's water.", ["road_generation"], [])


func _check_travel(spec: RefCounted, rel: Dictionary) -> void:
	var a: Dictionary = spec.anchor_by_id(str(rel["from"]))
	var b: Dictionary = spec.anchor_by_id(str(rel["to"]))
	if a.is_empty() or b.is_empty():
		return
	var ca: Vector2i = Vector2i(a.get("chunk", Vector2i.ZERO))
	var cb: Vector2i = Vector2i(b.get("chunk", Vector2i.ZERO))
	var pa := _chunk_center_world(ca)
	var pb := _chunk_center_world(cb)
	var secs := pa.distance_to(pb) / PLAYER_SPEED
	var want := float(rel["seconds"])
	var tol := float(rel.get("tolerance", 30.0))
	metrics["travel_%s_%s_s" % [str(rel["from"]), str(rel["to"])]] = snappedf(secs, 0.1)
	if absf(secs - want) > tol:
		_add(str(b.get("region", "*")), "low", "travel_time_violation",
			"Travel %s -> %s ~%.0fs (want %.0f +/- %.0f)." % [str(rel["from"]), str(rel["to"]), secs, want, tol],
			"Move the anchor closer/farther to hit the target travel time.", ["settlement_layout"], [])


func _check_entrances(spec: RefCounted, region_id: String, want: int) -> void:
	# Count walkable openings on the region disc's bounding ring (proxy metric).
	var r: Dictionary = spec.region_by_id(region_id)
	if r.is_empty():
		return
	var rad := int(ceil(float(r["radius"]))) + 1
	var openings := 0
	var cx := int(r["cx"])
	var cy := int(r["cy"])
	for d: int in range(-rad, rad + 1):
		for edge: Vector2i in [Vector2i(cx + d, cy - rad), Vector2i(cx + d, cy + rad), Vector2i(cx - rad, cy + d), Vector2i(cx + rad, cy + d)]:
			var center := _chunk_center_world(edge)
			if WorldGen.is_walkable_world(center):
				openings += 1
	metrics["entrances_%s" % region_id] = openings
	# Informational only unless wildly off.
	if openings < want:
		_add(region_id, "low", "entrance_count",
			"Region '%s' has ~%d walkable border openings (target %d)." % [region_id, openings, want],
			"This is a proxy metric; tune region edges or surrounding water.", ["regional_boundary"], [])


# ----------------------------------------------------------------- helpers ----

func _poi_of_type(chunk: RefCounted, poi_type: String) -> Dictionary:
	for poi: Dictionary in chunk.pois:
		if str(poi["type"]) == poi_type:
			return poi
	return {}


func _chunk_center_world(c: Vector2i) -> Vector2:
	return WG.tile_to_world(c.x * WG.CHUNK_TILES + 8, c.y * WG.CHUNK_TILES + 8)


func _line_walkable_ratio(ca: Vector2i, cb: Vector2i) -> float:
	var pa := _chunk_center_world(ca)
	var pb := _chunk_center_world(cb)
	var steps := maxi(int(pa.distance_to(pb) / WG.TILE), 1)
	var ok := 0
	for i: int in range(steps + 1):
		var p := pa.lerp(pb, float(i) / float(steps))
		if WorldGen.is_walkable_world(p):
			ok += 1
	return float(ok) / float(steps + 1)


func _region_chunks(spec: RefCounted, region_id: String) -> Array:
	var out: Array = []
	if spec == null:
		return out
	var r: Dictionary = spec.region_by_id(region_id)
	if r.is_empty():
		return out
	var rad := int(ceil(float(r["radius"])))
	for dy: int in range(-rad, rad + 1):
		for dx: int in range(-rad, rad + 1):
			var cx := int(r["cx"]) + dx
			var cy := int(r["cy"]) + dy
			if str(spec.region_for_chunk(cx, cy).get("id", "")) == region_id:
				out.append(Vector2i(cx, cy))
	return out


func _window_chunks(radius: int) -> Array:
	var out: Array = []
	for cy: int in range(-radius, radius + 1):
		for cx: int in range(-radius, radius + 1):
			out.append(Vector2i(cx, cy))
	return out


func _add(region: String, severity: String, code: String, problem: String,
		action: String, affected_passes: Array, preserve: Array) -> void:
	issues.append({
		"region": region, "severity": severity, "code": code,
		"problem": problem, "suggested_action": action,
		"affected_passes": affected_passes, "preserve": preserve,
	})


func _has_blocking_issues() -> bool:
	for i: Dictionary in issues:
		if str(i["severity"]) == "high":
			return true
	return false


func _print_result() -> void:
	print("\n=== WORLDC RESULT ===")
	print(JSON.stringify({
		"spec": (WorldGen.reg.spec.id if WorldGen.reg.spec != null else ""),
		"active": (WorldGen.reg.spec.active if WorldGen.reg.spec != null else false),
		"issues": issues,
		"metrics": metrics,
		"artifacts": artifacts,
	}))
