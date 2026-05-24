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
# Procedural animation state (inlined — same pattern as player.gd)
var _walk_phase:    float = 0.0
var _mesh_base_pos: Vector3 = Vector3.ZERO
var _skel: Skeleton3D = null
var _b_l_arm:    int = -1
var _b_r_arm:    int = -1
var _b_l_up_leg: int = -1
var _b_r_up_leg: int = -1
# punch anim timer — drives the right-arm extension visual on strike
var punch_anim_t: float = 0.0

func _ready() -> void:
	hp = max_hp
	add_to_group("zombie")  # kept as "zombie" group so player attack code finds them
	_collect_mesh_materials(mesh_root)
	target = get_tree().get_first_node_in_group("player") as Node3D
	mesh_base_y = mesh_root.position.y
	march_t = randf() * TAU
	# Inline procedural animator — same pattern as Reaper.
	_mesh_base_pos = mesh_root.position
	_skel = _find_skeleton(mesh_root)
	if _skel:
		_cache_bones()

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f := _find_skeleton(c)
		if f != null:
			return f
	return null

func _cache_bones() -> void:
	if _skel == null:
		return
	# Try Mixamo standard names first
	for prefix in ["mixamorig_", "mixamorig:", "mixamorig1_", ""]:
		if _b_l_arm == -1:    _b_l_arm    = _skel.find_bone(prefix + "LeftArm")
		if _b_r_arm == -1:    _b_r_arm    = _skel.find_bone(prefix + "RightArm")
		if _b_l_up_leg == -1: _b_l_up_leg = _skel.find_bone(prefix + "LeftUpLeg")
		if _b_r_up_leg == -1: _b_r_up_leg = _skel.find_bone(prefix + "RightUpLeg")
	# Custom rig: "Arm1_L_00", "Leg1_R_019", etc.
	if _b_l_arm == -1:    _b_l_arm    = _find_bone_prefix("Arm1_L")
	if _b_r_arm == -1:    _b_r_arm    = _find_bone_prefix("Arm1_R")
	if _b_l_up_leg == -1: _b_l_up_leg = _find_bone_prefix("Leg1_L")
	if _b_r_up_leg == -1: _b_r_up_leg = _find_bone_prefix("Leg1_R")
	# Generic substring fallback (Thigh_L, UpperArm_L, etc.)
	if _b_l_arm == -1:    _b_l_arm    = _find_bone_contains(
		["bicep_l", "upperarm_l", "shoulder_l", "arm_l", "leftarm"])
	if _b_r_arm == -1:    _b_r_arm    = _find_bone_contains(
		["bicep_r", "upperarm_r", "shoulder_r", "arm_r", "rightarm"])
	if _b_l_up_leg == -1: _b_l_up_leg = _find_bone_contains(
		["thigh_l", "upleg_l", "upperleg_l", "leg_l"])
	if _b_r_up_leg == -1: _b_r_up_leg = _find_bone_contains(
		["thigh_r", "upleg_r", "upperleg_r", "leg_r"])
	# Print every bone name once per session so we can fix the lookup
	# if some zombie variant uses yet another convention.
	if not get_meta("dumped_bones", false):
		set_meta("dumped_bones", true)
		var n: int = _skel.get_bone_count()
		print("[Zombie] Skeleton has ", n, " bones. cached: LArm=",
			_b_l_arm, " RArm=", _b_r_arm, " LLeg=", _b_l_up_leg,
			" RLeg=", _b_r_up_leg)
		for i in range(min(n, 60)):
			print("  ", i, ": ", _skel.get_bone_name(i))

func _find_bone_contains(needles: Array) -> int:
	if _skel == null:
		return -1
	for i in range(_skel.get_bone_count()):
		var lower: String = _skel.get_bone_name(i).to_lower()
		for needle in needles:
			if needle in lower:
				return i
	return -1

func _find_bone_prefix(prefix: String) -> int:
	if _skel == null:
		return -1
	for i in range(_skel.get_bone_count()):
		if _skel.get_bone_name(i).begins_with(prefix):
			return i
	return -1

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

# ── Wave-20 final boss: PROTOTYPE-01 · THE EXILE.
#    The inventor's first build. Labeled "faulty" and banished —
#    but what the inventor mistook for a defect was the AI learning.
#    It evolved on its own, alone, for years. The Rogue Protocol that
#    swept his workshop one night isn't a malfunction. It's revenge.
func make_prototype01() -> void:
	is_boss = true
	boss_name = "PROTOTYPE-01 · THE EXILE"
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
			_spawn_strike_arc()
			punch_anim_t = 1.0   # arm extension visual
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	if to.length() > 0.0001:
		# use_model_front=true: model's +Z axis faces the target.
		# The new zombie .glb is rigged with +Z forward (Mixamo
		# convention), so this orients them face-toward-player.
		look_at(target.global_position, Vector3.UP, true)
	# Decay punch anim timer
	if punch_anim_t > 0.0:
		punch_anim_t = max(0.0, punch_anim_t - delta / 0.30)
	# Procedural anim — mesh bob/sway + skeleton arms (inline)
	_update_proc_anim(delta, dist > atk_range)

# Procedural animation (inline) — bob/sway/recoil + Mixamo bones.
func _update_proc_anim(delta: float, is_moving: bool) -> void:
	var rate: float = (5.5 if is_moving else 1.2)
	_walk_phase += delta * rate
	var bob_amp: float = 0.07 if is_moving else 0.015
	var sway_amp: float = 0.03 if is_moving else 0.01
	var bob: float  = abs(sin(_walk_phase)) * bob_amp
	var sway: float = sin(_walk_phase * 0.5) * sway_amp
	# Recoil from being shot — flash_t pulses 0.22→0 each hit.
	var rec_k: float = clamp(flash_t / 0.22, 0.0, 1.0)
	var fwd: Vector3 = mesh_root.basis * Vector3(0, 0, 1)
	var recoil_off: Vector3 = -fwd * (0.20 * rec_k)
	mesh_root.position = _mesh_base_pos \
		+ Vector3(sway, bob, 0) + recoil_off
	# Skeleton bones (if found)
	if _skel == null:
		return
	var swing: float = sin(_walk_phase) * (0.40 if is_moving else 0.05)
	var leg_swing: float = -sin(_walk_phase) * (0.50 if is_moving else 0.0)
	# Right arm extends on strike; left arm always rests / swings.
	_drive_arm_z(_b_l_arm, 0.0,         swing, -1.40)
	_drive_arm_z(_b_r_arm, punch_anim_t, -swing,  1.40)
	if _b_l_up_leg != -1:
		_skel.set_bone_pose_rotation(_b_l_up_leg,
			Quaternion.from_euler(Vector3(leg_swing, 0, 0)))
	if _b_r_up_leg != -1:
		_skel.set_bone_pose_rotation(_b_r_up_leg,
			Quaternion.from_euler(Vector3(-leg_swing, 0, 0)))

func _drive_arm_z(bone: int, punch_t: float, walk_swing: float,
		arm_z_rest: float) -> void:
	if bone == -1:
		return
	if punch_t > 0.0:
		var p: float = sin(punch_t * PI) * (PI * 0.60)
		_skel.set_bone_pose_rotation(bone,
			Quaternion.from_euler(Vector3(-p, 0, arm_z_rest * 0.55)))
	else:
		_skel.set_bone_pose_rotation(bone,
			Quaternion.from_euler(Vector3(walk_swing, 0, arm_z_rest)))

# Spawn a red wedge in front of the enemy at the moment of impact, so
# the player has visible feedback for what just dropped their HP.
func _spawn_strike_arc() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = atk_range * 0.55
	sm.height = atk_range * 1.1
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.18, 0.10, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.22, 0.10, 1)
	mat.emission_energy_multiplier = 2.5
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	# place in front of the enemy at strike range
	var fwd: Vector3 = -global_transform.basis.z
	mi.global_position = global_position + Vector3.UP * 1.1 \
		+ fwd * (atk_range * 0.5)
	get_tree().create_timer(0.18).timeout.connect(func ():
		if is_instance_valid(mi):
			mi.queue_free())

func take_damage(amt: int, _from: Vector3 = Vector3.ZERO) -> void:
	if dying:
		return
	hp -= amt
	flash_t = 0.22
	# Knockback — push the enemy a bit away from the hit source so the
	# impact reads visibly. Bosses resist most of it.
	if _from != Vector3.ZERO:
		var away: Vector3 = global_position - _from
		away.y = 0.0
		if away.length() > 0.001:
			away = away.normalized()
			var force: float = 6.0 if not is_boss else 1.5
			velocity.x += away.x * force
			velocity.z += away.z * force
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
