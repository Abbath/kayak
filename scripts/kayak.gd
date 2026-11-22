extends Node3D

const START_SPEED := 3.0
const COAST_SPEED := 8.5
const PADDLE_SPEED := 13.0
const BRAKE_SPEED := 1.5
const PADDLE_ACCEL := 7.5
const BRAKE_DECEL := 12.0
const COAST_ACCEL := 4.5
const SIDE_DECEL := 16.0
const TURN_RATE := 1.75
const MAX_YAW := 0.95
const HIT_COOLDOWN := 0.6
const HULL_INSET := 0.8

var river
var distance := 0.0
var velocity := Vector3.ZERO
var forward := Vector3(0.0, 0.0, -1.0)
var speed := START_SPEED
var hit_cooldown := 0.0

var _bob := 0.0
var _steer := 0.0
var _paddle_phase := 0.0
var _paddler: Node3D
var _paddle: Node3D
var _arm_l: Node3D
var _arm_r: Node3D

const _SHOULDER_L := Vector3(-0.16, 0.3, 0.02)
const _SHOULDER_R := Vector3(0.16, 0.3, 0.02)
const _GRIP_L := Vector3(-0.3, 0.02, 0.0)
const _GRIP_R := Vector3(0.3, 0.02, 0.0)


func _ready() -> void:
	_build_hull()
	_spawn_at_start()


func _physics_process(delta: float) -> void:
	_steer = 0.0
	if Input.is_action_pressed("steer_left"):
		_steer -= 1.0
	if Input.is_action_pressed("steer_right"):
		_steer += 1.0

	var s := maxf(-global_position.z, 0.0)
	var frame = river.frame_at(s)
	_turn_heading(delta, frame.tangent)
	var heading_right := forward.cross(Vector3.UP).normalized()
	var forward_speed := velocity.dot(forward)
	var side_speed := velocity.dot(heading_right)

	var along_current: float = clampf(forward.dot(frame.tangent), 0.0, 1.0)
	var target := lerpf(3.5, COAST_SPEED, along_current)
	var accel := COAST_ACCEL
	if Input.is_action_pressed("brake"):
		target = BRAKE_SPEED
		accel = BRAKE_DECEL
	elif Input.is_action_pressed("paddle"):
		target = lerpf(6.0, PADDLE_SPEED, along_current)
		accel = PADDLE_ACCEL

	forward_speed = move_toward(forward_speed, target, accel * delta)
	side_speed = move_toward(side_speed, 0.0, SIDE_DECEL * delta)
	velocity = forward * forward_speed + heading_right * side_speed
	velocity.y = 0.0
	speed = velocity.length()

	global_position += velocity * delta
	_bob += delta
	distance = maxf(-global_position.z, 0.0)
	river.update_chunks(distance)
	if hit_cooldown > 0.0:
		hit_cooldown -= delta
	else:
		_check_rocks()
	_keep_in_river()
	speed = velocity.length()
	_apply_pose()
	_animate_paddles(delta)


func reset() -> void:
	_steer = 0.0
	_paddle_phase = 0.0
	_bob = 0.0
	hit_cooldown = 0.0
	_spawn_at_start()


func _spawn_at_start() -> void:
	var frame = river.frame_at(0.0)
	forward = frame.tangent
	velocity = forward * START_SPEED
	speed = START_SPEED
	distance = 0.0
	global_position = frame.center
	river.update_chunks(distance)
	_apply_pose()
	_animate_paddles(0.0)


func _turn_heading(delta: float, tangent: Vector3) -> void:
	forward = forward.rotated(Vector3.UP, -_steer * TURN_RATE * delta)
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = tangent
	forward = forward.normalized()
	var delta_to_current: float = forward.signed_angle_to(tangent, Vector3.UP)
	if absf(delta_to_current) <= MAX_YAW:
		return
	forward = forward.rotated(Vector3.UP, delta_to_current - signf(delta_to_current) * MAX_YAW)
	forward.y = 0.0
	forward = forward.normalized()


func _check_rocks() -> void:
	for rock in river.get_rocks_near(distance):
		var rock_frame = river.frame_at(float(rock["s"]))
		var rock_pos: Vector3 = rock_frame.center + rock_frame.right * float(rock["lateral"]) * river.HALF_WIDTH
		var away := Vector3(global_position.x - rock_pos.x, 0.0, global_position.z - rock_pos.z)
		var reach: float = float(rock["radius"]) + 0.7
		var dist := away.length()
		if dist > reach:
			continue
		if dist < 0.001:
			away = forward
		else:
			away /= dist
		global_position += away * (reach - dist + 0.08)
		velocity = velocity.slide(away)
		velocity += away * maxf(speed * 0.45, 2.5)
		velocity *= 0.5
		velocity.y = 0.0
		speed = velocity.length()
		hit_cooldown = HIT_COOLDOWN
		return


func _keep_in_river() -> void:
	if global_position.z > 0.0:
		global_position.z = 0.0
		if velocity.z > 0.0:
			velocity.z = 0.0
	var frame = river.frame_at(maxf(-global_position.z, 0.0))
	var lateral: float = (global_position - frame.center).dot(frame.right)
	var limit: float = river.HALF_WIDTH - HULL_INSET
	if absf(lateral) <= limit:
		return
	var side := signf(lateral)
	global_position -= frame.right * (lateral - side * limit)
	var outward: float = velocity.dot(frame.right) * side
	if outward > 0.0:
		velocity -= frame.right * side * outward
	if forward.dot(frame.right) * side > 0.0:
		forward -= frame.right * forward.dot(frame.right)
		if forward.dot(frame.tangent) <= 0.0 or forward.length_squared() < 0.001:
			forward = frame.tangent
		else:
			forward = forward.normalized()
		velocity = forward * maxf(velocity.dot(forward), 0.0)
	velocity.y = 0.0


func _apply_pose() -> void:
	var pos := global_position
	pos.y = 0.22 + sin(_bob * 2.3) * 0.04
	global_position = pos
	var basis := Basis.looking_at(forward, Vector3.UP)
	var roll := clampf(-_steer * 0.22, -0.28, 0.28)
	basis = basis.rotated(forward, roll)
	global_transform = Transform3D(basis, pos)


func _animate_paddles(delta: float) -> void:
	var rate := 1.5 + speed * 0.16 + absf(_steer) * 3.0
	_paddle_phase += delta * rate
	var stroke := sin(_paddle_phase)
	var steered := absf(_steer)
	var sweep := lerpf(deg_to_rad(58.0), deg_to_rad(24.0), steered)
	_paddle.rotation = Vector3(
		deg_to_rad(-8.0 - absf(stroke) * 10.0),
		deg_to_rad(_steer * -8.0),
		stroke * sweep + _steer * deg_to_rad(42.0)
	)
	_paddler.rotation = Vector3(deg_to_rad(-4.0), deg_to_rad(_steer * -10.0), deg_to_rad(_steer * 6.0))
	_stretch_arm(_arm_l, _SHOULDER_L, _paddle.transform * _GRIP_L)
	_stretch_arm(_arm_r, _SHOULDER_R, _paddle.transform * _GRIP_R)


func _stretch_arm(arm: Node3D, shoulder: Vector3, grip: Vector3) -> void:
	var span := grip - shoulder
	var length := maxf(span.length(), 0.08)
	arm.position = shoulder + span * 0.5
	arm.scale = Vector3(1.0, 1.0, length)
	var target := _paddler.to_global(grip)
	if arm.global_position.distance_squared_to(target) > 0.0001:
		arm.look_at(target, Vector3.UP)


func _build_hull() -> void:
	var hull := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.38
	mesh.height = 2.35
	mesh.radial_segments = 12
	mesh.rings = 4
	hull.mesh = mesh
	hull.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	hull.scale = Vector3(0.95, 1.15, 0.46)
	hull.material_override = _color(Color(0.84, 0.18, 0.12), 0.45)
	add_child(hull)

	var cockpit := MeshInstance3D.new()
	var cockpit_mesh := CylinderMesh.new()
	cockpit_mesh.top_radius = 0.2
	cockpit_mesh.bottom_radius = 0.2
	cockpit_mesh.height = 0.05
	cockpit.mesh = cockpit_mesh
	cockpit.position = Vector3(0.0, 0.16, 0.02)
	cockpit.material_override = _color(Color(0.1, 0.11, 0.13), 0.7)
	add_child(cockpit)

	_paddler = Node3D.new()
	_paddler.name = "Paddler"
	_paddler.position = Vector3(0.0, 0.1, 0.05)
	add_child(_paddler)
	_build_paddler()

	_paddle = _build_paddle()
	_paddler.add_child(_paddle)
	_arm_l = _build_arm()
	_arm_l.name = "ArmL"
	_paddler.add_child(_arm_l)
	_arm_r = _build_arm()
	_arm_r.name = "ArmR"
	_paddler.add_child(_arm_r)


func _build_paddler() -> void:
	_add_capsule(_paddler, "Torso", 0.11, 0.36, Vector3(0.0, 0.2, 0.0), _color(Color(0.16, 0.4, 0.68), 0.6))
	_add_sphere(_paddler, "Head", 0.092, Vector3(0.0, 0.44, 0.02), _color(Color(0.9, 0.72, 0.55), 0.55))
	_add_sphere(_paddler, "Hair", 0.086, Vector3(0.0, 0.49, 0.045), _color(Color(0.16, 0.1, 0.07), 0.7))
	_add_capsule(_paddler, "ThighL", 0.05, 0.34, Vector3(-0.06, 0.0, -0.22), _color(Color(0.12, 0.16, 0.28), 0.7), Vector3(-84.0, 4.0, 7.0))
	_add_capsule(_paddler, "ThighR", 0.05, 0.34, Vector3(0.06, 0.0, -0.22), _color(Color(0.12, 0.16, 0.28), 0.7), Vector3(-84.0, -4.0, -7.0))
	_add_capsule(_paddler, "ShinL", 0.04, 0.3, Vector3(-0.07, -0.06, -0.5), _color(Color(0.9, 0.72, 0.55), 0.55), Vector3(-78.0, 0.0, 0.0))
	_add_capsule(_paddler, "ShinR", 0.04, 0.3, Vector3(0.07, -0.06, -0.5), _color(Color(0.9, 0.72, 0.55), 0.55), Vector3(-78.0, 0.0, 0.0))


func _build_paddle() -> Node3D:
	var root := Node3D.new()
	root.name = "Paddle"
	root.position = Vector3(0.0, 0.3, -0.1)

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.018
	shaft_mesh.bottom_radius = 0.018
	shaft_mesh.height = 1.05
	shaft.mesh = shaft_mesh
	shaft.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	shaft.material_override = _color(Color(0.55, 0.36, 0.16), 0.65)
	root.add_child(shaft)

	var blade_mat := _color(Color(0.93, 0.72, 0.18), 0.4)
	_add_blade(root, "BladeL", -0.64, blade_mat)
	_add_blade(root, "BladeR", 0.64, blade_mat)

	var hand_mat := _color(Color(0.9, 0.72, 0.55), 0.55)
	_add_sphere(root, "HandL", 0.045, _GRIP_L, hand_mat)
	_add_sphere(root, "HandR", 0.045, _GRIP_R, hand_mat)
	return root


func _add_blade(root: Node3D, blade_name: String, x: float, mat: Material) -> void:
	var blade := MeshInstance3D.new()
	blade.name = blade_name
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.025, 0.34)
	blade.mesh = box
	blade.position = Vector3(x, 0.0, 0.0)
	blade.material_override = mat
	root.add_child(blade)


func _build_arm() -> Node3D:
	var arm := Node3D.new()
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.04
	capsule.height = 1.0
	mesh.mesh = capsule
	mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mesh.material_override = _color(Color(0.16, 0.4, 0.68), 0.6)
	arm.add_child(mesh)
	return arm


func _add_capsule(parent: Node3D, node_name: String, radius: float, height: float, pos: Vector3, mat: Material, rot_degrees := Vector3.ZERO) -> void:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0 + 0.01)
	inst.mesh = capsule
	inst.position = pos
	inst.rotation_degrees = rot_degrees
	inst.material_override = mat
	parent.add_child(inst)


func _add_sphere(parent: Node3D, node_name: String, radius: float, pos: Vector3, mat: Material) -> void:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	inst.mesh = sphere
	inst.position = pos
	inst.material_override = mat
	parent.add_child(inst)


func _color(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat
