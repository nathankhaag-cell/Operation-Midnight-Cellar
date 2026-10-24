extends CharacterBody3D
## First-person player: movement, mouse look, jump and glide, FOV, camera recoil.

const WALK_SPEED := 5.5
const SPRINT_SPEED := 8.5
const ADS_SPEED := 3.5
const ACCEL := 12.0
const AIR_ACCEL := 4.0
const JUMP_VELOCITY := 5.2
const GRAVITY := 14.0
const GLIDE_GRAVITY := 2.5
const GLIDE_LIFT := 1.2
const GLIDE_FUEL := 1.4  # seconds of glide per airtime
const EYE_HEIGHT := 1.65

var mouse_sensitivity := 0.0022
var base_fov := 90.0
var camera: Camera3D
var head: Node3D
var weapon: Node3D

var _pitch := 0.0
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _can_glide := false
var _gliding := false
var _glide_left := 0.0
var _bob_time := 0.0


func _ready() -> void:
	_ensure_input_actions()

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)

	camera = Camera3D.new()
	camera.fov = base_fov
	camera.near = 0.02
	camera.current = true
	head.add_child(camera)

	weapon = preload("res://scripts/weapon.gd").new()
	weapon.player = self
	camera.add_child(weapon)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * (0.55 if weapon.is_aiming() else 1.0)
		rotate_y(-event.relative.x * sens)
		weapon.add_sway(event.relative)
		_pitch = clampf(_pitch - event.relative.y * sens, deg_to_rad(-89), deg_to_rad(89))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fov_up"):
		base_fov = min(base_fov + 5.0, 110.0)
	elif event.is_action_pressed("fov_down"):
		base_fov = max(base_fov - 5.0, 60.0)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var sprinting := is_sprinting()
	var speed := WALK_SPEED
	if weapon.is_aiming():
		speed = ADS_SPEED
	elif sprinting:
		speed = SPRINT_SPEED

	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = lerpf(velocity.x, dir.x * speed, 1.0 - exp(-accel * delta))
	velocity.z = lerpf(velocity.z, dir.z * speed, 1.0 - exp(-accel * delta))

	if is_on_floor():
		_can_glide = true
		_gliding = false
		_glide_left = GLIDE_FUEL
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		# Second press in the air starts a glide; holding jump keeps it going.
		if Input.is_action_just_pressed("jump") and _can_glide:
			_gliding = true
			_can_glide = false
			velocity.y = max(velocity.y, 1.5)
		if _gliding and (not Input.is_action_pressed("jump") or _glide_left <= 0.0):
			_gliding = false
		if _gliding:
			_glide_left -= delta
			velocity.y += (GLIDE_LIFT - GLIDE_GRAVITY) * delta
			velocity.y = clamp(velocity.y, -1.5, 3.0)
		else:
			velocity.y -= GRAVITY * delta

	move_and_slide()

	if position.y < -50.0:
		position = Vector3(0, 1, 5)
		velocity = Vector3.ZERO


func _process(delta: float) -> void:
	# Controller look on the right stick.
	var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() > 0.15:
		var rate := 3.0 * (0.5 if weapon.is_aiming() else 1.0) * delta
		rotate_y(-look.x * rate)
		_pitch = clampf(_pitch - look.y * rate, deg_to_rad(-89), deg_to_rad(89))

	# Camera recoil recovers toward zero; the player's own aim stays where it was.
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, 1.0 - exp(-8.0 * delta))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, 1.0 - exp(-8.0 * delta))
	head.rotation.x = _pitch + _recoil_pitch
	head.rotation.y = _recoil_yaw

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat_speed > 0.5:
		_bob_time += delta * flat_speed * 1.6
	head.position.y = EYE_HEIGHT + sin(_bob_time * 2.0) * 0.025 * minf(flat_speed / WALK_SPEED, 1.5)

	var target_fov := base_fov
	if weapon.is_aiming():
		target_fov = base_fov * 0.72
	elif is_sprinting() and flat_speed > 1.0:
		target_fov = base_fov + 6.0
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-12.0 * delta))


func is_sprinting() -> bool:
	return Input.is_action_pressed("sprint") and Input.is_action_pressed("move_forward") \
		and is_on_floor() and not weapon.is_aiming()


func is_gliding() -> bool:
	return _gliding


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func add_recoil(pitch: float, yaw: float) -> void:
	_recoil_pitch += pitch
	_recoil_yaw += yaw
	# Part of the kick sticks, like Destiny's vertical recoil.
	_pitch = clampf(_pitch + pitch * 0.35, deg_to_rad(-89), deg_to_rad(89))


static func _ensure_input_actions() -> void:
	var keys := {
		"move_forward": [KEY_W],
		"move_back": [KEY_S],
		"move_left": [KEY_A],
		"move_right": [KEY_D],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"reload": [KEY_R],
		"fov_up": [KEY_BRACKETRIGHT],
		"fov_down": [KEY_BRACKETLEFT],
	}
	var pads := {
		"jump": JOY_BUTTON_A,
		"sprint": JOY_BUTTON_LEFT_STICK,
		"reload": JOY_BUTTON_X,
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		if pads.has(action):
			var jb := InputEventJoypadButton.new()
			jb.button_index = pads[action]
			InputMap.action_add_event(action, jb)
	var axes := {
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
		"move_back": [JOY_AXIS_LEFT_Y, 1.0],
		"move_left": [JOY_AXIS_LEFT_X, -1.0],
		"move_right": [JOY_AXIS_LEFT_X, 1.0],
	}
	for action in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axes[action][0]
		jm.axis_value = axes[action][1]
		InputMap.action_add_event(action, jm)
	for action in ["fire", "aim"]:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT if action == "fire" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action, mb)
		var trig := InputEventJoypadMotion.new()
		trig.axis = JOY_AXIS_TRIGGER_RIGHT if action == "fire" else JOY_AXIS_TRIGGER_LEFT
		trig.axis_value = 1.0
		InputMap.action_add_event(action, trig)
