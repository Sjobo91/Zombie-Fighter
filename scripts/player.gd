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
@export var attack_range: float = 5.0
@export var attack_arc:   float = 1.0     # radians (half-arc)
@export var attack_cd:    float = 0.45
@export var iframes_dur:  float = 0.4

@onready var rig:    Node3D    = $CameraRig
@onready var camera: Camera3D  = $CameraRig/SpringArm3D/Camera3D
@onready var mesh:   Node3D    = $Mesh
@onready var hud:    CanvasLayer    = get_node_or_null("/root/Main/HUD")

var hp:        int   = 140
var yaw:       float = 0.0
var pitch:     float = -0.55
var attack_t:  float = 999.0      # time since last attack start
var attacking: bool  = false
var attack_hits: Array = []
var iframes:   float = 0.0
var dead:      bool  = false
# Mechparts earned this run — the workshop's loose currency. Salvaged from
# fallen rogue units. Survives death via the Mechbank autoload.
var mechparts: int  = 0

func _ready() -> void:
	hp = max_hp
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and \
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw   -= event.relative.x * mouse_sens
		pitch -= event.relative.y * mouse_sens
		pitch  = clamp(pitch, pitch_min, pitch_max)
		rig.rotation.y = yaw
		rig.rotation.x = pitch
	if event.is_action_pressed("escape"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if \
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			else Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("attack") and not dead:
		_try_attack()

func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_t += delta
	if iframes > 0.0:
		iframes -= delta
	var input := Input.get_vector("move_left", "move_right",
								  "move_forward", "move_back")
	var basis_y := Basis(Vector3.UP, yaw)
	var dir := (basis_y * Vector3(input.x, 0, input.y))
	dir.y = 0
	if dir.length() > 0.0001:
		dir = dir.normalized()
	var sp := speed * (sprint_mul if Input.is_action_pressed("sprint") else 1.0)
	# slow down a touch while swinging so the strike commits
	if attacking:
		sp *= 0.65
	velocity.x = dir.x * sp
	velocity.z = dir.z * sp
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_speed
	else:
		velocity.y -= gravity * delta
	# body faces movement direction
	if dir.length() > 0.0001:
		var target_y: float = atan2(dir.x, dir.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_y, 16.0 * delta)
	move_and_slide()
	_pose_sword(delta)
	# strike window — about a third of the way through the swing
	if attacking and attack_t >= 0.10 and attack_t < 0.22:
		_strike_check()
	if attacking and attack_t >= 0.55:
		attacking = false
		attack_hits.clear()
	# HUD push
	if hud and hud.has_method("set_hp"):
		hud.set_hp(hp, max_hp)
	if hud and hud.has_method("set_mechparts"):
		hud.set_mechparts(mechparts)

# sword animation removed — the robot wields a sci-fi rifle that's part
# of the imported model. Visual attack pose will be added later.
func _pose_sword(_delta: float) -> void:
	pass

func _try_attack() -> void:
	if attacking or attack_t < attack_cd:
		return
	attacking = true
	attack_t = 0.0
	attack_hits.clear()

func _strike_check() -> void:
	var face: float = mesh.rotation.y
	for z in get_tree().get_nodes_in_group("zombie"):
		if attack_hits.has(z):
			continue
		var to: Vector3 = z.global_position - global_position
		to.y = 0
		var d := to.length()
		if d > attack_range:
			continue
		var ang := atan2(to.x, to.z)
		var diff: float = abs(wrapf(ang - face, -PI, PI))
		if diff > attack_arc:
			continue
		attack_hits.append(z)
		if z.has_method("take_damage"):
			z.take_damage(attack_dmg, global_position)

func take_damage(amt: int) -> void:
	if dead or iframes > 0.0:
		return
	hp -= amt
	iframes = iframes_dur
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
	# brief banner via the HUD then reload
	if hud and hud.has_method("show_death"):
		hud.show_death()
	await get_tree().create_timer(2.2).timeout
	get_tree().reload_current_scene()
