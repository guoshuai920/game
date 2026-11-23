class_name Enemy
extends Node2D
## 敌人：沿路径行进；血/甲/特性（飞行·治疗·分裂·召唤·瘫痪·狂暴）；
## 元素标签 + 连锁反应判定。数值来自 data/enemies.json 与 data/reactions.json。

var game = null  # main.gd，动态调用
var id := ""
var display_name := ""
var emoji := "🧌"
var max_hp := 1.0
var hp := 1.0
var base_speed := 60.0
var armor := 0.0
var bounty := 0
var lives_cost := 1
var flying := false
var immune: Array = []
var spawn_mul := 1.0

var wp_i := 0
var progress := 0.0  # 目标选择：越大越靠近城堡
var dead := false

var slow_mul := 1.0
var slow_timer := 0.0
var burn_dps := 0.0
var burn_timer := 0.0
var poison_stacks := 0
var poison_dps := 0.0
var poison_timer := 0.0
var poison_spread_dps := 0.0
var stun_timer := 0.0
var speed_buff := 1.0
var hold_by: Node2D = null  # 被民兵纠缠：站在原地交战
var _phases_done: Array = []

var _super_timer := 0.0
var _corrode_timer := 0.0
var _corrode_mul := 0.7
var _wp: Array = []
var _castle := Vector2.ZERO
var _last_elements: Dictionary = {}
var _heal_cd := 0.0
var _summon_cd := 0.0
var _disable_cd := 0.0
var _can_disable := false
var _rage_done: Array = []
var _sprite: AnimatedSprite2D
var _base_scale := Vector2.ONE
var _punch_tw: Tween = null
var _fx_burn: AnimatedSprite2D = null
var _fx_slow: AnimatedSprite2D = null
var _fx_poison: AnimatedSprite2D = null
var _fx_stun: AnimatedSprite2D = null


func setup(p_game, p_id: String, p_mul: float) -> void:
	game = p_game
	id = p_id
	spawn_mul = p_mul
	var def := DataLoader.enemy(id)
	display_name = String(def.get("name", id))
	emoji = String(def.get("emoji", "🧌"))
	max_hp = float(def.get("hp", 10.0)) * p_mul
	hp = max_hp
	base_speed = float(def.get("speed", 60.0))
	armor = float(def.get("armor", 0.0))
	bounty = int(def.get("bounty", 1))
	lives_cost = int(def.get("livesCost", 1))
	flying = bool(def.get("fly", false))
	var im: Variant = def.get("immune", [])
	if im is Array:
		immune = im
	var heal := def.get("heal", {}) as Dictionary
	if not heal.is_empty():
		_heal_cd = float(heal.get("interval", 2.0))
	var summon := def.get("summon", {}) as Dictionary
	if not summon.is_empty():
		_summon_cd = float(summon.get("interval", 4.0))
	if def.has("disable"):
		_can_disable = true
		_disable_cd = 2.0
	var r: Dictionary = DataLoader.rules
	_wp = r.get("path", [])
	var c: Array = r.get("castle", [1200, 600])
	_castle = Vector2(float(c[0]), float(c[1]))
	_make_sprite()


func _make_sprite() -> void:
	_sprite = UnitsBank.make(id)
	if _sprite == null:
		return
	_base_scale = _sprite.scale
	if bool(DataLoader.enemy(id).get("boss", false)):
		_base_scale *= 1.2
	_sprite.scale = _base_scale
	add_child(_sprite)


## 按 cond 维护挂在身上的循环状态特效（灼烧/冻结/中毒/感电）
func _attach_status(cond: bool, fx_name: String, store: String, y_off: float) -> void:
	var cur: AnimatedSprite2D = get(store)
	if cond and cur == null:
		var s := FxBank.play(self, fx_name, Vector2(0, y_off))
		if s != null:
			s.z_index = 2
			set(store, s)
	elif not cond and cur != null:
		cur.queue_free()
		set(store, null)


func armor_mult() -> float:
	var m := 1.0
	if _super_timer > 0.0:
		m = minf(m, 0.5)
	if _corrode_timer > 0.0:
		m = minf(m, _corrode_mul)
	return m


func _draw() -> void:
	if dead or max_hp <= 0.0:
		return
	var pct := clampf(hp / max_hp, 0.0, 1.0)
	if pct >= 1.0:
		return
	var w := 36.0
	if lives_cost >= 3:
		w = 54.0
	var col := Color(0.9, 0.35, 0.3)
	if pct > 0.25:
		col = Color(0.95, 0.8, 0.3)
	if pct > 0.5:
		col = Color(0.4, 0.9, 0.4)
	draw_rect(Rect2(-w * 0.5, -44, w, 5), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(-w * 0.5, -44, w * pct, 5), col)


func _process(delta: float) -> void:
	if dead:
		return
	_tick_status(delta)
	if dead:
		return
	_attach_status(burn_timer > 0.0, "st_burn", "_fx_burn", 0.0)
	_attach_status(slow_timer > 0.0, "st_slow", "_fx_slow", 0.0)
	_attach_status(poison_timer > 0.0, "st_poison", "_fx_poison", 2.0)
	_attach_status(stun_timer > 0.0, "st_stun", "_fx_stun", 0.0)
	if stun_timer > 0.0:
		stun_timer -= delta
		modulate = Color(1.0, 0.95, 0.4)
		queue_redraw()
		return
	if burn_timer > 0.0:
		modulate = Color(1.0, 0.55, 0.55)
	elif slow_timer > 0.0:
		modulate = Color(0.6, 0.8, 1.0)
	else:
		modulate = Color.WHITE
	_specials(delta)
	if dead:
		return
	_move(delta)
	queue_redraw()


func _tick_status(delta: float) -> void:
	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_mul = 1.0
	if burn_timer > 0.0:
		burn_timer -= delta
		_damage_raw(burn_dps * delta)
	if poison_timer > 0.0:
		poison_timer -= delta
		_damage_raw(poison_dps * float(poison_stacks) * delta)
		if poison_timer <= 0.0:
			poison_stacks = 0
			poison_dps = 0.0
	if _super_timer > 0.0:
		_super_timer -= delta
	if _corrode_timer > 0.0:
		_corrode_timer -= delta


func _damage_raw(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		_die()


func apply_burn(dps: float, dur: float) -> void:
	burn_dps = maxf(burn_dps, dps)
	burn_timer = maxf(burn_timer, dur)


func apply_slow(mul: float, dur: float) -> void:
	slow_mul = minf(slow_mul, mul)
	slow_timer = maxf(slow_timer, dur)


func apply_poison(dps: float, dur: float, spread: bool, corrode: float = 0.0) -> void:
	poison_stacks = mini(poison_stacks + 1, 3)
	poison_dps = maxf(poison_dps, dps)
	poison_timer = maxf(poison_timer, dur)
	if spread and poison_spread_dps <= 0.0:
		poison_spread_dps = dps
	if corrode > 0.0:
		_corrode_mul = 1.0 - corrode
		_corrode_timer = maxf(_corrode_timer, 3.0)


func take_damage(amount: float, element: String, pierce: float = 0.0) -> void:
	if dead:
		return
	if element != "reaction" and immune.has(element):
		return
	var dmg := amount
	if element == "none":
		dmg *= 1.0 - armor * armor_mult() * (1.0 - pierce)
	hp -= dmg
	if element != "none" and element != "reaction":
		_register_element(element)
	queue_redraw()
	_punch()
	if hp <= 0.0:
		_die()


## 受击弹跳：精灵短暂放大后回弹
func _punch() -> void:
	if _sprite == null:
		return
	if _punch_tw != null and _punch_tw.is_valid():
		_punch_tw.kill()
	_sprite.scale = _base_scale * 1.18
	_punch_tw = create_tween()
	_punch_tw.tween_property(_sprite, "scale", _base_scale, 0.12)


## 元素标签：2 秒内叠到两种不同元素 → 查反应表触发
func _register_element(elem: String) -> void:
	var now: float = game.game_time
	var partner := ""
	for k in _last_elements.keys():
		if String(k) != elem and now - float(_last_elements[k]) <= 2.0:
			partner = String(k)
	_last_elements[elem] = now
	if partner == "":
		return
	var pair: Array = [elem, partner]
	pair.sort()
	var key := "%s+%s" % [String(pair[0]), String(pair[1])]
	for r in DataLoader.reactions:
		if String(r.get("pair")) == key:
			_trigger_reaction(r as Dictionary)
			_last_elements.clear()
			return


## Boss 阶段动作：summon:怪:数量 / enrage:倍率 / armor:增量 / heal:比例 / disable
func _run_phase(act: String) -> void:
	var parts := act.split(":")
	if parts.is_empty():
		return
	match parts[0]:
		"summon":
			var mid := parts[1] if parts.size() > 1 else "skeleton"
			var count := int(parts[2]) if parts.size() > 2 else 2
			FxBank.play(game.fx_ground, "fx_summon", position, {"scale": 0.9})
			Sfx.play("build", -4.0)
			for i in count:
				game.spawn_enemy_at(mid, position + Vector2(randf_range(-24, 24), randf_range(-14, 14)), spawn_mul)
			game.log_msg("🌀 %s 召唤了援军！" % display_name)
		"enrage":
			var mul := float(parts[1]) if parts.size() > 1 else 1.4
			speed_buff *= mul
			FxBank.play(game.fx_air, "fx_rage", position, {"life": 1.2, "priority": true})
			game.log_msg("🔥 %s 进入狂暴！" % display_name)
		"armor":
			var add := float(parts[1]) if parts.size() > 1 else 0.2
			armor = minf(0.85, armor + add)
			FxBank.play(game.fx_air, "rx_overload", position, {"scale": 0.8, "priority": true})
			game.log_msg("🪨 %s 甲壳增生！护甲提升" % display_name)
		"heal":
			var pct := float(parts[1]) if parts.size() > 1 else 0.2
			hp = minf(max_hp, hp + max_hp * pct)
			FxBank.play(game.fx_ground, "fx_heal", position, {"priority": true})
			game.log_msg("💚 %s 恢复了 %d 点生命力" % [display_name, int(max_hp * pct)])
		"disable":
			var best: Variant = null
			var best_d := 240.0
			for t in game.towers_node.get_children():
				var d: float = position.distance_to(t.position)
				if d <= best_d and t.disabled_time <= 0.0:
					best_d = d
					best = t
			if best != null:
				best.disabled_time = 4.0
				Sfx.play("tower_disabled", -2.0)
				game.log_msg("🦂 %s 瘫痪了一座塔！" % display_name)


func _trigger_reaction(r: Dictionary) -> void:
	match String(r.get("id")):
		"steam":
			var dmg := float(r.get("dmg", 20.0)) * (1.0 + float(game.get_mod("reaction", 0.0)))
			game.aoe_damage(position, float(r.get("radius", 70.0)), dmg)
			FxBank.play(game.fx_ground, "rx_steam", position, {"scale": 1.1})
			Sfx.play("rx_steam", -2.0)
			game.log_msg("⚗️ 蒸汽爆发！")
		"superconductor":
			_super_timer = maxf(_super_timer, float(r.get("dur", 5.0)))
			FxBank.play(game.fx_air, "rx_superconductor", position)
			Sfx.play("rx_super", -2.0)
			game.log_msg("🧲 超导！护甲减半")
		"overload":
			stun_timer = maxf(stun_timer, float(r.get("stun", 0.5)))
			FxBank.play(game.fx_air, "rx_overload", position)
			Sfx.play("rx_overload", -2.0)
			game.log_msg("💥 感电过载！眩晕")


func _specials(delta: float) -> void:
	var def := DataLoader.enemy(id)
	# Boss 阶段脚本：血量阈值触发一次性动作
	var phases: Variant = def.get("phases", [])
	if phases is Array:
		for i in (phases as Array).size():
			var pp := phases[i] as Dictionary
			var key := "p%d" % i
			if hp / maxf(1.0, max_hp) <= float(pp.get("pct", 0.0)) and not _phases_done.has(key):
				_phases_done.append(key)
				_run_phase(String(pp.get("act", "")))
	# 狂暴阈值
	var rage: Variant = def.get("rage", [])
	if rage is Array:
		for rg in rage:
			var rr := rg as Dictionary
			var key := str(rr.get("pct", 0.0))
			if hp / maxf(1.0, max_hp) <= float(rr.get("pct", 0.0)) and not _rage_done.has(key):
				_rage_done.append(key)
				speed_buff *= float(rr.get("mul", 1.2))
				FxBank.play(game.fx_air, "fx_rage", position, {"life": 1.2})
				game.log_msg("🔥 %s 进入狂暴！" % display_name)
	# 群体治疗
	if _heal_cd > 0.0:
		_heal_cd -= delta
		if _heal_cd <= 0.0:
			var heal := def.get("heal", {}) as Dictionary
			_heal_cd = float(heal.get("interval", 2.0))
			var radius := float(heal.get("radius", 100.0))
			var amt := float(heal.get("amount", 10.0))
			FxBank.play(game.fx_ground, "fx_heal", position)
			for e in game.alive_enemies():
				var en := e as Enemy
				if not en.dead and en.position.distance_to(position) <= radius and en.hp < en.max_hp:
					en.hp = minf(en.max_hp, en.hp + amt)
					en.queue_redraw()
	# 持续召唤
	if _summon_cd > 0.0:
		_summon_cd -= delta
		if _summon_cd <= 0.0:
			var summon := def.get("summon", {}) as Dictionary
			_summon_cd = float(summon.get("interval", 4.0))
			# 召唤用小型法阵（fx_summon 的魔物登場演出保留给 Boss 出场）
			FxBank.play(game.fx_ground, "fx_merge", position, {"scale": 0.55, "speed": 1.6})
			game.spawn_enemy_at(String(summon.get("into", "skeleton")), position, spawn_mul)
			game.log_msg("💀 %s 召唤了骷髅！" % display_name)
	# 瘫痪附近的塔
	if _can_disable:
		_disable_cd -= delta
		if _disable_cd <= 0.0:
			var dd := def.get("disable", {}) as Dictionary
			_disable_cd = float(dd.get("cd", 6.0))
			var best: Variant = null
			var best_d := float(dd.get("radius", 60.0))
			for t in game.towers_node.get_children():
				var d: float = position.distance_to(t.position)
				if d <= best_d and t.disabled_time <= 0.0:
					best_d = d
					best = t
			if best != null:
				best.disabled_time = float(dd.get("dur", 3.0))
				Sfx.play("tower_disabled", -2.0)
				game.log_msg("🦂 %s 瘫痪了一座塔！" % display_name)


func _move(delta: float) -> void:
	var sp := base_speed * slow_mul * speed_buff
	if sp <= 0.0 or _wp.is_empty():
		return
	# 被民兵纠缠：原地交战（民兵结算双方伤害）
	if hold_by != null:
		if not is_instance_valid(hold_by) or not hold_by.alive:
			hold_by = null
		else:
			return
	if flying:
		var d := _castle - position
		var step := sp * delta
		if _sprite != null:
			_sprite.flip_h = d.x < -1.0
		if d.length() <= step:
			_leak()
			return
		position += d.normalized() * step
		progress += step * 0.01
		return
	if wp_i >= _wp.size() - 1:
		_leak()
		return
	var target_p := Vector2(float(_wp[wp_i + 1][0]), float(_wp[wp_i + 1][1]))
	var d2 := target_p - position
	if _sprite != null:
		_sprite.flip_h = d2.x < -1.0
	var step2 := sp * delta
	if d2.length() <= step2:
		position = target_p
		wp_i += 1
	else:
		position += d2.normalized() * step2
	progress = float(wp_i) * 1000.0 - position.distance_to(_castle)


func _leak() -> void:
	if dead:
		return
	dead = true
	game.on_enemy_leaked(self)
	queue_free()


func _die() -> void:
	if dead:
		return
	dead = true
	_death_fx()
	game.on_enemy_died(self)
	queue_free()


## 死亡特效：Boss 灰化 / 杂兵化烟 / 普通击杀化烟+金币
func _death_fx() -> void:
	if game == null or game.fx_air == null:
		return
	var fx := "death_coin"
	if bool(DataLoader.enemy(id).get("boss", false)):
		fx = "death_boss"
		Sfx.play("boss_die", -1.0)
	elif id == "skeleton" or id == "slimelet":
		fx = "death_poof"
		Sfx.play("enemy_die", -6.0)
	else:
		Sfx.play("enemy_die", -6.0)
	FxBank.play(game.fx_air, fx, position)
