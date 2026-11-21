class_name Projectile
extends Node2D
## 投射物：追踪目标或飞向落点；命中时结算伤害 / AOE / 元素效果。

const SPEED := 340.0
const ELEMENT_COLORS := {
	"none": Color(1, 1, 1),
	"fire": Color(1.0, 0.5, 0.3),
	"ice": Color(0.6, 0.85, 1.0),
	"lightning": Color(1.0, 0.9, 0.4),
	"poison": Color(0.6, 1.0, 0.5),
}

var payload: Dictionary = {}
var target: Enemy = null
var target_pos := Vector2.ZERO
var game = null
var _dead := false


func launch(p_game, from: Vector2, to: Vector2, p_payload: Dictionary, p_target: Enemy = null) -> void:
	game = p_game
	position = from
	target_pos = to
	target = p_target
	payload = p_payload
	if target != null:
		target_pos = target.position
	var l := Label.new()
	var elem := String(payload.get("element", "none"))
	if payload.has("aoe"):
		l.text = "💣" if elem == "none" else "☄️"
	else:
		l.text = "✦"
	l.size = Vector2(28, 28)
	l.position = Vector2(-14, -14)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.modulate = ELEMENT_COLORS.get(elem, Color(1, 1, 1)) as Color
	add_child(l)


func _process(delta: float) -> void:
	if _dead:
		return
	if target != null and not target.dead:
		target_pos = target.position
	var to := target_pos - position
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
	queue_free()


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
