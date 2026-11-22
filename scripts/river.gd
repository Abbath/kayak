extends Node3D

const CHUNK_LENGTH := 64.0
const STEP := 4.0
const HALF_WIDTH := 8.0
const BANK_WIDTH := 7.0
const GROUND_WIDTH := 36.0
const BANK_HEIGHT := 1.8

var chunks: Dictionary = {}

var _water_mat: ShaderMaterial
var _dirt_mat: StandardMaterial3D
var _grass_mat: StandardMaterial3D
var _rock_mat: StandardMaterial3D
var _trunk_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D


class Frame:
	var center: Vector3
	var tangent: Vector3
	var right: Vector3


func _ready() -> void:
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/water.gdshader")
	_dirt_mat = _standard(Color(0.48, 0.34, 0.2), 0.95)
	_grass_mat = _standard(Color(0.24, 0.46, 0.18), 0.92)
	_rock_mat = _standard(Color(0.45, 0.46, 0.5), 0.95)
	_trunk_mat = _standard(Color(0.36, 0.24, 0.12), 0.9)
	_leaf_mat = _standard(Color(0.16, 0.42, 0.16), 0.85)


func sample(s: float) -> Vector3:
	var x := sin(s * 0.015) * 40.0 + sin(s * 0.004 + 1.7) * 25.0
	return Vector3(x, 0.0, -s)


func frame_at(s: float) -> Frame:
	var ahead := sample(s + 0.5)
	var behind := sample(s - 0.5)
	var frame := Frame.new()
	frame.center = sample(s)
	frame.tangent = (ahead - behind).normalized()
	frame.right = frame.tangent.cross(Vector3.UP).normalized()
	return frame


func update_chunks(distance: float) -> void:
	var current := int(floor(distance / CHUNK_LENGTH))
	var keep := {}
	for offset in range(-1, 3):
		var index: int = current + offset
		if index < 0:
			continue
		keep[index] = true
		if not chunks.has(index):
			var chunk := _build_chunk(index)
			chunks[index] = chunk
			add_child(chunk)
	var stale: Array[int] = []
	for key in chunks.keys():
		if not keep.has(key):
			stale.append(int(key))
	for key in stale:
		chunks[key].queue_free()
		chunks.erase(key)


func get_rocks_near(distance: float) -> Array:
	var found: Array = []
	var current := int(floor(distance / CHUNK_LENGTH))
	for offset in range(-1, 2):
		var index: int = current + offset
		if chunks.has(index):
			found.append_array(chunks[index].get_meta("rocks"))
	return found


func _build_chunk(index: int) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "Chunk%d" % index
	var s0 := float(index) * CHUNK_LENGTH
	var sections: Array[Frame] = []
	var s := s0
	while s <= s0 + CHUNK_LENGTH + 0.001:
		sections.append(frame_at(s))
		s += STEP

	var water := _mesh_node(_ribbon(sections, 0.0, HALF_WIDTH, 0.0, 0.0), _water_mat, "Water")
	water.extra_cull_margin = 1.0
	chunk.add_child(water)
	chunk.add_child(_mesh_node(_banks(sections), _dirt_mat, "Banks"))
	chunk.add_child(_mesh_node(_ground(sections), _grass_mat, "Ground"))

	var rocks := _rocks_for(index)
	chunk.set_meta("rocks", rocks)
	for rock in rocks:
		chunk.add_child(_rock_node(rock))
	for tree in _trees_for(index):
		chunk.add_child(_tree_node(tree))
	return chunk


func _ribbon(sections: Array[Frame], inner: float, outer: float, y_inner: float, y_outer: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sections.size() - 1):
		var a := sections[i]
		var b := sections[i + 1]
		_quad_up(
			st,
			a.center + a.right * outer + Vector3.UP * y_outer,
			a.center + a.right * inner + Vector3.UP * y_inner,
			b.center + b.right * inner + Vector3.UP * y_inner,
			b.center + b.right * outer + Vector3.UP * y_outer
		)
		_quad_up(
			st,
			a.center - a.right * inner + Vector3.UP * y_inner,
			a.center - a.right * outer + Vector3.UP * y_outer,
			b.center - b.right * outer + Vector3.UP * y_outer,
			b.center - b.right * inner + Vector3.UP * y_inner
		)
	st.generate_normals()
	return st.commit()


func _banks(sections: Array[Frame]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := HALF_WIDTH + BANK_WIDTH
	for i in range(sections.size() - 1):
		var a := sections[i]
		var b := sections[i + 1]
		_quad_up(
			st,
			a.center + a.right * HALF_WIDTH,
			a.center + a.right * outer + Vector3.UP * BANK_HEIGHT,
			b.center + b.right * outer + Vector3.UP * BANK_HEIGHT,
			b.center + b.right * HALF_WIDTH
		)
		_quad_up(
			st,
			a.center - a.right * outer + Vector3.UP * BANK_HEIGHT,
			a.center - a.right * HALF_WIDTH,
			b.center - b.right * HALF_WIDTH,
			b.center - b.right * outer + Vector3.UP * BANK_HEIGHT
		)
	st.generate_normals()
	return st.commit()


func _ground(sections: Array[Frame]) -> ArrayMesh:
	var inner := HALF_WIDTH + BANK_WIDTH
	var outer := inner + GROUND_WIDTH
	return _ribbon(sections, inner, outer, BANK_HEIGHT, BANK_HEIGHT)


func _quad_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Godot treats clockwise vertices as the front face. The cross product
	# points up for the opposite, counter-clockwise order.
	var normal_y := (b - a).cross(d - a).y
	if normal_y > 0.0:
		st.add_vertex(a)
		st.add_vertex(d)
		st.add_vertex(b)
		st.add_vertex(d)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(d)
		st.add_vertex(d)
		st.add_vertex(b)
		st.add_vertex(c)


func _rocks_for(index: int) -> Array:
	var count := _hash(index * 9781 + 12345) % 3
	var rocks: Array = []
	for i in count:
		var h2 := _hash(index * 10007 + i * 7919 + 42)
		var along := 12.0 + float(i) * (CHUNK_LENGTH * 0.42) + float(h2 % 14)
		var lateral := (float(h2 % 1000) / 1000.0) * 1.1 - 0.55
		if i == 1 and not rocks.is_empty() and abs(lateral - float(rocks[0]["lateral"])) < 0.35:
			lateral = -float(rocks[0]["lateral"])
		var radius := 0.75 + float((h2 / 13) % 50) / 100.0
		rocks.append({
			"s": float(index) * CHUNK_LENGTH + along,
			"lateral": lateral,
			"radius": radius,
		})
	return rocks


func _trees_for(index: int) -> Array:
	var trees: Array = []
	for i in 4:
		var h := _hash(index * 48611 + i * 9176 + 99)
		var along := 4.0 + float(h % int(CHUNK_LENGTH - 8))
		var side := 1.0 if (h & 1) == 0 else -1.0
		var inset := float((h / 3) % 1000) / 1000.0
		var lateral := side * (HALF_WIDTH + BANK_WIDTH + 2.5 + inset * (GROUND_WIDTH - 6.0))
		var height := 1.7 + float((h / 11) % 100) / 100.0 * 1.5
		trees.append({
			"s": float(index) * CHUNK_LENGTH + along,
			"lateral": lateral,
			"height": height,
		})
	return trees


func _rock_node(rock: Dictionary) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var radius: float = rock["radius"]
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	inst.mesh = mesh
	inst.material_override = _rock_mat
	var frame := frame_at(rock["s"])
	var pos := frame.center + frame.right * float(rock["lateral"]) * HALF_WIDTH
	pos.y = radius * 0.32
	inst.position = pos
	inst.scale = Vector3(1.05, 0.72, 1.05)
	return inst


func _tree_node(tree: Dictionary) -> Node3D:
	var node := Node3D.new()
	var frame := frame_at(tree["s"])
	var pos := frame.center + frame.right * float(tree["lateral"])
	pos.y = BANK_HEIGHT
	node.position = pos

	var trunk_h: float = tree["height"]
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.1
	trunk_mesh.bottom_radius = 0.16
	trunk_mesh.height = trunk_h
	trunk.mesh = trunk_mesh
	trunk.material_override = _trunk_mat
	trunk.position.y = trunk_h * 0.5
	node.add_child(trunk)

	var crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.04
	crown_mesh.bottom_radius = 1.05
	crown_mesh.height = trunk_h * 1.25
	crown.mesh = crown_mesh
	crown.material_override = _leaf_mat
	crown.position.y = trunk_h + crown_mesh.height * 0.32
	node.add_child(crown)
	return node


func _mesh_node(mesh: ArrayMesh, mat: Material, node_name: String) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.material_override = mat
	return inst


func _standard(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


func _hash(n: int) -> int:
	var x := n & 0x7fffffff
	x = int((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	x = int((x ^ (x >> 16)) * 1103515245) & 0x7fffffff
	return x
