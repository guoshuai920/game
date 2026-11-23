class_name SettingsPanel
extends Control
## 设置浮层（主菜单与暂停菜单共用）：主/音效/环境音量滑条 + 减弱动效开关。
## 持久化到 user://settings.json，启动时由 Sfx.apply_settings 应用。

const PATH := "user://settings.json"


static func load_settings() -> Dictionary:
	if FileAccess.file_exists(PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			return data
	return {}


static func save_settings(s: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(s))
		f.close()


static func apply_saved() -> void:
	Sfx.apply_settings(load_settings())


var _sliders: Dictionary = {}  # key -> HSlider


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420, 0)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var saved := load_settings()
	for row in [["master", "主音量"], ["sfx", "音效"], ["ambient", "环境音"]]:
		var lab := Label.new()
		lab.text = String(row[1])
		lab.add_theme_font_size_override("font_size", 18)
		box.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(saved.get(String(row[0]), 1.0))
		sl.custom_minimum_size = Vector2(420, 24)
		sl.value_changed.connect(_on_volume.bind(String(row[0])))
		box.add_child(sl)
		_sliders[String(row[0])] = sl

	var motion_btn := Button.new()
	motion_btn.text = "减弱动效：%s" % ("开" if bool(saved.get("reduced_motion", false)) else "关")
	motion_btn.custom_minimum_size = Vector2(420, 44)
	motion_btn.add_theme_font_size_override("font_size", 18)
	motion_btn.pressed.connect(func() -> void:
		FxBank.reduced_motion = not FxBank.reduced_motion
		motion_btn.text = "减弱动效：%s" % ("开" if FxBank.reduced_motion else "关")
		_persist())
	box.add_child(motion_btn)

	var hint := Label.new()
	hint.text = "游戏内快捷键：M 静音 · 空格 暂停"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.64, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(420, 48)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(func() -> void: visible = false)
	box.add_child(close)


func _ready() -> void:
	# 面板属暂停树时仍需可交互
	process_mode = Node.PROCESS_MODE_ALWAYS


func open() -> void:
	visible = true


func _on_volume(value: float, key: String) -> void:
	Sfx.apply_settings({key: value})
	_persist()


func _persist() -> void:
	var s := Sfx.snapshot_settings()
	s["reduced_motion"] = FxBank.reduced_motion
	# 滑条当前值以 UI 为准（snapshot 在滑条变动时可能滞后一帧）
	for k in _sliders:
		s[k] = (_sliders[k] as HSlider).value
	save_settings(s)
