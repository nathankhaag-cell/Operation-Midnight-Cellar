extends Node3D
## First-person auto rifle. The viewmodel is built from boxes, and every animation
## (bob, sway, sprint, aim, recoil, reload, landing) is procedural so it needs no assets.

const FIRE_INTERVAL := 0.1  # 600 rounds per minute
const MAG_SIZE := 32
const RELOAD_TIME := 1.8
const RANGE := 200.0
const MODEL_SCALE := 0.6
const HIP_SPREAD := 1.2  # degrees
const ADS_SPREAD := 0.15

const HIP_POS := Vector3(0.17, -0.165, -0.38)
const ADS_POS := Vector3(0.0, -0.0462, -0.24)  # front post on screen centre
const SPRINT_POS := Vector3(0.11, -0.21, -0.33)
const SPRINT_ROT := Vector3(-0.25, 0.75, 0.35)

var player: CharacterBody3D
var ammo := MAG_SIZE

var _rig: Node3D  # moved by the animation code
var _model: Node3D
var _mag: Node3D
var _muzzle: Node3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D

var _cooldown := 0.0
var _flash_time := 0.0
var _ads_t := 0.0
var _sprint_t := 0.0
var _reload_t := -1.0  # < 0 when not reloading, else seconds elapsed
var _bob := 0.0
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _kick := 0.0  # 0..1 recoil impulse
var _kick_roll := 0.0
var _land_dip := 0.0
var _was_on_floor := true
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	_model = Node3D.new()
	_model.scale = Vector3.ONE * MODEL_SCALE
	_rig.add_child(_model)
	_build_model()
	_rig.position = HIP_POS


func is_aiming() -> bool:
	return Input.is_action_pressed("aim") and _reload_t < 0.0 and not player.is_sprinting()


func is_reloading() -> bool:
	return _reload_t >= 0.0


func add_sway(mouse_delta: Vector2) -> void:
	_sway_target += mouse_delta * 0.0009


func _process(delta: float) -> void:
	_time += delta
	_cooldown -= delta
	_handle_actions(delta)
	_animate(delta)


func _handle_actions(delta: float) -> void:
	if _reload_t >= 0.0:
		_reload_t += delta
		if _reload_t >= RELOAD_TIME:
			_reload_t = -1.0
			ammo = MAG_SIZE
			_hud_call("set_ammo", [ammo, MAG_SIZE])
		return

	if Input.is_action_just_pressed("reload") and ammo < MAG_SIZE:
		_start_reload()
		return

	var wants_fire := Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if wants_fire and _cooldown <= 0.0:
		if player.is_sprinting():
			return  # sprinting lowers the gun; the shot waits until it comes back up
		if ammo <= 0:
			_start_reload()
			return
		_fire()


func _start_reload() -> void:
	_reload_t = 0.0


func _fire() -> void:
	_cooldown = FIRE_INTERVAL
	ammo -= 1
	_hud_call("set_ammo", [ammo, MAG_SIZE])

	# Visual and camera recoil.
	_kick = min(_kick + 0.55, 1.0)
	_kick_roll = _rng.randf_range(-1.0, 1.0)
	var ads_scale := lerpf(1.0, 0.55, _ads_t)
	player.add_recoil(deg_to_rad(_rng.randf_range(0.5, 0.9)) * ads_scale, deg_to_rad(_rng.randf_range(-0.35, 0.35)) * ads_scale)

	_flash_time = 0.045
	_flash.visible = true
	_flash_light.visible = true
	_flash.rotation.z = _rng.randf() * TAU
	var s := _rng.randf_range(0.8, 1.3)
	_flash.scale = Vector3(s, s, 1.0)

	# Hitscan from the screen centre with spread.
	var cam := get_viewport().get_camera_3d()
	var spread: float = deg_to_rad(lerpf(HIP_SPREAD, ADS_SPREAD, _ads_t) + player.horizontal_speed() * 0.12 * (1.0 - _ads_t))
	var dir := -cam.global_transform.basis.z
	dir = dir.rotated(cam.global_transform.basis.x, _rng.randf_range(-spread, spread))
	dir = dir.rotated(cam.global_transform.basis.y, _rng.randf_range(-spread, spread))
	var from := cam.global_position
	var to := from + dir * RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := to
	if hit:
		end = hit.position
		_spawn_impact(hit.position, hit.normal)
		var target: Object = hit.collider
		if target and not target.has_method("hit"):
			target = target.get_parent()  # targets take hits on their parent node
		if target and target.has_method("hit"):
			var crit: bool = target.hit(hit.position, dir)
			_hud_call("show_hitmarker", [crit])
	_spawn_tracer(_muzzle.global_position, end)


func _animate(delta: float) -> void:
	var on_floor := player.is_on_floor()
	if on_floor and not _was_on_floor:
		_land_dip = min(_land_dip + 0.6, 1.0)
	_was_on_floor = on_floor

	_ads_t = move_toward(_ads_t, 1.0 if is_aiming() else 0.0, delta / 0.16)
	var sprint_target := 1.0 if (player.is_sprinting() and player.horizontal_speed() > 1.0 and _reload_t < 0.0) else 0.0
	_sprint_t = move_toward(_sprint_t, sprint_target, delta / 0.2)
	var ads_e := _ease(_ads_t)
	var sprint_e := _ease(_sprint_t)

	var speed: float = player.horizontal_speed() if on_floor else 0.0
	_bob += delta * speed * (1.9 if sprint_t_active() else 1.5)
	var bob_amt := clampf(speed / 5.5, 0.0, 1.6) * lerpf(1.0, 0.15, ads_e)
	var bob := Vector3(sin(_bob) * 0.012, -absf(cos(_bob)) * 0.012, 0.0) * bob_amt
	var breathe := Vector3(0, sin(_time * 1.6) * 0.0025, 0) * (1.0 - ads_e * 0.8)

	# Sway lags behind the mouse and springs back.
	_sway_target = _sway_target.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta))
	_sway = _sway.lerp(_sway_target, 1.0 - exp(-14.0 * delta))
	_sway = _sway.clamp(Vector2(-0.08, -0.08), Vector2(0.08, 0.08))
	var sway_scale := lerpf(1.0, 0.25, ads_e)

	_kick = lerpf(_kick, 0.0, 1.0 - exp(-14.0 * delta))
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-7.0 * delta))

	var pos := HIP_POS.lerp(ADS_POS, ads_e).lerp(SPRINT_POS, sprint_e)
	pos += bob + breathe
	pos += Vector3(-_sway.x * 0.25, _sway.y * 0.25, 0) * sway_scale
	pos.z += _kick * lerpf(0.045, 0.025, ads_e)
	pos.y -= _land_dip * 0.04
	if player.is_gliding():
		pos.y -= 0.03

	var rot := SPRINT_ROT * sprint_e
	rot.x += _kick * lerpf(0.09, 0.03, ads_e)
	rot.z += _kick * _kick_roll * 0.04
	rot.y += -_sway.x * 0.8 * sway_scale
	rot.x += -_sway.y * 0.8 * sway_scale
	rot.z += -_sway.x * 1.2 * sway_scale
	rot.z += sin(_bob) * 0.02 * bob_amt

	# Reload: tilt the gun, drop the old mag out, bring a new one up, then a little shake.
	var mag_offset := Vector3.ZERO
	if _reload_t >= 0.0:
		var p := _reload_t / RELOAD_TIME
		var tilt := _ease(clampf(p / 0.2, 0.0, 1.0)) * (1.0 - _ease(clampf((p - 0.8) / 0.2, 0.0, 1.0)))
		rot += Vector3(0.25, -0.35, 0.6) * tilt
		pos += Vector3(-0.03, -0.04, 0.02) * tilt
		if p > 0.15 and p < 0.4:
			mag_offset.y = -_ease((p - 0.15) / 0.25) * 0.35
		elif p >= 0.4 and p < 0.65:
			mag_offset.y = -(1.0 - _ease((p - 0.4) / 0.25)) * 0.35
		if p > 0.62 and p < 0.72:
			pos.y += sin((p - 0.62) / 0.1 * PI) * 0.015  # mag seat bump
		_mag.visible = not (p > 0.38 and p < 0.42)
	_mag.position = Vector3(0, -0.06, -0.04) + mag_offset

	_rig.position = pos
	_rig.rotation = rot

	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_flash.visible = false
			_flash_light.visible = false


func sprint_t_active() -> bool:
	return _sprint_t > 0.5


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _hud_call(method: String, args: Array) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.callv(method, args)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, length)
	tracer.mesh = mesh
	tracer.material_override = _emissive(Color(1.0, 0.8, 0.45), 6.0)
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(tracer)
	tracer.look_at_from_position((from + to) * 0.5, to)
	var tw := tracer.create_tween()
	tw.tween_property(tracer, "scale", Vector3(0.1, 0.1, 1.0), 0.06)
	tw.tween_callback(tracer.queue_free)


func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.amount = 10
	sparks.lifetime = 0.35
	sparks.explosiveness = 1.0
	sparks.direction = Vector3(0, 0, 1)
	sparks.spread = 50.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.gravity = Vector3(0, -9.8, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.02, 0.02)
	mesh.material = _emissive(Color(1.0, 0.7, 0.3), 4.0)
	sparks.mesh = mesh
	get_tree().current_scene.add_child(sparks)
	sparks.global_position = point + normal * 0.02
	if absf(normal.dot(Vector3.UP)) < 0.99:
		sparks.look_at(point + normal, Vector3.UP)
	else:
		sparks.look_at(point + normal, Vector3.FORWARD)
	sparks.rotate_object_local(Vector3.UP, PI)  # emit along +Z toward the normal
	sparks.emitting = true

	var mark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	mark.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark.material_override = mat
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mark)
	mark.global_position = point + normal * 0.005
	if absf(normal.dot(Vector3.UP)) < 0.99:
		mark.look_at(point - normal, Vector3.UP)
	else:
		mark.look_at(point - normal, Vector3.FORWARD)

	get_tree().create_timer(1.0).timeout.connect(sparks.queue_free)
	get_tree().create_timer(8.0).timeout.connect(mark.queue_free)


func _build_model() -> void:
	var dark := Color(0.13, 0.14, 0.16)
	var metal := Color(0.42, 0.44, 0.47)
	var accent := Color(0.85, 0.55, 0.2)
	var sleeve := Color(0.22, 0.27, 0.33)
	var glove := Color(0.1, 0.1, 0.11)

	_part(Vector3(0.06, 0.08, 0.34), Vector3(0, 0, 0), metal)  # receiver
	_part(Vector3(0.045, 0.05, 0.26), Vector3(0, 0.005, -0.28), dark)  # handguard
	_part(Vector3(0.022, 0.022, 0.16), Vector3(0, 0.01, -0.48), dark)  # barrel
	_part(Vector3(0.035, 0.035, 0.05), Vector3(0, 0.01, -0.57), metal)  # muzzle brake
	_part(Vector3(0.05, 0.07, 0.2), Vector3(0, -0.015, 0.25), dark)  # stock
	_part(Vector3(0.04, 0.09, 0.05), Vector3(0, -0.075, 0.1), dark)  # grip
	_part(Vector3(0.062, 0.012, 0.12), Vector3(0, 0.025, 0.06), accent)  # side stripe
	# Sight: a rear ring and a front post line up on the screen centre when aiming.
	_part(Vector3(0.05, 0.012, 0.1), Vector3(0, 0.046, 0.02), dark)
	_part(Vector3(0.01, 0.03, 0.02), Vector3(-0.02, 0.066, 0.05), dark)
	_part(Vector3(0.01, 0.03, 0.02), Vector3(0.02, 0.066, 0.05), dark)
	_part(Vector3(0.006, 0.026, 0.01), Vector3(0, 0.058, -0.07), dark)
	_part(Vector3(0.008, 0.012, 0.01), Vector3(0, 0.077, -0.07), _emissive(Color(1.0, 0.25, 0.15), 3.0))

	_mag = Node3D.new()
	_model.add_child(_mag)
	_part(Vector3(0.04, 0.14, 0.06), Vector3(0, -0.07, 0), dark, _mag)

	# Arms: the right hand on the grip, the left under the handguard.
	_part(Vector3(0.06, 0.06, 0.3), Vector3(0.03, -0.12, 0.28), sleeve).rotation = Vector3(0.35, -0.15, 0)
	_part(Vector3(0.055, 0.06, 0.07), Vector3(0.0, -0.08, 0.12), glove)
	_part(Vector3(0.06, 0.06, 0.32), Vector3(-0.09, -0.1, -0.08), sleeve).rotation = Vector3(0.3, 0.55, 0)
	_part(Vector3(0.06, 0.05, 0.08), Vector3(-0.01, -0.04, -0.26), glove)

	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.01, -0.61)
	_model.add_child(_muzzle)
	_flash = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	_flash.mesh = quad
	var fmat := _emissive(Color(1.0, 0.75, 0.35), 8.0)
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.no_depth_test = true
	_flash.material_override = fmat
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.light_energy = 3.0
	_flash_light.omni_range = 4.0
	_flash_light.visible = false
	_muzzle.add_child(_flash_light)


func _part(size: Vector3, pos: Vector3, color_or_mat, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	if color_or_mat is Material:
		mi.material_override = color_or_mat
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color_or_mat
		mat.roughness = 0.55
		mat.metallic = 0.3
		mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else _model).add_child(mi)
	return mi


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
