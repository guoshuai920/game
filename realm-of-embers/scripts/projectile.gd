class_name Projectile
extends Node2D
## 投射物：追踪目标或飞向落点；命中时结算伤害 / AOE / 元素效果。

const SPEED := 340.0

var payload: Dictionary = {}
var target: Enemy = null
var target_pos := Vector2.ZERO
var game = null
var _dead := false
var _sprite: AnimatedSprite2D


func launch(p_game, from: Vector2, to: Vector2, p_payload: Dictionary, p_target: Enemy = null) -> void:
	game = p_game
	position = from
	target_pos = to
	target = p_target
	payload = p_payload
	if target != null:
		target_pos = target.position
	var elem := String(payload.get("element", "none"))
	var spr_id := "proj_arrow"
	if payload.has("aoe"):
		spr_id = "proj_bomb"
	else:
		match elem:
			"fire":
				spr_id = "proj_fire"
			"ice":
				spr_id = "proj_ice"
			"lightning":
				spr_id = "proj_volt"
			"poison":
				spr_id = "proj_venom"
	_sprite = UnitsBank.make(spr_id)
	if _sprite != null:
		add_child(_sprite)


func _process(delta: float) -> void:
	if _dead:
		return
	if target != null and not target.dead:
		target_pos = target.position
	var to := target_pos - position
	if _sprite != null:
		# 弹道素材按"右上 45°"绘制，旋转到运动方向
		_sprite.rotation = to.angle() + PI * 0.25
	var step := SPEED * delta
	if to.length() <= step:
		position = target_pos
		_hit()
		return
	position += to.normalized() * step


func _hit() -> void:
	if _dead:
		return
	_dead = true
	var dmg := float(payload.get("dmg", 0.0))
	var elem := String(payload.get("element", "none"))
	var pierce := float(payload.get("pierce", 0.0))
	if payload.has("aoe"):
		var radius := float(payload["aoe"])
		for e in game.alive_enemies():
			var en := e as Enemy
			if bool(payload.get("ground_only", false)) and en.flying:
				continue
			if en.position.distance_to(position) <= radius:
				en.take_damage(dmg, elem, pierce)
				_apply_effects(en)
	else:
		if target != null and not target.dead:
			target.take_damage(dmg, elem, pierce)
			_apply_effects(target)
	if bool(payload.get("crit", false)):
		game._crit_float(position, int(dmg))
	_hit_fx(elem)
	queue_free()


## 命中特效：AOE 走地面层，单体命中走上层；暴击金色版，元素对应色板变体
func _hit_fx(elem: String) -> void:
	if game == null:
		return
	if payload.has("aoe"):
		var aoe_name := "aoe_bomb"
		if elem == "fire":
			aoe_name = "aoe_fire"
		elif elem == "poison":
			aoe_name = "aoe_venom"
		FxBank.play(game.fx_ground, aoe_name, position)
		return
	if bool(payload.get("crit", false)):
		FxBank.play(game.fx_air, "hit_crit", position)
		return
	var hit_name := "hit_arrow"
	match elem:
		"fire":
			hit_name = "hit_fire"
		"ice":
			hit_name = "hit_ice"
		"lightning":
			hit_name = "hit_lightning"
		"poison":
			hit_name = "hit_poison"
	FxBank.play(game.fx_air, hit_name, position)


func _apply_effects(e: Enemy) -> void:
	if payload.has("burn"):
		var b := payload["burn"] as Dictionary
		e.apply_burn(float(b.get("dps", 0.0)) * (1.0 + float(game.get_mod("burn", 0.0))), float(b.get("dur", 2.0)))
	if payload.has("slow"):
		var s := payload["slow"] as Dictionary
		e.apply_slow(maxf(0.1, float(s.get("mul", 0.6)) - float(game.get_mod("slow_extra", 0.0))), float(s.get("dur", 1.5)))
	if payload.has("poison"):
		var ps := payload["poison"] as Dictionary
		e.apply_poison(
			float(ps.get("dps", 0.0)) * (1.0 + float(game.get_mod("poison", 0.0))),
			float(ps.get("dur", 3.0)),
			bool(payload.get("spread", false)),
			float(payload.get("corrode", 0.0))
		)
