extends Control
## 《王国余烬》主循环：波次、经济（利息/赏金/卖塔）、建塔/移动/合成、
## 元素反应、波间三选一强化、胜负判定。数值全部来自 data/*.json。

const TOWER_SCENE := preload("res://scenes/Tower.tscn")
const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const MODE_NAMES := ["前排", "高血", "低血"]
const RARITY_NAMES := {"common": "普通", "rare": "稀有", "epic": "史诗"}
const RARITY_WEIGHTS := {"common": 60.0, "rare": 30.0, "epic": 10.0}

@onready var path_view: Node2D = $PathView
@onready var fx_ground: Node2D = $FxGround
@onready var towers_node: Node2D = $Towers
@onready var enemies_node: Node2D = $Enemies
@onready var projectiles_node: Node2D = $Projectiles
@onready var fx_air: Node2D = $FxAir
@onready var wave_label: Label = $TopBar/WaveLabel
@onready var gold_label: Label = $TopBar/GoldLabel
@onready var lives_label: Label = $TopBar/LivesLabel
@onready var preview_label: Label = $TopBar/PreviewLabel
@onready var log_label: Label = $LogLabel
@onready var shop_bar: HBoxContainer = $ShopBar
@onready var sel_panel: HBoxContainer = $SelPanel
@onready var sell_button: Button = $SelPanel/SellButton
@onready var mode_button: Button = $SelPanel/ModeButton
@onready var next_wave_button: Button = $NextWaveButton
@onready var restart_run_button: Button = $TopBar/RestartRunButton
@onready var quit_button: Button = $TopBar/QuitButton
@onready var save_overlay: Control = $SaveOverlay
@onready var slot_box: VBoxContainer = $SaveOverlay/SlotBox
@onready var new_game_button: Button = $SaveOverlay/NewGameButton
@onready var upgrade_overlay: Control = $UpgradeOverlay
@onready var upgrade_title: Label = $UpgradeOverlay/Title
@onready var choice_box: HBoxContainer = $UpgradeOverlay/ChoiceBox
@onready var end_overlay: Control = $EndOverlay
@onready var end_label: Label = $EndOverlay/EndLabel
@onready var restart_button: Button = $EndOverlay/RestartButton

var mods := {}  # 强化 id -> 累加值
var gold := 0
var lives := 0
var wave_idx := 0
var state := "planning"  # planning / wave / upgrade / over
var active_slot := 1  # 当前存档位 1~3
var test_mode := false  # autotest/testload 用独立测试档，保护真实存档
var shop_sel := ""
var sel_tower: Tower = null
var drag_tower: Tower = null
var drag_started := false
var drag_origin := Vector2.ZERO
var slots: Array = []  # {pos: Vector2, high: bool, tower: Tower|null}
var shop_buttons := {}  # family_id -> Button
var spawn_queue: Array = []
var wave_clock := 0.0
var game_time := 0.0
var upgrade_choices: Array = []
var autotest := false


func _ready() -> void:
	autotest = OS.get_cmdline_user_args().has("--autotest")
	test_mode = autotest or OS.get_cmdline_user_args().has("--testload")
	gold = int(DataLoader.rules.get("startGold", 220))
	lives = int(DataLoader.rules.get("lives", 20))
	for s in DataLoader.rules.get("slots", []):
		var high: bool = (s as Array).size() > 2 and bool((s as Array)[2])
		slots.append({"pos": Vector2(float(s[0]), float(s[1])), "high": high, "tower": null})
	next_wave_button.pressed.connect(_on_next_wave)
	next_wave_button.text = "开始"
	new_game_button.pressed.connect(_on_new_game)
	restart_run_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	sell_button.pressed.connect(_on_sell)
	mode_button.pressed.connect(_on_mode)
	restart_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	restart_button.focus_mode = Control.FOCUS_NONE
	_build_shop()
	_migrate_legacy_save()
	_refresh_preview()
	_render()
	log_msg("建立防线！点下方选塔，再点发光格位放置；拖同类同星合成升星")
	if not test_mode and _any_slot_save():
		_show_save_panel()
	if autotest:
		Engine.time_scale = 10.0
		log_msg("[自动测试] 引擎加速 10x")
		_autotest_step()
	if OS.get_cmdline_user_args().has("--testload"):
		call_deferred("_testload")


# ---------- 商店与渲染 ----------

func _build_shop() -> void:
	for fam in DataLoader.towers:
		var f := fam as Dictionary
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 62)
		b.text = "%s %s\n%d 金" % [f.get("emoji", ""), f.get("name", ""), int(f.get("cost", 0))]
		b.tooltip_text = String(f.get("desc", ""))
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_on_shop_click.bind(String(f.get("id"))))
		shop_bar.add_child(b)
		shop_buttons[String(f.get("id"))] = b


func get_mod(key: String, dflt: float) -> float:
	return float(mods.get(key, dflt))


func log_msg(text: String) -> void:
	log_label.text = text
	print(text)


func alive_enemies() -> Array:
	var out: Array = []
	for e in enemies_node.get_children():
		var en := e as Enemy
		if not en.dead:
			out.append(en)
	return out


func aoe_damage(pos: Vector2, radius: float, dmg: float) -> void:
	for e in alive_enemies():
		var en := e as Enemy
		if en.position.distance_to(pos) <= radius:
			en.take_damage(dmg, "reaction")


func spawn_enemy_at(id: String, pos: Vector2, mul: float) -> void:
	var e := ENEMY_SCENE.instantiate()
	enemies_node.add_child(e)
	e.setup(self, id, mul)
	e.position = pos


## 是否有模态弹窗打开（存档面板/三选一/结算）——打开期间背景一切交互禁用
func _modal_open() -> bool:
	return save_overlay.visible or upgrade_overlay.visible or end_overlay.visible


func _render() -> void:
	wave_label.text = "第 %d/%d 波" % [maxi(wave_idx, 1) if wave_idx > 0 else 1, DataLoader.waves.size()]
	if wave_idx == 0:
		wave_label.text = "准备阶段"
	gold_label.text = "💰 %d" % gold
	lives_label.text = "🏰 %d" % maxi(lives, 0)
	lives_label.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.45) if lives <= 5 else Color(0.9, 0.92, 0.95))
	var modal := _modal_open()
	for fid in shop_buttons:
		var b := shop_buttons[fid] as Button
		var cost := int(DataLoader.tower(fid).get("cost", 0))
		b.disabled = modal or gold < cost or state == "over"
	var show_sel := sel_tower != null and is_instance_valid(sel_tower) and not modal
	sel_panel.visible = show_sel
	next_wave_button.disabled = modal or state != "planning"
	restart_run_button.disabled = modal
	quit_button.disabled = modal
	path_view.build_mode = shop_sel != "" and state != "over" and not modal
	if show_sel:
		path_view.show_range = true
		path_view.range_center = sel_tower.position
		path_view.range_radius = sel_tower.stat("range")
		sell_button.text = "卖出 +%d" % _sell_value(sel_tower)
		mode_button.text = "目标：%s" % MODE_NAMES[sel_tower.target_mode]
	else:
		path_view.show_range = false
	path_view.queue_redraw()  # 自绘层数据变了必须手动触发重绘


func _refresh_preview() -> void:
	var nxt := wave_idx + 1
	if nxt > DataLoader.waves.size():
		preview_label.text = ""
		return
	var counts := {}
	for g in (DataLoader.waves[nxt - 1] as Dictionary).get("groups", []):
		var eid := String((g as Dictionary).get("enemy"))
		counts[eid] = int(counts.get(eid, 0)) + int((g as Dictionary).get("count", 0))
	var parts: Array = []
	for eid in counts:
		parts.append("%s×%d" % [DataLoader.enemy(eid).get("emoji", ""), counts[eid]])
	preview_label.text = "下一波：%s" % " ".join(parts)


# ---------- 输入：建塔 / 选择 / 移动 / 合成 ----------

func _unhandled_input(event: InputEvent) -> void:
	if state == "over":
		if event is InputEventKey and event.is_pressed():
			var k := event as InputEventKey
			if k.keycode == KEY_SPACE or k.keycode == KEY_ENTER:
				get_tree().reload_current_scene()
		return
	if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		# ESC：取消拖拽 / 取消选塔（桌面快捷键，触屏用取消按钮）
		_cancel_drag()
		shop_sel = ""
		sel_tower = null
		_render()
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var pos := get_global_mouse_position()
			var t: Variant = _tower_at(pos)
			if t != null:
				drag_tower = t as Tower
				drag_started = false
				drag_origin = drag_tower.position
				drag_tower.z_index = 10
				sel_tower = drag_tower
				_show_selected_info(sel_tower)
				_render()
			else:
				_handle_click(pos)


## 取消拖拽：塔弹回原位（ESC 快捷键）
func _cancel_drag() -> void:
	if drag_tower == null:
		return
	if is_instance_valid(drag_tower):
		var src := slots[drag_tower.slot_index] as Dictionary
		drag_tower.position = src.get("pos") as Vector2
		drag_tower.z_index = 0
	drag_tower = null
	_render()


## 拖拽跟手：用 _input 观察移动（不消费事件，UI 区域也能跟）
func _input(event: InputEvent) -> void:
	if drag_tower == null or not is_instance_valid(drag_tower):
		return
	if event is InputEventMouseMotion:
		var pos := get_global_mouse_position()
		if pos.distance_to(drag_origin) > 10.0:
			drag_started = true
		drag_tower.position = pos
		# 拖拽时射程圈实时跟随
		if sel_tower == drag_tower:
			path_view.show_range = true
			path_view.range_center = drag_tower.position
			path_view.range_radius = drag_tower.stat("range")
			path_view.queue_redraw()


func _handle_click(pos: Vector2) -> void:
	# 纯点击：选中 / 建塔 / 取消（移动与合成都走拖拽）
	var t: Variant = _tower_at(pos)
	if t != null:
		sel_tower = t as Tower
		_show_selected_info(sel_tower)
		_render()
		return
	var si := _slot_at(pos)
	if si >= 0 and shop_sel != "":
		_build_tower(shop_sel, si)
		return
	# 点商店以外的地方：取消选塔 + 退出建塔模式
	sel_tower = null
	shop_sel = ""
	_render()


func _show_selected_info(t: Tower) -> void:
	log_msg("%s Lv%d · 伤害%d 攻速%.1f 射程%d · 拖拽：同类同星→合成 / 空位→移动 / 有塔→交换%s" % [
		_tw_name(t), t.level, int(t.stat("dmg")), t.stat("rate"), int(t.stat("range")),
		"（高台射程+20%）" if t.is_high else "",
	])


func _tw_name(t: Tower) -> String:
	var fam := DataLoader.tower(t.family_id)
	var name := String(fam.get("name", t.family_id))
	if t.branch_id != "":
		name = String(DataLoader.branch_def(t.family_id, t.branch_id).get("name", name))
	return "%s %s" % [String(fam.get("emoji", "")), name]


func _tower_at(pos: Vector2, exclude: Tower = null) -> Variant:
	var best: Variant = null
	var best_d := 30.0
	for t in towers_node.get_children():
		var tw := t as Tower
		if tw == exclude:
			continue
		var d := pos.distance_to(tw.position)
		if d < best_d:
			best_d = d
			best = tw
	return best


func _slot_at(pos: Vector2) -> int:
	var best := -1
	var best_d := 32.0
	for i in slots.size():
		var s := slots[i] as Dictionary
		var d := pos.distance_to(s.get("pos") as Vector2)
		if d < best_d:
			best_d = d
			best = i
	return best


func _on_shop_click(fid: String) -> void:
	if shop_sel == fid:
		shop_sel = ""  # 再点一次同一个塔按钮 = 取消选择（触屏友好）
	else:
		shop_sel = fid
		sel_tower = null
		var fam := DataLoader.tower(fid)
		log_msg("已选 %s（%d金）——点击空格位连放；点商店以外的地方即取消" % [
			"%s %s" % [fam.get("emoji", ""), fam.get("name", "")], int(fam.get("cost", 0)),
		])
	_render()


func _build_tower(fid: String, slot_i: int) -> void:
	if _modal_open():
		return
	var fam := DataLoader.tower(fid)
	var cost := int(fam.get("cost", 0))
	var slot := slots[slot_i] as Dictionary
	if slot.get("tower") != null:
		log_msg("该塔位已被占用")
		return
	if gold < cost:
		log_msg("金币不足（需要 %d）" % cost)
		return
	gold -= cost
	var t := TOWER_SCENE.instantiate()
	towers_node.add_child(t)
	t.setup(self, fid, 1, cost, bool(slot.get("high")))
	t.position = slot.get("pos") as Vector2
	t.slot_index = slot_i
	slot["tower"] = t
	log_msg("建造 %s（-%d金）" % [_tw_name(t), cost])
	_render()


func _move_tower_to(t: Tower, slot_i: int) -> void:
	var src := slots[t.slot_index] as Dictionary
	var dst := slots[slot_i] as Dictionary
	src["tower"] = null
	dst["tower"] = t
	t.slot_index = slot_i
	t.position = dst.get("pos") as Vector2
	log_msg("%s 移动到新塔位" % _tw_name(t))


func _sell_value(t: Tower) -> int:
	return int(float(t.cost_paid) * (float(DataLoader.rules.get("sellRatio", 0.7)) + get_mod("sell", 0.0)))


func _on_sell() -> void:
	if sel_tower == null or not is_instance_valid(sel_tower):
		return
	var v := _sell_value(sel_tower)
	gold += v
	var slot := slots[sel_tower.slot_index] as Dictionary
	slot["tower"] = null
	sel_tower.queue_free()
	sel_tower = null
	log_msg("卖出塔 +%d金" % v)
	_render()


func _on_mode() -> void:
	if sel_tower == null:
		return
	sel_tower.target_mode = (sel_tower.target_mode + 1) % MODE_NAMES.size()
	log_msg("%s 目标改为「%s」" % [_tw_name(sel_tower), MODE_NAMES[sel_tower.target_mode]])
	_render()


## 同族同等级 → 合并升星；升到 3 级随机进化
func _try_merge(a: Tower, b: Tower) -> bool:
	if a.family_id != b.family_id or a.level != b.level or a.level >= 3:
		return false
	b.cost_paid += a.cost_paid
	b.level += 1
	var kept := randf() < get_mod("merge_keep", 0.0)
	if kept:
		log_msg("♻️ 合成师生效！材料塔保留")
	else:
		var src := slots[a.slot_index] as Dictionary
		src["tower"] = null
		a.queue_free()
	if b.level >= 3:
		FxBank.play(fx_air, "fx_merge", b.position, {"scale": 0.8})
		b.evolve()
		FxBank.play(fx_air, "fx_evolve", b.position)
	else:
		b._refresh_visual()
		FxBank.play(fx_air, "fx_merge", b.position)
		log_msg("⬆️ 合成 %s → Lv%d" % [_tw_name(b), b.level])
	sel_tower = b
	_render()
	return true


# ---------- 波次循环 ----------

func _on_next_wave() -> void:
	if state != "planning" or _modal_open():
		return
	wave_idx += 1
	state = "wave"
	spawn_queue = _build_queue(wave_idx)
	wave_clock = 0.0
	log_msg("⚔️ 第 %d/%d 波来袭！" % [wave_idx, DataLoader.waves.size()])
	_render()


func _build_queue(w: int) -> Array:
	var wdef: Dictionary = DataLoader.waves[w - 1] if w <= DataLoader.waves.size() else {}
	var q: Array = []
	var mul := float(wdef.get("hpMul", 1.0))
	var t := 0.0
	for g in wdef.get("groups", []):
		var gd := g as Dictionary
		t += float(gd.get("delay", 1.5))
		var count := int(gd.get("count", 1))
		var interval := float(gd.get("interval", 0.8))
		for i in count:
			q.append({"t": t, "id": String(gd.get("enemy")), "mul": mul})
			t += interval
	return q


## 松手结算（轮询左键状态，避免松手事件被 UI 吞掉）：合成 → 换位 → 移动 → 弹回
func _finish_drag(pos: Vector2) -> void:
	var t := drag_tower
	drag_tower = null
	if t == null or not is_instance_valid(t):
		_render()
		return
	t.z_index = 0
	if not drag_started:
		_render()
		return  # 纯点击：保持选中看信息
	var other: Variant = _tower_at(pos, t)
	if other != null:
		var o := other as Tower
		if _try_merge(t, o):
			_render()
			return
		_swap_towers(t, o)
		_render()
		return
	var si := _slot_at(pos)
	if si >= 0 and si != t.slot_index:
		var slot := slots[si] as Dictionary
		if slot.get("tower") != null:
			_swap_towers(t, slot.get("tower") as Tower)
		else:
			_move_tower_to(t, si)
	elif si != t.slot_index:
		var src := slots[t.slot_index] as Dictionary
		t.position = src.get("pos") as Vector2
		log_msg("无效位置，%s 弹回原位" % _tw_name(t))
	_render()


func _swap_towers(a: Tower, b: Tower) -> void:
	var sa := slots[a.slot_index] as Dictionary
	var sb := slots[b.slot_index] as Dictionary
	sa["tower"] = b
	sb["tower"] = a
	var ai := a.slot_index
	a.slot_index = b.slot_index
	b.slot_index = ai
	a.position = sb.get("pos") as Vector2
	b.position = sa.get("pos") as Vector2
	log_msg("🔄 交换 %s 与 %s 的位置" % [_tw_name(a), _tw_name(b)])


func _process(delta: float) -> void:
	game_time += delta
	if drag_tower != null and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_drag(get_global_mouse_position())
	if state == "wave":
		wave_clock += delta
		while spawn_queue.size() > 0 and float((spawn_queue[0] as Dictionary)["t"]) <= wave_clock:
			var s := spawn_queue.pop_front() as Dictionary
			var p: Array = DataLoader.rules.get("path", [])
			var start := Vector2(float(p[0][0]), float(p[0][1]))
			spawn_enemy_at(String(s["id"]), start, float(s["mul"]))
		if spawn_queue.is_empty() and alive_enemies().is_empty():
			_end_wave()
	if autotest:
		_autotest_step()


func _end_wave() -> void:
	state = "planning"
	var bonus := int(DataLoader.rules.get("waveBonusBase", 25)) \
		+ int(DataLoader.rules.get("waveBonusPerWave", 5)) * wave_idx \
		+ int(get_mod("wave_gold", 0.0))
	var rate := float(DataLoader.rules.get("interestRate", 0.10)) + get_mod("interest_rate", 0.0)
	var cap := float(DataLoader.rules.get("interestCap", 8)) + get_mod("interest_cap", 0.0)
	var interest := int(minf(float(gold) * rate, cap))
	gold += bonus + interest
	log_msg("✅ 第 %d 波守住！奖励 %d 金 + 利息 %d 金" % [wave_idx, bonus, interest])
	_save_progress()
	if autotest:
		print("AUTOTEST wave=%d gold=%d lives=%d" % [wave_idx, gold, lives])
	if wave_idx >= DataLoader.waves.size():
		_victory()
		return
	_show_upgrade()


# ---------- 波间三选一 ----------

func _show_upgrade() -> void:
	state = "upgrade"
	upgrade_choices = _roll_upgrades()
	for c in choice_box.get_children():
		c.queue_free()
	for u in upgrade_choices:
		var ud := u as Dictionary
		var b := Button.new()
		b.custom_minimum_size = Vector2(240, 150)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "%s %s [%s]\n%s" % [ud.get("emoji", ""), ud.get("name", ""), RARITY_NAMES.get(ud.get("rarity", ""), ""), ud.get("desc", "")]
		b.pressed.connect(_on_upgrade_chosen.bind(ud))
		choice_box.add_child(b)
	upgrade_overlay.visible = true
	_render()


func _roll_upgrades() -> Array:
	var picked: Array = []
	var pool := DataLoader.upgrades.duplicate()
	while picked.size() < 3 and pool.size() > 0:
		var total := 0.0
		for u in pool:
			total += float(RARITY_WEIGHTS.get(String((u as Dictionary).get("rarity", "common")), 60.0))
		var roll := randf() * total
		var chosen: Dictionary = {}
		for u in pool:
			roll -= float(RARITY_WEIGHTS.get(String((u as Dictionary).get("rarity", "common")), 60.0))
			if roll <= 0.0:
				chosen = u as Dictionary
				break
		if chosen.is_empty():
			chosen = pool[0] as Dictionary
		picked.append(chosen)
		pool.erase(chosen)
	return picked


func _on_upgrade_chosen(u: Dictionary) -> void:
	var key := String(u.get("mod", ""))
	var amount := float(u.get("amount", 0.0))
	if key == "gold":
		gold += int(amount)
	elif key == "lives":
		lives += int(amount)
	else:
		mods[key] = get_mod(key, 0.0) + amount
	log_msg("获得强化：%s %s" % [u.get("emoji", ""), u.get("name", "")])
	upgrade_overlay.visible = false
	state = "planning"
	_save_progress()
	_refresh_preview()
	_render()


# ---------- 胜负 ----------

func on_enemy_leaked(e: Enemy) -> void:
	lives -= e.lives_cost
	log_msg("💥 %s 冲进城堡！城堡耐久 -%d" % [e.display_name, e.lives_cost])
	_castle_hit_fx(e.lives_cost)
	if lives <= 0 and state != "over":
		_game_over("城堡耐久耗尽")
	else:
		_render()


## 城堡被打：爆炸 + 震屏 + 飘伤害数字 + 红光
func _castle_hit_fx(cost: int) -> void:
	var c: Array = DataLoader.rules.get("castle", [1200, 600])
	var cpos := Vector2(float(c[0]), float(c[1]))
	FxBank.play(fx_air, "aoe_fire", cpos, {"scale": 0.45})
	_shake()
	path_view.flash(cpos + Vector2(-34, -24), cpos + Vector2(34, 24), Color(1.0, 0.3, 0.3, 0.9))
	var l := Label.new()
	l.text = "💥 -%d" % cost
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	l.position = cpos + Vector2(-50, -80)
	add_child(l)
	var tw: Tween = create_tween()
	tw.tween_property(l, "position:y", l.position.y - 44.0, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


## 全屏轻震：城堡受击/失败时的打击感
func _shake(strength := 5.0) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(strength, -strength * 0.6), 0.05)
	tw.tween_property(self, "position", Vector2(-strength, strength * 0.4), 0.05)
	tw.tween_property(self, "position", Vector2.ZERO, 0.06)


func on_enemy_died(e: Enemy) -> void:
	var gain := int(round(float(e.bounty) * (1.0 + get_mod("bounty", 0.0))))
	gold += gain
	log_msg("☠️ 击杀 %s +%d金" % [e.display_name, gain])
	var def := DataLoader.enemy(e.id)
	var split := def.get("split", {}) as Dictionary
	if not split.is_empty():
		for i in int(split.get("count", 2)):
			var off := Vector2(randf_range(-20, 20), randf_range(-20, 20))
			spawn_enemy_at(String(split.get("into", "slimelet")), e.position + off, e.spawn_mul)
	if e.poison_spread_dps > 0.0:
		for x in alive_enemies():
			var en := x as Enemy
			if en.position.distance_to(e.position) <= 80.0:
				en.apply_poison(e.poison_spread_dps, 3.0, false)
	var buff := String(def.get("deathBuff", ""))
	if buff != "":
		for x in alive_enemies():
			var en := x as Enemy
			if en.id == buff:
				en.speed_buff *= 1.5
				log_msg("👑 暗影国王陨落，%s 狂化加速！" % en.display_name)
	_render()


func _victory() -> void:
	state = "over"
	_delete_save(active_slot)  # 通关 = 清当前档
	var c: Array = DataLoader.rules.get("castle", [1200, 600])
	FxBank.play(fx_air, "fx_evolve", Vector2(float(c[0]), float(c[1])), {"scale": 1.5})
	end_label.text = "🎉 王国守住了！\n15 波全部击退，剩余耐久 %d" % lives
	end_overlay.visible = true
	_render()


func _game_over(reason: String) -> void:
	state = "over"
	var c: Array = DataLoader.rules.get("castle", [1200, 600])
	FxBank.play(fx_air, "rx_overload", Vector2(float(c[0]), float(c[1])), {"scale": 1.5})
	_shake(8.0)
	end_label.text = "💀 王国陷落……\n止步第 %d/%d 波" % [wave_idx, DataLoader.waves.size()]
	end_overlay.visible = true
	_render()


# ---------- 自动化冒烟测试：--autotest 时全速跑完整局 ----------

func _autotest_step() -> void:
	if state == "over":
		print("AUTOTEST_RESULT wave=%d lives=%d gold=%d" % [wave_idx, lives, gold])
		get_tree().quit()
		return
	if state == "upgrade":
		if upgrade_choices.size() > 0:
			_on_upgrade_chosen(upgrade_choices[0] as Dictionary)
		return
	if state != "planning":
		return
	# 合成：任意同族同级
	for a in towers_node.get_children():
		var ta := a as Tower
		if ta.level >= 3:
			continue
		for b in towers_node.get_children():
			var tb := b as Tower
			if tb != ta and tb.family_id == ta.family_id and tb.level == ta.level:
				_try_merge(ta, tb)
				return
	# 建塔：轮换各族覆盖元素/反应/AOE 通路，买得起才建
	if towers_node.get_child_count() < slots.size():
		var order: Array = ["arrow", "frost", "thunder", "flame", "bomb", "venom"]
		var start := towers_node.get_child_count()
		for k in order.size():
			var fid := String(order[(start + k) % order.size()])
			var fam := DataLoader.tower(fid)
			if gold >= int(fam.get("cost", 0)):
				for i in slots.size():
					if (slots[i] as Dictionary).get("tower") == null:
						_build_tower(fid, i)
						return
	# 没有可执行动作（格位已满/买不起）→ 下一波
	_on_next_wave()


# ---------- 存档：3 个档位，每波结束自动 checkpoint ----------

func _slot_path(n: int) -> String:
	if test_mode:
		return "user://save_test.json"  # 自动测试专用档，保护真实存档
	return "user://save_%d.json" % n


func _save_progress() -> void:
	var towers_data: Array = []
	for t in towers_node.get_children():
		var tw := t as Tower
		towers_data.append({
			"family": tw.family_id, "level": tw.level, "branch": tw.branch_id,
			"slot": tw.slot_index, "paid": tw.cost_paid,
		})
	var data := {"wave": wave_idx, "gold": gold, "lives": lives, "mods": mods, "towers": towers_data}
	var f := FileAccess.open(_slot_path(active_slot), FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败：%s" % _slot_path(active_slot))
		return
	f.store_string(JSON.stringify(data))
	f.close()


func _load_save_file(n: int) -> Dictionary:
	var path := _slot_path(n)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		return data
	return {}


func _any_slot_save() -> bool:
	for i in [1, 2, 3]:
		if FileAccess.file_exists(_slot_path(i)):
			return true
	return false


func _delete_save(n: int) -> void:
	var path := _slot_path(n)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 旧版单档 save.json → 档位 1（一次性迁移；目标写死真实档位名，测试模式也不受影响）
func _migrate_legacy_save() -> void:
	var old := "user://save.json"
	var dst := "user://save_1.json"
	if FileAccess.file_exists(old) and not FileAccess.file_exists(dst):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(old), ProjectSettings.globalize_path(dst))


func _slot_summary(i: int) -> String:
	var d := _load_save_file(i)
	if d.is_empty():
		return ""
	return "第%d波 · 💰%d · 🏰%d · %d塔" % [
		int(d.get("wave", 0)), int(d.get("gold", 0)), int(d.get("lives", 0)),
		(d.get("towers", []) as Array).size(),
	]


func _show_save_panel() -> void:
	for c in slot_box.get_children():
		c.queue_free()
	for i in [1, 2, 3]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := Label.new()
		info.custom_minimum_size = Vector2(430, 40)
		info.add_theme_font_size_override("font_size", 17)
		var enter_btn := Button.new()
		enter_btn.custom_minimum_size = Vector2(90, 40)
		var del_btn := Button.new()
		del_btn.custom_minimum_size = Vector2(90, 40)
		del_btn.add_theme_font_size_override("font_size", 14)
		var d := _load_save_file(i)
		if d.is_empty():
			info.text = "档位 %d：空" % i
			enter_btn.text = "新档"
			enter_btn.pressed.connect(_on_pick_slot.bind(i, true))
			del_btn.visible = false
		else:
			info.text = "档位 %d：%s" % [i, _slot_summary(i)]
			enter_btn.text = "进入"
			enter_btn.pressed.connect(_on_pick_slot.bind(i, false))
			del_btn.text = "删除"
			del_btn.pressed.connect(_on_delete_slot.bind(i, del_btn))
		row.add_child(info)
		row.add_child(enter_btn)
		row.add_child(del_btn)
		slot_box.add_child(row)
	save_overlay.visible = true
	_render()  # 弹窗打开的同时禁用背景按钮


## fresh=true：从空档位开新局；false：读档续玩
func _on_pick_slot(i: int, fresh: bool) -> void:
	active_slot = i
	save_overlay.visible = false
	if fresh:
		log_msg("档位 %d 已就绪，祝武运昌隆！" % i)
		_render()
		return
	var data := _load_save_file(i)
	if data.is_empty():
		return
	gold = int(data.get("gold", 0))
	lives = int(data.get("lives", 20))
	var m: Variant = data.get("mods", {})
	if m is Dictionary:
		mods = m
	wave_idx = int(data.get("wave", 0))
	for t in towers_node.get_children():
		t.queue_free()
	for s in slots:
		(s as Dictionary)["tower"] = null
	for rec in data.get("towers", []):
		var rd := rec as Dictionary
		var si := int(rd.get("slot", -1))
		if si < 0 or si >= slots.size():
			continue
		var slot := slots[si] as Dictionary
		if slot.get("tower") != null:
			continue
		var t := TOWER_SCENE.instantiate()
		towers_node.add_child(t)
		t.setup(self, String(rd.get("family", "arrow")), int(rd.get("level", 1)), int(rd.get("paid", 0)), bool(slot.get("high")))
		t.position = slot.get("pos") as Vector2
		t.slot_index = si
		if String(rd.get("branch", "")) != "":
			t.apply_branch(String(rd.get("branch")))
		slot["tower"] = t
	log_msg("📂 已载入档位 %d：从第 %d 波继续" % [i, wave_idx + 1])
	_refresh_preview()
	_render()


func _on_delete_slot(i: int, btn: Button) -> void:
	if not bool(btn.get_meta("armed", false)):
		btn.set_meta("armed", true)
		btn.text = "确认删除?"
		return
	_delete_save(i)
	_show_save_panel()


func _on_new_game() -> void:
	for i in [1, 2, 3]:
		if not FileAccess.file_exists(_slot_path(i)):
			active_slot = i
			save_overlay.visible = false
			log_msg("新开局将存入档位 %d" % i)
			_render()
			return
	log_msg("三个档位都满了，请先删除一个")


func _testload() -> void:
	# --testload：冒烟测试 存档→读档→重建 布局链路
	gold = 500
	lives = 17
	mods = {"dmg": 0.1}
	wave_idx = 2
	_build_tower("arrow", 0)
	_save_progress()
	var data := _load_save_file(active_slot)
	print("TESTLOAD saved wave=", data.get("wave"), " gold=", data.get("gold"), " towers=", (data.get("towers", []) as Array).size())
	_on_pick_slot(active_slot, false)
	print("TESTLOAD loaded wave=", wave_idx, " gold=", gold, " lives=", lives, " mods=", mods, " towers=", towers_node.get_child_count(), " slot0_occupied=", (slots[0] as Dictionary).get("tower") != null)
	get_tree().quit()
	# 没事可做 → 下一波
	_on_next_wave()
