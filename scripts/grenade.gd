extends Node3D
## A thrown grenade. It moves itself with a ray cast each physics frame so it never
## tunnels through thin walls, bounces and rolls to a stop, and goes off when its fuse
## runs out or the moment it touches a target.

const Combat := preload("res://scripts/combat.gd")

const GRAVITY := 16.0
const BOUNCE := 0.4  # share of the speed into a surface that comes back out
const FRICTION := 0.65  # share of the sliding speed kept per bounce
const FUSE := 1.6
const RADIUS := 5.0
const DAMAGE := 260.0
const SIZE := 0.07

var velocity := Vector3.ZERO
var exclude: Array = []  # RIDs the throw ignores (the thrower)

var _age := 0.0
var _resting := false
var _light: OmniLight3D
var _mesh: Node3D


func _ready() -> void:
	_mesh = Node3D.new()
	add_child(_mesh)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = SIZE
	sphere.height = SIZE * 2.0
	body.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.2, 0.22)
	mat.metallic = 0.5
	mat.roughness = 0.4
	body.material_override = mat
	_mesh.add_child(body)
	var band := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = SIZE * 1.04
	ring.bottom_radius = SIZE * 1.04
	ring.height = SIZE * 0.35
	band.mesh = ring
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.55, 0.2)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.55, 0.2)
	glow.emission_energy_multiplier = 4.0
	band.material_override = glow
	_mesh.add_child(band)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 1.5
	_light.omni_range = 1.5
	add_child(_light)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= FUSE:
		detonate()
		return
	# The light blinks faster as the fuse runs down.
	var rate := lerpf(4.0, 18.0, _age / FUSE)
	_light.visible = fmod(_age * rate, 1.0) < 0.5
	if _resting:
		return

	velocity.y -= GRAVITY * delta
	var from := global_position
	var motion := velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, from + motion + motion.normalized() * SIZE)
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = from + motion
	else:
		var normal: Vector3 = hit.normal
		global_position = hit.position + normal * (SIZE + 0.005)
		if Combat.find_damageable(hit.collider) != null:
			detonate()
			return
		var into := normal * velocity.dot(normal)
		velocity = (velocity - into) * FRICTION - into * BOUNCE
		if normal.y > 0.7 and velocity.length() < 1.2:
			_resting = true
			velocity = Vector3.ZERO
	_mesh.rotate_x(velocity.length() * delta * 6.0)


func detonate() -> void:
	if is_queued_for_deletion():
		return
	Combat.explode(self, global_position + Vector3(0, 0.1, 0), RADIUS, DAMAGE)
	queue_free()
