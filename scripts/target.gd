extends Node3D
## A practice target. Flashes on hit, the head counts as a precision hit, and it
## folds down when its health runs out, then pops back up at full health.

var display_name := "Practice Target"
var max_health := 200.0
var is_major := false

var _health := max_health
var _body_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _pivot: AnimatableBody3D
var _body: Node3D
var _head: Node3D
var _head_half := 0.16
var _down := false


func setup(color: Color, title := "Practice Target", health := 200.0, size := 1.0, major := false) -> void:
	display_name = title
	max_health = health
	_health = health
	is_major = major
	_head_half = 0.16 * size
	add_to_group("damageable")

	_pivot = AnimatableBody3D.new()
	_pivot.sync_to_physics = false
	add_child(_pivot)
	_body_mat = _mat(color)
	_head_mat = _mat(color.lightened(0.3))
	_body = _add_box(Vector3(0.6, 1.1, 0.12) * size, Vector3(0, 0.95, 0) * size, _body_mat)
	_head = _add_box(Vector3(0.32, 0.32, 0.12) * size, Vector3(0, 1.72, 0) * size, _head_mat)
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.06, 0.4, 0.06) * size
	post.mesh = post_mesh
	post.material_override = _mat(Color(0.2, 0.2, 0.2))
	post.position.y = 0.2 * size
	add_child(post)


## Applies one hit and reports what happened: {dealt, crit, killed}. Melee and
## explosions pass can_crit = false, since only bullets find the precision spot.
func take_hit(point: Vector3, amount: float, crit_mult: float, can_crit := true) -> Dictionary:
	if _down:
		return {"dealt": 0.0, "crit": false, "killed": false}
	var local := _head.global_transform.affine_inverse() * point
	var crit := can_crit and local.y > -_head_half - 0.01
	var dealt := minf(amount * (crit_mult if crit else 1.0), _health)
	_health -= dealt
	_flash()
	var killed := _health <= 0.0
	if killed:
		_fall()
	return {"dealt": dealt, "crit": crit, "killed": killed}


func health_fraction() -> float:
	return maxf(_health, 0.0) / max_health


func is_alive() -> bool:
	return not _down


## Where aim assist pulls toward: the body centre, then the head.
func aim_points() -> Array[Vector3]:
	return [_body.global_position, _head.global_position]


func _flash() -> void:
	for m in [_body_mat, _head_mat]:
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_energy_multiplier = 1.5
		var tw := create_tween()
		tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.12)


func _fall() -> void:
	_down = true
	var tw := create_tween()
	tw.tween_property(_pivot, "rotation:x", -PI / 2.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.5)
	tw.tween_property(_pivot, "rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_reset)


func _reset() -> void:
	_down = false
	_health = max_health


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_pivot.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	_pivot.add_child(col)
	return mi


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m
