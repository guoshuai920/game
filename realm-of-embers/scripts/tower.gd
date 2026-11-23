class_name Tower
extends Node2D
## 塔：族/等级/进化分支，目标选择与开火。数值全部来自 data/towers.json。

const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")

var game = null  # main.gd，动态调用，避免脚本循环引用
var family_id := ""
var level := 1
var branch_id := ""
var element := "none"
var cost_paid := 0
var slot_index := -1
var is_high := false
var target_mode := 0  # 0=前排 1=高血 2=低血
var cooldown := 0.0
var disabled_time := 0.0

var _sprite: AnimatedSprite2D
var _sprite_family := ""
var _stars_label: Label
var _recoil_tw: Tween = null
var _fx_dis: AnimatedSprite2D = null
var _display_name := ""
var _tint := Color.WHITE


func setup(p_game, p_family: String, p_level: int, p_cost: int, p_high: bool) -> void:
	game = p_game
	family_id = p_family
	level = p_level
	cost_paid = p_cost
	is_high = p_high
	var fam := DataLoader.tower(family_id)
	element = String(fam.get("element", "none"))
	_display_name = String(fam.get("name", family_id))
	cooldown = 0.0
	_refresh_visual()


func _ready() -> void:
	_stars_label = Label.new()
	_stars_label.position = Vector2(-26, 26)
	_stars_label.size = Vector2(52, 18)
	_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stars_label.add_theme_font_size_override("font_size", 13)
	add_child(_stars_label)
	_refresh_visual()


func _refresh_visual() -> void:
	if family_id == "":
		return  # _ready 首次触发时 setup 还没来，等真正族名
	if _sprite == null or _sprite_family != family_id:
		if _sprite != null:
			_sprite.queue_free()
		_sprite = UnitsBank.make("tower_" + family_id)
		if _sprite != null:
			add_child(_sprite)
		_sprite_family = family_id
	if _stars_label != null:
		_stars_label.text = "★".repeat(level)
	_tint = Color.WHITE
	var fam2 := DataLoader.tower(family_id)
	_display_name = String(fam2.get("name", family_id))
	if branch_id != "":
		var b := DataLoader.branch_def(family_id, branch_id)
		_display_name = String(b.get("name", _display_name))
		_tint = Color(1.12, 1.05, 0.82)  # 进化后微微镀金
	if _sprite != null:
		_sprite.modulate = _tint


func branch_def_dict() -> Dictionary:
	if branch_id == "":
		return {}
	return DataLoader.branch_def(family_id, branch_id)


## 取最终数值（等级 → 分支覆盖 → 全局强化 → 高台加成）
func stat(key: String) -> float:
	var v := float(DataLoader.level_def(family_id, level).get(key, 0.0))
	if branch_id != "":
		var b := branch_def_dict()
		if b.has(key):
			v = float(b[key])
	if key == "dmg":
		v *= 1.0 + float(game.get_mod("dmg", 0.0))
	elif key == "rate":
		v *= 1.0 + float(game.get_mod("rate", 0.0))
	elif key == "range":
		v *= 1.0 + float(game.get_mod("range", 0.0))
		if is_high:
			v *= float(DataLoader.rules.get("highSlotRangeMul", 1.2))
	return v


func _process(delta: float) -> void:
	if disabled_time > 0.0:
		disabled_time -= delta
		modulate = Color(0.45, 0.45, 0.5)
		if _fx_dis == null:
			_fx_dis = FxBank.play(self, "fx_disable", Vector2.ZERO)
		return
	if _fx_dis != null:
		_fx_dis.queue_free()
		_fx_dis = null
	modulate = _tint
	cooldown -= delta
	if cooldown > 0.0:
		return
	var b := branch_def_dict()
	if branch_id != "" and bool(b.get("aura", false)):
		_fire_aura(b)
		cooldown = 1.0 / maxf(0.01, stat("rate"))
		return
	var target: Variant = _acquire_target()
	if target == null:
		cooldown = 0.0
		return
	cooldown = 1.0 / maxf(0.01, stat("rate"))
	_fire_at(target)


func _acquire_target() -> Variant:
	var rng := stat("range")
	var best: Variant = null
	var best_score := -INF
	for e in game.alive_enemies():
		if e.flying and family_id == "bomb":
			continue
		if e.position.distance_to(position) > rng:
			continue
		var score := -INF
		if target_mode == 1:
			score = float(e.hp)
		elif target_mode == 2:
			score = -float(e.hp)
		else:
			score = float(e.progress)
		if score > best_score:
			best_score = score
			best = e
	return best


func _effect_dict(key: String) -> Dictionary:
	if branch_id != "":
		var b := branch_def_dict()
		if b.has(key):
			return b[key] as Dictionary
	var v: Variant = DataLoader.level_def(family_id, level).get(key, {})
	if v is Dictionary:
		return v
	return {}


func _fire_at(target: Variant) -> void:
	match family_id:
		"arrow":
			Sfx.play("fire_arrow", -6.0)
		"frost":
			Sfx.play("fire_frost", -6.0)
		"thunder":
			Sfx.play("fire_thunder", -6.0)
		"flame":
			Sfx.play("fire_flame", -6.0)
		"bomb":
			Sfx.play("fire_bomb", -5.0)
		"venom":
			Sfx.play("fire_venom", -6.0)
	var b := branch_def_dict()
	var dmg := stat("dmg")
	var pierce := 0.0
	if b.has("pierce"):
		pierce = float(b["pierce"])
	var crit := randf() < 0.10 + float(game.get_mod("crit", 0.0))
	if crit:
		dmg *= 2.0
	if family_id == "thunder":
		_chain_hit(target, dmg, int(stat("chain")))
		_recoil()
		return
	var payload := {"dmg": dmg, "element": element, "pierce": pierce}
	if crit:
		payload["crit"] = true
	var aoe := stat("aoe")
	if aoe > 0.0:
		payload["aoe"] = aoe
		payload["ground_only"] = family_id == "bomb"
	if element == "fire":
		payload["burn"] = _effect_dict("burn")
	elif element == "ice":
		payload["slow"] = _effect_dict("slow")
	elif element == "poison":
		payload["poison"] = _effect_dict("poison")
		if bool(b.get("spread", false)):
			payload["spread"] = true
		if b.has("corrode"):
			payload["corrode"] = float(b["corrode"])
	var p := PROJECTILE_SCENE.instantiate()
	game.projectiles_node.add_child(p)
	if payload.has("aoe"):
		p.launch(game, position, (target as Node2D).position, payload)
	else:
		p.launch(game, position, Vector2.ZERO, payload, target)
	_recoil()


## 开火后坐：精灵下压回弹
func _recoil() -> void:
	if _sprite == null:
		return
	if _recoil_tw != null and _recoil_tw.is_valid():
		_recoil_tw.kill()
	_sprite.position.y = 3.0
	_recoil_tw = create_tween()
	_recoil_tw.tween_property(_sprite, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 雷塔连锁：立即结算，向最近未命中目标弹跳
func _chain_hit(first: Variant, dmg: float, chains: int) -> void:
	var hit: Array = [first]
	first.take_damage(dmg, element)
	FxBank.play(game.fx_air, "hit_lightning", (first as Node2D).position)
	var cur := first as Node2D
	var cur_dmg := dmg
	for i in chains:
		var nxt: Variant = null
		var best_d := 110.0
		for e in game.alive_enemies():
			if hit.has(e):
				continue
			var d: float = cur.position.distance_to((e as Node2D).position)
			if d < best_d:
				best_d = d
				nxt = e
		if nxt == null:
			break
		cur_dmg *= 0.7
		(nxt as Node2D).take_damage(cur_dmg, element)
		FxBank.play(game.fx_air, "hit_lightning", (nxt as Node2D).position)
		game.path_view.flash(cur.position, (nxt as Node2D).position, Color(0.75, 0.85, 1.0, 0.9))
		hit.append(nxt)
		cur = nxt as Node2D


## 极寒领域：范围脉冲减速
func _fire_aura(b: Dictionary) -> void:
	var slow := b.get("slow", {}) as Dictionary
	if slow.is_empty():
		return
	var rng := stat("range")
	var mul := maxf(0.1, float(slow.get("mul", 0.6)) - float(game.get_mod("slow_extra", 0.0)))
	var dur := float(slow.get("dur", 1.0))
	for e in game.alive_enemies():
		if e.position.distance_to(position) <= rng:
			e.apply_slow(mul, dur)


## 读档时恢复进化分支
func apply_branch(branch: String) -> void:
	branch_id = branch
	_refresh_visual()


## 升到 3 级时随机定型分支
func evolve() -> void:
	var fam := DataLoader.tower(family_id)
	var branches: Array = fam.get("branches", [])
	if branches.is_empty():
		return
	var pick: Dictionary = branches[randi() % branches.size()] as Dictionary
	branch_id = String(pick.get("id"))
	_refresh_visual()
	if game != null:
		game.log_msg("⭐ %s 进化为「%s」：%s" % [String(fam.get("name", "")), pick.get("name", ""), pick.get("desc", "")])
