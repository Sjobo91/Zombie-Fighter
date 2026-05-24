# Player — REAPER. A gun-toting combat robot fighting the zombie horde.
# Big guns in both hands. Light gun on LMB, heavy cannon on RMB.
#   LMB   — light gun (fast, low damage per shot, white tracer)
#   RMB   — heavy cannon (slow, high damage + AoE splash, orange tracer)
#   Q     — MELTDOWN ult (3× rate + 1.6× damage for 5s)
#   R     — summon Ringworker ally
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
# LMB — light gun (rapid, single-target, white tracer)
@export var attack_dmg:   int   = 14
@export var attack_range: float = 55.0
@export var attack_cd:    float = 0.18      # fast pew-pew
# RMB — heavy cannon (slow, big AoE splash, orange tracer)
@export var gun_dmg:      int   = 55        # direct hit
@export var gun_splash:   int   = 25        # AoE around impact
@export var gun_splash_radius: float = 4.0
@export var gun_range:    float = 65.0
@export var gun_cd:       float = 0.75      # slow heavy cannon
# Legacy smash plumbing — used only by Q ult math now
@export var attack_arc:   float = 0.85
@export var smash_dmg:    int   = 70
@export var smash_range:  float = 5.2
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
var _b_l_elbow:  int = -1
var _b_r_elbow:  int = -1
var _b_l_up_leg: int = -1
var _b_r_up_leg: int = -1
var _b_spine:    int = -1
var _debug_t: float = 0.0
# Set each frame in _physics_process; consumed by _update_proc_anim
# to translate the mesh forward during the strike phase of a punch.
var _punch_lunge_now: float = 0.0
# How long to keep the AnimationPlayer playing (real seconds). Set
# by _punch / _smash; decremented each frame. When it hits 0, the
# animation is stopped early so we get just one punch's worth of
# the longer whirlwind clip.
var _anim_play_t: float = 0.0

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
var _clip_shoot:  String = ""

var hp:        int   = 140
var yaw:       float = 0.0
var pitch:     float = -0.55
var attack_t:  float = 999.0      # time since last hammer punch
var gun_t:     float = 999.0      # time since last gun shot
var smash_t:   float = 999.0      # time since last smash (legacy)
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
	# Repaint Reaper's body — sober industrial gunmetal so he reads
	# like the other workshop robots (the model ships with bright
	# cartoonish materials we don't want).
	_tint_player(mesh)
	# Hide any baked-in pedestal/base mesh that ships with the .glb
	# (common Sketchfab quirk — the model stands on its own disc).
	_hide_model_base(mesh)
	# Dump every MeshInstance3D name once so we can spot what to hide
	# if the auto-pass missed it.
	_dump_mesh_names(mesh, "  ")
	# Cache mesh base pose + find skeleton bones for procedural anim.
	_mesh_base_pos = mesh.position
	_skel = _find_skeleton(mesh)
	if _skel:
		_cache_bones()
		# Dump bone names ONCE so we can match the procedural anim
		# rotations to whatever rig this model uses.
		var nb: int = _skel.get_bone_count()
		print("[Reaper] Skeleton has ", nb, " bones:")
		for i in range(min(nb, 80)):
			print("  ", i, ": ", _skel.get_bone_name(i))
		print("[Reaper] cached: LArm=", _b_l_arm, " RArm=", _b_r_arm,
			" LLeg=", _b_l_up_leg, " RLeg=", _b_r_up_leg)
	# AnimationPlayer is now reserved for the SMASH — we DON'T auto-play
	# anything on spawn, so procedural anim is free to drive the
	# skeleton for idle/walk/punch.
	_anim_player = _find_anim_player(mesh)
	if _anim_player:
		_anim_list = _anim_player.get_animation_list()
		print("[Reaper] AnimationPlayer found with ", _anim_list.size(),
			" clips:")
		for n in _anim_list:
			print("  - ", n)
		_pick_clip_aliases()
		# explicitly stop so nothing auto-plays at scene load
		_anim_player.stop()
	else:
		print("[Reaper] no AnimationPlayer — procedural anim only")

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
	_clip_idle  = _first_matching(["idle", "T-Pose", "rest", "Stand"])
	_clip_walk  = _first_matching(["walk", "run", "walking"])
	_clip_punch = _first_matching(["punch", "attack", "hit", "swing",
		"jab", "hammer", "melee", "strike"])
	_clip_shoot = _first_matching(["shoot", "fire", "gun", "shot"])
	_clip_smash = _first_matching(["smash", "slam", "whirlwind", "reap",
		"heavy"])
	# Fall back to whatever's available so we have SOMETHING to play.
	if _clip_idle == "" and _anim_list.size() > 0:
		_clip_idle = _anim_list[0]
	if _clip_walk == "":
		_clip_walk = _clip_idle
	if _clip_smash == "":
		_clip_smash = _clip_punch
	print("[Reaper] clip map: idle=", _clip_idle,
		" walk=", _clip_walk,
		" punch=", _clip_punch,
		" shoot=", _clip_shoot,
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
	# Try Mixamo standard names first
	for prefix in ["mixamorig_", "mixamorig:", "mixamorig1_", "mixamorig2_", ""]:
		if _b_l_arm == -1:    _b_l_arm    = _skel.find_bone(prefix + "LeftArm")
		if _b_r_arm == -1:    _b_r_arm    = _skel.find_bone(prefix + "RightArm")
		if _b_l_up_leg == -1: _b_l_up_leg = _skel.find_bone(prefix + "LeftUpLeg")
		if _b_r_up_leg == -1: _b_r_up_leg = _skel.find_bone(prefix + "RightUpLeg")
		if _b_spine == -1:    _b_spine    = _skel.find_bone(prefix + "Spine")
	# Fallback: prefix-style custom rigs (Arm1_L_00, Leg1_R_019)
	if _b_l_arm == -1:    _b_l_arm    = _find_bone_prefix("Arm1_L")
	if _b_r_arm == -1:    _b_r_arm    = _find_bone_prefix("Arm1_R")
	if _b_l_up_leg == -1: _b_l_up_leg = _find_bone_prefix("Leg1_L")
	if _b_r_up_leg == -1: _b_r_up_leg = _find_bone_prefix("Leg1_R")
	# Reaper rig uses Thigh_L / Thigh_R for upper legs, plus various
	# arm-ish names we don't know yet. Substring search per side.
	if _b_l_up_leg == -1: _b_l_up_leg = _find_bone_contains(
		["thigh_l", "upleg_l", "upperleg_l", "leg_l_"])
	if _b_r_up_leg == -1: _b_r_up_leg = _find_bone_contains(
		["thigh_r", "upleg_r", "upperleg_r", "leg_r_"])
	if _b_l_arm == -1:    _b_l_arm    = _find_bone_contains(
		["bicep_l", "arm_l", "arml_", "leftarm", "shoulder_l",
		 "shoulderl", "upperarm_l", "upper_arm_l"])
	if _b_r_arm == -1:    _b_r_arm    = _find_bone_contains(
		["bicep_r", "arm_r", "armr_", "rightarm", "shoulder_r",
		 "shoulderr", "upperarm_r", "upper_arm_r"])
	# The actual elbow-bend rotation usually lives on the Forearm bone
	# (it's parented to the Bicep, so its local rotation = elbow joint).
	# Try forearm first, fall back to a separately-named Elbow bone.
	if _b_l_elbow == -1: _b_l_elbow = _find_bone_contains(
		["forearm_l", "leftforearm"])
	if _b_r_elbow == -1: _b_r_elbow = _find_bone_contains(
		["forearm_r", "rightforearm"])
	if _b_l_elbow == -1: _b_l_elbow = _find_bone_contains(["elbow_l"])
	if _b_r_elbow == -1: _b_r_elbow = _find_bone_contains(["elbow_r"])

func _find_bone_prefix(prefix: String) -> int:
	if _skel == null:
		return -1
	for i in range(_skel.get_bone_count()):
		if _skel.get_bone_name(i).begins_with(prefix):
			return i
	return -1

func _find_bone_contains(needles: Array) -> int:
	if _skel == null:
		return -1
	for i in range(_skel.get_bone_count()):
		var lower: String = _skel.get_bone_name(i).to_lower()
		for needle in needles:
			if needle in lower:
				return i
	return -1

# Hide any baked-in pedestal / floor-disc mesh that ships with the
# imported model. We're careful to skip body-part meshes whose names
# also contain words like "base" or "ground" by accident.
func _hide_model_base(node: Node) -> void:
	if node is MeshInstance3D:
		var n: String = node.name.to_lower()
		var is_body_part: bool = "legs" in n or "hands" in n \
			or "arm" in n or "head" in n or "body" in n \
			or "torso" in n or "chest" in n or "hip" in n
		var looks_like_pedestal: bool = ("floor" in n \
			or "pedestal" in n or "plinth" in n or "podium" in n \
			or n.begins_with("base") or n.begins_with("disc"))
		if looks_like_pedestal and not is_body_part:
			node.visible = false
			print("[Reaper] HID base mesh: ", node.name)
	for child in node.get_children():
		_hide_model_base(child)

# Print every MeshInstance3D in the model so we can manually identify
# any base/pedestal mesh that didn't match the auto-hide names.
func _dump_mesh_names(node: Node, indent: String) -> void:
	if node is MeshInstance3D:
		print(indent, "MESH: ", node.name)
	for child in node.get_children():
		_dump_mesh_names(child, indent + "  ")

func _tint_player(node: Node) -> void:
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
		_tint_player(child)

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
		_punch()        # LMB → hammer punch (left hand)
	if event.is_action_pressed("smash") and not dead:
		_fire_gun()     # RMB → gun (right hand)
	if event.is_action_pressed("summon_ally") and not dead:
		_summon_ally()
	if event.is_action_pressed("ult") and not dead:
		_activate_ult()

func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_t += delta
	gun_t    += delta
	smash_t  += delta
	summon_t += delta
	ult_t    += delta
	# Decay punch/smash animation timers (used by the procedural anim).
	# Longer punch window so the wind-up + strike + recover phases read.
	if l_punch_t > 0.0:
		l_punch_t = max(0.0, l_punch_t - delta / 0.55)
	if r_punch_t > 0.0:
		r_punch_t = max(0.0, r_punch_t - delta / 0.55)
	if smash_anim_t > 0.0:
		smash_anim_t = max(0.0, smash_anim_t - delta / 0.45)
	# Cut the AnimationPlayer clip short so we get just one punch's
	# worth of the long whirlwind, not its full multi-punch + step.
	if _anim_play_t > 0.0:
		_anim_play_t -= delta
		if _anim_play_t <= 0.0 and _anim_player \
				and _anim_player.is_playing():
			_anim_player.stop()
			_current_anim = ""
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
	# Reaper faces the camera direction (third-person aim).
	# Punch TWIST is an S-curve: body rotates AWAY from the punch
	# direction during wind-up (charge), then sweeps THROUGH into the
	# punch direction during the strike, then back to neutral. Per
	# user spec: "rotate upper body, arm follows, then continue
	# rotating through".
	var which_arm: float = 0.0     # +1 left, -1 right
	if l_punch_t > r_punch_t:
		which_arm = 1.0
	elif r_punch_t > 0.0:
		which_arm = -1.0
	var max_punch_t: float = max(l_punch_t, r_punch_t)
	var twist: float = 0.0
	if max_punch_t > 0.0:
		var inv: float = 1.0 - max_punch_t
		var amount: float = 0.0
		if inv < 0.36:
			amount = lerp(0.0, -1.30, inv / 0.36)            # cock back
		elif inv < 0.55:
			amount = lerp(-1.30, 1.20, (inv - 0.36) / 0.19)  # sweep through
		else:
			amount = lerp(1.20, 0.0, (inv - 0.55) / 0.45)
		twist = amount * which_arm
	var target_y: float = yaw + PI + twist
	mesh.rotation.y = lerp_angle(mesh.rotation.y, target_y, 28.0 * delta)
	# 3-phase whole-body punch pitch — wind-up back, strike forward,
	# recover. Inv goes 0 (just triggered) to 1 (done).
	# Also lunge forward in the strike window so the punch reads as
	# launched from the shoulder, not flapped from the elbow.
	var max_punch: float = max(l_punch_t, r_punch_t)
	var punch_lunge: float = 0.0
	if max_punch > 0.0:
		var inv: float = 1.0 - max_punch
		var pitch: float = 0.0
		if inv < 0.36:
			pitch = lerp(0.0, 0.40, inv / 0.36)            # cock back
		elif inv < 0.55:
			pitch = lerp(0.40, -0.55, (inv - 0.36) / 0.19) # SLAM forward
			punch_lunge = sin((inv - 0.36) / 0.19 * PI) * 1.20
		else:
			pitch = lerp(-0.55, 0.0, (inv - 0.55) / 0.45)
		mesh.rotation.x = pitch
	# Forward bow on smash. smash_anim_t decays 1.0 -> 0.0 over 0.45s.
	if smash_anim_t > 0.0:
		mesh.rotation.x = -1.0 * smash_anim_t
	move_and_slide()
	# Store lunge so _update_proc_anim can apply the position offset
	# alongside its mesh.position bookkeeping. (Set on self so the
	# function can read it without another out-parameter.)
	_punch_lunge_now = punch_lunge
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

# ── LMB: light gun (rapid pew-pew, low damage, alternating barrels).
func _punch() -> void:
	if attack_t < attack_cd * _ult_cd_mul():
		return
	attack_t = 0.0
	# Toggle muzzle side for visual variation, but DON'T trigger
	# the body twist/lunge — user wants a stable firing pose, just
	# tracers/flash/recoil as feedback.
	punch_left = not punch_left
	# Hitscan from camera ray
	var cam_xf := camera.global_transform
	var origin: Vector3 = cam_xf.origin
	var forward: Vector3 = -cam_xf.basis.z
	# Alternate the muzzle between left and right hands for that
	# dual-gun feel
	var dread_fwd: Vector3 = mesh.basis * Vector3(0, 0, 1)
	var dread_right: Vector3 = mesh.basis * Vector3(-1, 0, 0)
	var side: float = -0.50 if punch_left else 0.50
	# Muzzle at the model's arm/shoulder height — with the +2.5 m
	# model lift and 0.5 scale, arms sit around world Y 2.8-3.0.
	# Wider side-offset so left/right alternation shows clearly.
	var muzzle: Vector3 = global_position + Vector3.UP * 2.80 \
		+ dread_fwd * 0.40 + dread_right * side
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + forward * attack_range)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state \
		.intersect_ray(query)
	var end_point: Vector3 = origin + forward * attack_range
	var dmg: int = int(round(float(attack_dmg) * _ult_dmg_mul()))
	var direct_target: Node = null
	if hit:
		end_point = hit.position
		var col: Object = hit.collider
		if col and col is Node:
			var n: Node = col as Node
			if n.is_in_group("zombie"):
				direct_target = n
			elif n.get_parent() and n.get_parent().is_in_group("zombie"):
				direct_target = n.get_parent()
		if direct_target and direct_target.has_method("take_damage"):
			direct_target.take_damage(dmg, global_position)
		# Small explosion on impact — flash + shockwave ring + sparks
		_spawn_explosion(end_point, 0.90,
			Color(1.0, 0.85, 0.40, 0.85),
			Color(1.0, 0.65, 0.20, 1))
	# Bigger effective hitbox — large rounds, any zombie within 1.2m
	# of the impact point ALSO takes damage. Covers near-misses.
	var bullet_radius: float = 1.2
	for z in get_tree().get_nodes_in_group("zombie"):
		if not (z is Node3D) or z == direct_target:
			continue
		var d: float = (z as Node3D).global_position \
			.distance_to(end_point)
		if d <= bullet_radius and z.has_method("take_damage"):
			z.take_damage(dmg, global_position)
	# Fat white-yellow tracer streak — bigger so it actually reads
	_spawn_tracer(muzzle, end_point, 0.20, 0.18,
		Color(1.0, 0.95, 0.55, 1), Color(1.0, 0.80, 0.20, 1))
	# Big muzzle flash
	_spawn_punch_burst(muzzle, 0.30, 0.10)
	recoil_t = 0.05
	shake_t = max(shake_t, 0.04)
	shake_amp = max(shake_amp, 0.03)
	if _anim_player and _clip_shoot != "":
		_anim_player.stop()
		_anim_player.play(_clip_shoot, -1, 1.8)
		_current_anim = _clip_shoot
		_anim_play_t = 0.20

# ── RMB: double-fisted SMASH. Both arms slam down — 360° lava shockwave.
func _smash() -> void:
	if smash_t < smash_cd * _ult_cd_mul():
		return
	smash_t = 0.0
	smash_anim_t = 1.0
	# Smash gets the longer chunk of the whirlwind — multiple punches.
	if _anim_player and _clip_smash != "":
		_anim_player.stop()
		_anim_player.play(_clip_smash, -1, 1.0)
		_current_anim = _clip_smash
		_anim_play_t = 1.3    # 1.3 s of authored whirlwind at 1× speed
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
	# Lava shockwave ring around Reaper
	_spawn_lava_ring(global_position, smash_range)
	# BIG recoil + camera shake
	recoil_t = 0.25
	shake_t = max(shake_t, 0.32)
	shake_amp = max(shake_amp, 0.32)

# ── RMB: HEAVY CANNON. Slow, big tracer, AoE splash on impact.
func _fire_gun() -> void:
	if gun_t < gun_cd * _ult_cd_mul():
		return
	gun_t = 0.0
	var cam_xf := camera.global_transform
	var origin: Vector3 = cam_xf.origin
	var forward: Vector3 = -cam_xf.basis.z
	var dread_fwd: Vector3 = mesh.basis * Vector3(0, 0, 1)
	var dread_right: Vector3 = mesh.basis * Vector3(-1, 0, 0)
	# Heavy cannon — centered on the chest of the scaled model (~1.4 m).
	var muzzle: Vector3 = global_position + Vector3.UP * 1.40 \
		+ dread_fwd * 0.55
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + forward * gun_range)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state \
		.intersect_ray(query)
	var end_point: Vector3 = origin + forward * gun_range
	if hit:
		end_point = hit.position
		var col: Object = hit.collider
		var dmg: int = int(round(float(gun_dmg) * _ult_dmg_mul()))
		# Direct hit on the targeted zombie
		if col and col is Node:
			var n: Node = col as Node
			var target: Node = null
			if n.is_in_group("zombie"):
				target = n
			elif n.get_parent() and n.get_parent().is_in_group("zombie"):
				target = n.get_parent()
			if target and target.has_method("take_damage"):
				target.take_damage(dmg, global_position)
		# AoE splash — every zombie in radius takes splash damage
		var splash_dmg: int = int(round(float(gun_splash) * _ult_dmg_mul()))
		for z in get_tree().get_nodes_in_group("zombie"):
			if not (z is Node3D):
				continue
			var d: float = (z as Node3D).global_position \
				.distance_to(end_point)
			if d <= gun_splash_radius and z.has_method("take_damage"):
				z.take_damage(splash_dmg, global_position)
		# BIG orange explosion at the impact — flash, shockwave, sparks
		_spawn_explosion(end_point, gun_splash_radius * 1.1,
			Color(1.0, 0.50, 0.10, 0.92),
			Color(1.0, 0.30, 0.05, 1))
	# Big fat ORANGE tracer beam — heavy cannon round
	_spawn_tracer(muzzle, end_point, 0.30, 0.40,
		Color(1.0, 0.55, 0.15, 1), Color(1.0, 0.40, 0.08, 1))
	# Huge muzzle flash
	_spawn_punch_burst(muzzle, 0.65, 0.18)
	# Heavy recoil + camera shake
	recoil_t = 0.20
	shake_t = max(shake_t, 0.22)
	shake_amp = max(shake_amp, 0.18)
	if _anim_player and _clip_shoot != "":
		_anim_player.stop()
		_anim_player.play(_clip_shoot, -1, 1.0)
		_current_anim = _clip_shoot
		_anim_play_t = 0.50

# Bullet impact explosion — flash + expanding shockwave ring + scatter
# sparks. Used for both gun impacts (LMB small radius, RMB big radius).
func _spawn_explosion(pos: Vector3, radius: float,
		color_albedo: Color = Color(1.0, 0.55, 0.15, 0.85),
		color_emit: Color = Color(1.0, 0.40, 0.08, 1)) -> void:
	# Central bright flash
	_spawn_punch_burst(pos, radius * 0.55, 0.10)
	# Expanding shockwave ring
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.65
	tm.outer_radius = radius * 0.90
	tm.ring_segments = 24
	tm.rings = 8
	mi.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color_albedo
	mat.emission_enabled = true
	mat.emission = color_emit
	mat.emission_energy_multiplier = 5.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	var tween := create_tween().set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(1.6, 0.4, 1.6), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mi, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(func ():
		if is_instance_valid(mi):
			mi.queue_free())
	# Scatter sparks — small bursts radiating outward
	var sparks: int = max(3, int(radius * 4))
	for i in range(sparks):
		var ang: float = randf() * TAU
		var d: float = randf() * radius * 0.7
		var sp_pos: Vector3 = pos + Vector3(cos(ang) * d,
			randf() * radius * 0.4, sin(ang) * d)
		_spawn_punch_burst(sp_pos, radius * 0.18, 0.22)

# Glowing cylinder from muzzle to hit point — the bullet streak.
# radius and color let LMB (small, white-yellow) differ from RMB
# (fat, orange) without duplicating code.
func _spawn_tracer(a: Vector3, b: Vector3, ttl: float,
		radius: float = 0.15,
		color_albedo: Color = Color(1.0, 0.85, 0.4, 1),
		color_emit: Color = Color(1.0, 0.75, 0.25, 1)) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var length: float = (b - a).length()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = max(0.01, length)
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color_albedo
	mat.emission_enabled = true
	mat.emission = color_emit
	mat.emission_energy_multiplier = 6.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	var mid: Vector3 = (a + b) * 0.5
	mi.global_position = mid
	var dir: Vector3 = (b - a)
	if dir.length() > 0.001:
		mi.look_at(mi.global_position + dir, Vector3.UP, true)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	get_tree().create_timer(ttl).timeout.connect(func ():
		if is_instance_valid(mi):
			mi.queue_free())

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
	# spawn slightly behind Reaper so the model doesn't intersect with us
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
	# AnimationPlayer is triggered explicitly from _punch / _smash.
	# While it's playing, IT owns the skeleton; procedural bone
	# overrides would just get overwritten. When it finishes (or was
	# never started) procedural takes over.
	var anim_owns_skeleton: bool = _anim_player != null \
		and _anim_player.is_playing()
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
	# Smash dip — Reaper drops down + slightly forward on RMB.
	var smash_drop: float = -0.4 * smash_anim_t
	# Punch LUNGE — translate forward during strike phase so the body
	# shoots into the punch (set by _physics_process this frame).
	# fwd is mesh's +Z (back of the model); forward is -fwd.
	var lunge_off: Vector3 = -fwd * _punch_lunge_now
	mesh.position = _mesh_base_pos + Vector3(sway, bob + smash_drop, 0) \
		+ recoil_off + lunge_off
	# Debug ping every ~1s so we can verify the function is running.
	_debug_t += delta
	if _debug_t > 1.0:
		_debug_t = 0.0
		print("[Reaper anim] pos=", mesh.position,
			" walk=", snappedf(_walk_phase, 0.1),
			" moving=", is_moving)
	# Forward lean
	var target_pitch: float = 0.0
	if is_in_air:
		target_pitch = -0.10
	elif is_moving:
		target_pitch = -0.20 if is_sprint else -0.10
	mesh.rotation.x = lerp(mesh.rotation.x, target_pitch, 8.0 * delta)
	# Skeleton overrides (only when AnimationPlayer isn't owning the
	# skeleton — otherwise our bone sets would be overwritten).
	if _skel == null or anim_owns_skeleton:
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
		# Elbow piston-pumps for the actual punch motion
		_drive_elbow(_b_l_elbow, l_punch_t)
		_drive_elbow(_b_r_elbow, r_punch_t)
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
	# Bicep just gets a small pitch during punch — the visible motion
	# comes from the BODY TWIST (S-curve in _physics_process), BODY
	# LUNGE (mesh.position offset), and the ELBOW extension. Trying to
	# point the bicep "forward" via bone-local rotation kept producing
	# wrong-axis results for this rig.
	if punch_t > 0.0:
		var inv: float = 1.0 - punch_t
		var arm_x: float = 0.0
		if inv < 0.36:
			arm_x = lerp(0.0, 0.20, inv / 0.36)         # tuck back
		elif inv < 0.55:
			arm_x = lerp(0.20, -0.40, (inv - 0.36) / 0.19) # push forward
		else:
			arm_x = lerp(-0.40, 0.0, (inv - 0.55) / 0.45)
		_skel.set_bone_pose_rotation(bone,
			Quaternion.from_euler(Vector3(arm_x, 0, arm_z_rest)))
	else:
		_skel.set_bone_pose_rotation(bone,
			Quaternion.from_euler(Vector3(walk_swing, 0, arm_z_rest)))

# Piston pump on the elbow joint (rotation lives on Forearm bone).
# Wind-up folds the forearm in toward the bicep; strike snaps it back
# to straight while the body lunges forward.
func _drive_elbow(bone: int, punch_t: float) -> void:
	if bone == -1:
		return
	if punch_t > 0.0:
		var inv: float = 1.0 - punch_t
		var bend: float = 0.0
		if inv < 0.36:
			bend = lerp(0.0, PI * 0.85, inv / 0.36)
		elif inv < 0.55:
			bend = lerp(PI * 0.85, 0.0, (inv - 0.36) / 0.19)
		_skel.set_bone_pose_rotation(bone,
			Quaternion.from_euler(Vector3(bend, 0, 0)))
	else:
		_skel.set_bone_pose_rotation(bone, Quaternion.IDENTITY)

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
