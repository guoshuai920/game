class_name GameGrid
extends Control
## 6×4 背包网格：占位检测、拖放接收、落点红绿高亮。

signal parcel_placed(parcel: Parcel)

const CELL_SCENE := preload("res://scenes/GridCell.tscn")
const BASE_COLOR := Color(0.14, 0.17, 0.24)
const OK_COLOR := Color(0.2, 0.5, 0.28)
const BAD_COLOR := Color(0.5, 0.2, 0.22)

var cols := 6
var rows := 4
var cell_size := 96.0
var cells: Dictionary = {}   # Vector2i -> Parcel

var _panels: Array[Panel] = []
var _was_tinted := false


func setup(p_cols: int, p_rows: int, p_cell: float) -> void:
	cols = p_cols
	rows = p_rows
	cell_size = p_cell
	var sz := Vector2(cols * cell_size, rows * cell_size)
	custom_minimum_size = sz
	size = sz
	for r in rows:
		for c in cols:
			var p := CELL_SCENE.instantiate() as Panel
			p.position = Vector2(c, r) * cell_size + Vector2(4, 4)
			p.size = Vector2(cell_size - 8, cell_size - 8)
			p.mouse_filter = MOUSE_FILTER_IGNORE
			var sb := (p.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
			p.add_theme_stylebox_override("panel", sb)
			add_child(p)
			_panels.append(p)


func anchor_for(p: Parcel, local_pos: Vector2) -> Vector2i:
	# 拖拽预览把形状中心对准鼠标，这里反算形状 (0,0) 格所在的格子
	var b := p.bounding_cells()
	var px := local_pos - Vector2(b.x, b.y) * cell_size * 0.5 + Vector2(cell_size * 0.5, cell_size * 0.5)
	return Vector2i(floori(px.x / cell_size), floori(px.y / cell_size))


func can_place(p: Parcel, origin: Vector2i) -> bool:
	for cell in p.cells_at(origin):
		var c := cell as Vector2i
		if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
			return false
		if cells.has(c):
			return false
	return true


func place(p: Parcel, origin: Vector2i) -> void:
	for cell in p.cells_at(origin):
		cells[cell as Vector2i] = p
	p.in_grid = true
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var par := p.get_parent()
	if par != null and par != self:
		par.remove_child(p)
	add_child(p)
	p.position = Vector2(origin) * cell_size
	p.update_visual()
	parcel_placed.emit(p)


func parcels() -> Array:
	var out: Array = []
	for p in cells.values():
		if not out.has(p):
			out.append(p)
	return out


func tag_area(tag: String) -> int:
	var total := 0
	for p in parcels():
		if p.tag() == tag:
			total += p.area()
	return total


func tag_parcels(tag: String) -> Array:
	var out: Array = []
	for p in parcels():
		if p.tag() == tag:
			out.append(p)
	return out


func neighbor_parcels(p: Parcel) -> Array:
	# 上下左右紧邻格上的其他包裹（按包裹去重，与“相邻包裹 ≥2 个”的规则一致）
	var out: Array = []
	var own: Array = p.cells_at(_origin_of(p))
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var d := dir as Vector2i
		for cell in own:
			var n: Vector2i = (cell as Vector2i) + d
			if cells.has(n) and cells[n] != p and not out.has(cells[n]):
				out.append(cells[n])
	return out


func _origin_of(p: Parcel) -> Vector2i:
	return Vector2i(roundi(p.position.x / cell_size), roundi(p.position.y / cell_size))


func remove_parcel(p: Parcel) -> void:
	var keys: Array = []
	for k in cells:
		if cells[k] == p:
			keys.append(k)
	for k in keys:
		cells.erase(k)


func _can_drop_data(pos: Vector2, data: Variant) -> bool:
	if data is Dictionary and (data as Dictionary).get("parcel") is Parcel:
		var p: Parcel = (data as Dictionary)["parcel"]
		if p.in_grid:
			return false
		return can_place(p, anchor_for(p, pos))
	return false


func _drop_data(pos: Vector2, data: Variant) -> void:
	if data is Dictionary and (data as Dictionary).get("parcel") is Parcel:
		var p: Parcel = (data as Dictionary)["parcel"]
		var anchor := anchor_for(p, pos)
		if can_place(p, anchor):
			place(p, anchor)


func _process(_delta: float) -> void:
	_update_drag_preview()


func _update_drag_preview() -> void:
	var vp := get_viewport()
	if not vp.gui_is_dragging():
		if _was_tinted:
			_reset_panel_colors()
			_was_tinted = false
		return
	var data: Variant = vp.gui_get_drag_data()
	if not (data is Dictionary and (data as Dictionary).get("parcel") is Parcel):
		return
	var p: Parcel = (data as Dictionary)["parcel"]
	if p.in_grid:
		return
	_reset_panel_colors()
	_was_tinted = true
	var anchor := anchor_for(p, get_local_mouse_position())
	var ok := can_place(p, anchor)
	for cell in p.cells_at(anchor):
		var c := cell as Vector2i
		if c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows:
			_set_panel_color(c.y * cols + c.x, OK_COLOR if ok else BAD_COLOR)


func _reset_panel_colors() -> void:
	for p in _panels:
		var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.bg_color = BASE_COLOR


func _set_panel_color(idx: int, color: Color) -> void:
	var sb := _panels[idx].get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = color
