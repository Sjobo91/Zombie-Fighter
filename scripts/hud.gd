# HUD — HP bar, wave info, Mechparts counter, boss bar, banners.
extends CanvasLayer

@onready var hp_fill:    ColorRect = $Root/HpBar/Fill
@onready var hp_label:   Label     = $Root/HpBar/Label
@onready var death:      Label     = $Root/Death
@onready var death_stat: Label     = $Root/DeathStats
@onready var wave_text:  Label     = $Root/WaveInfo/WaveText
@onready var act_text:   Label     = $Root/WaveInfo/ActText
@onready var ult_text:   Label     = $Root/WaveInfo/UltText
@onready var mp_label:   Label     = $Root/Mechparts/Label
@onready var banner:     Label     = $Root/Banner
@onready var boss_root:  Control   = $Root/BossBar
@onready var boss_fill:  ColorRect = $Root/BossBar/Fill
@onready var boss_label: Label     = $Root/BossBar/Label
@onready var dmg_flash:  ColorRect = $Root/DamageFlash
@onready var pause_root: Panel     = $Root/Pause
@onready var resume_btn: Button    = $Root/Pause/ResumeBtn
@onready var quit_btn:   Button    = $Root/Pause/QuitBtn

var _banner_t: float = 0.0
var _dmg_flash_t: float = 0.0
var _paused: bool = false

func _ready() -> void:
	# The HUD is a heads-up display, never interactive. Force every
	# child Control to ignore mouse input so the Banner / labels can't
	# silently eat LMB clicks that should have been an attack.
	_make_passthrough(self)
	death.visible = false
	death_stat.visible = false
	banner.visible = false
	boss_root.visible = false
	wave_text.text = ""
	act_text.text = ""
	# Pause overlay starts hidden; its buttons MUST receive mouse input
	# (so re-enable them after _make_passthrough nuked their filter).
	pause_root.visible = false
	resume_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	quit_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	resume_btn.pressed.connect(_on_resume)
	quit_btn.pressed.connect(_on_quit_to_title)

func _make_passthrough(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_make_passthrough(child)

func _process(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			banner.visible = false
	if _dmg_flash_t > 0.0:
		_dmg_flash_t -= delta
		var k: float = max(0.0, _dmg_flash_t / 0.32)
		dmg_flash.color = Color(0.85, 0.10, 0.05, 0.55 * k)

func pulse_damage_flash() -> void:
	_dmg_flash_t = 0.32
	dmg_flash.color = Color(0.85, 0.10, 0.05, 0.55)

# ── Pause menu ──
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("escape") and not death.visible:
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	set_paused(not _paused)

func set_paused(p: bool) -> void:
	_paused = p
	pause_root.visible = p
	get_tree().paused = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p \
		else Input.MOUSE_MODE_CAPTURED

func _on_resume() -> void:
	set_paused(false)

func _on_quit_to_title() -> void:
	# bank what we earned this run (50% — same rule as dying mid-run)
	var bank := get_node_or_null("/root/Mechbank")
	if bank and bank.has_method("on_run_end"):
		bank.on_run_end(false)
	set_paused(false)
	get_tree().change_scene_to_file("res://scenes/title.tscn")

func set_hp(hp: int, max_hp: int) -> void:
	var k: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)
	hp_fill.scale.x = k
	hp_label.text = "%d / %d" % [hp, max_hp]

func set_mechparts(n: int) -> void:
	mp_label.text = "⚙ %d" % n

# MELTDOWN ult readout. active_t > 0 means it's currently running.
func set_ult(active_t: float, cd_remaining: float) -> void:
	if active_t > 0.0:
		ult_text.text = "MELTDOWN · %0.1fs" % active_t
		ult_text.modulate = Color(1.0, 0.42, 0.10, 1)
	elif cd_remaining > 0.0:
		ult_text.text = "Q  %0.0fs" % cd_remaining
		ult_text.modulate = Color(0.62, 0.62, 0.66, 1)
	else:
		ult_text.text = "Q  READY"
		ult_text.modulate = Color(1.0, 0.55, 0.20, 1)

func show_wave_banner(n: int, total: int, act: String) -> void:
	wave_text.text = "WAVE %d / %d" % [n, total]
	act_text.text = act
	banner.text = "WAVE %d" % n
	banner.visible = true
	_banner_t = 2.4

func show_clear_banner(n: int) -> void:
	banner.text = "WAVE %d CLEARED" % n
	banner.visible = true
	_banner_t = 2.0

func announce_boss(name: String) -> void:
	banner.text = name
	banner.visible = true
	_banner_t = 3.0

func set_boss_hp(hp: int, max_hp: int, name: String) -> void:
	boss_root.visible = true
	boss_label.text = name
	var k: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)
	boss_fill.scale.x = k

func clear_boss_hp() -> void:
	boss_root.visible = false

func show_death(wave: int = 0, earned: int = 0, banked: int = 0) -> void:
	death.text = "REAPER FELL"
	death.modulate = Color(1.0, 1.0, 1.0, 1)
	death.visible = true
	death_stat.text = "WAVE %d REACHED\n⚙ %d EARNED   →   ⚙ %d BANKED\nreturning to the workshop…" \
		% [wave, earned, banked]
	death_stat.visible = true

func show_victory(wave: int = 20, earned: int = 0, banked: int = 0) -> void:
	death.text = "PROTOCOL ENDED\nTHE WORKSHOP GOES SILENT"
	death.modulate = Color(1.0, 0.86, 0.4, 1)
	death.visible = true
	death_stat.text = "ALL %d WAVES CLEARED\n⚙ %d EARNED   →   ⚙ %d BANKED" \
		% [wave, earned, banked]
	death_stat.visible = true
