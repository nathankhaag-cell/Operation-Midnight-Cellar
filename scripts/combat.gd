extends RefCounted
## Shared hit handling: finding what was hit, floating damage numbers and HUD feedback.

const BODY_COLOR := Color(1, 1, 1)
const CRIT_COLOR := Color(1.0, 0.82, 0.2)


## Walks up from a collider to the node that takes damage (targets keep their
## collision shapes a level or two below the script).
static func find_damageable(collider: Object) -> Node:
	var node := collider as Node
	for i in 4:
		if node == null:
			return null
		if node.has_method("take_hit"):
			return node
		node = node.get_parent()
	return null


## Shows a damage number, the hitmarker and the target's health bar for one hit.
static func feedback(ctx: Node, target: Node, point: Vector3, amount: float, crit: bool, killed: bool) -> void:
	spawn_number(ctx, point, amount, crit)
	var hud := ctx.get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_hitmarker(crit, killed)
		hud.show_target(target)


## A number that pops up from the hit point, drifts and fades. White for body hits,
## yellow for precision hits.
static func spawn_number(ctx: Node, point: Vector3, amount: float, crit: bool) -> void:
	var label := Label3D.new()
	label.text = str(roundi(amount))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 44 if crit else 36
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.75)
	label.modulate = CRIT_COLOR if crit else BODY_COLOR
	label.render_priority = 10
	label.outline_render_priority = 9
	ctx.get_tree().current_scene.add_child(label)
	var drift := Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	label.global_position = point + Vector3(0, 0.15, 0) + drift * 0.3
	label.scale = Vector3.ONE * 1.35

	var tw := label.create_tween().set_parallel(true)
	tw.tween_property(label, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "global_position", label.global_position + Vector3(0, 0.55, 0) + drift, 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.5)
	tw.tween_property(label, "outline_modulate:a", 0.0, 0.3).set_delay(0.5)
	tw.chain().tween_callback(label.queue_free)
