extends SceneTree
## AI 立绘后处理：白底洪泛抠图 → 蚀边去白晕 → 裁紧 → 128px → custom.json
## 用法（headless 即可）：
##   Godot_console.exe --headless --path . --script res://tools/chroma_remove.gd [-- slime slimelet ...]
## 输入 D:/AI/gens/<id>.png → 输出 assets/units/custom/<id>.png

const GEN_DIR := "D:/AI/gens"
const OUT_DIR := "res://assets/units/custom"
const BOX := 128

# 目标显示高度（世界像素），缩放 = 目标 / 裁剪后实际高
const TARGETS := {
	"goblin": 40, "orc": 44, "wolf": 40, "shield": 40, "bat": 36, "shaman": 40,
	"slime": 40, "slimelet": 30, "gargoyle": 44, "necro": 42, "skeleton": 40,
	"sandworm": 46, "shadowking": 46, "inferno": 46,
	"tower_arrow": 56, "tower_frost": 56, "tower_thunder": 56,
	"tower_bomb": 56, "tower_flame": 56, "tower_venom": 56,
	"castle": 78,
}
const DEFAULT_TARGET := 40

var _todo: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_todo = args if not args.is_empty() else _scan()
	_run.call_deferred()


func _scan() -> Array:
	var out: Array = []
	var d := DirAccess.open(GEN_DIR)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".png"):
				out.append(f.get_basename())
	return out


func _is_white(c: Color) -> bool:
	return minf(c.r, minf(c.g, c.b)) >= 0.86 and (maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))) <= 0.1


func _is_whiteish(c: Color) -> bool:
	return minf(c.r, minf(c.g, c.b)) >= 0.78 and (maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))) <= 0.18


func _cdist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


## 背景参考色：四角+边中点采样去重（白底/深底/棋盘格都能取到）
func _bg_refs(img: Image, w: int, h: int) -> Array:
	var refs: Array = []
	var pts := [Vector2i(2, 2), Vector2i(w - 3, 2), Vector2i(2, h - 3), Vector2i(w - 3, h - 3),
		Vector2i(w / 2, 2), Vector2i(w / 2, h - 3), Vector2i(2, h / 2), Vector2i(w - 3, h / 2)]
	for p: Vector2i in pts:
		var c := img.get_pixel(p.x, p.y)
		var dup := false
		for r: Color in refs:
			if _cdist(c, r) < 0.15:
				dup = true
				break
		if not dup:
			refs.append(c)
	return refs


func _is_bg(c: Color, refs: Array) -> bool:
	if _is_white(c):
		return true
	for r: Color in refs:
		if _cdist(c, r) <= 0.14:
			return true
	return false


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var manifest := {}
	# 已有 custom.json 先读进来（本次没处理的条目保留）
	var fp := "res://assets/units/custom.json"
	if FileAccess.file_exists(fp):
		var prev: Variant = JSON.parse_string(FileAccess.get_file_as_string(fp))
		if prev is Dictionary:
			manifest = prev
	var ok := 0
	for id: String in _todo:
		var path := "%s/%s.png" % [GEN_DIR, id]
		if not FileAccess.file_exists(path):
			print("MISS ", id)
			continue
		var img := Image.load_from_file(path)
		if img == null:
			print("LOADFAIL ", id)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		# 1) 洪泛：从四边出发，按背景参考色清掉连通底色
		var refs := _bg_refs(img, w, h)
		var stack: Array = []
		var bg := PackedByteArray()
		bg.resize(w * h)
		for x: int in w:
			for y: int in [0, h - 1]:
				var i: int = y * w + x
				if bg[i] == 0 and _is_bg(img.get_pixel(x, y), refs):
					bg[i] = 1
					stack.append(i)
		for y: int in h:
			for x: int in [0, w - 1]:
				var i: int = y * w + x
				if bg[i] == 0 and _is_bg(img.get_pixel(x, y), refs):
					bg[i] = 1
					stack.append(i)
		while not stack.is_empty():
			var i: int = stack.pop_back()
			var x: int = i % w
			var y: int = i / w
			for n: int in [i - 1, i + 1, i - w, i + w]:
				if n < 0 or n >= w * h:
					continue
				if (x == 0 and n == i - 1) or (x == w - 1 and n == i + 1):
					continue
				if bg[n] == 0:
					var c := img.get_pixel(n % w, n / w)
					if _is_bg(c, refs):
						bg[n] = 1
						stack.append(n)
		for i: int in w * h:
			if bg[i] == 1:
				img.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
		# 1.5) 大块白色连通域清除：模型画的白色徽章/圆盘底（>4% 画幅的白团 ≠ 角色细节）
		var seen := PackedByteArray()
		seen.resize(w * h)
		for i0: int in w * h:
			if seen[i0] == 1 or img.get_pixel(i0 % w, i0 / w).a == 0.0 or not _is_white(img.get_pixel(i0 % w, i0 / w)):
				continue
			var comp: Array = [i0]
			seen[i0] = 1
			var head := 0
			while head < comp.size():
				var i: int = comp[head]
				head += 1
				var x: int = i % w
				for n: int in [i - 1, i + 1, i - w, i + w]:
					if n < 0 or n >= w * h or seen[n] == 1:
						continue
					if (x == 0 and n == i - 1) or (x == w - 1 and n == i + 1):
						continue
					seen[n] = 1
					if img.get_pixel(n % w, n / w).a != 0.0 and _is_white(img.get_pixel(n % w, n / w)):
						comp.append(n)
			if comp.size() > w * h * 0.04:
				for i2: int in comp:
					img.set_pixel(i2 % w, i2 / w, Color(0, 0, 0, 0))
				print("  badge removed %d px" % comp.size())
		# 2) 蚀边 3 轮：贴着透明区的近白像素清掉（去白晕/贴纸白边）
		for pass_i: int in 3:
			var kill: Array = []
			for y: int in h:
				for x: int in w:
					var i: int = y * w + x
					if img.get_pixel(x, y).a == 0.0:
						continue
					var edge := false
					for n: int in [i - 1, i + 1, i - w, i + w]:
						if n < 0 or n >= w * h:
							edge = true
							break
						if (x == 0 and n == i - 1) or (x == w - 1 and n == i + 1):
							continue
						if img.get_pixel(n % w, n / w).a == 0.0:
							edge = true
							break
					if edge and _is_whiteish(img.get_pixel(x, y)):
						kill.append(i)
			for i: int in kill:
				img.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
			if kill.is_empty():
				break
		# 3) 裁紧 + 缩到 128 盒内
		var used := img.get_used_rect()
		if used.size.x < 4 or used.size.y < 4:
			print("EMPTY ", id)
			continue
		var crop := img.get_region(used)
		var s := minf(float(BOX) / crop.get_width(), float(BOX) / crop.get_height())
		var nw := maxi(1, int(crop.get_width() * s))
		var nh := maxi(1, int(crop.get_height() * s))
		crop.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
		var out := "%s/%s.png" % [OUT_DIR, id]
		crop.save_png(ProjectSettings.globalize_path(out))
		var target := float(TARGETS.get(id, DEFAULT_TARGET))
		manifest[id] = {
			"image": "custom/%s.png" % id, "fw": nw, "fh": nh, "frames": 1, "fps": 1,
			"scale": snappedf(target / float(nh), 0.01), "kind": "emoji",
		}
		ok += 1
		print("KEYED %s %dx%d scale=%.3f" % [id, nw, nh, target / float(nh)])
	var f := FileAccess.open(fp, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	print("CHROMA_DONE ok=%d manifest=%d" % [ok, manifest.size()])
	quit(0)
