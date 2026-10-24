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


## Radial damage that falls off from the centre to `edge_scale` at the radius. Cover
## blocks it. Also draws the blast and shakes the camera of a player close enough to feel it.
static func explode(ctx: Node3D, center: Vector3, radius: float, damage: float, edge_scale := 0.25) -> void:
	var tree := ctx.get_tree()
	var space := ctx.get_world_3d().direct_space_state
	_blast(ctx, center, radius)
	for target in tree.get_nodes_in_group("damageable"):
		if not target.is_alive():
			continue
		var best := INF
		var point := Vector3.ZERO
		for p in target.aim_points():
			var d := center.distance_to(p)
			if d < best:
				best = d
				point = p
		if best > radius:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center, point))
		if not hit.is_empty() and find_damageable(hit.collider) != target:
			continue  # behind cover
		var amount := damage * lerpf(1.0, edge_scale, best / radius)
		var result: Dictionary = target.take_hit(point, amount, 1.0, false)
		if result["dealt"] > 0.0:
			feedback(ctx, target, point, result["dealt"], false, result["killed"])

	var player := tree.get_first_node_in_group("player")
	if player:
		var dist: float = player.global_position.distance_to(center)
		var reach := radius * 3.0
		if dist < reach:
			player.add_shake(lerpf(1.0, 0.15, dist / reach))


## Flash, light, an expanding shockwave sphere, sparks, smoke and a scorch mark.
static func _blast(ctx: Node3D, center: Vector3, radius: float) -> void:
	var scene := ctx.get_tree().current_scene
	var fx := Node3D.new()
	scene.add_child(fx)
	fx.global_position = center

	var flash := _glow_sphere(Color(1.0, 0.8, 0.5), 6.0, 0.95)
	fx.add_child(flash)
	flash.scale = Vector3.ONE * 0.2
	var wave := _glow_sphere(Color(1.0, 0.6, 0.3), 2.0, 0.45)
	fx.add_child(wave)
	wave.scale = Vector3.ONE * 0.3

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.4)
	light.light_energy = 12.0
	light.omni_range = radius * 3.0
	fx.add_child(light)

	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.amount = 48
	sparks.lifetime = 0.7
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 5.0
	sparks.initial_velocity_max = 14.0
	sparks.gravity = Vector3(0, -12, 0)
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.4
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.04, 0.04, 0.04)
	spark_mesh.material = _unshaded(Color(1.0, 0.7, 0.3), 5.0, 1.0)
	sparks.mesh = spark_mesh
	fx.add_child(sparks)
	sparks.emitting = true

	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.amount = 14
	smoke.lifetime = 1.6
	smoke.explosiveness = 0.9
	smoke.direction = Vector3.UP
	smoke.spread = 70.0
	smoke.initial_velocity_min = 0.8
	smoke.initial_velocity_max = 2.2
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.damping_min = 1.0
	smoke.damping_max = 2.0
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.35, 0.33, 0.32, 0.7))
	ramp.set_color(1, Color(0.5, 0.48, 0.46, 0.0))
	smoke.color_ramp = ramp
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 12
	puff.rings = 6
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = smoke_mat
	smoke.mesh = puff
	fx.add_child(smoke)
	smoke.emitting = true

	# Scorch mark on the ground under the blast.
	var down := ctx.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(center, center + Vector3.DOWN * 1.5))
	if not down.is_empty() and find_damageable(down.collider) == null:
		var mark := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.2
		disc.bottom_radius = 1.2
		disc.height = 0.005
		disc.radial_segments = 32
		disc.rings = 1
		mark.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.04, 0.04, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mark.material_override = mat
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(mark)
		var n: Vector3 = down.normal
		mark.global_position = down.position + n * 0.01
		if n.dot(Vector3.UP) < 0.999:
			mark.global_basis = Basis(Quaternion(Vector3.UP, n))  # disc axis along the surface normal
		var fade := mark.create_tween()
		fade.tween_interval(8.0)
		fade.tween_property(mat, "albedo_color:a", 0.0, 2.0)
		fade.tween_callback(mark.queue_free)

	var tw := fx.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * radius * 0.45, 0.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash.material_override, "albedo_color:a", 0.0, 0.18).set_delay(0.06)
	tw.tween_property(wave, "scale", Vector3.ONE * radius, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(wave.material_override, "albedo_color:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_property(light, "light_energy", 0.0, 0.4).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.6)
	tw.chain().tween_callback(fx.queue_free)


static func _glow_sphere(color: Color, energy: float, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mi.mesh = mesh
	mi.material_override = _unshaded(color, energy, alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _unshaded(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
