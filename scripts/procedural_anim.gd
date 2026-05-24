# Procedural animation helper. Attach as a child of a CharacterBody3D,
# point `mesh_root` at the rendered Mesh node. Each frame the parent
# sets state (moving, sprint, in_air, l_punch_t, r_punch_t, smash_t,
# recoil_t); this script combines that state into mesh-level motion
# (bob / sway / tilt / recoil) and optional Skeleton3D bone overrides
# for Mixamo-named rigs (arms-down rest pose + walk swing + punch /
# smash overrides).
#
# Mesh-level motion always runs. Skeleton overrides only run if a
# Skeleton3D with Mixamo-style bones is found inside mesh_root — so
# even on non-rigged models you still get bob/sway/tilt.

extends Node

# ── External wiring ──
var mesh_root:   Node3D
var face_offset: float = 0.0  # PI for Dread (model's +Z faces forward)

# ── State driven by the parent each frame ──
var moving:    bool  = false
var sprint:    bool  = false
var in_air:    bool  = false
var l_punch_t: float = 0.0    # 0..1, 1 = mid-extension
var r_punch_t: float = 0.0
var smash_t:   float = 0.0    # 0..1, 1 = just triggered
var recoil_t:  float = 0.0    # 0..1, decays externally
var recoil_amp: float = 0.35

# ── Internal ──
var _walk_phase:    float = 0.0
var _mesh_base_pos: Vector3 = Vector3.ZERO
var _skel: Skeleton3D
# Cached bone IDs (-1 if not found)
var _b_l_arm:    int = -1
var _b_r_arm:    int = -1
var _b_l_forearm: int = -1
var _b_r_forearm: int = -1
var _b_l_up_leg: int = -1
var _b_r_up_leg: int = -1
var _b_spine:    int = -1
var _b_hips:     int = -1
# Hanging-arm rest rotations (computed at _ready) so we can return arms
# to a sensible idle pose between swings.
var _l_arm_rest: Quaternion = Quaternion.IDENTITY
var _r_arm_rest: Quaternion = Quaternion.IDENTITY

func _ready() -> void:
	if mesh_root == null:
		return
	_mesh_base_pos = mesh_root.position
	_skel = _find_skel(mesh_root)
	if _skel:
		_cache_bones()
		# Stash rest rotations (~80° down from T-pose, mirrored)
		_l_arm_rest = Quaternion.from_euler(Vector3(0.0, 0.0, -1.40))
		_r_arm_rest = Quaternion.from_euler(Vector3(0.0, 0.0,  1.40))

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null

func _cache_bones() -> void:
	for prefix in ["mixamorig_", "mixamorig:", "mixamorig1_", ""]:
		if _b_l_arm == -1:    _b_l_arm    = _skel.find_bone(prefix + "LeftArm")
		if _b_r_arm == -1:    _b_r_arm    = _skel.find_bone(prefix + "RightArm")
		if _b_l_forearm == -1: _b_l_forearm = _skel.find_bone(prefix + "LeftForeArm")
		if _b_r_forearm == -1: _b_r_forearm = _skel.find_bone(prefix + "RightForeArm")
		if _b_l_up_leg == -1: _b_l_up_leg = _skel.find_bone(prefix + "LeftUpLeg")
		if _b_r_up_leg == -1: _b_r_up_leg = _skel.find_bone(prefix + "RightUpLeg")
		if _b_spine == -1:    _b_spine    = _skel.find_bone(prefix + "Spine")
		if _b_hips == -1:     _b_hips     = _skel.find_bone(prefix + "Hips")

func _process(delta: float) -> void:
	if mesh_root == null:
		return

	# Advance walk phase faster when moving / sprinting.
	var rate: float = 1.6
	if moving:
		rate = 9.5 if sprint else 6.8
	_walk_phase += delta * rate

	# ── Mesh-level motion (always works) ──
	# Vertical bob from foot-plant, faint horizontal sway from hip
	# rotation. Both amplitudes shrink to a subtle idle pulse.
	var bob_amp:  float = 0.10 if moving else 0.02
	var sway_amp: float = 0.05 if moving else 0.015
	var bob:  float = abs(sin(_walk_phase)) * bob_amp
	var sway: float = sin(_walk_phase * 0.5) * sway_amp
	# Recoil: bob the mesh BACK along its facing.
	var fwd: Vector3 = mesh_root.basis * Vector3(0, 0, 1)
	# fwd already accounts for face_offset because the parent applies
	# yaw + face_offset to mesh_root.rotation.y before this runs.
	var recoil_offset: Vector3 = -fwd * (recoil_amp * recoil_t)
	mesh_root.position = _mesh_base_pos \
		+ Vector3(sway, bob, 0) + recoil_offset

	# Forward lean while running / sprinting.
	var target_pitch: float = 0.0
	if in_air:
		target_pitch = -0.10
	elif moving:
		target_pitch = -0.20 if sprint else -0.10
	mesh_root.rotation.x = lerp(mesh_root.rotation.x,
		target_pitch, 8.0 * delta)

	# ── Skeleton overrides (only if Mixamo bones were found) ──
	if _skel != null:
		_apply_skel_pose()

func _apply_skel_pose() -> void:
	# Walk-cycle: arms + legs swing on alternating phases.
	var swing: float = sin(_walk_phase) * (0.45 if moving else 0.06)
	var leg_swing: float = -sin(_walk_phase) * (0.55 if moving else 0.0)

	# ── Smash anim takes precedence: both arms raise then slam ──
	if smash_t > 0.0:
		# smash_t starts at 1.0 and decays to 0.0 (parent decays it).
		# inv = how far through the anim we are.
		var inv: float = clamp(1.0 - smash_t, 0.0, 1.0)
		var arm_z: float
		if inv < 0.35:
			# Wind-up: arms swing up overhead.
			arm_z = lerp(-1.40, -3.0, inv / 0.35)
		else:
			# Slam: arms come down hard past rest.
			arm_z = lerp(-3.0, -0.35, (inv - 0.35) / 0.65)
		_set_arm_rot(_b_l_arm,  arm_z)
		_set_arm_rot(_b_r_arm, -arm_z)
	else:
		# ── Each arm: punch override OR walk swing on top of rest ──
		_drive_arm(_b_l_arm,  l_punch_t, swing,  -1.40)
		_drive_arm(_b_r_arm,  r_punch_t, -swing,  1.40)

	# Legs swing whether punching or not — Dread keeps walking.
	if _b_l_up_leg != -1:
		_skel.set_bone_pose_rotation(_b_l_up_leg,
			Quaternion.from_euler(Vector3(leg_swing, 0, 0)))
	if _b_r_up_leg != -1:
		_skel.set_bone_pose_rotation(_b_r_up_leg,
			Quaternion.from_euler(Vector3(-leg_swing, 0, 0)))

# arm_z_rest: -1.4 for left arm, +1.4 for right arm (~80° down).
# punch_t (0..1) overrides the rest pose, swinging the arm forward.
func _drive_arm(bone: int, punch_t: float, walk_swing: float,
		arm_z_rest: float) -> void:
	if bone == -1:
		return
	if punch_t > 0.0:
		# Arm extends forward — rotate around X so the bone pitches
		# down/forward from the shoulder. Keep a touch of the rest Z
		# rotation so the arm doesn't snap straight to the side.
		var p: float = sin(punch_t * PI) * (PI * 0.65)
		_skel.set_bone_pose_rotation(bone,
			Quaternion.from_euler(
				Vector3(-p, 0, arm_z_rest * 0.55)))
	else:
		# Idle/walk: rest pose plus small forward/back swing.
		_skel.set_bone_pose_rotation(bone,
			Quaternion.from_euler(
				Vector3(walk_swing, 0, arm_z_rest)))

func _set_arm_rot(bone: int, z: float) -> void:
	if bone == -1:
		return
	_skel.set_bone_pose_rotation(bone,
		Quaternion.from_euler(Vector3(0, 0, z)))
