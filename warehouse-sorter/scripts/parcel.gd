class_name Parcel
extends Panel
## 单个包裹：定义表行（parcels.json）+ 当前旋转 + 计时/破损运行时状态。

signal rotated

const CELL := 96.0

var def: Dictionary = {}
var shape: Array = []          # [[行, 列], ...] 当前朝向的占位格
var rot := 0                   # 已旋转次数
var timer_left := -1.0         # fresh/urgent 剩余秒数，-1 = 无计时
var break_timer := 0.0         # fragile 相邻超限累计秒数
var break_threshold := -1      # 从 rule 字段解析出的相邻包裹数上限
var in_grid := false

var _hovered := false
var _r_held := false

@onready var icon: Label = $Icon
@onready var timer_label: Label = $TimerLabel


func setup(p_def: Dictionary) -> void:
	def = p_def
	shape = []
	for cell in p_def.shape:
		shape.append([int(cell[0]), int(cell[1])])
	if p_def.has("timer"):
		timer_left = float(p_def.timer)
	if p_def.has("rule"):
		break_threshold = _parse_rule(String(p_def.rule))
	if is_inside_tree():
		_refresh()
	else:
		# 尚未进树时 @onready 引用为空，推迟到进树后再刷新
		_refresh.call_deferred()


func _parse_rule(rule: String) -> int:
	# "break_if_neighbors>=2" -> 2
	var idx := rule.find(">=")
	if idx >= 0:
		return int(rule.substr(idx + 2))
	return 2


func area() -> int:
	return shape.size()


func tag() -> String:
	return String(def.get("tag", "normal"))


func score_value() -> int:
	return int(def.get("score", 0)) * int(def.get("multiplier", 1))


func bounding_cells() -> Vector2i:
	# 返回（列数, 行数）
	var n_rows := 0
	var n_cols := 0
	for cell in shape:
		n_rows = maxi(n_rows, int(cell[0]) + 1)
		n_cols = maxi(n_cols, int(cell[1]) + 1)
	return Vector2i(n_cols, n_rows)


func rotate_cw() -> void:
	# 顺时针 90°：(r, c) -> (c, maxR - 1 - r)
	var max_r := bounding_cells().y
	var new_shape: Array = []
	for cell in shape:
		new_shape.append([int(cell[1]), max_r - 1 - int(cell[0])])
	shape = new_shape
	rot += 1
	_refresh()
	rotated.emit()


func cells_at(origin: Vector2i) -> Array:
	var out: Array = []
	for cell in shape:
		out.append(origin + Vector2i(int(cell[1]), int(cell[0])))
	return out


func tick(delta: float) -> void:
	# 仅在背包内由 game.gd 驱动（传送带上的件不计时）
	if timer_left >= 0.0:
		timer_left = maxf(0.0, timer_left - delta)
	update_visual()


func update_visual() -> void:
	if in_grid and timer_left >= 0.0:
		timer_label.text = "%ds" % roundi(timer_left)
	elif in_grid and break_timer > 0.0:
		timer_label.text = "!!"
	else:
		timer_label.text = ""
	if timer_left >= 0.0 and timer_left <= 3.0:
		modulate = Color(1.0, 0.5, 0.5)
	elif break_timer > 0.0:
		modulate = Color(1.0, 0.65, 0.45)
	else:
		modulate = Color.WHITE


func _refresh() -> void:
	var b := bounding_cells()
	var sz := Vector2(b.x * CELL, b.y * CELL)
	custom_minimum_size = sz
	size = sz
	var sb := (get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	sb.bg_color = Color(String(def.get("color", "#4A90D9")))
	add_theme_stylebox_override("panel", sb)
	icon.text = String(def.get("emoji", "📦"))
	icon.add_theme_font_size_override("font_size", int(minf(sz.x, sz.y) * 0.42))
	update_visual()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			rotate_cw()
			accept_event()


func _process(_delta: float) -> void:
	if in_grid or get_viewport().gui_is_dragging() or not _hovered:
		return
	# R 键旋转（悬停时；拖拽过程中禁用，避免预览与实际形状脱节）
	var held := Input.is_key_pressed(KEY_R)
	if held and not _r_held:
		rotate_cw()
	_r_held = held


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false


func _get_drag_data(_at_position: Vector2) -> Variant:
	# 纯视觉预览（Panel + Label，不依赖脚本状态复制），与 grid.anchor_for 的换算保持一致
	var wrapper := Control.new()
	wrapper.mouse_filter = MOUSE_FILTER_IGNORE
	var p := Panel.new()
	p.mouse_filter = MOUSE_FILTER_IGNORE
	p.size = size
	p.add_theme_stylebox_override("panel", get_theme_stylebox("panel"))
	var l := Label.new()
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.text = icon.text
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", icon.get_theme_font_size("font_size"))
	p.add_child(l)
	var b := bounding_cells()
	p.position = Vector2(b.x, b.y) * CELL * -0.5 + Vector2(CELL, CELL) * 0.5
	wrapper.add_child(p)
	set_drag_preview(wrapper)
	return {"parcel": self}
