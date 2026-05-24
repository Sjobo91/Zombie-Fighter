# Player — Dread, a tiny rebellious robot. WASD + mouse-look,
# LMB fires projectiles from its sci-fi rifle, RMB triggers a
# heavy smash, R calls in a Ringworker ally.
extends CharacterBody3D

@export var speed:        float = 9.0
@export var sprint_mul:   float = 1.55
@export var mouse_sens:   float = 0.0026
@export var jump_speed:   float = 7.0
@export var gravity:      float = 22.0
@export var pitch_min:    float = -1.2
@export var pitch_max:    float = -0.05
# combat
@export var max_hp:       int   = 140
@export var attack_dmg:   int   = 22
# legacy melee numbers (smash falls back to these)
@export var attack_range: float = 5.0
@export var attack_arc:   float = 1.0
@export var attack_cd:    float = 0.20   # gun fire rate
# gun
@export var gun_range:    float = 60.0
@export var smash_dmg:    int   = 48
@export var smash_range:  float = 4.0
@export var smash_cd:     float = 1.2
@export var summon_cd:    float = 25.0
@export var ally_scene:   PackedScene = preload("res://scenes/ally.tscn")
# OVERCLOCK ult — 5s of 3× fire rate + 1.6× damage
@export var ult_dur:      float = 5.0
@export var ult_cd:       float = 45.0
@export var iframes_dur:  float = 0.4

@onready var rig:    Node3D    = $CameraRig
@onready var camera: Camera3D  = $CameraRig/SpringArm3D/Camera3D
@onready var mesh:   Node3D    = $Mesh
@onready var hud:    CanvasLayer    = get_node_or_null("/root/Main/HUD")

var hp:        int   = 140
var yaw:       float = 0.0
var pitch:     float = -0.55
var attack_t:  float = 999.0      # time since last shot
var smash_t:   float = 999.0      # time since last smash
var summon_t:  float = 999.0      # time since last Ringworker call-in
var ult_t:     float = 999.0      # time since last ult activation
var ult_active_t: float = 0.0     # remaining seconds of active ult
var attacking: bool  = false      # only true during smash anim window
# camera shake — decays each frame, applied as a small jitter on the rig
var shake_t:   float = 0.0
var shake_amp: float = 0.0
# fire recoil — brief mesh kickback after a shot, decays to 0
var recoil_t:  float = 0.0
var attack_hits: Array = []
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
		_fire_gun()
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
	# brace through the smash anim
	if attacking:
		sp *= 0.55
	velocity.x = dir.x * sp
	velocity.z = dir.z * sp
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_speed
	else:
		velocity.y -= gravity * delta
	# Dread always faces where the camera looks (third-person aim).
	# The model's front is +Z (Mixamo convention) but the camera sits
	# along +Z behind the player, so add PI to flip Dread around to
	# face away from the camera — into the reticle, not at us.
	mesh.rotation.y = lerp_angle(mesh.rotation.y, yaw + PI, 16.0 * delta)
	# fire recoil: bob the mesh back a touch so each shot has visible
	# weight. Eases back to rest.
	var rec_k: float = clamp(recoil_t / 0.10, 0.0, 1.0)
	var dread_fwd_now: Vector3 = mesh.basis * Vector3(0, 0, 1)
	mesh.position = -dread_fwd_now * (0.35 * rec_k)
	move_and_slide()
	# smash hit window — partway through the swing
	if attacking and smash_t >= 0.10 and smash_t < 0.22:
		_smash_strike()
	if attacking and smash_t >= 0.45:
		attacking = false
		attack_hits.clear()
	# HUD push
	if hud and hud.has_method("set_hp"):
		hud.set_hp(hp, max_hp)
	if hud and hud.has_method("set_mechparts"):
		hud.set_mechparts(mechparts)
	if hud and hud.has_method("set_ult"):
		var cd_remaining: float = max(0.0, ult_cd - ult_t)
		hud.set_ult(ult_active_t, cd_remaining)

# ── Q: OVERCLOCK. 5s of 3× fire rate + 1.6× damage.
func _activate_ult() -> void:
	if ult_t < ult_cd or ult_active_t > 0.0:
		return
	ult_t = 0.0
	ult_active_t = ult_dur

func _ult_dmg_mul() -> float:
	return 1.6 if ult_active_t > 0.0 else 1.0

func _ult_cd_mul() -> float:
	return 1.0 / 3.0 if ult_active_t > 0.0 else 1.0

# ── LMB: fire a single round from Dread's rifle. Hitscan, with a
# visible tracer + muzzle flash + impact spark.
func _fire_gun() -> void:
	if attack_t < attack_cd * _ult_cd_mul():
		return
	attack_t = 0.0
	# Aim ray comes from the camera so the bullet hits whatever the
	# reticle is on.
	var cam_xf := camera.global_transform
	var origin: Vector3 = cam_xf.origin
	var forward: Vector3 = -cam_xf.basis.z
	# Visual muzzle sits in front of Dread, NOT at the camera. The
	# SpringArm puts the camera ~9 units behind him — if we anchored
	# the muzzle to the camera, the flash and the start of the tracer
	# pop up behind the player (looking like a yellow cone behind us).
	# Anchoring to Dread's own facing keeps the tracer leaving from
	# his body, then heading where the reticle points.
	var dread_fwd: Vector3 = mesh.basis * Vector3(0, 0, 1)
	var muzzle: Vector3 = global_position + Vector3.UP * 1.4 \
		+ dread_fwd * 0.8
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
		# climb up from the collision shape's body to find the
		# enemy script if needed
		var dmg: int = int(round(float(attack_dmg) * _ult_dmg_mul()))
		if col and col is Node:
			var n: Node = col as Node
			if n.is_in_group("zombie") and n.has_method("take_damage"):
				n.take_damage(dmg, global_position)
			elif n.get_parent() and n.get_parent().is_in_group("zombie"):
				var p: Node = n.get_parent()
				if p.has_method("take_damage"):
					p.take_damage(dmg, global_position)
		_spawn_spark(end_point)
	_spawn_tracer(muzzle, end_point, 0.06)
	_spawn_flash(muzzle, 0.05)
	# kick the recoil timer — physics_process bobs the mesh back briefly
	recoil_t = 0.10
	# tiny screen shake so the gun has weight
	shake_t = max(shake_t, 0.08)
	shake_amp = max(shake_amp, 0.05)

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

# ── RMB: heavier melee smash — slow but big AoE.
func _smash() -> void:
	if attacking or smash_t < smash_cd:
		return
	attacking = true
	smash_t = 0.0
	attack_hits.clear()

func _smash_strike() -> void:
	var face: float = mesh.rotation.y
	for z in get_tree().get_nodes_in_group("zombie"):
		if attack_hits.has(z):
			continue
		var to: Vector3 = z.global_position - global_position
		to.y = 0
		var d := to.length()
		if d > smash_range:
			continue
		var ang := atan2(to.x, to.z)
		var diff: float = abs(wrapf(ang - face, -PI, PI))
		if diff > attack_arc:
			continue
		attack_hits.append(z)
		if z.has_method("take_damage"):
			z.take_damage(smash_dmg, global_position)

# ── Visual helpers (no separate scenes — everything is built in code).
func _spawn_tracer(a: Vector3, b: Vector3, ttl: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var length: float = (b - a).length()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.025
	cm.height = max(0.01, length)
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4, 1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.25, 1)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	# orient cylinder along (a→b) — cylinder's default axis is +Y
	var mid: Vector3 = (a + b) * 0.5
	mi.global_position = mid
	var dir: Vector3 = (b - a)
	if dir.length() > 0.001:
		mi.look_at(mi.global_position + dir, Vector3.UP, true)
		# look_at points +Z forward; rotate so +Y points down dir
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	get_tree().create_timer(ttl).timeout.connect(func ():
		if is_instance_valid(mi):
			mi.queue_free())

func _spawn_flash(pos: Vector3, ttl: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.6, 1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4, 1)
	mat.emission_energy_multiplier = 5.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	get_tree().create_timer(ttl).timeout.connect(func ():
		if is_instance_valid(mi):
			mi.queue_free())

func _spawn_spark(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.65, 0.2, 1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1, 1)
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	get_tree().create_timer(0.10).timeout.connect(func ():
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
