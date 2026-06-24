extends RefCounted
class_name AuthoredOverlay
## Preserves hand-authored editor content across a FULL re-bake.
##
## Generation is deterministic from the masks + worldspec, so anything in the PREVIOUSLY baked world
## that a fresh generation does NOT reproduce is hand-authored: placed structures / decor / fences,
## settlement buildings, and deleted procedural trees (cuts). On every bake we diff those out, merge
## them back into the freshly-generated chunks, and write them to <id>_overlay.json as a readable,
## version-controllable record (with stable ids). That makes the authored layer survive:
##   • biome/terrain generation changes   • world expansion   • model swaps   • road improvements
## without losing your placed objects.
##
## ELEVATION is also preserved: tiles sculpted with the editor's Elevate/Smoothen tools override the
## mask-generated height and survive re-bakes (the designer's tool edits win over generation). Edit
## elevation with the TOOL — repainting the elev mask is a generation change the diff can't tell from
## a hand-edit. Hand-painted biome / terrain still belong in the mask images (not preserved here).


## Diff the previous baked world at `world_path` against freshly-generated `chunks`, MERGE authored
## placements + cut trees back into those chunks IN PLACE, and return the overlay record for saving.
static func merge_existing(world_path: String, chunks: Dictionary) -> Dictionary:
	var record := {"structures": [], "cuts": {}, "elev": {}, "monsters": []}
	if not FileAccess.file_exists(world_path):
		return record
	var parsed: Variant = str_to_var(FileAccess.get_file_as_string(world_path))
	if not (parsed is Dictionary):
		return record
	var old_chunks: Dictionary = (parsed as Dictionary).get("chunks", {})
	for key: String in chunks:
		var oc: Dictionary = old_chunks.get(key, {})
		if oc.is_empty():
			continue
		var chunk: RefCounted = chunks[key]
		# Structures THIS generation produced (POIs / roads / settlement anchors), keyed so the diff
		# can tell them apart from hand-placed ones.
		var generated := {}
		for p: Dictionary in chunk.structures:
			generated[_skey(p)] = true
		for raw: Variant in oc.get("structures", []):
			var pd: Dictionary = raw
			if generated.has(_skey(pd)):
				continue   # regenerated this bake — not authored
			chunk.structures.append(pd.duplicate(true))
			var rec: Dictionary = pd.duplicate(true)
			rec["cx"] = chunk.cx
			rec["cy"] = chunk.cy
			rec["id"] = str(pd.get("id", "%d_%d_%s_%s_%d_%d" % [
				chunk.cx, chunk.cy, str(pd.get("kind", "")), str(pd.get("prop", "")),
				int(pd.get("tx", 0)), int(pd.get("ty", 0))]))
			record["structures"].append(rec)
		# Hand-placed enemy spawns (editor Creature tool): same generated-vs-authored diff as structures.
		var gen_mon := {}
		for mm: Dictionary in chunk.monsters:
			gen_mon[_mkey(mm)] = true
		for raw_m: Variant in oc.get("monsters", []):
			var md: Dictionary = raw_m
			if gen_mon.has(_mkey(md)):
				continue   # regenerated this bake — not authored
			chunk.monsters.append(md.duplicate(true))
			var mrec: Dictionary = md.duplicate(true)
			mrec["cx"] = chunk.cx
			mrec["cy"] = chunk.cy
			record["monsters"].append(mrec)
		# Carry over cut/removed procedural trees so they stay gone after the re-bake.
		var cuts: Array = oc.get("cuts", [])
		if not cuts.is_empty():
			for ci: Variant in cuts:
				chunk.tree_cuts[int(ci)] = true
			record["cuts"][key] = cuts.duplicate()
		# Carry over hand-sculpted ELEVATION: any tile whose saved height differs from the freshly
		# generated (mask) value was edited with the Elevate/Smoothen tool, so override the fresh value.
		var old_e := Marshalls.base64_to_raw(str(oc.get("e", "")))
		if old_e.size() == chunk.elev.size() and old_e.size() > 0:
			var ov: Array = []
			for i: int in old_e.size():
				if old_e[i] != chunk.elev[i]:
					chunk.elev[i] = old_e[i]
					ov.append([i, int(old_e[i])])
			if not ov.is_empty():
				record["elev"][key] = ov
	return record


## Identity of a structure part for the generated-vs-authored diff: same kind + prop on the same
## chunk-local tile is "the same thing" the generator would produce.
static func _skey(p: Dictionary) -> String:
	return "%s|%s|%d|%d" % [str(p.get("kind", "")), str(p.get("prop", "")),
		int(p.get("tx", -999)), int(p.get("ty", -999))]


## Identity of an enemy spawn for the generated-vs-authored diff.
static func _mkey(m: Dictionary) -> String:
	return "%s|%d|%d" % [str(m.get("name", "")), int(m.get("tx", -999)), int(m.get("ty", -999))]
