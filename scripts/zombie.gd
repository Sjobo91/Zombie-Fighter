# Enemy (a construct — file is still called zombie.gd for now). Marches
# toward the player, strikes on contact, sparks and crumples on 0 HP.
# make_colossus() / make_prototype01() turn this into a boss variant.

extends CharacterBody3D

@export var max_hp:    int   = 60        # tougher than the old zombies
@export var speed:     float = 4.2
@export var gravity:   float = 22.0
@export var damage:    int   = 14
@export var atk_cd:    float = 1.1
@export var atk_range: float = 2.0
@export var mechparts:  int  = 1

@onready var mesh_root: Node3D = $Mesh

# Collected at _ready: every MeshInstance3D in the imported model,
# with a copy of its material so we can flash + restore.
var _mat_pairs: Array = []

var hp:     int   = 60
var target: Node3D = null
var atk_t:  float = 0.0
var flash_t: float = 0.0
var dying:  bool = false
var die_t:  float = 0.0
var is_boss: bool = false
var boss_name: String = ""

# subtle robot-march wobble (no organic zombie shamble; constructs walk
# stiffly with a tiny vertical bob)
var march_t: float = 0.0
var mesh_base_y: float = 0.0

func _ready() -> void:
	hp = max_hp
	add_to_group("zombie")  # kept as "zombie" group so player attack code finds them
	_collect_mesh_materials(mesh_root)
	target = get_tree().get_first_node_in_group("player") as Node3D
	mesh_base_y = mesh_root.position.y
	march_t = randf() * TAU

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

# ── Wave-10 mini-boss: THE IRON COLOSSUS
func make_colossus() -> void:
	is_boss = true
	boss_name = "THE IRON COLOSSUS"
	max_hp = 1500
	hp = max_hp
	damage = 44
	speed = 3.2
	atk_range = 3.6
	atk_cd = 1.7
	mechparts = 40
	scale = Vector3(2.6, 2.6, 2.6)
	# bronze-and-coal — heavy industrial juggernaut
	_tint_all(Color(0.46, 0.30, 0.14, 1), Color(0.8, 0.18, 0.05, 1), 0.7)
	_announce()

# ── Wave-20 final boss: PROTOTYPE-01 — the first construct that ever
#    rolled off the workshop's assembly line. The progenitor of the
#    rogue protocol.
func make_prototype01() -> void:
	is_boss = true
	boss_name = "PROTOTYPE-01 · THE PROGENITOR"
	max_hp = 3500
	hp = max_hp
	damage = 58
	speed = 4.4
	atk_range = 3.2
	atk_cd = 1.1
	mechparts = 120
	scale = Vector3(2.1, 2.1, 2.1)
	# brass + spectral steam-violet
	_tint_all(Color(0.30, 0.20, 0.12, 1), Color(0.7, 0.35, 0.95, 1), 0.85)
	_announce()

func _tint_all(albedo: Color, emission: Color, em_energy: float) -> void:
	for p in _mat_pairs:
		var m: StandardMaterial3D = p.mat
		m.albedo_color = albedo
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = em_energy
		p.base = albedo

func _announce() -> void:
	var hud := get_node_or_null("/root/Main/HUD")
	if hud and hud.has_method("announce_boss"):
		hud.announce_boss(boss_name)

func _physics_process(delta: float) -> void:
	if dying:
		die_t += delta
		var k: float = clamp(die_t / 0.9, 0.0, 1.0)
		# collapse — slight rotation + sink
		rotation.x = k * 1.4
		position.y -= delta * 1.2
		for p in _mat_pairs:
			# fade to dim, then black — like a powered-down machine
			p.mat.albedo_color = (p.base as Color).lerp(Color(0, 0, 0, 1), k)
			p.mat.emission_energy_multiplier = max(0.0, 0.7 * (1.0 - k))
		if die_t > 1.1:
			queue_free()
		return
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
		if target == null:
			return
	atk_t -= delta
	flash_t -= delta
	for p in _mat_pairs:
		p.mat.albedo_color = (p.base as Color) if flash_t <= 0.0 \
			else (p.base as Color).lerp(Color(1, 1, 1, 1), 0.7)
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
				target.take_damage(damage)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	if to.length() > 0.0001:
		look_at(target.global_position, Vector3.UP, false)
	# robot march — tiny stiff bob, no organic sway
	var moving := dist > atk_range
	march_t += delta * (4.0 if moving else 0.6)
	var amp_bob: float = 0.06 if moving else 0.015
	mesh_root.position.y = mesh_base_y + abs(sin(march_t)) * amp_bob

func take_damage(amt: int, _from: Vector3 = Vector3.ZERO) -> void:
	if dying:
		return
	hp -= amt
	flash_t = 0.12
	if is_boss:
		var hud := get_node_or_null("/root/Main/HUD")
		if hud and hud.has_method("set_boss_hp"):
			hud.set_boss_hp(hp, max_hp, boss_name)
	if hp <= 0:
		dying = true
		die_t = 0.0
		var pl := get_tree().get_first_node_in_group("player")
		if pl and pl.has_method("collect_mechparts"):
			pl.collect_mechparts(mechparts)
		if is_boss:
			var hud := get_node_or_null("/root/Main/HUD")
			if hud and hud.has_method("clear_boss_hp"):
				hud.clear_boss_hp()
