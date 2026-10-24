extends Node3D
## First-person weapons. Carries the archetypes from weapon_data.gd, one per slot, and
## switches between them with a lower-and-raise. The viewmodels are built from boxes and
## every animation (bob, sway, sprint, aim, recoil, reload, switch, landing) is procedural,
## so it needs no assets.

const Data := preload("res://scripts/weapon_data.gd")
const Combat := preload("res://scripts/combat.gd")

const RANGE := 200.0
const MODEL_SCALE := 0.6
const LOWER_TIME := 0.15
const RAISE_TIME := 0.2
const FIRE_BUFFER := 0.18  # a semi-auto pull this early still fires when the gun is ready

# Controller aim assist: shots inside this cone bend toward a target, and the look
# speed drops inside the wider one. Both grow a little when aiming down sights.
const MAGNET_CONE := 1.6  # degrees
const MAGNET_PULL := 0.7
const SLOWDOWN_CONE := 4.0
const SLOWDOWN := 0.55

const HIP_POS := Vector3(0.17, -0.165, -0.38)
const ADS_POS := Vector3(0.0, -0.0462, -0.24)  # the model's sight line (y = 0.077) on screen centre at any z
const SPRINT_POS := Vector3(0.11, -0.21, -0.33)
const SPRINT_ROT := Vector3(-0.25, 0.75, 0.35)
const SIGHT_Y := 0.077

var player: CharacterBody3D
var slot := 0
var stats: Dictionary = Data.ARCHETYPES[Data.ORDER[0]]
var mags := {}  # rounds left in each archetype's magazine

var _rig: Node3D  # moved by the animation code
var _model: Node3D
var _mag: Node3D
var _muzzle: Node3D
var _flash: MeshInstance3D
var _flash_light: OmniLight3D

var _cooldown := 0.0
var _fire_buffer := 0.0
var _flash_time := 0.0
var _ads_t := 0.0
var _sprint_t := 0.0
var _reload_t := -1.0  # < 0 when not reloading, else seconds elapsed
var _switch_t := -1.0  # < 0 when not switching, else seconds into lower-and-raise
var _next_slot := 0
var _bloom := 0.0
var _bob := 0.0
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _kick := 0.0  # 0..1 recoil impulse
var _kick_roll := 0.0
var _land_dip := 0.0
var _was_on_floor := true
var _time := 0.0
var _over_target := false
var _assist_angle := 180.0  # degrees from the reticle to the nearest target point
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for id in Data.ORDER:
		mags[id] = Data.ARCHETYPES[id]["mag"]
	_rig = Node3D.new()
	add_child(_rig)
	_model = Node3D.new()
	_model.scale = Vector3.ONE * MODEL_SCALE
	_rig.add_child(_model)
	_equip(0)
	_rig.position = HIP_POS


# --- state other scripts read -------------------------------------------------

func current_id() -> String:
	return Data.ORDER[slot]


func ammo() -> int:
	return mags[current_id()]


func is_aiming() -> bool:
	return Input.is_action_pressed("aim") and _reload_t < 0.0 and _switch_t < 0.0


func is_reloading() -> bool:
	return _reload_t >= 0.0


func aim_blend() -> float:
	return _ease(_ads_t)


func zoom() -> float:
	return stats["zoom"]


## Current cone half-angle in degrees, for shots and the reticle.
func spread_degrees() -> float:
	var move: float = player.horizontal_speed() * 0.12 * (1.0 - _ads_t)
	var air := 0.0 if player.is_on_floor() else 1.5 * (1.0 - _ads_t)
	var base: float = lerpf(stats["hip_spread"], stats["ads_spread"], _ads_t)
	return base + move + air + _bloom * lerpf(1.0, 0.35, _ads_t)


## True when the reticle sits on a live target inside the weapon's range.
func is_over_target() -> bool:
	return _over_target


## Look-speed multiplier for controller slowdown (1.0 when nothing is near).
func look_slowdown() -> float:
	if not player.using_controller:
		return 1.0
	var cone := SLOWDOWN_CONE * lerpf(1.0, 1.4, _ads_t)
	if _assist_angle >= cone:
		return 1.0
	return lerpf(SLOWDOWN, 1.0, _assist_angle / cone)


func add_sway(mouse_delta: Vector2) -> void:
	_sway_target += mouse_delta * 0.0009


# --- input and firing ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Wheel and controller cycling come through events so a wheel notch never gets lost.
	if event.is_action_pressed("next_weapon"):
		switch_to((target_slot() + 1) % Data.ORDER.size())
	elif event.is_action_pressed("prev_weapon"):
		switch_to((target_slot() - 1 + Data.ORDER.size()) % Data.ORDER.size())


func switch_to(new_slot: int) -> void:
	if new_slot == target_slot():
		return
	_next_slot = new_slot
	_reload_t = -1.0
	if _switch_t < 0.0:
		_switch_t = 0.0
	elif _switch_t > LOWER_TIME:
		# Already raising another gun: drop it again from where it is.
		_switch_t = LOWER_TIME - (_switch_t - LOWER_TIME) * LOWER_TIME / RAISE_TIME


func target_slot() -> int:
	return _next_slot if _switch_t >= 0.0 else slot


func _process(delta: float) -> void:
	_time += delta
	_cooldown -= delta
	_fire_buffer -= delta
	_bloom = lerpf(_bloom, 0.0, 1.0 - exp(-5.0 * delta))
	_handle_actions(delta)
	_update_target_info()
	_animate(delta)


func _handle_actions(delta: float) -> void:
	for i in Data.ORDER.size():
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			switch_to(i)

	if _switch_t >= 0.0:
		var before := _switch_t
		_switch_t += delta
		if before < LOWER_TIME and _switch_t >= LOWER_TIME:
			_equip(_next_slot)
		if _switch_t >= LOWER_TIME + RAISE_TIME:
			_switch_t = -1.0
		return

	if _reload_t >= 0.0:
		_reload_t += delta
		if _reload_t >= stats["reload"]:
			_reload_t = -1.0
			mags[current_id()] = stats["mag"]
		return

	if Input.is_action_just_pressed("reload") and ammo() < stats["mag"]:
		_reload_t = 0.0
		return

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured and Input.is_action_just_pressed("fire"):
		_fire_buffer = FIRE_BUFFER
	var wants_fire := false
	if stats["mode"] == "auto":
		wants_fire = captured and Input.is_action_pressed("fire")
	else:
		wants_fire = _fire_buffer > 0.0
	if wants_fire and _cooldown <= 0.0:
		if player.is_sprinting():
			return  # sprinting lowers the gun; the shot waits until it comes back up
		_fire_buffer = 0.0
		if ammo() <= 0:
			_reload_t = 0.0
			return
		_fire()


func _fire() -> void:
	_cooldown = 60.0 / stats["rpm"]
	mags[current_id()] -= 1

	# Visual and camera recoil. Most of the camera kick recovers on its own.
	_kick = minf(_kick + stats["kick"], 1.0)
	_kick_roll = _rng.randf_range(-1.0, 1.0)
	var ads_scale := lerpf(1.0, 0.6, _ads_t)
	var rv: Array = stats["recoil_v"]
	var rh: Array = stats["recoil_h"]
	player.add_recoil(deg_to_rad(_rng.randf_range(rv[0], rv[1])) * ads_scale,
		deg_to_rad(_rng.randf_range(rh[0], rh[1])) * ads_scale, stats["recoil_keep"])

	_flash_time = 0.045
	_flash.visible = true
	_flash_light.visible = true
	_flash.rotation.z = _rng.randf() * TAU
	var s := _rng.randf_range(0.8, 1.3) * (1.4 if current_id() == "hand_cannon" else 1.0)
	_flash.scale = Vector3(s, s, 1.0)

	# Hitscan from the screen centre, spread inside a cone.
	var cam := get_viewport().get_camera_3d()
	var spread := deg_to_rad(spread_degrees())
	var forward := -cam.global_transform.basis.z
	var r := spread * sqrt(_rng.randf())
	var a := _rng.randf() * TAU
	var dir := forward.rotated(cam.global_transform.basis.x, r * sin(a))
	dir = dir.rotated(cam.global_transform.basis.y, r * cos(a)).normalized()
	_bloom = minf(_bloom + stats["bloom"], stats["bloom_max"])
	if player.using_controller:
		dir = _magnetise(cam.global_position, dir)

	var from := cam.global_position
	var to := from + dir * RANGE
	var hit := _ray(from, to)
	var end := to
	if hit:
		end = hit.position
		_spawn_impact(hit.position, hit.normal)
		var target := Combat.find_damageable(hit.collider)
		if target:
			var dist := from.distance_to(hit.position)
			var result: Dictionary = target.take_hit(hit.position, stats["damage"] * _falloff(dist), stats["crit"])
			if result["dealt"] > 0.0:
				Combat.feedback(self, target, hit.position, result["dealt"], result["crit"], result["killed"])
	_spawn_tracer(_muzzle.global_position, end)


func _falloff(dist: float) -> float:
	var f: Array = stats["falloff"]
	var t := clampf((dist - f[0]) / (f[1] - f[0]), 0.0, 1.0)
	return lerpf(1.0, stats["falloff_min"], t)


## Bullet magnetism: a shot that lands just off a target bends most of the way onto it.
## The head is preferred when both are inside the cone.
func _magnetise(from: Vector3, dir: Vector3) -> Vector3:
	var cone := deg_to_rad(MAGNET_CONE * lerpf(1.0, 1.5, _ads_t))
	var best := Vector3.ZERO
	var best_angle := cone
	for target in get_tree().get_nodes_in_group("damageable"):
		if not target.is_alive():
			continue
		var points: Array[Vector3] = target.aim_points()
		for i in points.size():
			var to_point: Vector3 = points[i] - from
			if to_point.length() > stats["falloff"][1]:
				continue
			var angle := dir.angle_to(to_point.normalized())
			if i == 1:
				angle *= 0.8  # a head inside the cone beats a body
			if angle < best_angle and _line_clear(from, points[i], target):
				best_angle = angle
				best = to_point.normalized()
	if best == Vector3.ZERO:
		return dir
	return dir.slerp(best, MAGNET_PULL).normalized()


func _line_clear(from: Vector3, to: Vector3, target: Node) -> bool:
	var hit := _ray(from, to)
	return hit.is_empty() or Combat.find_damageable(hit.collider) == target


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## Works out whether the reticle is on a target (for the red reticle) and how close
## the nearest target point is (for controller slowdown).
func _update_target_info() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var forward := -cam.global_transform.basis.z
	var reach: float = stats["falloff"][1] * 1.25
	var hit := _ray(from, from + forward * reach)
	var target: Node = null
	if hit:
		target = Combat.find_damageable(hit.collider)
	_over_target = target != null and target.is_alive()

	_assist_angle = 180.0
	if not player.using_controller:
		return
	for t in get_tree().get_nodes_in_group("damageable"):
		if not t.is_alive():
			continue
		for p in t.aim_points():
			var to_point: Vector3 = p - from
			if to_point.length() < reach:
				_assist_angle = minf(_assist_angle, rad_to_deg(forward.angle_to(to_point.normalized())))


# --- animation ----------------------------------------------------------------

func _animate(delta: float) -> void:
	var on_floor := player.is_on_floor()
	if on_floor and not _was_on_floor:
		_land_dip = minf(_land_dip + 0.6, 1.0)
	_was_on_floor = on_floor

	_ads_t = move_toward(_ads_t, 1.0 if is_aiming() else 0.0, delta / stats["ads_time"])
	var sprint_target := 1.0 if (player.is_sprinting() and player.horizontal_speed() > 1.0 and _reload_t < 0.0) else 0.0
	_sprint_t = move_toward(_sprint_t, sprint_target, delta / 0.2)
	var ads_e := _ease(_ads_t)
	var sprint_e := _ease(_sprint_t)

	var speed: float = player.horizontal_speed() if on_floor else 0.0
	_bob += delta * speed * (1.9 if _sprint_t > 0.5 else 1.5)
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

	var ads_pos := Vector3(ADS_POS.x, ADS_POS.y, stats["ads_z"])
	var pos := HIP_POS.lerp(ads_pos, ads_e).lerp(SPRINT_POS, sprint_e)
	pos += bob + breathe
	pos += Vector3(-_sway.x * 0.25, _sway.y * 0.25, 0) * sway_scale
	pos.z += _kick * lerpf(0.045, 0.025, ads_e)
	pos.y -= _land_dip * 0.04
	if player.is_gliding():
		pos.y -= 0.03

	var rot := SPRINT_ROT * sprint_e
	rot.x += _kick * lerpf(0.09, 0.03, ads_e) * (1.8 if current_id() == "hand_cannon" else 1.0)
	rot.z += _kick * _kick_roll * 0.04
	rot.y += -_sway.x * 0.8 * sway_scale
	rot.x += -_sway.y * 0.8 * sway_scale
	rot.z += -_sway.x * 1.2 * sway_scale
	rot.z += sin(_bob) * 0.02 * bob_amt

	# Switch: the old gun drops out of view to the lower right, the new one rises back up.
	if _switch_t >= 0.0:
		var down := 0.0
		if _switch_t < LOWER_TIME:
			down = _ease(_switch_t / LOWER_TIME)
		else:
			down = 1.0 - _ease(clampf((_switch_t - LOWER_TIME) / RAISE_TIME, 0.0, 1.0))
		pos += Vector3(0.04, -0.22, 0.05) * down
		rot += Vector3(-0.7, 0.2, 0.3) * down

	# Reload: tilt the gun, drop the old mag out, bring a new one up, then a little shake.
	# The hand cannon rolls its cylinder out instead.
	var mag_offset := Vector3.ZERO
	if _reload_t >= 0.0:
		var p: float = _reload_t / stats["reload"]
		var tilt := _ease(clampf(p / 0.2, 0.0, 1.0)) * (1.0 - _ease(clampf((p - 0.8) / 0.2, 0.0, 1.0)))
		rot += Vector3(0.25, -0.35, 0.6) * tilt
		pos += Vector3(-0.03, -0.04, 0.02) * tilt
		if current_id() == "hand_cannon":
			_mag.position.x = -0.045 * tilt
			_mag.rotation.z = p * TAU * 2.0 * tilt
		else:
			if p > 0.15 and p < 0.4:
				mag_offset.y = -_ease((p - 0.15) / 0.25) * 0.35
			elif p >= 0.4 and p < 0.65:
				mag_offset.y = -(1.0 - _ease((p - 0.4) / 0.25)) * 0.35
			_mag.visible = not (p > 0.38 and p < 0.42)
		if p > 0.62 and p < 0.72:
			pos.y += sin((p - 0.62) / 0.1 * PI) * 0.015  # seat bump
	if current_id() != "hand_cannon":
		_mag.position = _mag_rest + mag_offset

	_rig.position = pos
	_rig.rotation = rot

	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_flash.visible = false
			_flash_light.visible = false


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


# --- effects --------------------------------------------------------------------

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var w := 0.02 if current_id() == "hand_cannon" else 0.012
	mesh.size = Vector3(w, w, length)
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


# --- viewmodel ------------------------------------------------------------------

var _mag_rest := Vector3.ZERO


func _equip(new_slot: int) -> void:
	slot = new_slot
	_next_slot = new_slot
	stats = Data.ARCHETYPES[current_id()]
	_reload_t = -1.0
	_bloom = 0.0
	_cooldown = maxf(_cooldown, 0.0)
	for c in _model.get_children():
		c.free()
	_build_model(stats["model"])


func _build_model(m: Dictionary) -> void:
	var dark := Color(0.13, 0.14, 0.16)
	var metal: Color = m["metal"]
	var accent: Color = m["accent"]
	var sleeve := Color(0.22, 0.27, 0.33)
	var glove := Color(0.1, 0.1, 0.11)
	var body: float = m["body"]
	var guard: float = m["handguard"]
	var barrel: float = m["barrel"]
	var front := -body * 0.5  # where the receiver ends and the handguard begins

	_part(Vector3(0.06, 0.08, body), Vector3(0, 0, 0), metal)  # receiver
	_part(Vector3(0.062, 0.012, body * 0.35), Vector3(0, 0.025, body * 0.15), accent)  # side stripe
	if guard > 0.0:
		_part(Vector3(0.045, 0.05, guard), Vector3(0, 0.005, front - guard * 0.5), dark)  # handguard
	var barrel_z := front - guard - barrel * 0.5 + 0.02
	_part(Vector3(0.022, 0.022, barrel), Vector3(0, 0.01, barrel_z), dark)  # barrel
	var muzzle_z := front - guard - barrel + 0.02
	_part(Vector3(0.035, 0.035, 0.05), Vector3(0, 0.01, muzzle_z), metal)  # muzzle brake
	if m["stock"]:
		_part(Vector3(0.05, 0.07, 0.2), Vector3(0, -0.015, body * 0.5 + 0.08), dark)  # stock
	_part(Vector3(0.04, 0.09, 0.05), Vector3(0, -0.075, body * 0.3), dark)  # grip

	_mag = Node3D.new()
	_model.add_child(_mag)
	if m.get("cylinder", false):
		# Revolver: a chunky cylinder in front of the hammer, a heavy top strap and a
		# long barrel shroud.
		_mag_rest = Vector3(0, 0.0, -0.03)
		_mag.position = _mag_rest
		_part(Vector3(0.075, 0.075, 0.07), Vector3.ZERO, metal.darkened(0.25), _mag)
		_part(Vector3(0.08, 0.02, 0.05), Vector3(0, 0.0, 0), accent, _mag)
		_part(Vector3(0.04, 0.03, barrel + 0.04), Vector3(0, 0.032, barrel_z - 0.01), metal)
		_part(Vector3(0.02, 0.03, 0.03), Vector3(0, 0.045, body * 0.4), dark)  # hammer
	else:
		var mag_size: Vector3 = m["mag"]
		_mag_rest = Vector3(0, -0.06, -0.04)
		_part(mag_size, Vector3(0, -mag_size.y * 0.5, 0), dark, _mag)

	# Sights. Every optic puts its aim point at y = SIGHT_Y on the centre line, so
	# ADS_POS lines it up with the screen centre for any gun.
	var sight_mat := _emissive(Color(1.0, 0.25, 0.15), 3.0)
	if m["optic"] == "scope":
		# A long scope: a mount, a tube drawn as an open frame so you can see through
		# it, and a lit dot at the front for the reticle.
		_part(Vector3(0.03, 0.02, 0.06), Vector3(0, 0.03, -0.02), dark)  # mount, below the tube
		for z in [0.04, -0.12]:
			_frame(Vector3(0, SIGHT_Y, z), 0.06, 0.008, dark)
		for side in [-1.0, 1.0]:
			_part(Vector3(0.008, 0.008, 0.16), Vector3(side * 0.034, SIGHT_Y + 0.034, -0.04), dark)
			_part(Vector3(0.008, 0.008, 0.16), Vector3(side * 0.034, SIGHT_Y - 0.034, -0.04), dark)
		# Thin posts from the bottom and sides that stop short of the dot.
		_part(Vector3(0.002, 0.022, 0.002), Vector3(0, SIGHT_Y - 0.019, -0.12), dark)
		for side in [-1.0, 1.0]:
			_part(Vector3(0.022, 0.002, 0.002), Vector3(side * 0.019, SIGHT_Y, -0.12), dark)
		_part(Vector3(0.004, 0.004, 0.004), Vector3(0, SIGHT_Y, -0.12), _emissive(accent, 4.0))
	else:
		# Iron sights: a rear notch and a front post with a lit tip.
		_part(Vector3(0.05, 0.012, 0.1), Vector3(0, 0.046, body * 0.06), dark)
		_part(Vector3(0.01, 0.03, 0.02), Vector3(-0.02, 0.066, body * 0.15), dark)
		_part(Vector3(0.01, 0.03, 0.02), Vector3(0.02, 0.066, body * 0.15), dark)
		var post_z := front - guard * 0.3 if guard > 0.0 else muzzle_z + 0.03
		_part(Vector3(0.006, 0.026, 0.01), Vector3(0, 0.058, post_z), dark)
		_part(Vector3(0.008, 0.012, 0.01), Vector3(0, SIGHT_Y, post_z), sight_mat)
		if guard <= 0.0:
			_part(Vector3(0.012, 0.03, 0.02), Vector3(0, 0.035, post_z), metal)  # post base on the shroud

	# Arms: the right hand on the grip, the left under the handguard (or cupping the
	# grip on a pistol).
	var grip_z := body * 0.3
	_part(Vector3(0.06, 0.06, 0.3), Vector3(0.03, -0.12, grip_z + 0.18), sleeve).rotation = Vector3(0.35, -0.15, 0)
	_part(Vector3(0.055, 0.06, 0.07), Vector3(0.0, -0.08, grip_z + 0.02), glove)
	if guard > 0.0:
		var hand_z := front - guard * 0.55
		_part(Vector3(0.06, 0.06, 0.32), Vector3(-0.09, -0.1, hand_z + 0.18), sleeve).rotation = Vector3(0.3, 0.55, 0)
		_part(Vector3(0.06, 0.05, 0.08), Vector3(-0.01, -0.04, hand_z), glove)
	else:
		_part(Vector3(0.06, 0.06, 0.3), Vector3(-0.1, -0.13, grip_z + 0.16), sleeve).rotation = Vector3(0.35, 0.45, 0)
		_part(Vector3(0.05, 0.06, 0.07), Vector3(-0.03, -0.09, grip_z + 0.01), glove)

	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.01, muzzle_z - 0.04)
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


## A square ring facing the camera, used for see-through optics.
func _frame(center: Vector3, opening: float, thickness: float, color: Color) -> void:
	var outer := opening + thickness * 2.0
	var off := (opening + thickness) * 0.5
	_part(Vector3(outer, thickness, thickness), center + Vector3(0, off, 0), color)
	_part(Vector3(outer, thickness, thickness), center + Vector3(0, -off, 0), color)
	_part(Vector3(thickness, opening, thickness), center + Vector3(off, 0, 0), color)
	_part(Vector3(thickness, opening, thickness), center + Vector3(-off, 0, 0), color)


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
