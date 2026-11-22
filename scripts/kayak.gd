extends Node3D

const CRUISE_SPEED := 12.0
const STEER_ACCEL := 3.2
const LATERAL_DAMP := 2.0
const MAX_LATERAL := 0.86
const HIT_COOLDOWN := 0.6

var river
var distance := 0.0
var lateral := 0.0
var lateral_vel := 0.0
var speed := CRUISE_SPEED
var hit_cooldown := 0.0

var _bob := 0.0


func _ready() -> void:
	_build_hull()
	river.update_chunks(distance)
	_apply_pose()


func _physics_process(delta: float) -> void:
	var steer := 0.0
	if Input.is_action_pressed("steer_left"):
		steer -= 1.0
	if Input.is_action_pressed("steer_right"):
		steer += 1.0

	lateral_vel += steer * STEER_ACCEL * delta
	lateral_vel = move_toward(lateral_vel, 0.0, LATERAL_DAMP * delta)
	lateral += lateral_vel * delta
	if lateral > MAX_LATERAL or lateral < -MAX_LATERAL:
		lateral = clampf(lateral, -MAX_LATERAL, MAX_LATERAL)
		lateral_vel = 0.0

	speed = move_toward(speed, CRUISE_SPEED, 4.0 * delta)
	distance += speed * delta
	_bob += delta

	river.update_chunks(distance)
	if hit_cooldown > 0.0:
		hit_cooldown -= delta
	else:
		_check_rocks()
	_apply_pose()


func reset() -> void:
	distance = 0.0
	lateral = 0.0
	lateral_vel = 0.0
	speed = CRUISE_SPEED
	hit_cooldown = 0.0
	_bob = 0.0
	river.update_chunks(distance)
	_apply_pose()


func _check_rocks() -> void:
	var half_width: float = river.HALF_WIDTH
	for rock in river.get_rocks_near(distance):
		var along := distance - float(rock["s"])
		var reach: float = float(rock["radius"]) + 0.85
		if abs(along) > reach:
			continue
		var across := (lateral - float(rock["lateral"])) * half_width
		if along * along + across * across > reach * reach:
			continue
		var away := signf(lateral - float(rock["lateral"]))
		if away == 0.0:
			away = 1.0
		lateral_vel = away * 3.6
		lateral = clampf(lateral + away * 0.06, -MAX_LATERAL, MAX_LATERAL)
		speed *= 0.4
		hit_cooldown = HIT_COOLDOWN
		return


func _apply_pose() -> void:
	var frame = river.frame_at(distance)
	var half_width: float = river.HALF_WIDTH
	var pos: Vector3 = frame.center + frame.right * lateral * half_width
	pos.y = 0.22 + sin(_bob * 2.4) * 0.045
	var basis: Basis = Basis.looking_at(frame.tangent, Vector3.UP)
	var roll := clampf(-lateral_vel * 0.4, -0.4, 0.4)
	basis = basis.rotated(frame.tangent, roll)
	global_transform = Transform3D(basis, pos)


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
	var cockpit_mesh := SphereMesh.new()
	cockpit_mesh.radius = 0.2
	cockpit_mesh.height = 0.26
	cockpit.mesh = cockpit_mesh
	cockpit.position = Vector3(0.0, 0.16, 0.12)
	cockpit.material_override = _color(Color(0.12, 0.14, 0.16), 0.6)
	add_child(cockpit)

	var paddle := MeshInstance3D.new()
	var paddle_mesh := CylinderMesh.new()
	paddle_mesh.top_radius = 0.025
	paddle_mesh.bottom_radius = 0.025
	paddle_mesh.height = 1.55
	paddle.mesh = paddle_mesh
	paddle.rotation_degrees = Vector3(0.0, 0.0, 78.0)
	paddle.position = Vector3(0.12, 0.28, -0.2)
	paddle.material_override = _color(Color(0.55, 0.36, 0.16), 0.7)
	add_child(paddle)


func _color(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat
