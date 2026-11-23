extends Node2D
## 场景绘制层：路径、塔位、城堡、选中塔的射程圈、电弧闪光。

var show_range := false
var range_center := Vector2.ZERO
var range_radius := 0.0
var build_mode := false  # 建塔选塔中：塔位高亮显示 + 号
var _flashes: Array = []  # {a: Vector2, b: Vector2, ttl: float, color: Color}


func _draw() -> void:
	var r: Dictionary = DataLoader.rules
	# 路径
	var pts: Array = r.get("path", [])
	if pts.size() >= 2:
		var line := PackedVector2Array()
		for p in pts:
			line.append(Vector2(float(p[0]), float(p[1])))
		draw_polyline(line, Color(0.32, 0.27, 0.19, 1.0), 30.0, true)
		draw_polyline(line, Color(0.52, 0.45, 0.32, 1.0), 24.0, true)
	# 塔位
	var font := ThemeDB.fallback_font
	for s in r.get("slots", []):
		var pos := Vector2(float(s[0]), float(s[1]))
		var high: bool = s.size() > 2 and bool(s[2])
		if high:
			draw_circle(pos, 23.0, Color(0.34, 0.29, 0.10, 0.95))
			draw_arc(pos, 23.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.35, 0.9), 2.0)
		else:
			var fill := Color(0.16, 0.20, 0.28, 0.9)
			var ring := Color(0.45, 0.55, 0.75, 0.7)
			if build_mode:
				fill = Color(0.18, 0.30, 0.42, 0.95)
				ring = Color(0.55, 0.85, 1.0, 0.95)
			draw_circle(pos, 22.0, fill)
			draw_arc(pos, 22.0, 0.0, TAU, 24, ring, 2.0)
		if build_mode:
			draw_string(font, pos + Vector2(-22, 7), "+", HORIZONTAL_ALIGNMENT_CENTER, 44, 18, Color(0.85, 0.95, 1.0, 0.9))
	# 城堡（像素精灵，脚底对齐城堡锚点）
	var c: Array = r.get("castle", [1200, 600])
	var cpos := Vector2(float(c[0]), float(c[1]))
	var castle_tex := UnitsBank.frame_texture("castle")
	if castle_tex != null:
		var cs := 3.0
		var cw := castle_tex.get_width() * cs
		var ch2 := castle_tex.get_height() * cs
		draw_texture_rect(castle_tex, Rect2(cpos.x - cw * 0.5, cpos.y - ch2 + 8.0, cw, ch2), false)
	else:
		draw_string(font, cpos + Vector2(-44, 22), "🏰", HORIZONTAL_ALIGNMENT_CENTER, 88, 46, Color.WHITE)
	# 选中塔射程
	if show_range and range_radius > 0.0:
		draw_circle(range_center, range_radius, Color(1.0, 0.95, 0.6, 0.07))
		draw_arc(range_center, range_radius, 0.0, TAU, 64, Color(1.0, 0.95, 0.6, 0.85), 2.0)
	# 电弧等闪光
	for f in _flashes:
		draw_line(f["a"], f["b"], f["color"], 3.0, true)


func flash(a: Vector2, b: Vector2, color: Color) -> void:
	_flashes.append({"a": a, "b": b, "ttl": 0.12, "color": color})
	queue_redraw()


func _process(delta: float) -> void:
	if _flashes.is_empty():
		return
	var alive: Array = []
	for f in _flashes:
		f["ttl"] = float(f["ttl"]) - delta
		if float(f["ttl"]) > 0.0:
			alive.append(f)
	_flashes = alive
	queue_redraw()
