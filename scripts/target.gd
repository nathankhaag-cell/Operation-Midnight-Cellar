extends Node3D
## A practice target. Flashes on hit, the head counts as a critical, and it
## folds down when its health runs out, then pops back up.

const MAX_HEALTH := 10

var _health := MAX_HEALTH
var _body_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _pivot: AnimatableBody3D
var _head: Node3D
var _down := false


func setup(color: Color) -> void:
	_pivot = AnimatableBody3D.new()
	_pivot.sync_to_physics = false
	add_child(_pivot)
	_body_mat = _mat(color)
	_head_mat = _mat(color.lightened(0.3))
	_add_box(Vector3(0.6, 1.1, 0.12), Vector3(0, 0.95, 0), _body_mat)
	_head = _add_box(Vector3(0.32, 0.32, 0.12), Vector3(0, 1.72, 0), _head_mat)
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.06, 0.4, 0.06)
	post.mesh = post_mesh
	post.material_override = _mat(Color(0.2, 0.2, 0.2))
	post.position.y = 0.2
	add_child(post)


func hit(point: Vector3, _dir: Vector3) -> bool:
	if _down:
		return false
	var crit := point.y > _head.global_position.y - 0.17
	_health -= 3 if crit else 1
	_flash()
	if _health <= 0:
		_fall()
	return crit


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
	_health = MAX_HEALTH


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
