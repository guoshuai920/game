class_name Militia
extends Node2D
## 空投民兵（主动技能）：站在落点阻截附近地面敌人，敌我互殴，被打死或超时后消散。
## KR 式驻军阻挡的轻量版：敌人进入纠缠范围即停下交战。

const HOLD_R := 30.0     # 纠缠半径
const ENEMY_DPS := 14.0  # 每个纠缠者对民兵的每秒伤害

var game = null
var max_hp := 60.0
var hp := 60.0
var dps := 18.0
var life := 10.0
var alive := true
var _held: Array = []
var _sprite: AnimatedSprite2D
var _bar_y := -52.0


func setup(p_game, p_hp: float, p_dps: float, p_life: float) -> void:
	game = p_game
	max_hp = p_hp
	hp = p_hp
	dps = p_dps
	life = p_life
	_sprite = UnitsBank.make("shield")
	if _sprite != null:
		_sprite.scale = Vector2(1.35, 1.35)
		_sprite.modulate = Color(0.85, 0.95, 1.25)  # 王室蓝披风感
		_bar_y = -float(UnitsBank.info("shield").get("fh", 14.0)) * 1.35 - 8.0
		add_child(_sprite)


func _draw() -> void:
	if hp >= max_hp:
		return
	var pct := clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-16, _bar_y, 32, 5), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-16, _bar_y, 32 * pct, 5), Color(0.5, 0.8, 1.0))


func _process(delta: float) -> void:
	if not alive:
		return
	life -= delta
	# 纠缠判定：范围内的地面敌人停下交战
	var in_range: Array = []
	for e in game.alive_enemies():
		var en := e as Enemy
		if en.flying or en.dead:
			continue
		if en.position.distance_to(position) <= HOLD_R:
			in_range.append(en)
			if en.hold_by != self:
				en.hold_by = self
	for e in _held:
		var en := e as Enemy
		if is_instance_valid(en) and en.hold_by == self and not in_range.has(en):
			en.hold_by = null
	_held = in_range
	# 互殴结算
	if not _held.is_empty():
		var target := _held[0] as Enemy
		if is_instance_valid(target) and not target.dead:
			target.take_damage(dps * delta, "reaction")
		hp -= float(_held.size()) * ENEMY_DPS * delta
		queue_redraw()
	if hp <= 0.0 or life <= 0.0:
		_die()


func _die() -> void:
	if not alive:
		return
	alive = false
	for e in _held:
		var en := e as Enemy
		if is_instance_valid(en) and en.hold_by == self:
			en.hold_by = null
	if game != null and game.fx_air != null:
		FxBank.play(game.fx_air, "death_poof", position, {"scale": 0.7})
	queue_free()
