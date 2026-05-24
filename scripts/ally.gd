# Ringworker ally — friendly construct Reaper summons with R.
#
# Picks the nearest enemy in the "zombie" group, runs at it, swings on
# contact. Has a short lifetime (~15s) and limited HP, then fades.

extends CharacterBody3D

@export var max_hp:    int   = 100
@export var speed:     float = 5.4
@export var gravity:   float = 22.0
@export var damage:    int   = 18
@export var atk_cd:    float = 0.9
@export var atk_range: float = 2.2
@export var lifetime:  float = 15.0

@onready var mesh_root: Node3D = $Mesh

var hp:       int   = 100
var life_t:   float = 0.0
var atk_t:    float = 0.0
var target:   Node3D = null
var flash_t:  float = 0.0
var dying:    bool  = false
var die_t:    float = 0.0

var _mat_pairs: Array = []

func _ready() -> void:
	add_to_group("ally")
	hp = max_hp
	_collect_mesh_materials(mesh_root)
	# tint cyan so the player can read friend-from-foe at a glance
	_tint_all(Color(0.45, 0.78, 0.95, 1), Color(0.25, 0.78, 1.0, 1), 0.85)

func _collect_mesh_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var src_mat := mi.get_active_material(0)
		if src_mat is StandardMaterial3D:
			var dup := (src_mat as StandardMaterial3D).duplicate() \
				as StandardMaterial3D
			mi.set_surface_override_material(0, dup)
			_mat_pairs.append({
				"mi": mi,
				"mat": dup,
				"base": dup.albedo_color,
			})
	for child in node.get_children():
		_collect_mesh_materials(child)

func _tint_all(albedo: Color, emission: Color, em_energy: float) -> void:
	for p in _mat_pairs:
		var m: StandardMaterial3D = p.mat
		m.albedo_color = albedo
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = em_energy
		p.base = albedo

func _physics_process(delta: float) -> void:
	if dying:
		die_t += delta
		var k: float = clamp(die_t / 0.6, 0.0, 1.0)
		for p in _mat_pairs:
			p.mat.albedo_color = (p.base as Color).lerp(
				Color(0, 0, 0, 1), k)
			p.mat.emission_energy_multiplier = max(0.0, 0.85 * (1.0 - k))
		if die_t > 0.7:
			queue_free()
		return
	life_t += delta
	if life_t > lifetime:
		dying = true
		die_t = 0.0
		return
	atk_t -= delta
	flash_t -= delta
	for p in _mat_pairs:
		p.mat.albedo_color = (p.base as Color) if flash_t <= 0.0 \
			else (p.base as Color).lerp(Color(1, 1, 1, 1), 0.7)
	target = _find_target()
	if target == null:
		velocity.x = move_toward(velocity.x, 0.0, speed * 60.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 60.0 * delta)
	else:
		var to: Vector3 = target.global_position - global_position
		to.y = 0.0
		var dist: float = to.length()
		if dist > 0.0001:
			to = to / dist
		if dist > atk_range:
			velocity.x = to.x * speed
			velocity.z = to.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed * 60.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, speed * 60.0 * delta)
			if atk_t <= 0.0:
				atk_t = atk_cd
				if target.has_method("take_damage"):
					target.take_damage(damage, global_position)
		if to.length() > 0.0001:
			look_at(target.global_position, Vector3.UP, false)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

func _find_target() -> Node3D:
	var nearest: Node3D = null
	var best:    float  = 999999.0
	for z in get_tree().get_nodes_in_group("zombie"):
		if not (z is Node3D):
			continue
		var n: Node3D = z as Node3D
		var d: float = n.global_position.distance_squared_to(global_position)
		if d < best:
			best = d
			nearest = n
	return nearest

func take_damage(amt: int, _from: Vector3 = Vector3.ZERO) -> void:
	if dying:
		return
	hp -= amt
	flash_t = 0.12
	if hp <= 0:
		dying = true
		die_t = 0.0
