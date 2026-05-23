# Mechbank — autoloaded singleton at /root/Mechbank.
#
# Holds two numbers:
#   balance     = Mechparts the player has banked between runs (spendable
#                 at the Mech Repair Shop)
#   run_earned  = Mechparts earned in the *current* run (only banks on
#                 a successful retreat / victory, half-banks on death)
#
# Saves to user://mechbank.cfg on every change so a crash never wipes
# the bank.

extends Node

const SAVE_PATH := "user://mechbank.cfg"

var balance:    int = 0
var run_earned: int = 0
# permanent upgrades — bought at the hub, applied at run start
var upgrades: Dictionary = {
	"max_hp":     0,   # +20 per level
	"damage":     0,   # +3 per level
	"fire_rate":  0,   # -10% cooldown per level (max 5)
	"summon_cd":  0,   # -5s ally cooldown per level (max 4)
}

func _ready() -> void:
	_load()

func add_run_earn(amt: int) -> void:
	run_earned += max(0, amt)
	# don't save the run amount yet — it's not banked until run-end

func on_run_end(victory: bool) -> void:
	# successful run banks 100%, death banks 50% (rogue-lite mercy)
	var keep_frac := 1.0 if victory else 0.5
	var keep := int(round(float(run_earned) * keep_frac))
	balance += keep
	run_earned = 0
	_save()

func spend(amt: int) -> bool:
	if amt < 0 or balance < amt:
		return false
	balance -= amt
	_save()
	return true

func buy_upgrade(key: String, cost: int) -> bool:
	if not upgrades.has(key):
		return false
	if not spend(cost):
		return false
	upgrades[key] = int(upgrades[key]) + 1
	_save()
	return true

func reset_run() -> void:
	run_earned = 0

# ── apply upgrades to a freshly spawned player
func apply_to_player(player: Node) -> void:
	if player == null:
		return
	var lvl_hp:   int = int(upgrades.get("max_hp", 0))
	var lvl_dmg:  int = int(upgrades.get("damage", 0))
	var lvl_rate: int = int(upgrades.get("fire_rate", 0))
	if "max_hp" in player and lvl_hp > 0:
		player.max_hp = int(player.max_hp) + lvl_hp * 20
		player.hp = player.max_hp
	if "attack_dmg" in player and lvl_dmg > 0:
		player.attack_dmg = int(player.attack_dmg) + lvl_dmg * 3
	if "attack_cd" in player and lvl_rate > 0:
		var mul := pow(0.9, lvl_rate)
		player.attack_cd = float(player.attack_cd) * mul

# ── persistence
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("bank", "balance", balance)
	cfg.set_value("upgrades", "max_hp",    upgrades.max_hp)
	cfg.set_value("upgrades", "damage",    upgrades.damage)
	cfg.set_value("upgrades", "fire_rate", upgrades.fire_rate)
	cfg.set_value("upgrades", "summon_cd", upgrades.summon_cd)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	balance = int(cfg.get_value("bank", "balance", 0))
	upgrades.max_hp     = int(cfg.get_value("upgrades", "max_hp", 0))
	upgrades.damage    = int(cfg.get_value("upgrades", "damage", 0))
	upgrades.fire_rate = int(cfg.get_value("upgrades", "fire_rate", 0))
	upgrades.summon_cd = int(cfg.get_value("upgrades", "summon_cd", 0))
