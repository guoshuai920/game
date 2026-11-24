class_name UnitsBank
extends Node
## 单位精灵库：读取 tools/bake_units.mjs 生成的 assets/units/units.json。
## make(id) 返回已锚定的 AnimatedSprite2D：单位脚底中心、弹道中心。

static var _manifest: Dictionary = {}
static var _cache: Dictionary = {}   # id -> SpriteFrames
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	var f := FileAccess.open("res://assets/units/units.json", FileAccess.READ)
	if f != null:
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			_manifest = data
	# emoji 高清层（tools/bake_emoji.gd 产出）覆盖像素稿；缺字体的机器不会生成对应条目，自然回落
	var fe := FileAccess.open("res://assets/units/emoji.json", FileAccess.READ)
	if fe != null:
		var ed: Variant = JSON.parse_string(fe.get_as_text())
		fe.close()
		if ed is Dictionary:
			for k: String in (ed as Dictionary):
				_manifest[k] = (ed as Dictionary)[k]
	_loaded = true


static func info(id: String) -> Dictionary:
	ensure()
	return _manifest.get(id, {})


static func frames(id: String) -> SpriteFrames:
	ensure()
	if _cache.has(id):
		return _cache[id]
	var inf := info(id)
	if inf.is_empty():
		push_warning("UnitsBank: 未知精灵 %s" % id)
		return null
	var tex := load("res://assets/units/" + String(inf.get("image", ""))) as Texture2D
	if tex == null:
		push_warning("UnitsBank: 纹理缺失 %s" % id)
		return null
	var sf := SpriteFrames.new()
	sf.add_animation("move")
	var n := int(inf.get("frames", 1))
	var fw := int(inf.get("fw", 1))
	var fh := int(inf.get("fh", 1))
	for i in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame(&"move", at)
	sf.set_animation_speed(&"move", float(inf.get("fps", 6)))
	sf.set_animation_loop(&"move", true)
	_cache[id] = sf
	return sf


static func frame_texture(id: String) -> Texture2D:
	## 第一帧纹理（供 _draw 使用，如城堡）
	var inf := info(id)
	if inf.is_empty():
		return null
	var tex := load("res://assets/units/" + String(inf.get("image", ""))) as Texture2D
	if tex == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, 0, float(inf.get("fw", 1)), float(inf.get("fh", 1)))
	return at


static func make(id: String) -> AnimatedSprite2D:
	var inf := info(id)
	if inf.is_empty():
		return null
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames(id)
	if s.sprite_frames == null:
		return null
	# 关键：SpriteFrames.new() 自带空的 "default" 动画，不指到 "move" 的话
	# 静态精灵（frames==1，不会 play）会停在空动画上——什么都不画
	s.animation = &"move"
	var fw := float(inf.get("fw", 1))
	var fh := float(inf.get("fh", 1))
	s.centered = false
	if id.begins_with("proj_"):
		s.offset = Vector2(-fw * 0.5, -fh * 0.5)  # 弹道：中心锚点
	else:
		s.offset = Vector2(-fw * 0.5, -fh)          # 单位/塔：脚底中心锚点
	s.scale = Vector2.ONE * float(inf.get("scale", 1.0))
	if int(inf.get("frames", 1)) > 1:
		s.play(&"move")
	return s
