class_name Belt
extends Control
## 传送带：固定槽位队列；堆满由 game.gd 在生成时判定失败。

const SLOT_W := 200.0
const SLOT_H := 208.0

var capacity := 6
var _slots: Array = []      # 每槽存 Parcel 或 null


func setup(p_capacity: int) -> void:
	capacity = p_capacity
	custom_minimum_size = Vector2(SLOT_W * capacity, SLOT_H)
	size = custom_minimum_size
	_slots.resize(capacity)
	for i in capacity:
		_slots[i] = null
		var frame := Panel.new()
		frame.position = Vector2(i * SLOT_W, 0.0)
		frame.size = Vector2(SLOT_W - 8.0, SLOT_H)
		frame.mouse_filter = MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.15, 0.22, 0.7)
		sb.border_color = Color(0.24, 0.29, 0.4, 1)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		frame.add_theme_stylebox_override("panel", sb)
		add_child(frame)


func is_full() -> bool:
	return occupied() >= capacity


func occupied() -> int:
	var n := 0
	for s in _slots:
		if s != null:
			n += 1
	return n


func push_parcel(p: Parcel) -> bool:
	for i in _slots.size():
		if _slots[i] == null:
			_slots[i] = p
			p.rotated.connect(_layout)
			add_child(p)
			_layout()
			return true
	return false


func remove_parcel(p: Parcel) -> void:
	for i in _slots.size():
		if _slots[i] == p:
			_slots[i] = null
	_layout()


func _layout() -> void:
	# 包裹向左压紧排列
	var packed: Array = []
	for s in _slots:
		if s != null:
			packed.append(s)
	for i in _slots.size():
		_slots[i] = packed[i] if i < packed.size() else null
		var p: Parcel = _slots[i]
		if p == null or p.get_parent() != self:
			continue
		var b := p.bounding_cells()
		p.position = Vector2(
			i * SLOT_W + (SLOT_W - b.x * Parcel.CELL) * 0.5,
			(SLOT_H - b.y * Parcel.CELL) * 0.5
		)
