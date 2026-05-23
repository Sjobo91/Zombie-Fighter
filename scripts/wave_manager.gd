# Wave Manager — drives the 20-wave campaign across three acts.
#
#   Act I  (waves 1-7)   THE GRAVEYARD
#   Act II (waves 8-13)  THE CITY
#   Act III (waves 14-19) THE CATHEDRAL
#   Wave 10  → THE BONE COLOSSUS (mini-boss)
#   Wave 20  → MORTIMER, THE GRIEVING KING (final boss)
#
# Spawns zombies in a ring around the player. After all spawns are dead,
# a short breather plays, then the next wave begins.

extends Node

@export var zombie_scene:    PackedScene
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
		var hud := get_node_or_null("/root/Main/HUD")
		if hud and hud.has_method("show_victory"):
			hud.show_victory()
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
	var z: Node = zombie_scene.instantiate()
	if not (z is Node3D):
		return
	get_parent().add_child(z)
	(z as Node3D).global_position = pos
	# the LAST spawn of wave 10 is the Colossus; wave 20 = Mortimer
	var is_last: bool = (spawned == to_spawn - 1)
	if is_last and wave == 10 and z.has_method("make_colossus"):
		z.make_colossus()
	elif is_last and wave == 20 and z.has_method("make_mortimer"):
		z.make_mortimer()
	spawned += 1

# how many regular zombies to spawn this wave
func wave_size(n: int) -> int:
	if n == 10:
		return 11    # 10 minions + the Bone Colossus
	if n == 20:
		return 21    # 20 minions + Mortimer
	return 5 + n * 2

func act_label(n: int) -> String:
	if n >= 20: return "THE THRONE ROOM"
	if n >= 14: return "ACT III · THE CATHEDRAL"
	if n >= 8:  return "ACT II · THE CITY"
	return "ACT I · THE GRAVEYARD"
