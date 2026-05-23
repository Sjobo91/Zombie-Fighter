# Mech Repair Shop — between-runs hub.
# Robots are being fixed on workbenches in the background. The player
# spends banked Mechparts on permanent upgrades.

extends Control

# upgrade key -> [display name, description, base cost, cost-per-level,
#                  max level]
const UPGRADES := {
	"max_hp": {
		"name":       "REINFORCED CHASSIS",
		"desc":       "+20 max HP per level",
		"base":       50,
		"step":       40,
		"max":        8,
	},
	"damage": {
		"name":       "HOTTER ROUNDS",
		"desc":       "+3 weapon damage per level",
		"base":       70,
		"step":       55,
		"max":        8,
	},
	"fire_rate": {
		"name":       "OVERCLOCKED TRIGGER",
		"desc":       "10% faster fire rate per level",
		"base":       110,
		"step":       90,
		"max":        5,
	},
	"summon_cd": {
		"name":       "RINGWORKER UPLINK",
		"desc":       "-5s summon-ally cooldown per level",
		"base":       180,
		"step":       140,
		"max":        4,
	},
}

@onready var bank_lbl:  Label   = $TopBar/BankLabel
@onready var back_btn:  Button  = $TopBar/BackBtn
@onready var rows_root: VBoxContainer = $Center/Panel/Rows

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	back_btn.pressed.connect(_on_back)
	_build_rows()
	_refresh()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/title.tscn")

func _build_rows() -> void:
	for child in rows_root.get_children():
		child.queue_free()
	for key in UPGRADES.keys():
		var data: Dictionary = UPGRADES[key]
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		rows_root.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var nm := Label.new()
		nm.text = str(data.name)
		nm.add_theme_font_size_override("font_size", 24)
		nm.modulate = Color(0.96, 0.86, 0.5, 1)
		info.add_child(nm)

		var ds := Label.new()
		ds.text = str(data.desc)
		ds.modulate = Color(0.84, 0.78, 0.66, 1)
		info.add_child(ds)

		var lvl := Label.new()
		lvl.name = "LevelLabel"
		lvl.set_meta("key", key)
		info.add_child(lvl)

		var btn := Button.new()
		btn.name = "BuyBtn"
		btn.set_meta("key", key)
		btn.custom_minimum_size = Vector2(190, 64)
		btn.pressed.connect(_on_buy.bind(key))
		row.add_child(btn)

func _refresh() -> void:
	var bank := get_node_or_null("/root/Mechbank")
	var bal:  int = 0
	var upg:  Dictionary = {}
	if bank:
		bal = int(bank.balance)
		upg = bank.upgrades
	bank_lbl.text = "BANK   ⚙ %d" % bal

	for row in rows_root.get_children():
		var info: VBoxContainer = row.get_child(0) as VBoxContainer
		var lvl_lbl: Label = info.get_node("LevelLabel") as Label
		var btn:     Button = row.get_node("BuyBtn") as Button
		var key: String = btn.get_meta("key")
		var data: Dictionary = UPGRADES[key]
		var lv:   int = int(upg.get(key, 0))
		var max_lv: int = int(data.max)
		var cost: int = int(data.base) + int(data.step) * lv
		lvl_lbl.text = "LEVEL %d / %d" % [lv, max_lv]
		if lv >= max_lv:
			btn.text = "MAXED"
			btn.disabled = true
		elif bal < cost:
			btn.text = "⚙ %d  (need more)" % cost
			btn.disabled = true
		else:
			btn.text = "BUY  ⚙ %d" % cost
			btn.disabled = false

func _on_buy(key: String) -> void:
	var bank := get_node_or_null("/root/Mechbank")
	if bank == null:
		return
	var data: Dictionary = UPGRADES[key]
	var lv:   int = int(bank.upgrades.get(key, 0))
	if lv >= int(data.max):
		return
	var cost: int = int(data.base) + int(data.step) * lv
	bank.buy_upgrade(key, cost)
	_refresh()
