extends Node3D

const RiverScript := preload("res://scripts/river.gd")
const KayakScript := preload("res://scripts/kayak.gd")

var river
var kayak
var camera: Camera3D
var distance_label: Label
var _snap_camera := true


func _ready() -> void:
	_ensure_input()
	_setup_world()
	river = RiverScript.new()
	river.name = "River"
	add_child(river)
	kayak = KayakScript.new()
	kayak.name = "Kayak"
	kayak.river = river
	add_child(kayak)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.current = true
	camera.fov = 60.0
	add_child(camera)
	_setup_hud()
	_update_camera(0.0)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		kayak.reset()
		_snap_camera = true
	_update_camera(delta)
	distance_label.text = "Distance  %d m" % int(kayak.distance)


func _update_camera(delta: float) -> void:
	var frame = river.frame_at(kayak.distance)
	var tangent: Vector3 = frame.tangent
	var desired: Vector3 = kayak.global_position - tangent * 5.6 + Vector3.UP * 2.6
	if kayak.hit_cooldown > 0.35:
		desired += Vector3(sin(kayak.hit_cooldown * 70.0) * 0.12, 0.0, 0.0)
	if _snap_camera:
		camera.global_position = desired
		_snap_camera = false
	else:
		var blend := 1.0 - exp(-3.5 * delta)
		camera.global_position = camera.global_position.lerp(desired, blend)
	camera.look_at(kayak.global_position + tangent * 6.0 + Vector3.UP * 0.4, Vector3.UP)


func _setup_world() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.55, 0.86)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.86)
	sky_mat.ground_bottom_color = Color(0.16, 0.28, 0.14)
	sky_mat.ground_horizon_color = Color(0.5, 0.55, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.78, 0.86)
	env.fog_density = 0.0035
	env.fog_aerial_perspective = 0.35

	var world := WorldEnvironment.new()
	world.name = "World"
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46.0, 32.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	distance_label = Label.new()
	distance_label.name = "Distance"
	distance_label.position = Vector2(24, 18)
	distance_label.size = Vector2(420, 48)
	distance_label.text = "Distance  0 m"
	_style_label(distance_label, 32)
	layer.add_child(distance_label)

	var hint := Label.new()
	hint.name = "Hint"
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 0.0
	hint.offset_right = 0.0
	hint.offset_top = -56.0
	hint.offset_bottom = -16.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "A / D or Left / Right to steer     R to restart"
	_style_label(hint, 22)
	layer.add_child(hint)


func _style_label(label: Label, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))


func _ensure_input() -> void:
	_bind("steer_left", [KEY_A, KEY_LEFT])
	_bind("steer_right", [KEY_D, KEY_RIGHT])
	_bind("restart", [KEY_R])


func _bind(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
