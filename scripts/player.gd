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
var using_controller := false  # true while the last input came from a gamepad
var base_fov := 90.0
var camera: Camera3D
var head: Node3D
var weapon: Node3D
var abilities: Node

var _pitch := 0.0
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _can_glide := false
var _gliding := false
var _glide_left := 0.0
var _bob_time := 0.0
var _shake := 0.0  # 0..1 camera shake, decays on its own
var _shake_time := 0.0
var _lunge_velocity := Vector3.ZERO
var _lunge_left := 0.0  # seconds of lunge remaining


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

	abilities = preload("res://scripts/abilities.gd").new()
	abilities.player = self
	add_child(abilities)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	# Track the active device so aim assist only helps controller players.
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
		using_controller = true
	elif event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey:
		using_controller = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = mouse_sensitivity * _zoom_sensitivity()
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

	# A melee lunge takes over horizontal movement for its short burst.
	if _lunge_left > 0.0:
		_lunge_left -= delta
		velocity.x = _lunge_velocity.x
		velocity.z = _lunge_velocity.z
		if _lunge_left <= 0.0:
			velocity *= Vector3(0.15, 1.0, 0.15)  # stop at arm's length instead of sliding on

	move_and_slide()

	if position.y < -50.0:
		position = Vector3(0, 1, 5)
		velocity = Vector3.ZERO


func _process(delta: float) -> void:
	# Controller look on the right stick.
	var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() > 0.15:
		var rate: float = 3.0 * _zoom_sensitivity() * weapon.look_slowdown() * delta
		rotate_y(-look.x * rate)
		_pitch = clampf(_pitch - look.y * rate, deg_to_rad(-89), deg_to_rad(89))

	# Camera recoil recovers toward zero; the player's own aim stays where it was.
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, 1.0 - exp(-8.0 * delta))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, 1.0 - exp(-8.0 * delta))
	head.rotation.x = _pitch + _recoil_pitch
	head.rotation.y = _recoil_yaw

	# Shake: layered sines rather than random jumps, so it rumbles instead of jittering.
	_shake = maxf(_shake - delta * 1.8, 0.0)
	_shake_time += delta
	var k := _shake * _shake * 0.035
	head.rotation.x += sin(_shake_time * 41.0) * k
	head.rotation.y += sin(_shake_time * 37.0 + 1.3) * k
	head.rotation.z = sin(_shake_time * 29.0 + 2.1) * k * 0.6

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat_speed > 0.5:
		_bob_time += delta * flat_speed * 1.6
	head.position.y = EYE_HEIGHT + sin(_bob_time * 2.0) * 0.025 * minf(flat_speed / WALK_SPEED, 1.5)

	var target_fov := base_fov
	if weapon.is_aiming():
		target_fov = base_fov * weapon.zoom()
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


## Kicks the camera. Most of it springs back; `keep` is the share that stays in your
## aim, so long strings climb and need pulling down, like Destiny's vertical recoil.
func add_recoil(pitch: float, yaw: float, keep := 0.35) -> void:
	_recoil_pitch += pitch * (1.0 - keep)
	_recoil_yaw += yaw * (1.0 - keep)
	_pitch = clampf(_pitch + pitch * keep, deg_to_rad(-89), deg_to_rad(89))
	rotate_y(yaw * keep)


func add_shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.0)


## Drives the player along `vel` (horizontal) for `duration` seconds.
func lunge(vel: Vector3, duration: float) -> void:
	_lunge_velocity = vel
	_lunge_left = duration


## Look speed follows the zoom, so tracking feels the same at any FOV.
func _zoom_sensitivity() -> float:
	return camera.fov / base_fov


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
		"weapon_1": [KEY_1],
		"weapon_2": [KEY_2],
		"weapon_3": [KEY_3],
		"melee": [KEY_F],
		"grenade": [KEY_Q],
	}
	var pads := {
		"jump": JOY_BUTTON_A,
		"sprint": JOY_BUTTON_LEFT_STICK,
		"reload": JOY_BUTTON_X,
		"melee": JOY_BUTTON_RIGHT_SHOULDER,
		"grenade": JOY_BUTTON_LEFT_SHOULDER,
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
	# Melee also sits on the mouse's back thumb button.
	var thumb := InputEventMouseButton.new()
	thumb.button_index = MOUSE_BUTTON_XBUTTON1
	InputMap.action_add_event("melee", thumb)
	# Cycling: mouse wheel, and Y on a controller.
	var cycle := {
		"next_weapon": [MOUSE_BUTTON_WHEEL_DOWN, JOY_BUTTON_Y],
		"prev_weapon": [MOUSE_BUTTON_WHEEL_UP, -1],
	}
	for action in cycle:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var wheel := InputEventMouseButton.new()
		wheel.button_index = cycle[action][0]
		InputMap.action_add_event(action, wheel)
		if cycle[action][1] >= 0:
			var jb := InputEventJoypadButton.new()
			jb.button_index = cycle[action][1]
			InputMap.action_add_event(action, jb)
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
