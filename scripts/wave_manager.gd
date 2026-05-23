# Wave Manager — drives the 20-wave campaign through the workshop.
#
# You are a tiny robot loose inside a giant inventor's workshop.
# Every act is a different section of that workshop, and the rogue
# constructs there march to silence you.
#
#   Act I   (waves 1-7)   THE ASSEMBLY FLOOR
#   Act II  (waves 8-13)  THE LOGISTICS BAY
#   Act III (waves 14-19) THE ENGINEERING LAB
#   Wave 10  → THE IRON COLOSSUS (mini-boss)
#   Wave 20  → PROTOTYPE-01 · THE PROGENITOR (final boss, at the
#              ENGINE CORE — heart of the workshop's power)
#
# Spawns enemies in a ring around the player. After all spawns are
# dead, a short breather plays, then the next wave begins.

extends Node

# The basic enemy scene (and the chassis for the bosses — wave_manager
# always uses zombie_scene for the wave-10/20 last spawn so the boss
# methods on zombie.gd hit the imported model.)
@export var zombie_scene:           PackedScene
@export var zombie_warrior_scene:   PackedScene
@export var zombie_runner_scene:    PackedScene
@export var zombie_x10_scene:       PackedScene
@export var zombie_lugnut_scene:    PackedScene
@export var spawn_radius:    float = 19.0
@export var spawn_radius_jitter: float = 10.0
@export var spawn_interval:  float = 0.45
@export var breather_seconds: float = 4.0
@export var total_waves:     int   = 20

var wave: int = 0
var to_spawn:  int   = 0
var spawned:   int   = 0
var spawn_t:   float = 0.0
var wave_active: bool = false
var rest_t:    float = 0.0
var player:    Node3D = null
var victory:   bool = false

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node3D
	# kick off wave 1 after the rest of the scene settles
	call_deferred("_start_wave", 1)

func _physics_process(delta: float) -> void:
	if victory:
		return
	if player == null or not player.is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as Node3D
		if player == null:
			return
	# breather between waves
	if rest_t > 0.0:
		rest_t -= delta
		if rest_t <= 0.0:
			_start_wave(wave + 1)
		return
	if not wave_active:
		return
	# spawn over time
	if spawned < to_spawn:
		spawn_t -= delta
		if spawn_t <= 0.0:
			_spawn_one()
			spawn_t = spawn_interval
	# clear-check — all spawned + no alive zombies = wave done
	if spawned >= to_spawn:
		var alive: int = get_tree().get_nodes_in_group("zombie").size()
		if alive == 0:
			_end_wave()

func _start_wave(n: int) -> void:
	wave = n
	to_spawn = wave_size(n)
	spawned = 0
	spawn_t = 0.0
	wave_active = true
	var hud := get_node_or_null("/root/Main/HUD")
	if hud and hud.has_method("show_wave_banner"):
		hud.show_wave_banner(n, total_waves, act_label(n))

func _end_wave() -> void:
	wave_active = false
	if wave >= total_waves:
		victory = true
		var bank := get_node_or_null("/root/Mechbank")
		if bank and bank.has_method("on_run_end"):
			bank.on_run_end(true)
		var hud := get_node_or_null("/root/Main/HUD")
		if hud and hud.has_method("show_victory"):
			hud.show_victory()
		# after the victory banner, return to title so the bank
		# upgrades become spendable
		await get_tree().create_timer(6.0).timeout
		get_tree().change_scene_to_file("res://scenes/title.tscn")
		return
	rest_t = breather_seconds
	var hud := get_node_or_null("/root/Main/HUD")
	if hud and hud.has_method("show_clear_banner"):
		hud.show_clear_banner(wave)

func _spawn_one() -> void:
	var a: float = randf() * TAU
	var d: float = spawn_radius + randf() * spawn_radius_jitter
	var pos: Vector3 = player.global_position + \
		Vector3(cos(a) * d, 1.0, sin(a) * d)
	var is_last: bool = (spawned == to_spawn - 1)
	# Bosses always use the basic chassis (zombie.gd's make_colossus /
	# make_mortimer tint and scale it). All other spawns pick a variant
	# weighted by act.
	var scn: PackedScene = zombie_scene
	if not is_last:
		scn = _pick_variant_scene()
	if scn == null:
		return
	var z: Node = scn.instantiate()
	if not (z is Node3D):
		return
	get_parent().add_child(z)
	(z as Node3D).global_position = pos
	if is_last and wave == 10 and z.has_method("make_colossus"):
		z.make_colossus()
	elif is_last and wave == 20 and z.has_method("make_mortimer"):
		z.make_mortimer()
	spawned += 1

# Weighted variant pick. Per-act tables — weights are integers and
# don't need to sum to 100. Falls back to the basic scene if the
# referenced variant scene isn't assigned (so the level still spawns
# something even mid-setup).
func _pick_variant_scene() -> PackedScene:
	# weights: [basic, warrior, runner, x10, lugnut]
	var w: PackedInt32Array
	if wave >= 14:        # Act III — the lab, all chaos
		w = PackedInt32Array([30, 25, 20, 15, 10])
	elif wave >= 8:       # Act II — logistics bay
		w = PackedInt32Array([50, 15, 25,  0, 10])
	else:                  # Act I — assembly floor
		w = PackedInt32Array([80,  0,  5,  0, 15])
	# weighted draw
	var total: int = w[0] + w[1] + w[2] + w[3] + w[4]
	var r: int = randi() % max(1, total)
	var acc: int = 0
	for i in range(w.size()):
		acc += w[i]
		if r < acc:
			return _variant_by_index(i)
	return zombie_scene

func _variant_by_index(i: int) -> PackedScene:
	match i:
		1:
			return zombie_warrior_scene if zombie_warrior_scene else zombie_scene
		2:
			return zombie_runner_scene  if zombie_runner_scene  else zombie_scene
		3:
			return zombie_x10_scene     if zombie_x10_scene     else zombie_scene
		4:
			return zombie_lugnut_scene  if zombie_lugnut_scene  else zombie_scene
		_:
			return zombie_scene

# how many regular enemies to spawn this wave
func wave_size(n: int) -> int:
	if n == 10:
		return 11    # 10 minions + the Iron Colossus
	if n == 20:
		return 21    # 20 minions + Prototype-01
	return 5 + n * 2

func act_label(n: int) -> String:
	if n >= 20: return "THE ENGINE CORE"
	if n >= 14: return "ACT III · THE ENGINEERING LAB"
	if n >= 8:  return "ACT II · THE LOGISTICS BAY"
	return "ACT I · THE ASSEMBLY FLOOR"
