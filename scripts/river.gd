extends Node3D

const CHUNK_LENGTH := 64.0
const STEP := 4.0
const HALF_WIDTH := 8.0
const SHORE_WIDTH := 6.0
const WALL_WIDTH := 18.0
const GROUND_WIDTH := 40.0
const RIM_HEIGHT := 7.8
const WATER_DEPTH := 1.85
const RAPID_SLOT := 150.0

var chunks: Dictionary = {}

var _water_mat: ShaderMaterial
var _dirt_mat: StandardMaterial3D
var _grass_mat: StandardMaterial3D
var _rock_mat: StandardMaterial3D
var _under_mat: StandardMaterial3D
var _bed_mat: StandardMaterial3D
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
	_rock_mat = _standard(Color(0.48, 0.48, 0.52), 0.95)
	_under_mat = _standard(Color(0.28, 0.36, 0.4), 0.55)
	_bed_mat = _standard(Color(0.26, 0.3, 0.26), 0.95)
	_trunk_mat = _standard(Color(0.36, 0.24, 0.12), 0.9)
	_leaf_mat = _standard(Color(0.16, 0.42, 0.16), 0.85)


func sample(s: float) -> Vector3:
	var x := sin(s * 0.015) * 40.0 + sin(s * 0.004 + 1.7) * 25.0
	return Vector3(x, 0.0, -s)


func water_offset(s: float) -> float:
	if s <= 0.0:
		return 0.0
	var y := 0.0
	var last_slot := int(floor(s / RAPID_SLOT)) + 1
	for i in range(1, last_slot + 1):
		var h := _hash(i * 9176 + 404)
		if h % 3 != 0:
			continue
		var center := float(i) * RAPID_SLOT + 20.0 + float(h % 40)
		var width := 22.0 + float((h / 7) % 16)
		var drop := 2.3 + float((h / 19) % 130) / 100.0
		var start := center - width * 0.5
		if s <= start:
			break
		var u := clampf((s - start) / width, 0.0, 1.0)
		var smooth := u * u * (3.0 - 2.0 * u)
		y -= drop * smooth
	return y


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

	var water := _mesh_node(_water_surface(sections), _water_mat, "Water")
	water.extra_cull_margin = 1.5
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(water)
	chunk.add_child(_mesh_node(_river_bed(sections), _bed_mat, "Bed"))
	chunk.add_child(_mesh_node(_valley(sections), _dirt_mat, "Banks"))
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


func _water_surface(sections: Array[Frame]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sections.size() - 1):
		var a := sections[i]
		var b := sections[i + 1]
		var sa := -a.center.z
		var sb := -b.center.z
		var ya := water_offset(sa)
		var yb := water_offset(sb)
		var fa := _foam(sa)
		var fb := _foam(sb)
		_quad_colored(
			st,
			a.center + a.right * HALF_WIDTH + Vector3.UP * ya, fa,
			a.center - a.right * HALF_WIDTH + Vector3.UP * ya, fa,
			b.center - b.right * HALF_WIDTH + Vector3.UP * yb, fb,
			b.center + b.right * HALF_WIDTH + Vector3.UP * yb, fb
		)
	st.generate_normals()
	return st.commit()


func _river_bed(sections: Array[Frame]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sections.size() - 1):
		var a := sections[i]
		var b := sections[i + 1]
		var ya := water_offset(-a.center.z) - WATER_DEPTH
		var yb := water_offset(-b.center.z) - WATER_DEPTH
		_quad_up(
			st,
			a.center + a.right * HALF_WIDTH + Vector3.UP * ya,
			a.center - a.right * HALF_WIDTH + Vector3.UP * ya,
			b.center - b.right * HALF_WIDTH + Vector3.UP * yb,
			b.center + b.right * HALF_WIDTH + Vector3.UP * yb
		)
	st.generate_normals()
	return st.commit()


func _valley(sections: Array[Frame]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shore := HALF_WIDTH + SHORE_WIDTH
	var rim := shore + WALL_WIDTH
	for i in range(sections.size() - 1):
		var a := sections[i]
		var b := sections[i + 1]
		var ya := water_offset(-a.center.z)
		var yb := water_offset(-b.center.z)
		var ba := ya + 0.35
		var bb := yb + 0.35
		var ra := ya + RIM_HEIGHT
		var rb := yb + RIM_HEIGHT
		var da := ya - WATER_DEPTH
		var db := yb - WATER_DEPTH
		_quad_facing(
			st,
			a.center + a.right * HALF_WIDTH + Vector3.UP * ya,
			a.center + a.right * HALF_WIDTH + Vector3.UP * da,
			b.center + b.right * HALF_WIDTH + Vector3.UP * db,
			b.center + b.right * HALF_WIDTH + Vector3.UP * yb,
			-a.right
		)
		_quad_facing(
			st,
			a.center - a.right * HALF_WIDTH + Vector3.UP * ya,
			a.center - a.right * HALF_WIDTH + Vector3.UP * da,
			b.center - b.right * HALF_WIDTH + Vector3.UP * db,
			b.center - b.right * HALF_WIDTH + Vector3.UP * yb,
			a.right
		)
		_quad_up(
			st,
			a.center + a.right * HALF_WIDTH + Vector3.UP * ya,
			a.center + a.right * shore + Vector3.UP * ba,
			b.center + b.right * shore + Vector3.UP * bb,
			b.center + b.right * HALF_WIDTH + Vector3.UP * yb
		)
		_quad_up(
			st,
			a.center + a.right * shore + Vector3.UP * ba,
			a.center + a.right * rim + Vector3.UP * ra,
			b.center + b.right * rim + Vector3.UP * rb,
			b.center + b.right * shore + Vector3.UP * bb
		)
		_quad_up(
			st,
			a.center - a.right * shore + Vector3.UP * ba,
			a.center - a.right * HALF_WIDTH + Vector3.UP * ya,
			b.center - b.right * HALF_WIDTH + Vector3.UP * yb,
			b.center - b.right * shore + Vector3.UP * bb
		)
		_quad_up(
			st,
			a.center - a.right * rim + Vector3.UP * ra,
			a.center - a.right * shore + Vector3.UP * ba,
			b.center - b.right * shore + Vector3.UP * bb,
			b.center - b.right * rim + Vector3.UP * rb
		)
	st.generate_normals()
	return st.commit()


func _foam(s: float) -> float:
	var slope := absf(water_offset(s + 2.0) - water_offset(s - 2.0))
	return clampf(slope * 0.55, 0.0, 1.0)


func _ground(sections: Array[Frame]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := HALF_WIDTH + SHORE_WIDTH + WALL_WIDTH
	var outer := inner + GROUND_WIDTH
	for i in range(sections.size() - 1):
		var a := sections[i]
		var b := sections[i + 1]
		var ra := water_offset(-a.center.z) + RIM_HEIGHT
		var rb := water_offset(-b.center.z) + RIM_HEIGHT
		_quad_up(
			st,
			a.center + a.right * outer + Vector3.UP * ra,
			a.center + a.right * inner + Vector3.UP * ra,
			b.center + b.right * inner + Vector3.UP * rb,
			b.center + b.right * outer + Vector3.UP * rb
		)
		_quad_up(
			st,
			a.center - a.right * inner + Vector3.UP * ra,
			a.center - a.right * outer + Vector3.UP * ra,
			b.center - b.right * outer + Vector3.UP * rb,
			b.center - b.right * inner + Vector3.UP * rb
		)
	st.generate_normals()
	return st.commit()


func _quad_colored(st: SurfaceTool, a: Vector3, ca: float, b: Vector3, cb: float, c: Vector3, cc: float, d: Vector3, cd: float) -> void:
	var normal_y := (b - a).cross(d - a).y
	if normal_y > 0.0:
		_colored_vertex(st, a, ca)
		_colored_vertex(st, d, cd)
		_colored_vertex(st, b, cb)
		_colored_vertex(st, d, cd)
		_colored_vertex(st, c, cc)
		_colored_vertex(st, b, cb)
	else:
		_colored_vertex(st, a, ca)
		_colored_vertex(st, b, cb)
		_colored_vertex(st, d, cd)
		_colored_vertex(st, d, cd)
		_colored_vertex(st, b, cb)
		_colored_vertex(st, c, cc)


func _colored_vertex(st: SurfaceTool, point: Vector3, foam: float) -> void:
	st.set_color(Color(1.0, 1.0, 1.0, foam))
	st.add_vertex(point)


func _quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3) -> void:
	# Clockwise is the front face, so the right-handed cross product points backward.
	var normal := (b - a).cross(d - a)
	if normal.dot(facing) > 0.0:
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
	var rocks: Array = []
	var surface_count := _hash(index * 9781 + 12345) % 3
	var under_count := _hash(index * 3187 + 777) % 3
	for i in surface_count:
		rocks.append(_make_rock(index, i, false))
	for i in under_count:
		rocks.append(_make_rock(index, i + 8, true))
	return rocks


func _make_rock(index: int, i: int, submerged: bool) -> Dictionary:
	var salt := 401 if submerged else 42
	var h2 := _hash(index * 10007 + i * 7919 + salt)
	var along := 14.0 + float(h2 % int(CHUNK_LENGTH - 24))
	var s := float(index) * CHUNK_LENGTH + along
	var water_y := water_offset(s)
	var bed := water_y - WATER_DEPTH
	var width := _rock_width(h2, submerged)
	var depth := width * (0.72 + float((h2 / 5) % 28) / 100.0)
	var expose := 0.45 + float((h2 / 13) % 70) / 100.0
	if submerged:
		expose = 0.02 + float((h2 / 17) % 10) / 100.0
	var rise := WATER_DEPTH + expose
	# The belly sits in the bed, so the rock has to be about as wide as it is tall
	# or the buried half reads as a pillar.
	var span_x := maxf(width, rise * 0.95)
	var span_z := maxf(depth, rise * 0.78)
	var lateral_span := maxf(span_x, span_z)
	var max_lat := 0.36 if lateral_span > 1.15 else 0.6
	var lateral := (float(h2 % 1000) / 1000.0) * max_lat * 2.0 - max_lat
	return {
		"s": s,
		"lateral": lateral,
		"radius": lateral_span * 0.5,
		"vr": rise,
		"visual_radius": 0.5,
		"y": bed,
		"submerged": submerged,
		"sx": span_x,
		"sy": rise * 2.0,
		"sz": span_z,
	}


func _rock_width(h: int, submerged: bool) -> float:
	var roll := h % 100
	if submerged:
		if roll < 60:
			return 0.42 + float((h / 7) % 28) / 100.0
		return 0.75 + float((h / 9) % 40) / 100.0
	if roll < 34:
		return 0.48 + float((h / 7) % 30) / 100.0
	if roll < 70:
		return 0.85 + float((h / 5) % 35) / 100.0
	return 1.25 + float((h / 9) % 45) / 100.0


func _trees_for(index: int) -> Array:
	var trees: Array = []
	for i in 4:
		var h := _hash(index * 48611 + i * 9176 + 99)
		var along := 4.0 + float(h % int(CHUNK_LENGTH - 8))
		var side := 1.0 if (h & 1) == 0 else -1.0
		var inset := float((h / 3) % 1000) / 1000.0
		var rim := HALF_WIDTH + SHORE_WIDTH + WALL_WIDTH
		var lateral := side * (rim + 2.5 + inset * (GROUND_WIDTH - 8.0))
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
	var radius: float = rock["visual_radius"]
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	inst.mesh = mesh
	inst.material_override = _under_mat if rock["submerged"] else _rock_mat
	var frame := frame_at(rock["s"])
	var pos := frame.center + frame.right * float(rock["lateral"]) * HALF_WIDTH
	pos.y = rock["y"]
	inst.position = pos
	inst.scale = Vector3(rock["sx"], rock["sy"], rock["sz"])
	return inst


func _tree_node(tree: Dictionary) -> Node3D:
	var node := Node3D.new()
	var frame := frame_at(tree["s"])
	var pos := frame.center + frame.right * float(tree["lateral"])
	pos.y = water_offset(tree["s"]) + RIM_HEIGHT
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
