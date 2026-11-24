extends SceneTree
## 把 assets/units/custom/ 里所有贴图拼到暗底总览图（游戏内同款底色），目检用。
##   Godot_console.exe --headless --path . --script res://tools/montage.gd
## 产出 review/custom_montage.png

const SRC := "res://assets/units/custom"
const OUT := "res://review/custom_montage.png"
const CELL := 140  # 单元格
const COLS := 8


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = []
	var d := DirAccess.open(SRC)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".png"):
				ids.append(f.get_basename())
	ids.sort()
	var rows := int(ceil(float(ids.size()) / COLS))
	var out := Image.create(COLS * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
	# 暗底（近似游戏战场色）
	out.fill(Color(0.09, 0.11, 0.09))
	for i: int in ids.size():
		var img := Image.load_from_file(ProjectSettings.globalize_path("%s/%s.png" % [SRC, ids[i]]))
		if img == null:
			continue
		var s := minf(120.0 / img.get_width(), 120.0 / img.get_height())
		var nw := maxi(1, int(img.get_width() * s))
		var nh := maxi(1, int(img.get_height() * s))
		img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
		var cx := (i % COLS) * CELL + (CELL - nw) / 2
		var cy := (i / COLS) * CELL + (CELL - nh)
		out.blend_rect(img, Rect2i(0, 0, nw, nh), Vector2i(cx, cy))
	var target := "D:/ycharmProjects/game/realm-of-embers/" + OUT.trim_prefix("res://")
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	out.save_png(target)
	print("MONTAGE_SAVED %d units -> %s" % [ids.size(), target])
	quit(0)
