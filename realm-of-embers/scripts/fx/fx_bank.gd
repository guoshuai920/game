class_name FxBank
extends Node
## 特效播放库：读取 tools/export_fx.mjs 生成的 assets/fx/index.json，
## 惰性构建 SpriteFrames；在指定层上播放一次性/循环特效。
## 用法：FxBank.play(game.fx_air, "hit_fire", pos)

static var _index: Dictionary = {}
static var _cache: Dictionary = {}   # name -> SpriteFrames
static var _loaded := false
static var reduced_motion := false   # 减弱动效：关震屏/转场/顿帧（无障碍开关，main 接线）
static var _last_play_ms: Dictionary = {}  # 反馈限流：fx_name -> msec
const THROTTLE_MS := 60   # 同名一次性特效最小间隔（防视觉"习惯化"，循环特效不受限）


static func ensure() -> void:
	if _loaded:
		return
	var f := FileAccess.open("res://assets/fx/index.json", FileAccess.READ)
	if f != null:
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Array:
			for e in data:
				_index[String((e as Dictionary).get("name", ""))] = e
	_loaded = true


static func info(fx_name: String) -> Dictionary:
	ensure()
	return _index.get(fx_name, {})


static func frames(fx_name: String) -> SpriteFrames:
	ensure()
	if _cache.has(fx_name):
		return _cache[fx_name]
	var inf := info(fx_name)
	if inf.is_empty():
		push_warning("FxBank: 未知特效 %s" % fx_name)
		return null
	var tex := load("res://assets/fx/" + String(inf.get("image", ""))) as Texture2D
	var atlas_text := FileAccess.get_file_as_string("res://assets/fx/" + String(inf.get("atlas", "")))
	var atlas: Variant = JSON.parse_string(atlas_text)
	if tex == null or not (atlas is Dictionary):
		push_warning("FxBank: 特效资源缺失 %s" % fx_name)
		return null
	var sf := SpriteFrames.new()
	sf.add_animation("fx")
	var anim := &"fx"
	sf.set_animation_speed(anim, float(inf.get("fps", 15)))
	sf.set_animation_loop(anim, bool(inf.get("loop", false)))
	for fr in (atlas as Dictionary).get("frames", []):
		var r: Dictionary = (fr as Dictionary).get("frame", {})
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(float(r.get("x", 0)), float(r.get("y", 0)), float(r.get("w", 0)), float(r.get("h", 0)))
		sf.add_frame(anim, at)
	_cache[fx_name] = sf
	return sf


## 在 layer 上于 pos 播放特效；opts: flip/scale/speed/modulate/life(循环特效的存活秒数)/z/priority(绕过限流)
static func play(layer: Node, fx_name: String, pos: Vector2, opts: Dictionary = {}) -> AnimatedSprite2D:
	if layer == null:
		return null
	var inf := info(fx_name)
	if inf.is_empty():
		return null
	# 同名一次性反馈限流：命中火花这类高频特效 60ms 内只放一次，防视觉噪声
	if not bool(inf.get("loop", false)) and not bool(opts.get("priority", false)):
		var now := Time.get_ticks_msec()
		var last := int(_last_play_ms.get(fx_name, -100000))
		if now - last < THROTTLE_MS:
			return null
		_last_play_ms[fx_name] = now
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames(fx_name)
	if s.sprite_frames == null:
		s.queue_free()
		return null
	var fw := float(inf.get("fw", 1))
	var fh := float(inf.get("fh", 1))
	var piv: Array = inf.get("pivot", [fw * 0.5, fh * 0.5])
	s.centered = true
	s.offset = Vector2(float(piv[0]) - fw * 0.5, float(piv[1]) - fh * 0.5)
	s.position = pos
	s.scale = Vector2.ONE * float(inf.get("scale", 1.0)) * float(opts.get("scale", 1.0))
	s.speed_scale = maxf(0.05, float(inf.get("speed", 1.0)) * float(opts.get("speed", 1.0)))
	s.flip_h = bool(opts.get("flip", false))
	if opts.has("modulate"):
		s.modulate = opts["modulate"] as Color
	s.z_index = int(opts.get("z", 0))
	layer.add_child(s)
	s.play(&"fx")
	if not bool(inf.get("loop", false)):
		var n := maxi(1, s.sprite_frames.get_frame_count(&"fx"))
		var life := float(n) / (float(inf.get("fps", 15)) * s.speed_scale)
		var tw := s.create_tween()
		tw.tween_interval(life)
		tw.tween_callback(s.queue_free)
	elif opts.has("life"):
		var tw2 := s.create_tween()
		tw2.tween_interval(float(opts["life"]))
		tw2.tween_callback(s.queue_free)
	return s
