extends Node3D
## Builds a greybox social hub shaped like a city-wall tower plaza: a long courtyard
## on a high wall, a parapet overlooking a city far below, a tall facade with arches,
## a lower garden reached by stairs, a hangar, vendor kiosks, and a giant pale sphere
## hanging over the city. Everything is primitives, so it needs no art assets.

const STONE := Color(0.62, 0.6, 0.56)
const STONE_DARK := Color(0.42, 0.41, 0.39)
const TRIM := Color(0.28, 0.3, 0.33)
const BANNER_COLORS := [Color(0.55, 0.12, 0.1), Color(0.12, 0.25, 0.5), Color(0.75, 0.55, 0.15)]

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_build_environment()
	_build_plaza()
	_build_facade()
	_build_parapet_and_city()
	_build_courtyard()
	_build_hangar()
	_build_vendors()
	_build_targets()

	var player := CharacterBody3D.new()
	player.set_script(preload("res://scripts/player.gd"))
	player.add_to_group("player")
	add_child(player)
	player.position = Vector3(0, 0.1, 6)

	var hud := CanvasLayer.new()
	hud.set_script(preload("res://scripts/hud.gd"))
	add_child(hud)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.32, 0.52)
	sky_mat.sky_horizon_color = Color(0.92, 0.66, 0.45)
	sky_mat.ground_horizon_color = Color(0.7, 0.55, 0.45)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.25)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.68, 0.62)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.7, 0.6)
	env.fog_density = 0.0025
	env.fog_aerial_perspective = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.88, 0.72)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.rotation_degrees = Vector3(-28, 150, 0)
	add_child(sun)


func _build_plaza() -> void:
	# Main walkway: 70 m long on X, 26 m deep on Z, sitting on top of the wall.
	_block(Vector3(70, 1, 26), Vector3(0, -0.5, 0), STONE)
	# Paving strips for scale.
	for i in range(-6, 7):
		_block(Vector3(0.25, 0.02, 26), Vector3(i * 5.0, 0.01, 0), STONE_DARK, false)
	# Central raised dais with a beacon pillar, the hub's meeting point.
	_block(Vector3(8, 0.4, 8), Vector3(0, 0.2, 0), STONE_DARK)
	_block(Vector3(1.2, 6, 1.2), Vector3(0, 3.4, 0), TRIM)
	_glow_block(Vector3(0.5, 0.5, 0.5), Vector3(0, 6.8, 0), Color(0.6, 0.85, 1.0), 4.0)
	# Wall thickness below, so the edge reads as a cliff.
	_block(Vector3(70, 60, 4), Vector3(0, -31, 11), STONE_DARK)


func _build_facade() -> void:
	# The tall tower building on the north side, with arched openings at ground level.
	var z := -15.0
	_block(Vector3(70, 28, 4), Vector3(0, 16, z - 0.5), STONE)
	for i in range(-3, 4):
		var x := i * 9.0
		# Pillars either side of each arch, with the gap above as the arch head.
		_block(Vector3(1.6, 8, 1.6), Vector3(x - 3.2, 4, z + 2), STONE_DARK)
		_block(Vector3(1.6, 8, 1.6), Vector3(x + 3.2, 4, z + 2), STONE_DARK)
		_block(Vector3(8, 1.2, 1.8), Vector3(x, 8.6, z + 2), TRIM)
		_block(Vector3(4.8, 6.6, 0.3), Vector3(x, 3.3, z + 1.4), Color(0.12, 0.12, 0.14), false)
		if i % 2 == 0:
			var c: Color = BANNER_COLORS[abs(i) % BANNER_COLORS.size()]
			_block(Vector3(2.0, 7.0, 0.08), Vector3(x, 14.5, z + 1.55), c, false)
			_block(Vector3(2.2, 0.15, 0.2), Vector3(x, 18.1, z + 1.6), TRIM, false)
	# Upper balcony and the rising tower beyond.
	_block(Vector3(40, 0.6, 4), Vector3(0, 12, z + 3), STONE_DARK)
	_block(Vector3(40, 1.0, 0.3), Vector3(0, 12.8, z + 4.9), TRIM)
	_block(Vector3(18, 50, 12), Vector3(0, 30, z - 8), STONE)
	_block(Vector3(20, 1.5, 14), Vector3(0, 55, z - 8), TRIM)
	_block(Vector3(6, 14, 6), Vector3(0, 62, z - 8), STONE_DARK)


func _build_parapet_and_city() -> void:
	var z := 13.0
	# Low parapet with crenellation-style gaps.
	for i in range(-17, 18):
		_block(Vector3(1.8, 1.1, 0.6), Vector3(i * 2.0, 0.55, z), STONE_DARK)
	_block(Vector3(70, 0.15, 0.8), Vector3(0, 1.15, z), TRIM)
	# Invisible wall so nobody walks off by accident.
	_collider(Vector3(70, 4, 0.5), Vector3(0, 2, z + 0.4))

	# The city far below: scattered towers fading into the fog.
	_block(Vector3(900, 1, 900), Vector3(0, -80, 400), Color(0.35, 0.33, 0.32), false)
	for i in 260:
		var x := _rng.randf_range(-350, 350)
		var zz := _rng.randf_range(40, 600)
		var h := _rng.randf_range(10, 70) * (1.0 + 0.6 * exp(-abs(x) / 120.0))
		var w := _rng.randf_range(6, 18)
		var shade := _rng.randf_range(0.35, 0.6)
		_block(Vector3(w, h, w), Vector3(x, -80 + h * 0.5, zz), Color(shade, shade * 0.97, shade * 0.93), false)
		if _rng.randf() < 0.3:
			_glow_block(Vector3(w * 0.4, 0.4, w * 0.4), Vector3(x, -80 + h + 0.2, zz), Color(1.0, 0.75, 0.4), 2.0)

	# The great sphere hanging over the city, with a little rim light of its own.
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 90.0
	mesh.height = 180.0
	mesh.radial_segments = 96
	mesh.rings = 48
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.93, 0.9)
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.9, 1.0)
	mat.emission_energy_multiplier = 0.25
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sphere.position = Vector3(-60, 110, 420)
	add_child(sphere)
	# A cracked, broken-off section floating beside it.
	for i in 5:
		_block(Vector3(_rng.randf_range(10, 25), _rng.randf_range(6, 14), _rng.randf_range(8, 18)),
			Vector3(-60 + 95 + i * 9, 80 - i * 7, 400 + i * 6), Color(0.85, 0.85, 0.82), false) \
			.rotation = Vector3(_rng.randf(), _rng.randf(), _rng.randf())


func _build_courtyard() -> void:
	# West end: stairs down to a sunken garden 3 m below the plaza.
	var drop := 3.0
	var x0 := -35.0
	_stairs(Vector3(x0, 0, 0), Vector3(-1, 0, 0), 10, 12.0, drop)
	_block(Vector3(28, 1, 30), Vector3(x0 - 8 - 14, -drop - 0.5, 0), STONE)
	_block(Vector3(1, 6, 30), Vector3(x0 - 8 - 28, -drop + 3, 0), STONE_DARK)
	_block(Vector3(28, 6, 1), Vector3(x0 - 22, -drop + 3, -15), STONE_DARK)
	_block(Vector3(28, 2, 1), Vector3(x0 - 22, -drop + 1, 15), STONE_DARK)
	# Trees and planters.
	for p in [Vector3(-48, 0, -8), Vector3(-56, 0, 6), Vector3(-46, 0, 9), Vector3(-58, 0, -9)]:
		var base := Vector3(p.x, -drop, p.z)
		_block(Vector3(3, 0.6, 3), base + Vector3(0, 0.3, 0), STONE_DARK)
		_cylinder(0.25, 4.0, base + Vector3(0, 2.6, 0), Color(0.35, 0.25, 0.18))
		_sphere(2.0, base + Vector3(0, 5.0, 0), Color(0.75, 0.45, 0.2))
	# The plaza/garden side walls of the stairs.
	_block(Vector3(12, 4, 0.8), Vector3(x0 - 6, -1, -6.4), STONE_DARK)
	_block(Vector3(12, 4, 0.8), Vector3(x0 - 6, -1, 6.4), STONE_DARK)


func _build_hangar() -> void:
	# East end: a covered hangar bay with a parked ship silhouette.
	var x := 35.0
	_block(Vector3(24, 1, 30), Vector3(x + 12, -0.5, 0), STONE_DARK)
	_block(Vector3(24, 1.2, 30), Vector3(x + 12, 12, 0), TRIM)
	for zz in [-14.0, 14.0]:
		_block(Vector3(24, 12, 1.2), Vector3(x + 12, 6, zz), STONE)
	_block(Vector3(1.2, 12, 30), Vector3(x + 24, 6, 0), STONE)
	for i in 4:
		_block(Vector3(0.6, 0.6, 30), Vector3(x + 3 + i * 6, 11.2, 0), Color(0.2, 0.2, 0.22), false)
		_glow_block(Vector3(2.0, 0.1, 0.4), Vector3(x + 3 + i * 6, 10.8, 0), Color(1.0, 0.95, 0.85), 3.0)
	# Ship: fuselage, wings, engines.
	var s := Vector3(x + 13, 1.6, 0)
	_block(Vector3(3, 1.4, 9), s, Color(0.75, 0.75, 0.78)).rotation.x = 0.04
	_block(Vector3(10, 0.25, 3), s + Vector3(0, 0, 1.2), Color(0.6, 0.62, 0.66))
	_block(Vector3(1.6, 1.0, 2.0), s + Vector3(0, 0.9, -1.6), Color(0.15, 0.2, 0.28))
	for side in [-1, 1]:
		_cylinder(0.45, 2.4, s + Vector3(side * 3.6, 0, 2.6), Color(0.3, 0.3, 0.32)).rotation.x = PI / 2
		_glow_block(Vector3(0.6, 0.6, 0.1), s + Vector3(side * 3.6, 0, 3.85), Color(0.4, 0.7, 1.0), 4.0)
	_block(Vector3(1.4, 1.2, 0.3), s + Vector3(0, -1.2, 0), TRIM)


func _build_vendors() -> void:
	# Kiosks along the facade and by the parapet.
	var spots := [Vector3(-20, 0, -9), Vector3(-10, 0, -9), Vector3(12, 0, -9), Vector3(22, 0, -9),
		Vector3(-16, 0, 9), Vector3(16, 0, 9)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var c: Color = BANNER_COLORS[i % BANNER_COLORS.size()]
		_block(Vector3(3.2, 1.1, 1.2), p + Vector3(0, 0.55, 0), TRIM)
		_block(Vector3(3.6, 0.12, 2.2), p + Vector3(0, 3.0, 0), c)
		for sx in [-1.6, 1.6]:
			_block(Vector3(0.12, 3.0, 0.12), p + Vector3(sx, 1.5, -0.9 if p.z < 0 else 0.9), STONE_DARK)
		# Vendor stand-in: a figure behind the counter.
		var back := -1.0 if p.z < 0 else 1.0
		_cylinder(0.3, 1.2, p + Vector3(0, 1.0, back), Color(0.3, 0.32, 0.38))
		_sphere(0.22, p + Vector3(0, 1.85, back), Color(0.8, 0.7, 0.6))
		_glow_block(Vector3(0.5, 0.3, 0.05), p + Vector3(0, 1.4, -0.62 * back), c.lightened(0.4), 2.0)


func _build_targets() -> void:
	# A practice range in the sunken garden, facing the stairs.
	for i in 5:
		var t := Node3D.new()
		t.set_script(preload("res://scripts/target.gd"))
		add_child(t)
		t.position = Vector3(-60, -3.0, -8 + i * 4)
		t.rotation.y = PI / 2
		t.setup(BANNER_COLORS[i % BANNER_COLORS.size()])
	# A few on the plaza for close-range testing.
	for i in 3:
		var t := Node3D.new()
		t.set_script(preload("res://scripts/target.gd"))
		add_child(t)
		t.position = Vector3(-6 + i * 6, 0, -5)
		t.setup(Color(0.6, 0.6, 0.65))
	# A tough one at the back of the range for practising precision strings.
	var major := Node3D.new()
	major.set_script(preload("res://scripts/target.gd"))
	add_child(major)
	major.position = Vector3(-66, -3.0, 11)
	major.rotation.y = PI / 2
	major.setup(Color(0.75, 0.6, 0.2), "Heavy Practice Target", 1200.0, 1.5, true)


# --- building helpers -------------------------------------------------------

func _block(size: Vector3, pos: Vector3, color: Color, collide := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color)
	if not collide:
		mi.position = pos
		add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.position = pos
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	return body


func _glow_block(size: Vector3, pos: Vector3, color: Color, energy: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := _mat(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _collider(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _stairs(top: Vector3, dir: Vector3, steps: int, length: float, drop: float) -> void:
	# Visual steps, plus one smooth ramp collider so the player glides down them.
	var run := length / steps
	var rise := drop / steps
	for i in steps:
		var h := drop - rise * i
		var center := top + dir * (run * (i + 0.5))
		_block(Vector3(run, h, 12), Vector3(center.x, -drop + h * 0.5 - rise, center.z), STONE, false)
	var ramp := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var slope_len := sqrt(length * length + drop * drop)
	shape.size = Vector3(slope_len, 0.2, 12)
	col.shape = shape
	ramp.add_child(col)
	ramp.position = top + dir * (length * 0.5) + Vector3(0, -drop * 0.5 - 0.1, 0)
	ramp.rotation.z = atan2(drop, length) * (1.0 if dir.x < 0 else -1.0)
	add_child(ramp)


func _cylinder(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	add_child(mi)
	return mi


func _sphere(radius: float, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	add_child(mi)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m
