extends Node
## Dump a GLB scene's node tree, mesh surfaces, materials, and overall AABB so we can
## color/scale it correctly. Run: godot --headless --path . res://tools/glb_inspect.tscn

const PATH := "res://models/smithy.glb"


func _ready() -> void:
	var ps := load(PATH)
	if ps == null:
		print("FAILED to load ", PATH)
		get_tree().quit(1)
		return
	var root: Node = ps.instantiate()
	print("=== GLB TREE: ", PATH, " ===")
	_walk(root, 0)
	var aabb := _scene_aabb(root)
	print("\n=== AABB ===")
	print(JSON.stringify({
		"pos": [aabb.position.x, aabb.position.y, aabb.position.z],
		"size": [aabb.size.x, aabb.size.y, aabb.size.z],
	}))
	get_tree().quit(0)


func _walk(n: Node, depth: int) -> void:
	var pad := ""
	for i in depth:
		pad += "  "
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			var sc := mesh.get_surface_count()
			extra = " [mesh surfaces=%d]" % sc
			for s in sc:
				var mat := mesh.surface_get_material(s)
				var mname := mat.resource_name if mat != null else "<none>"
				var col := "-"
				var tex := "-"
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					col = str(sm.albedo_color)
					tex = "yes" if sm.albedo_texture != null else "no"
				print("%s    surface %d: mat='%s' albedo=%s tex=%s class=%s" % [pad, s, mname, col, tex, mat.get_class() if mat else "nil"])
				var arrays: Array = mesh.surface_get_arrays(s)
				var has_col: bool = arrays.size() > Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR] != null
				var has_uv: bool = arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] != null
				print("%s      vertex_colors=%s  uvs=%s  verts=%d" % [pad, has_col, has_uv, (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if arrays.size() > 0 and arrays[Mesh.ARRAY_VERTEX] != null else 0])
				if has_col:
					var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
					var samp := ""
					for i in mini(8, cols.size()):
						samp += str(cols[i * maxi(1, cols.size() / 8)].to_html(false)) + " "
					print("%s      color samples: %s" % [pad, samp])
	print("%s- %s (%s)%s" % [pad, n.name, n.get_class(), extra])
	for c in n.get_children():
		_walk(c, depth + 1)


func _scene_aabb(n: Node) -> AABB:
	var acc := AABB()
	var first := true
	for mi: Node in _all_meshes(n):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var local := m.mesh.get_aabb()
		var xf := m.global_transform if m.is_inside_tree() else m.transform
		var world_aabb := xf * local
		if first:
			acc = world_aabb
			first = false
		else:
			acc = acc.merge(world_aabb)
	return acc


func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out
