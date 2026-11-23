class_name GameMenu
extends Control
## 主菜单：新冒险 / 继续 / 设置 / 退出。底部像素展示条（地面+单位+城堡）。
## start_fresh 供主场景读取：新冒险跳过存档面板直接开新档。

static var start_fresh := false

var _settings: SettingsPanel

@onready var continue_btn: Button = $UI/Box/ContinueBtn


func _ready() -> void:
	# 自动测试/读档冒烟/技能专项直接进战斗场景，不经菜单
	var args := OS.get_cmdline_user_args()
	if args.has("--autotest") or args.has("--testload") or args.has("--skilltest"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/Main.tscn")
		return
	SettingsPanel.apply_saved()
	SettingsPanel.apply_saved()  # 幂等：总线音量+动效开关
	$UI/Box/NewBtn.pressed.connect(_on_new)
	continue_btn.pressed.connect(_on_continue)
	$UI/Box/SettingsBtn.pressed.connect(_on_settings)
	$UI/Box/QuitBtn.pressed.connect(func() -> void: get_tree().quit())
	continue_btn.disabled = not _has_save()
	_settings = SettingsPanel.new()
	add_child(_settings)


func _has_save() -> bool:
	for i in [1, 2, 3]:
		if FileAccess.file_exists("user://save_%d.json" % i):
			return true
	return false


func _on_new() -> void:
	start_fresh = true
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_continue() -> void:
	start_fresh = false
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_settings() -> void:
	_settings.open()


func _draw() -> void:
	# 底部展示条：平铺草地 + 站立的城堡与来犯者
	var grass := load("res://assets/ground/grass.png") as Texture2D
	if grass != null:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		draw_texture_rect(grass, Rect2(0, 560, 1280, 160), true)
		var path_tex := load("res://assets/ground/path.png") as Texture2D
		if path_tex != null:
			draw_texture_rect(path_tex, Rect2(0, 600, 1280, 64), true)
		_show_unit("castle", 1130, 706)
		_show_unit("inferno", 980, 704)
		_show_unit("gargoyle", 860, 700)
		_show_unit("goblin", 740, 706)
		_show_unit("slime", 640, 706)


func _show_unit(id: String, x: float, foot_y: float) -> void:
	var tex := UnitsBank.frame_texture(id)
	if tex == null:
		return
	var s := 3.0
	draw_texture_rect(tex, Rect2(x - tex.get_width() * s * 0.5, foot_y - tex.get_height() * s, tex.get_width() * s, tex.get_height() * s), false)
