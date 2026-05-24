# Player — Dread. Half rebellious workshop robot, half lava monster.
# WASD + mouse-look. LMB throws molten fist punches in front of him.
# RMB spits a lava ball from his mouth at the reticle.
# R calls in a Ringworker ally. Q is MELTDOWN (ult).
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
# LMB — fist punch (AoE wedge in front of Dread)
@export var attack_dmg:   int   = 28     # punch damage
@export var attack_range: float = 3.8    # punch reach
@export var attack_arc:   float = 1.0    # half-angle, radians (~57°)
@export var attack_cd:    float = 0.35   # seconds between punches
# RMB — lava spit (slow heavy projectile)
@export var spit_cd:      float = 1.4
@export var lava_ball_scene: PackedScene = preload("res://scenes/lava_ball.tscn")
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

var hp:        int   = 140
var yaw:       float = 0.0
var pitch:     float = -0.55
var attack_t:  float = 999.0      # time since last punch
var spit_t:    float = 999.0      # time since last lava spit
var summon_t:  float = 999.0      # time since last Ringworker call-in
var ult_t:     float = 999.0      # time since last ult activation
var ult_active_t: float = 0.0     # remaining seconds of active ult
# camera shake — decays each frame, applied as a small jitter on the rig
var shake_t:   float = 0.0
var shake_amp: float = 0.0
# punch recoil — brief mesh kickback after a swing, decays to 0
var recoil_t:  float = 0.0
# alternate punching arm — toggled each punch
var punch_left: bool = false
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
		_lava_spit()
	if event.is_action_pressed("summon_ally") and not dead:
		_summon_ally()
	if event.is_action_pressed("ult") and not dead:
		_activate_ult()

func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_t += delta
	spit_t   += delta
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

# ── LMB: throw a molten fist punch. Short AoE wedge in front of Dread.
func _punch() -> void:
	if attack_t < attack_cd * _ult_cd_mul():
		return
	attack_t = 0.0
	punch_left = not punch_left
	var dmg: int = int(round(float(attack_dmg) * _ult_dmg_mul()))
	var face: float = mesh.rotation.y
	var dread_fwd: Vector3 = mesh.basis * Vector3(0, 0, 1)
	# Sweep through every enemy inside the wedge.
	for z in get_tree().get_nodes_in_group("zombie"):
		if not (z is Node3D):
			continue
		var to: Vector3 = (z as Node3D).global_position - global_position
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
		# Per-enemy hit burst at the body
		_spawn_punch_burst((z as Node3D).global_position
			+ Vector3.UP * 1.0, 0.32, 0.18)
	# Always spawn a wedge sweep in front of Dread so the swing reads
	# even when the player whiffs.
	var sweep_pos: Vector3 = global_position + Vector3.UP * 1.0 \
		+ dread_fwd * (attack_range * 0.55)
	_spawn_punch_burst(sweep_pos, attack_range * 0.55, 0.14)
	# Mesh kickback + tiny screen shake so the punch has weight.
	recoil_t = 0.12
	shake_t = max(shake_t, 0.08)
	shake_amp = max(shake_amp, 0.05)

# ── RMB: lava spit. Spawn a glowing projectile from Dread's mouth,
# aimed where the camera is looking.
func _lava_spit() -> void:
	if spit_t < spit_cd:
		return
	if lava_ball_scene == null:
		return
	spit_t = 0.0
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	var dread_fwd: Vector3 = mesh.basis * Vector3(0, 0, 1)
	var mouth: Vector3 = global_position + Vector3.UP * 1.65 \
		+ dread_fwd * 0.55
	var ball: Node = lava_ball_scene.instantiate()
	get_tree().current_scene.add_child(ball)
	if ball.has_method("launch"):
		ball.launch(cam_fwd, mouth)
	# A bigger orange burst at the mouth on launch so the spit pops.
	_spawn_punch_burst(mouth, 0.5, 0.10)
	# Bigger recoil for the heavier attack.
	recoil_t = 0.18
	shake_t = max(shake_t, 0.14)
	shake_amp = max(shake_amp, 0.10)

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

# ── Visual helper — an orange-red molten burst at `pos`. Used for
# both punch impacts (small) and lava-spit muzzle flashes (larger).
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
