extends SceneTree
## emoji 高清贴图烘焙：用系统彩色 emoji 字体把每个单位渲染成 PNG（窗口模式运行，
## headless 的 dummy 渲染器不出图）。
##   Godot_v4.3-stable_win64_console.exe --path . --script res://tools/bake_emoji.gd
## 产出：assets/units/emoji/<id>.png + assets/units/emoji.json（UnitsBank 里覆盖像素稿清单；
## 某台机器缺字体时对应条目不产出，自动回落到像素稿）。

const OUT_DIR := "res://assets/units/emoji"
const BOX := 128
const FONT_SIZE := 96

# 塔 / 城堡 / 民兵（敌人取 data/enemies.json 的 emoji 字段）
const FIXED := {
	"tower_arrow": ["🏹", 0.6],
	"tower_frost": ["❄️", 0.6],
	"tower_thunder": ["⚡", 0.6],
	"tower_bomb": ["💣", 0.6],
	"tower_flame": ["🔥", 0.6],
	"tower_venom": ["☠️", 0.6],
	"castle": ["🏰", 0.8],
	"shield": ["🛡️", 0.5],
}
const ENEMY_SCALE := 0.45


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji"])
	var vp := SubViewport.new()
	vp.size = Vector2i(BOX, BOX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	var lbl := Label.new()
	lbl.size = Vector2(BOX, BOX)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	vp.add_child(lbl)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var manifest := {}
	var specs := FIXED.duplicate()
	# 敌人 emoji 优先取 autoload，--script 模式没有 autoload 时直接读表
	var enemies: Variant = null
	if root.has_node("DataLoader"):
		enemies = root.get_node("DataLoader").enemies
	else:
		var ef := FileAccess.open("res://data/enemies.json", FileAccess.READ)
		if ef != null:
			enemies = JSON.parse_string(ef.get_as_text())
			ef.close()
	if enemies is Array:
		for e in enemies:
			var ed := e as Dictionary
			specs[String(ed.get("id"))] = [String(ed.get("emoji", "🧌")), ENEMY_SCALE]
	var ok := 0
	var skipped: Array = []
	for id: String in specs:
		var emoji := String((specs[id] as Array)[0])
		var scale := float((specs[id] as Array)[1])
		if not font.has_char(emoji.unicode_at(0)):
			skipped.append(id)
			continue
		lbl.text = emoji
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img == null:
			skipped.append(id)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var used := img.get_used_rect()
		if used.size.x < 8 or used.size.y < 8:
			skipped.append(id)  # 空白/豆腐块，保留像素稿
			continue
		var crop := img.get_region(used)
		var path := "%s/%s.png" % [OUT_DIR, id]
		crop.save_png(ProjectSettings.globalize_path(path))
		manifest[id] = {
			"image": "emoji/%s.png" % id,
			"fw": crop.get_width(),
			"fh": crop.get_height(),
			"frames": 1,
			"fps": 1,
			"scale": scale,
			"kind": "emoji",
		}
		ok += 1
	var f := FileAccess.open("res://assets/units/emoji.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	print("EMOJI_BAKED ok=", ok, " skipped=", skipped)
	quit(0)
