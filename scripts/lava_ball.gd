# Lava ball — Reaper spits these from his mouth. Travels in a slight
# arc, detonates on first zombie it touches (or after lifetime), dealing
# direct damage to the impact target + splash to nearby zombies.

extends Area3D

@export var speed:         float = 28.0
# How fast the projectile falls each second (can't be named `gravity`
# because Area3D already has its own `gravity` property).
@export var fall_rate:     float = 7.0
@export var direct_dmg:    int   = 60
@export var splash_dmg:    int   = 28
@export var splash_radius: float = 3.6
@export var lifetime:      float = 2.5

var velocity:  Vector3 = Vector3.ZERO
var life_t:    float   = 0.0
var detonated: bool    = false

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

# Launch from `from` toward `dir` (which doesn't need to be normalized).
func launch(dir: Vector3, from: Vector3) -> void:
	global_position = from
	if dir.length() > 0.001:
		velocity = dir.normalized() * speed

func _physics_process(delta: float) -> void:
	if detonated:
		return
	life_t += delta
	if life_t > lifetime:
		_detonate()
		return
	velocity.y -= fall_rate * delta
	global_position += velocity * delta

func _on_body_entered(body: Node) -> void:
	if detonated:
		return
	# Friendly fire guard — never explode on Reaper or the Ringworker ally.
	if body.is_in_group("player") or body.is_in_group("ally"):
		return
	if body.is_in_group("zombie") and body.has_method("take_damage"):
		body.take_damage(direct_dmg, global_position)
	_detonate()

func _detonate() -> void:
	if detonated:
		return
	detonated = true
	for z in get_tree().get_nodes_in_group("zombie"):
		if not (z is Node3D):
			continue
		var d: float = (z as Node3D).global_position \
			.distance_to(global_position)
		if d < splash_radius:
			if z.has_method("take_damage"):
				z.take_damage(splash_dmg, global_position)
	_spawn_explosion()
	# Let the explosion mesh draw a frame, then free this projectile.
	set_physics_process(false)
	monitoring = false
	visible = false
	await get_tree().create_timer(0.5).timeout
	queue_free()

func _spawn_explosion() -> void:
	# Bright orange flash sphere at the impact point.
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = splash_radius
	sm.height = splash_radius * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.42, 0.10, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.30, 0.05, 1)
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = global_position
	get_tree().create_timer(0.32).timeout.connect(func ():
		if is_instance_valid(mi):
			mi.queue_free())
