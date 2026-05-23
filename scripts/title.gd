# Title screen — DREAD: Rogue Protocol.
# Three options: PLAY (start a run), MECH REPAIR SHOP (spend Mechparts),
# QUIT. Bank balance is shown top-right.
extends Control

@onready var play_btn:  Button = $Center/VBox/PlayBtn
@onready var shop_btn:  Button = $Center/VBox/ShopBtn
@onready var quit_btn:  Button = $Center/VBox/QuitBtn
@onready var bank_lbl:  Label  = $TopRight/BankLabel

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	play_btn.pressed.connect(_on_play)
	shop_btn.pressed.connect(_on_shop)
	quit_btn.pressed.connect(_on_quit)
	_refresh_bank()

func _refresh_bank() -> void:
	var bank := get_node_or_null("/root/Mechbank")
	var bal:  int  = 0
	if bank:
		bal = int(bank.balance)
	bank_lbl.text = "BANK   ⚙ %d" % bal

func _on_play() -> void:
	var bank := get_node_or_null("/root/Mechbank")
	if bank and bank.has_method("reset_run"):
		bank.reset_run()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_shop() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")

func _on_quit() -> void:
	get_tree().quit()
