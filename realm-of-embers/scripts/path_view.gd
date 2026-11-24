extends Node2D
## 场景绘制层：纹理化地面/土路/塔位基座、城堡、选中塔的射程圈、电弧闪光。
## 纹理由 tools/bake_ground.mjs 烘焙；缺失时自动退回纯色绘制（v0.3 前外观）。

var show_range := false
var range_center := Vector2.ZERO
var range_radius := 0.0
var build_mode := false
var _flashes: Array = []

var _tex_grass: Texture2D
var _tex_path: Texture2D
var _tex_slot: Texture2D
var _tex_castle: Texture2D


func _ready() -> void:
	# 平铺绘制需要纹理 repeat
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_tex_grass = load("res://assets/ground/grass.png")
	_tex_path = load("res://assets/ground/path.png")
	_tex_slot = load("res://assets/ground/slot.png")
	# 纹理必须在 _ready 预载：_draw 里首次 load 的纹理 GPU 上传不生效，会渲染成白色占位块
	_tex_castle = UnitsBank.frame_texture("castle")


func _draw() -> void:
	var r: Dictionary = DataLoader.rules
	# 地面（有纹理则整屏平铺，否则退回底色由 Background 承担）
	if _tex_grass != null:
		draw_texture_rect(_tex_grass, Rect2(0, 0, 1280, 720), true)
	# 路径
	var pts: Array = r.get("path", [])
	if pts.size() >= 2:
		if _tex_path != null:
			# 逐段按角度铺路砖，转角用方块补
			for i in pts.size() - 1:
				var a := Vector2(float(pts[i][0]), float(pts[i][1]))
				var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
				var seg := b - a
				var mid := (a + b) * 0.5
				draw_set_transform(Vector2(mid.x, mid.y), seg.angle(), Vector2.ONE)
				draw_texture_rect(_tex_path, Rect2(-seg.length() * 0.5 - 4, -13, seg.length() + 8, 26), true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for p in pts:
				draw_texture_rect(_tex_path, Rect2(float(p[0]) - 13, float(p[1]) - 13, 26, 26), true)
		else:
			var line := PackedVector2Array()
			for p in pts:
				line.append(Vector2(float(p[0]), float(p[1])))
			draw_polyline(line, Color(0.32, 0.27, 0.19, 1.0), 30.0, true)
			draw_polyline(line, Color(0.52, 0.45, 0.32, 1.0), 24.0, true)
	# 塔位：石板基座 + 高台金环
	var font := ThemeDB.fallback_font
	for s in r.get("slots", []):
		var pos := Vector2(float(s[0]), float(s[1]))
		var high: bool = s.size() > 2 and bool(s[2])
		if _tex_slot != null:
			draw_texture_rect(_tex_slot, Rect2(pos.x - 22, pos.y - 22, 44, 44), false)
		if high:
			draw_arc(pos, 23.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.35, 0.9), 2.0)
		elif _tex_slot == null:
			var fill := Color(0.16, 0.20, 0.28, 0.9)
			var ring := Color(0.45, 0.55, 0.75, 0.7)
			if build_mode:
				fill = Color(0.18, 0.30, 0.42, 0.95)
				ring = Color(0.55, 0.85, 1.0, 0.95)
			draw_circle(pos, 22.0, fill)
			draw_arc(pos, 22.0, 0.0, TAU, 24, ring, 2.0)
		if build_mode and _tex_slot != null:
			draw_circle(pos, 22.0, Color(0.55, 0.85, 1.0, 0.10))
		if build_mode:
			draw_string(font, pos + Vector2(-22, 7), "+", HORIZONTAL_ALIGNMENT_CENTER, 44, 18, Color(0.85, 0.95, 1.0, 0.9))
	# 城堡（像素精灵，脚底对齐城堡锚点）
	var c: Array = r.get("castle", [1200, 600])
	var cpos := Vector2(float(c[0]), float(c[1]))
	var castle_tex := _tex_castle
	if castle_tex != null:
		var cs := 4.0
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
