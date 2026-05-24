# Player — Dread. Half rebellious workshop robot, half lava monster.
# Plays like the Hulk: fast, jumpy, brutal.
#   LMB  — single-hand alternating molten punch (rapid)
#   RMB  — double-fisted ground smash with lava shockwave ring
#   Q    — MELTDOWN ult (3× swing rate + 1.6× dmg for 5s)
#   R    — summon Ringworker ally
#   Space — jump (plus 2 air-jumps for verticality)
extends CharacterBody3D

@export var speed:        float = 10.5    # base run speed
@export var sprint_mul:   float = 1.65
@export var mouse_sens:   float = 0.0026
@export var jump_speed:   float = 8.2
@export var air_jumps_max: int  = 2       # extra mid-air jumps
@export var gravity:      float = 22.0
@export var pitch_min:    float = -1.2
@export var pitch_max:    float = -0.05
# combat
@export var max_hp:       int   = 140
# LMB — single-hand alternating fist (Hulk style, fast)
@export var attack_dmg:   int   = 22
@export var attack_range: float = 3.6
@export var attack_arc:   float = 0.85    # ~49° half-angle (one arm)
@export var attack_cd:    float = 0.22    # rapid
# RMB — double-fisted SMASH (slow, big AoE, lava ring)
@export var smash_dmg:    int   = 70
@export var smash_range:  float = 5.2     # radius around Dread
@export var smash_cd:     float = 0.9
@export var summon_cd:    float = 25.0
@export var ally_scene:   PackedScene = preload("res://scenes/ally.tscn")
# MELTDOWN ult — 5s of 3× swing rate + 1.6× damage
@export var ult_dur:      float = 5.0
@export var ult_cd:       float = 45.0
@export var iframes_dur:  float = 0.4

@onready var rig:    Node3D    = $CameraRig
@onready var camera: Camera3D  = $CameraRig/SpringArm3D/Camera3D
@onready var mesh:   Node3D    = $Mesh
@onready var hud:    CanvasLayer    = get_node_or_null("/root/Main/HUD")

# Procedural animation state (fallback when there's no AnimationPlayer)
var _walk_phase:    float = 0.0
var _mesh_base_pos: Vector3 = Vector3.ZERO
var _skel: Skeleton3D = null
var _b_l_arm:    int = -1
var _b_r_arm:    int = -1
var _b_l_up_leg: int = -1
var _b_r_up_leg: int = -1
var _b_spine:    int = -1
var _debug_t: float = 0.0

# Real animation — if the glb has an AnimationPlayer, we play named
# clips from it instead of procedurally driving bones.
var _anim_player: AnimationPlayer = null
var _anim_list:   PackedStringArray = PackedStringArray()
var _current_anim: String = ""
# Best-guess names of clips for each state (filled in once we know
# what's actually in the model).
var _clip_idle:   String = ""
var _clip_walk:   String = ""
var _clip_punch:  String = ""
var _clip_smash:  String = ""

var hp:        int   = 140
var yaw:       float = 0.0
var pitch:     float = -0.55
var attack_t:  float = 999.0      # time since last punch
var smash_t:   float = 999.0      # time since last double-fist smash
var summon_t:  float = 999.0      # time since last Ringworker call-in
var ult_t:     float = 999.0      # time since last ult activation
var ult_active_t: float = 0.0     # remaining seconds of active ult
var air_jumps_left: int = 0       # refreshed when landing
# camera shake — decays each frame, applied as a small jitter on the rig
var shake_t:   float = 0.0
var shake_amp: float = 0.0
# attack recoil — brief mesh kickback after a swing, decays to 0
var recoil_t:  float = 0.0
# alternate punching arm — toggled each punch (for animation)
var punch_left: bool = false
# per-arm animation timers, 0..1 (1 = mid-extension). Drive the
# Skeleton3D arm overrides for visible swings.
var l_punch_t: float = 0.0
var r_punch_t: float = 0.0
# smash anim timer — 0..1 over the smash window for both arms slam.
var smash_anim_t: float = 0.0
var iframes:   float = 0.0
var dead:      bool  = false
# Mechparts earned this run — the workshop's loose currency. Salvaged from
# fallen rogue units. Survives death via the Mechbank autoload.
var mechparts: int  = 0

func _ready() -> void:
	add_to_group("player")
	# pull in any permanent upgrades the player bought between runs
	var bank := get_node_or_null("/root/Mechbank")
	if bank and bank.has_method("apply_to_player"):
		bank.apply_to_player(self)
	hp = max_hp
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Tint Dread lava-themed — dark molten rock with bright orange
	# emission cracks. Runs after the model is fully loaded so every
	# MeshInstance3D in the .glb gets repainted.
	_tint_dread(mesh)
	# Cache mesh base pose + find skeleton bones for procedural anim.
	_mesh_base_pos = mesh.position
	_skel = _find_skeleton(mesh)
	if _skel:
		_cache_bones()
	# Hook up the model's AnimationPlayer if it has one.
	_anim_player = _find_anim_player(mesh)
	if _anim_player:
		_anim_list = _anim_player.get_animation_list()
		print("[Dread] AnimationPlayer found with ", _anim_list.size(),
			" clips:")
		for n in _anim_list:
			print("  - ", n)
		_pick_clip_aliases()
		if _clip_idle != "":
			_anim_player.play(_clip_idle)
			_current_anim = _clip_idle
	else:
		print("[Dread] no AnimationPlayer — falling back to procedural anim")

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_anim_player(c)
		if f != null:
			return f
	return null

# Pick which clip names map to our gameplay states. Different rigs name
# things differently — we accept any reasonable alias.
func _pick_clip_aliases() -> void:
	_clip_idle  = _first_matching(["idle", "Idle", "T-Pose", "rest", "Stand"])
	_clip_walk  = _first_matching(["walk", "Walk", "run", "Run", "walking"])
	_clip_punch = _first_matching(["punch", "Punch", "attack", "Attack",
		"swing", "jab"])
	_clip_smash = _first_matching(["smash", "Smash", "slam", "Slam",
		"whirlwind", "reap", "Reap"])
	# If nothing matched a category, fall back to whatever's available.
	if _clip_idle == "" and _anim_list.size() > 0:
		_clip_idle = _anim_list[0]
	if _clip_walk == "":
		_clip_walk = _clip_idle
	if _clip_punch == "":
		_clip_punch = _clip_idle
	if _clip_smash == "":
		_clip_smash = _clip_punch
	print("[Dread] clip map: idle=", _clip_idle,
		" walk=", _clip_walk,
		" punch=", _clip_punch,
		" smash=", _clip_smash)

func _first_matching(needles: Array) -> String:
	for n in _anim_list:
		var lower: String = String(n).to_lower()
		for needle in needles:
			if lower.find(String(needle).to_lower()) != -1:
				return n
	return ""

func _play_clip(name: String, speed: float = 1.0) -> void:
	if _anim_player == null or name == "" or name == _current_anim:
		return
	_current_anim = name
	_anim_player.play(name, -1, speed)

# Pick the right clip based on player state. Punch / smash take
# priority because they're transient; walk / idle are the steady states.
func _drive_real_animations(is_moving: bool, is_sprint: bool) -> void:
	if smash_anim_t > 0.0:
		_play_clip(_clip_smash, 1.4)
	elif l_punch_t > 0.0 or r_punch_t > 0.0:
		_play_clip(_clip_punch, 1.6)
	elif is_moving:
		_play_clip(_clip_walk, 1.4 if is_sprint else 1.0)
	else:
		_play_clip(_clip_idle, 1.0)

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
	for prefix in ["mixamorig_", "mixamorig:", "mixamorig1_", "mixamorig2_", ""]:
		if _b_l_arm == -1:    _b_l_arm    = _skel.find_bone(prefix + "LeftArm")
		if _b_r_arm == -1:    _b_r_arm    = _skel.find_bone(prefix + "RightArm")
		if _b_l_up_leg == -1: _b_l_up_leg = _skel.find_bone(prefix + "LeftUpLeg")
		if _b_r_up_leg == -1: _b_r_up_leg = _skel.find_bone(prefix + "RightUpLeg")
		if _b_spine == -1:    _b_spine    = _skel.find_bone(prefix + "Spine")

func _tint_dread(node: Node) -> void:
	# Sober industrial-robot palette — cool gunmetal, brushed,
	# no emission. Reads like the other workshop bots, not cartoonish.
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var src := mi.get_active_material(0)
		if src is StandardMaterial3D:
			var dup := (src as StandardMaterial3D).duplicate() \
				as StandardMaterial3D
			dup.albedo_color = Color(0.30, 0.32, 0.36, 1)
			dup.metallic = 0.85
			dup.roughness = 0.45
			dup.emission_enabled = false
			mi.set_surface_override_material(0, dup)
	for child in node.get_children():
		_tint_dread(child)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and \
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw   -= event.relative.x * mouse_sens
		pitch -= event.relative.y * mouse_sens
		pitch  = clamp(pitch, pitch_min, pitch_max)
		rig.rotation.y = yaw
		rig.rotation.x = pitch
	# Esc is owned by the HUD (it opens the pause menu).
	if event.is_action_pressed("attack") and not dead:
		_punch()
	if event.is_action_pressed("smash") and not dead:
		_smash()
	if event.is_action_pressed("summon_ally") and not dead:
		_summon_ally()
	if event.is_action_pressed("ult") and not dead:
		_activate_ult()

func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_t += delta
	smash_t  += delta
	summon_t += delta
	ult_t    += delta
	# Decay punch/smash animation timers (used by the procedural anim)
	if l_punch_t > 0.0:
		l_punch_t = max(0.0, l_punch_t - delta / 0.18)
	if r_punch_t > 0.0:
		r_punch_t = max(0.0, r_punch_t - delta / 0.18)
	if smash_anim_t > 0.0:
		smash_anim_t = max(0.0, smash_anim_t - delta / 0.45)
	if ult_active_t > 0.0:
		ult_active_t -= delta
	if iframes > 0.0:
		iframes -= delta
	# decay shake + recoil timers
	if shake_t > 0.0:
		shake_t -= delta
		if shake_t <= 0.0:
			shake_amp = 0.0
			rig.position = Vector3(0, 2.0, 0)
		else:
			var k: float = shake_t / 0.28
			var jx: float = (randf() * 2.0 - 1.0) * shake_amp * k
			var jy: float = (randf() * 2.0 - 1.0) * shake_amp * k
			rig.position = Vector3(jx, 2.0 + jy, 0)
	if recoil_t > 0.0:
		recoil_t -= delta
	var input := Input.get_vector("move_left", "move_right",
								  "move_forward", "move_back")
	var basis_y := Basis(Vector3.UP, yaw)
	var dir := (basis_y * Vector3(input.x, 0, input.y))
	dir.y = 0
	if dir.length() > 0.0001:
		dir = dir.normalized()
	var sp := speed * (sprint_mul if Input.is_action_pressed("sprint") else 1.0)
	velocity.x = dir.x * sp
	velocity.z = dir.z * sp
	if is_on_floor():
		air_jumps_left = air_jumps_max
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_speed
	else:
		velocity.y -= gravity * delta
		# Hulk-hops: extra mid-air jumps
		if Input.is_action_just_pressed("jump") and air_jumps_left > 0:
			velocity.y = jump_speed
			air_jumps_left -= 1
	# Dread faces the camera direction (third-person aim).
	# Per-arm punch TWIST whips body left/right with each LMB.
	# Smash-pitch tips body forward on RMB.
	var twist: float = (l_punch_t * 1.0) - (r_punch_t * 1.0)
	var target_y: float = yaw + PI + twist
	mesh.rotation.y = lerp_angle(mesh.rotation.y, target_y, 22.0 * delta)
	# Forward bow on smash. smash_anim_t goes 1.0 -> 0.0 over 0.45s.
	# We tilt forward steeply (max -1.0 rad ≈ -57°) at peak smash.
	var smash_pitch: float = -1.0 * smash_anim_t
	# (don't fight the walk-lean from _update_proc_anim; that uses a
	# slower lerp on rotation.x. Override here in physics so smash_pitch
	# wins during the smash window.)
	if smash_anim_t > 0.0:
		mesh.rotation.x = smash_pitch
	move_and_slide()
	# Procedural animation — mesh bob/sway + Skeleton3D bone overrides
	var is_moving: bool = dir.length() > 0.0001
	var is_sprint: bool = Input.is_action_pressed("sprint")
	var is_in_air: bool = not is_on_floor()
	_update_proc_anim(delta, is_moving, is_sprint, is_in_air)
	# HUD push
	if hud and hud.has_method("set_hp"):
		hud.set_hp(hp, max_hp)
	if hud and hud.has_method("set_mechparts"):
		hud.set_mechparts(mechparts)
	if hud and hud.has_method("set_ult"):
		var cd_remaining: float = max(0.0, ult_cd - ult_t)
		hud.set_ult(ult_active_t, cd_remaining)

# ── Q: MELTDOWN. 5s of 3× swing rate + 1.6× damage.
func _activate_ult() -> void:
	if ult_t < ult_cd or ult_active_t > 0.0:
		return
	ult_t = 0.0
	ult_active_t = ult_dur

func _ult_dmg_mul() -> float:
	return 1.6 if ult_active_t > 0.0 else 1.0

func _ult_cd_mul() -> float:
	return 1.0 / 3.0 if ult_active_t > 0.0 else 1.0

# ── LMB: single-hand alternating fist punch. Hulk-style — rapid jabs.
func _punch() -> void:
	if attack_t < attack_cd * _ult_cd_mul():
		return
	attack_t = 0.0
	punch_left = not punch_left
	# Drive the procedural anim's per-arm extension
	if punch_left:
		l_punch_t = 1.0
	else:
		r_punch_t = 1.0
	var dmg: int = int(round(float(attack_dmg) * _ult_dmg_mul()))
	var face: float = mesh.rotation.y
	var dread_fwd: Vector3 = mesh.basis * Vector3(0, 0, 1)
	var dread_right: Vector3 = mesh.basis * Vector3(-1, 0, 0)
	# Offset the hit-test slightly to the punching side so the AoE
	# actually feels like one arm.
	var side: float = 0.4 if punch_left else -0.4
	var hit_origin: Vector3 = global_position + dread_right * side
	for z in get_tree().get_nodes_in_group("zombie"):
		if not (z is Node3D):
			continue
		var to: Vector3 = (z as Node3D).global_position - hit_origin
		to.y = 0.0
		var d: float = to.length()
		if d > attack_range:
			continue
		var ang := atan2(to.x, to.z)
		var diff: float = abs(wrapf(ang - face, -PI, PI))
		if diff > attack_arc:
			continue
		if z.has_method("take_damage"):
			z.take_damage(dmg, global_position)
		_spawn_punch_burst((z as Node3D).global_position
			+ Vector3.UP * 1.0, 0.34, 0.18)
	# Burst at the punching fist's reach so even a whiff reads
	var burst_pos: Vector3 = global_position + Vector3.UP * 1.0 \
		+ dread_fwd * (attack_range * 0.55) + dread_right * side
	_spawn_punch_burst(burst_pos, attack_range * 0.32, 0.10)
	recoil_t = 0.08
	shake_t = max(shake_t, 0.06)
	shake_amp = max(shake_amp, 0.04)

# ── RMB: double-fisted SMASH. Both arms slam down — 360° lava shockwave.
func _smash() -> void:
	if smash_t < smash_cd * _ult_cd_mul():
		return
	smash_t = 0.0
	smash_anim_t = 1.0
	var dmg: int = int(round(float(smash_dmg) * _ult_dmg_mul()))
	for z in get_tree().get_nodes_in_group("zombie"):
		if not (z is Node3D):
			continue
		var to: Vector3 = (z as Node3D).global_position - global_position
		to.y = 0.0
		var d: float = to.length()
		if d > smash_range:
			continue
		if z.has_method("take_damage"):
			z.take_damage(dmg, global_position)
		_spawn_punch_burst((z as Node3D).global_position
			+ Vector3.UP * 1.0, 0.5, 0.26)
	# Lava shockwave ring around Dread
	_spawn_lava_ring(global_position, smash_range)
	# BIG recoil + camera shake
	recoil_t = 0.25
	shake_t = max(shake_t, 0.32)
	shake_amp = max(shake_amp, 0.32)

# ── R: call in a Ringworker ally that fights for ~15s.
func _summon_ally() -> void:
	if summon_t < summon_cd:
		return
	if ally_scene == null:
		return
	summon_t = 0.0
	var inst: Node = ally_scene.instantiate()
	if not (inst is Node3D):
		return
	# spawn slightly behind Dread so the model doesn't intersect with us
	var back: Vector3 = (Basis(Vector3.UP, yaw) * Vector3(0, 0, 1.4))
	(inst as Node3D).global_position = global_position + back
	get_tree().current_scene.add_child(inst)

# ── Lava shockwave ring — torus on the floor that expands + fades.
# Spawned by the double-fisted smash.
func _spawn_lava_ring(center: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.55
	tm.outer_radius = radius * 0.75
	tm.ring_segments = 24
	tm.rings = 8
	mi.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.45, 0.10, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.32, 0.05, 1)
	mat.emission_energy_multiplier = 5.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = center + Vector3.UP * 0.05
	# Expand the ring outward + fade out over 0.45s.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(1.55, 1.0, 1.55), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mi, "modulate:a", 0.0, 0.45)
	tween.chain().tween_callback(func ():
		if is_instance_valid(mi):
			mi.queue_free())

# ── Visual helper — an orange-red molten burst at `pos`. Used for
# punch impacts and (formerly) lava-spit launch flashes.
func _spawn_punch_burst(pos: Vector3, radius: float, ttl: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.70)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.40, 0.08, 1)
	mat.emission_energy_multiplier = 4.5
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	get_tree().create_timer(ttl).timeout.connect(func ():
		if is_instance_valid(mi):
			mi.queue_free())

# ── Procedural animation — mesh bob/sway/lean/recoil (always), plus
# Skeleton3D arm/leg overrides when the model is Mixamo-rigged.
func _update_proc_anim(delta: float, is_moving: bool,
		is_sprint: bool, is_in_air: bool) -> void:
	# Real animations override everything else when available.
	if _anim_player != null:
		_drive_real_animations(is_moving, is_sprint)
		return
	var rate: float = 1.6
	if is_moving:
		rate = 9.5 if is_sprint else 6.8
	_walk_phase += delta * rate
	# Mesh-level: vertical bob + horizontal sway + recoil + smash dip.
	# Cranked since the model is tiny vs. the 9m camera distance.
	var bob_amp:  float = 0.55 if is_moving else 0.18
	var sway_amp: float = 0.25 if is_moving else 0.08
	var bob:  float = abs(sin(_walk_phase)) * bob_amp
	var sway: float = sin(_walk_phase * 0.5) * sway_amp
	var rec_k: float = clamp(recoil_t / 0.20, 0.0, 1.0)
	var fwd: Vector3 = mesh.basis * Vector3(0, 0, 1)
	var recoil_off: Vector3 = -fwd * (0.55 * rec_k)
	# Smash dip — when smashing, Dread drops down and forward.
	var smash_drop: float = -0.4 * smash_anim_t
	mesh.position = _mesh_base_pos + Vector3(sway, bob + smash_drop, 0) \
		+ recoil_off
	# Debug ping every ~1s so we can verify the function is running.
	_debug_t += delta
	if _debug_t > 1.0:
		_debug_t = 0.0
		print("[Dread anim] pos=", mesh.position,
			" walk=", snappedf(_walk_phase, 0.1),
			" moving=", is_moving)
	# Forward lean
	var target_pitch: float = 0.0
	if is_in_air:
		target_pitch = -0.10
	elif is_moving:
		target_pitch = -0.20 if is_sprint else -0.10
	mesh.rotation.x = lerp(mesh.rotation.x, target_pitch, 8.0 * delta)
	# Skeleton overrides (only if bones found)
	if _skel == null:
		return
	var swing: float = sin(_walk_phase) * (0.45 if is_moving else 0.06)
	var leg_swing: float = -sin(_walk_phase) * (0.55 if is_moving else 0.0)
	# Smash overrides both arms (raise + slam)
	if smash_anim_t > 0.0:
		var inv: float = clamp(1.0 - smash_anim_t, 0.0, 1.0)
		var arm_z: float
		if inv < 0.35:
			arm_z = lerp(-1.40, -3.0, inv / 0.35)
		else:
			arm_z = lerp(-3.0, -0.35, (inv - 0.35) / 0.65)
		if _b_l_arm != -1:
			_skel.set_bone_pose_rotation(_b_l_arm,
				Quaternion.from_euler(Vector3(0, 0, arm_z)))
		if _b_r_arm != -1:
			_skel.set_bone_pose_rotation(_b_r_arm,
				Quaternion.from_euler(Vector3(0, 0, -arm_z)))
	else:
		_drive_arm(_b_l_arm, l_punch_t,  swing, -1.40)
		_drive_arm(_b_r_arm, r_punch_t, -swing,  1.40)
	if _b_l_up_leg != -1:
		_skel.set_bone_pose_rotation(_b_l_up_leg,
			Quaternion.from_euler(Vector3(leg_swing, 0, 0)))
	if _b_r_up_leg != -1:
		_skel.set_bone_pose_rotation(_b_r_up_leg,
			Quaternion.from_euler(Vector3(-leg_swing, 0, 0)))

func _drive_arm(bone: int, punch_t: float, walk_swing: float,
		arm_z_rest: float) -> void:
	if bone == -1:
		return
	if punch_t > 0.0:
		var p: float = sin(punch_t * PI) * (PI * 0.65)
		_skel.set_bone_pose_rotation(bone,
			Quaternion.from_euler(Vector3(-p, 0, arm_z_rest * 0.55)))
	else:
		_skel.set_bone_pose_rotation(bone,
			Quaternion.from_euler(Vector3(walk_swing, 0, arm_z_rest)))

func take_damage(amt: int) -> void:
	if dead or iframes > 0.0:
		return
	hp -= amt
	iframes = iframes_dur
	# screen flash + camera shake so the hit lands visibly
	if hud and hud.has_method("pulse_damage_flash"):
		hud.pulse_damage_flash()
	shake_t = 0.28
	shake_amp = 0.18
	if hp <= 0:
		hp = 0
		dead = true
		_die()

func collect_mechparts(amt: int) -> void:
	mechparts += amt
	if hud and hud.has_method("set_mechparts"):
		hud.set_mechparts(mechparts)
	# accumulate into the persistent bank so they survive death
	var bank := get_node_or_null("/root/Mechbank")
	if bank and bank.has_method("add_run_earn"):
		bank.add_run_earn(amt)

func _die() -> void:
	# bank what we earned (death = 50%) and return to title with stats.
	var bank := get_node_or_null("/root/Mechbank")
	var earned: int = 0 if bank == null else int(bank.run_earned)
	var banked: int = int(round(float(earned) * 0.5))
	if bank and bank.has_method("on_run_end"):
		bank.on_run_end(false)
	var wave_reached: int = 0
	var wm := get_node_or_null("/root/Main/WaveManager")
	if wm:
		wave_reached = int(wm.wave)
	if hud and hud.has_method("show_death"):
		hud.show_death(wave_reached, earned, banked)
	await get_tree().create_timer(3.4).timeout
	get_tree().change_scene_to_file("res://scenes/title.tscn")
