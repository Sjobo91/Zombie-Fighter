# HUD — HP bar, wave info, Mechparts counter, boss bar, banners.
extends CanvasLayer

@onready var hp_fill:    ColorRect = $Root/HpBar/Fill
@onready var hp_label:   Label     = $Root/HpBar/Label
@onready var death:      Label     = $Root/Death
@onready var death_stat: Label     = $Root/DeathStats
@onready var wave_text:  Label     = $Root/WaveInfo/WaveText
@onready var act_text:   Label     = $Root/WaveInfo/ActText
@onready var mp_label:   Label     = $Root/Mechparts/Label
@onready var banner:     Label     = $Root/Banner
@onready var boss_root:  Control   = $Root/BossBar
@onready var boss_fill:  ColorRect = $Root/BossBar/Fill
@onready var boss_label: Label     = $Root/BossBar/Label

var _banner_t: float = 0.0

func _ready() -> void:
	death.visible = false
	death_stat.visible = false
	banner.visible = false
	boss_root.visible = false
	wave_text.text = ""
	act_text.text = ""

func _process(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			banner.visible = false

func set_hp(hp: int, max_hp: int) -> void:
	var k: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)
	hp_fill.scale.x = k
	hp_label.text = "%d / %d" % [hp, max_hp]

func set_mechparts(n: int) -> void:
	mp_label.text = "⚙ %d" % n

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
	death.text = "DREAD FELL"
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
