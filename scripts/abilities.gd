extends Node
## Melee and grenade. Melee is always there with a short recovery between swings and
## lunges at a target just in front of you. The grenade has one charge that refills slowly.

const Combat := preload("res://scripts/combat.gd")
const Grenade := preload("res://scripts/grenade.gd")

const MELEE_COOLDOWN := 1.0
const MELEE_DAMAGE := 150.0
const MELEE_RANGE := 1.9
const MELEE_HIT_TIME := 0.1  # seconds into the swing when the fist lands
const LUNGE_RANGE := 3.2
const LUNGE_CONE := 22.0  # degrees either side of the reticle
const LUNGE_SPEED := 14.0
const LUNGE_TURN := 0.5  # share of the angle to the target the lunge turns you through

const GRENADE_RECHARGE := 20.0
const THROW_RELEASE := 0.13  # seconds into the throw when the grenade leaves the hand
const THROW_SPEED := 15.0
const THROW_LIFT := 3.5

var player: CharacterBody3D
var grenade_charge := 1.0  # 0..1; a throw needs a full charge
var melee_wait := 0.0  # seconds until the next swing

var _swing_t := -1.0  # < 0 when not swinging
var _swing_target: Node = null


func _process(delta: float) -> void:
	grenade_charge = minf(grenade_charge + delta / GRENADE_RECHARGE, 1.0)
	melee_wait = maxf(melee_wait - delta, 0.0)

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("melee"):
			melee()
		if Input.is_action_just_pressed("grenade"):
			throw_grenade()

	if _swing_t >= 0.0:
		var before := _swing_t
		_swing_t += delta
		if before < MELEE_HIT_TIME and _swing_t >= MELEE_HIT_TIME:
			_melee_hit()
		if _swing_t > 0.4:
			_swing_t = -1.0


## 0..1 readiness for the HUD.
func melee_fraction() -> float:
	return 1.0 - melee_wait / MELEE_COOLDOWN


func melee() -> bool:
	if melee_wait > 0.0 or not player.weapon.can_act():
		return false
	melee_wait = MELEE_COOLDOWN
	_swing_t = 0.0
	player.weapon.play_melee()

	# Lunge: a live target close in front pulls you toward it and turns you a little.
	_swing_target = _lunge_target()
	if _swing_target:
		var aim: Vector3 = _swing_target.aim_points()[0]
		var to := aim - player.global_position
		to.y = 0.0
		var gap := to.length() - 1.0
		if gap > 0.05:
			player.lunge(to.normalized() * LUNGE_SPEED, gap / LUNGE_SPEED)
		var forward := -player.global_transform.basis.z
		var turn := forward.signed_angle_to(to.normalized(), Vector3.UP)
		player.rotate_y(turn * LUNGE_TURN)
	return true


func throw_grenade() -> bool:
	if grenade_charge < 1.0 or not player.weapon.can_act():
		return false
	grenade_charge = 0.0
	player.weapon.play_throw()
	get_tree().create_timer(THROW_RELEASE).timeout.connect(_release_grenade)
	return true


func _release_grenade() -> void:
	var cam: Camera3D = player.camera
	var basis := cam.global_transform.basis
	var forward := -basis.z
	var g := Node3D.new()
	g.set_script(Grenade)
	g.exclude = [player.get_rid()]
	g.velocity = forward * THROW_SPEED + Vector3.UP * THROW_LIFT + player.velocity * 0.6
	get_tree().current_scene.add_child(g)
	g.global_position = cam.global_position + forward * 0.45 - basis.x * 0.12 - basis.y * 0.08


func _lunge_target() -> Node:
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var forward := -cam.global_transform.basis.z
	var best: Node = null
	var best_dist := LUNGE_RANGE
	for t in get_tree().get_nodes_in_group("damageable"):
		if not t.is_alive():
			continue
		var p: Vector3 = t.aim_points()[0]
		var to := p - from
		var dist := to.length()
		if dist < best_dist and rad_to_deg(forward.angle_to(to.normalized())) < LUNGE_CONE:
			best = t
			best_dist = dist
	return best


func _melee_hit() -> void:
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var basis := cam.global_transform.basis
	var forward := -basis.z
	# A small fan of rays, plus one straight at the lunge target if there is one.
	var dirs: Array[Vector3] = [forward, forward.rotated(basis.y, 0.25), forward.rotated(basis.y, -0.25),
		forward.rotated(basis.x, -0.2)]
	if is_instance_valid(_swing_target):
		dirs.push_front((_swing_target.aim_points()[0] - from).normalized())
	var space := player.get_world_3d().direct_space_state
	for dir in dirs:
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * MELEE_RANGE)
		query.exclude = [player.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var target := Combat.find_damageable(hit.collider)
		if target == null:
			player.add_shake(0.15)  # knuckles on stone
			return
		var result: Dictionary = target.take_hit(hit.position, MELEE_DAMAGE, 1.0, false)
		if result["dealt"] > 0.0:
			Combat.feedback(self, target, hit.position, result["dealt"], false, result["killed"])
			player.add_shake(0.45)
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.flash_impact()
		return
