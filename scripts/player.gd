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
var anim: Node = null

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
	# Attach procedural animation. It handles mesh bob/sway/recoil
	# plus Skeleton3D arm overrides when a Mixamo skeleton is found.
	var anim_script: Script = load("res://scripts/procedural_anim.gd")
	anim = Node.new()
	anim.set_script(anim_script)
	anim.mesh_root = mesh
	anim.face_offset = PI
	anim.recoil_amp = 0.35
	add_child(anim)

func _tint_dread(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var src := mi.get_active_material(0)
		if src is StandardMaterial3D:
			var dup := (src as StandardMaterial3D).duplicate() \
				as StandardMaterial3D
			dup.albedo_color = Color(0.18, 0.09, 0.05, 1)
			dup.metallic = 0.20
			dup.roughness = 0.85
			dup.emission_enabled = true
			dup.emission = Color(1.0, 0.32, 0.06, 1)
			dup.emission_energy_multiplier = 1.15
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
	# Dread always faces where the camera looks (third-person aim).
	# The model's front is +Z (Mixamo convention) but the camera sits
	# along +Z behind the player, so add PI to flip Dread around to
	# face away from the camera — into the reticle, not at us.
	mesh.rotation.y = lerp_angle(mesh.rotation.y, yaw + PI, 16.0 * delta)
	move_and_slide()
	# Feed the procedural animator. It owns mesh.position + bone poses.
	if anim:
		anim.moving    = dir.length() > 0.0001
		anim.sprint    = Input.is_action_pressed("sprint")
		anim.in_air    = not is_on_floor()
		anim.l_punch_t = l_punch_t
		anim.r_punch_t = r_punch_t
		anim.smash_t   = smash_anim_t
		anim.recoil_t  = clamp(recoil_t / 0.20, 0.0, 1.0)
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
