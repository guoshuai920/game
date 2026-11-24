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
@onready var tw_info: Label = $SelPanel/TwInfo
@onready var sell_button: Button = $SelPanel/SellButton
@onready var mode_button: Button = $SelPanel/ModeButton
@onready var motion_button: Button = $TopBar/MotionButton
@onready var next_wave_button: Button = $NextWaveButton
@onready var restart_run_button: Button = $TopBar/RestartRunButton
@onready var quit_button: Button = $TopBar/QuitButton
@onready var speed_button: Button = $TopBar/SpeedButton
@onready var pause_button: Button = $TopBar/PauseButton
@onready var tips_label: Label = $TipsLabel
@onready var tips_skip: Button = $TipsSkip
@onready var pause_overlay: Control = $PauseOverlay
@onready var pause_resume: Button = $PauseOverlay/Box/ResumeButton
@onready var pause_settings_btn: Button = $PauseOverlay/Box/SettingsButton
@onready var pause_menu_btn: Button = $PauseOverlay/Box/MenuButton
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
var _boss_shown := {}  # 本波已演出过出场的 Boss id
var _bestiary := {}  # 已遇敌人图鉴（user://bestiary.json）

# ---------- 主动技能（KR 式：免费+冷却+点地释放；解锁/升级走三选一） ----------

const SKILLS := {
	"skill_meteor": {"name": "陨星术", "icon": "☄️", "cd": 12.0},
	"skill_slow": {"name": "时滞", "icon": "🌀", "cd": 15.0},
	"skill_militia": {"name": "民兵", "icon": "🛡️", "cd": 10.0},
}
var skill_cd := {}  # id -> 剩余冷却秒
var targeting := ""  # 待点地释放的技能 id
var skill_buttons := {}
var skill_bar: HBoxContainer


func _ready() -> void:
	autotest = OS.get_cmdline_user_args().has("--autotest")
	test_mode = autotest or OS.get_cmdline_user_args().has("--testload") \
		or OS.get_cmdline_user_args().has("--skilltest") \
		or OS.get_cmdline_user_args().has("--shot")
	gold = int(DataLoader.rules.get("startGold", 220))
	lives = int(DataLoader.rules.get("lives", 20))
	# 开局保底：自带陨星术 Lv1（三选一的 skill_meteor 牌可继续升级）
	# 存档/测试档在后续加载 mods 时会整体覆盖本值
	mods["skill_meteor"] = 1
	for s in DataLoader.rules.get("slots", []):
		var high: bool = (s as Array).size() > 2 and bool((s as Array)[2])
		slots.append({"pos": Vector2(float(s[0]), float(s[1])), "high": high, "tower": null})
	SettingsPanel.apply_saved()
	next_wave_button.pressed.connect(_on_next_wave)
	next_wave_button.text = "开始"
	motion_button.pressed.connect(_on_toggle_motion)
	motion_button.text = "动效:全开"
	speed_button.pressed.connect(_on_speed)
	pause_button.pressed.connect(_on_pause)
	pause_resume.pressed.connect(_on_resume)
	pause_settings_btn.pressed.connect(func() -> void: _pause_settings.open())
	pause_menu_btn.pressed.connect(_back_to_menu)
	tips_skip.pressed.connect(_tutorial_finish)
	new_game_button.pressed.connect(_on_new_game)
	restart_run_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	quit_button.pressed.connect(_back_to_menu)
	sell_button.pressed.connect(_on_sell)
	mode_button.pressed.connect(_on_mode)
	restart_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	restart_button.focus_mode = Control.FOCUS_NONE
	_build_shop()
	_build_skills()
	_load_bestiary()
	_migrate_legacy_save()
	_refresh_preview()
	_render()
	log_msg("建立防线！点下方选塔，再点发光格位放置；拖同类同星合成升星（M 键静音）")
	Sfx.ambient()
	_pause_settings = SettingsPanel.new()
	add_child(_pause_settings)
	# 新冒险：静默选第一个空档；老玩家：弹存档面板
	if not test_mode:
		if GameMenu.start_fresh:
			GameMenu.start_fresh = false
			for i in [1, 2, 3]:
				if not FileAccess.file_exists(_slot_path(i)):
					active_slot = i
					log_msg("新开局存入档位 %d" % i)
					break
			if active_slot == 0:
				_show_save_panel()
		elif _any_slot_save():
			_show_save_panel()
		_tutorial_start()
	if autotest:
		Engine.time_scale = 10.0
		log_msg("[自动测试] 引擎加速 10x")
		_autotest_step()
	if OS.get_cmdline_user_args().has("--testload"):
		call_deferred("_testload")
	if OS.get_cmdline_user_args().has("--skilltest"):
		call_deferred("_skilltest")


# ---------- 商店与渲染 ----------

func _build_shop() -> void:
	for fam in DataLoader.towers:
		var f := fam as Dictionary
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 62)
		b.text = ""
		b.tooltip_text = String(f.get("desc", ""))
		b.add_theme_font_size_override("font_size", 16)
		# 像素图标（塔精灵第一帧），左侧立绘 + 右侧名称/价格
		var icon := TextureRect.new()
		icon.texture = UnitsBank.frame_texture("tower_" + String(f.get("id")))
		icon.custom_minimum_size = Vector2(46, 54)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(5, 4)
		icon.size = Vector2(46, 54)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		var lb := Label.new()
		lb.text = "%s\n%d 金" % [String(f.get("name", "")), int(f.get("cost", 0))]
		lb.position = Vector2(56, 8)
		lb.size = Vector2(90, 46)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.add_theme_font_size_override("font_size", 15)
		lb.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
		b.add_child(lb)
		b.pressed.connect(_on_shop_click.bind(String(f.get("id"))))
		shop_bar.add_child(b)
		shop_buttons[String(f.get("id"))] = b


func get_mod(key: String, dflt: float) -> float:
	return float(mods.get(key, dflt))


## 减弱动效开关：关震屏/开波转场/顿帧（保留特效与音效本身）
func _on_toggle_motion() -> void:
	FxBank.reduced_motion = not FxBank.reduced_motion
	motion_button.text = "动效:减弱" if FxBank.reduced_motion else "动效:全开"
	log_msg("动效已%s（震屏/转场/顿帧）" % ("减弱" if FxBank.reduced_motion else "全开"))


# ---------- 速度 / 暂停 / 回菜单 ----------

const SPEED_STEPS := [1.0, 2.0, 3.0]
var speed_idx := 0
var _pause_settings: SettingsPanel


func _on_speed() -> void:
	if autotest:
		return
	speed_idx = (speed_idx + 1) % SPEED_STEPS.size()
	Engine.time_scale = SPEED_STEPS[speed_idx]
	speed_button.text = "%dx" % int(SPEED_STEPS[speed_idx])
	log_msg("游戏速度 %dx" % int(SPEED_STEPS[speed_idx]))


func _on_pause() -> void:
	if state == "over" or get_tree().paused or _modal_open():
		return
	get_tree().paused = true
	pause_overlay.visible = true


func _on_resume() -> void:
	get_tree().paused = false
	pause_overlay.visible = false


func _back_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Menu.tscn")


## 早期召唤奖励（KR 式）：按剩余未出怪数折算金币
func _early_call_bonus() -> int:
	return spawn_queue.size() * int(DataLoader.rules.get("earlyCallGoldPer", 2))


func _early_call() -> void:
	if state != "wave" or spawn_queue.is_empty() or wave_idx >= DataLoader.waves.size():
		return
	var bonus := _early_call_bonus()
	gold += bonus
	Sfx.play("coin", -3.0)
	# 追加下一波出怪队列：时间顺延到当前队列末尾 + 1.2s 预备
	var max_t := 0.0
	for s in spawn_queue:
		max_t = maxf(max_t, float((s as Dictionary)["t"]))
	for s in _build_queue(wave_idx + 1):
		var sd := s as Dictionary
		sd["t"] = float(sd["t"]) + max_t + 1.2
		spawn_queue.append(sd)
	wave_idx += 1
	_boss_shown = {}
	log_msg("⏩ 提前召唤第 %d 波！奖励 %d 金" % [wave_idx, bonus])
	_refresh_preview()
	_render()


## 提前召唤后 waves 用尽保护：末波不再奖励
# ---------- 新手引导（事件驱动 6 步，可跳过，完成后不再出现） ----------

const TUT_PATH := "user://seen_tutorial.txt"
const TUT_STEPS := [
	"① 点击下方商店，选一座塔（先从便宜的弩塔练手）",
	"② 点击发光的 ⊕ 石板格位放置（金环高台射程更远）",
	"③ 拖一座塔到同类同星塔上 → 合成升星",
	"④ 点「开始」放第一波；右上 ☄️ 陨星术点它再点战场释放，⏩ 可提前召唤赚金币",
	"⑤ 挺住！波末有金币利息——攒钱也是一种防御",
	"⑥ 战后三选一强化决定流派；顶栏可调速/暂停/动效",
]
var tut_step := -1


func _tutorial_start() -> void:
	if test_mode or FileAccess.file_exists(TUT_PATH):
		return
	tut_step = 0
	_tut_show()


func _tut_show() -> void:
	if tut_step < 0 or tut_step >= TUT_STEPS.size():
		return
	tips_label.text = TUT_STEPS[tut_step]
	tips_label.visible = true
	tips_skip.visible = true


func _tutorial_next() -> void:
	tut_step += 1
	if tut_step >= TUT_STEPS.size():
		_tutorial_finish()
	else:
		_tut_show()


func _tutorial_finish() -> void:
	tut_step = -1
	tips_label.visible = false
	tips_skip.visible = false
	var f := FileAccess.open(TUT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("ok")
		f.close()


func log_msg(text: String) -> void:
	log_label.text = text
	print(text)


# ---------- 主动技能 ----------

func _build_skills() -> void:
	skill_bar = HBoxContainer.new()
	skill_bar.anchor_left = 1.0
	skill_bar.anchor_right = 1.0
	skill_bar.offset_left = -350
	skill_bar.offset_top = 52
	skill_bar.offset_right = -16
	skill_bar.offset_bottom = 104
	skill_bar.alignment = BoxContainer.ALIGNMENT_END
	skill_bar.add_theme_constant_override("separation", 8)
	add_child(skill_bar)
	for id in SKILLS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(104, 48)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_on_skill_pressed.bind(id))
		b.visible = false
		skill_bar.add_child(b)
		skill_buttons[id] = b


func _skill_unlocked(id: String) -> bool:
	return get_mod(id, 0.0) > 0.0


func _on_skill_pressed(id: String) -> void:
	if _skill_cd_left(id) > 0.0:
		log_msg("%s 冷却中（%.0fs）" % [SKILLS[id]["name"], _skill_cd_left(id)])
		return
	if id == "skill_slow":
		_cast_skill(id, Vector2.ZERO)  # 全场技能无需点地
	else:
		targeting = id
		log_msg("点击战场释放【%s】（ESC 取消）" % SKILLS[id]["name"])


func _skill_cd_left(id: String) -> float:
	return float(skill_cd.get(id, 0.0))


func _cast_skill(id: String, pos: Vector2) -> void:
	if not _skill_unlocked(id) or _skill_cd_left(id) > 0.0:
		return
	var lv := int(get_mod(id, 0.0))
	skill_cd[id] = float(SKILLS[id]["cd"])
	match id:
		"skill_meteor":
			var dmg := 40.0 + 25.0 * float(lv - 1)
			for e in alive_enemies():
				var en := e as Enemy
				if en.position.distance_to(pos) <= 70.0:
					en.take_damage(dmg, "fire")
					en.apply_burn(6.0 + 2.0 * lv, 2.0)
			FxBank.play(fx_ground, "aoe_fire", pos, {"scale": 0.85, "priority": true})
			Sfx.play("explode", -1.0)
			_shake(2.5)
			log_msg("☄️ 陨星术命中！")
		"skill_slow":
			var dur := 3.0 + 0.5 * float(lv - 1)
			for e in alive_enemies():
				(e as Enemy).apply_slow(0.6, dur)
			if not FxBank.reduced_motion:
				var tw := create_tween()
				modulate = Color(0.72, 0.85, 1.0)
				tw.tween_property(self, "modulate", Color.WHITE, 0.4)
			Sfx.play("rx_steam", -1.0)
			log_msg("🌀 时滞领域展开！")
		"skill_militia":
			var hp := 60.0 + 30.0 * float(lv - 1)
			var m := Militia.new()
			m.setup(self, hp, 18.0, 10.0)
			m.position = _snap_to_path(pos)
			add_child(m)
			FxBank.play(fx_ground, "fx_summon", m.position, {"scale": 0.5, "speed": 1.8})
			Sfx.play("build", -3.0)
			log_msg("🛡️ 民兵就位！")


## 民兵落点吸附：40px 内的路径线段投影点自动吸附
func _snap_to_path(pos: Vector2) -> Vector2:
	var best := pos
	var best_d := 40.0
	var p: Array = DataLoader.rules.get("path", [])
	if p.size() >= 2:
		for i in p.size() - 1:
			var a := Vector2(float(p[i][0]), float(p[i][1]))
			var b := Vector2(float(p[i + 1][0]), float(p[i + 1][1]))
			var c := Geometry2D.get_closest_point_to_segment(pos, a, b)
			var d := pos.distance_to(c)
			if d < best_d:
				best_d = d
				best = c
	return best


func _load_bestiary() -> void:
	if FileAccess.file_exists("user://bestiary.json"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://bestiary.json"))
		if data is Dictionary:
			_bestiary = data


func _save_bestiary() -> void:
	var f := FileAccess.open("user://bestiary.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_bestiary))
		f.close()


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
	var def := DataLoader.enemy(id)
	if bool(def.get("boss", false)) and not _boss_shown.has(id):
		_boss_shown[id] = true
		_boss_intro(String(def.get("name", id)), pos)
	# 图鉴首见：弹提示条（测试模式静默）
	if not test_mode and not _bestiary.has(id):
		_bestiary[id] = 1
		_save_bestiary()
		_new_enemy_toast(def)


## 新敌人首见提示条
func _new_enemy_toast(def: Dictionary) -> void:
	var l := Label.new()
	l.text = "新敌人 %s %s： %s" % [def.get("emoji", "👹"), def.get("name", "???"), def.get("desc", "")]
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02, 0.92))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(140, 118)
	l.size = Vector2(1000, 32)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


## Boss 出场演出：压暗 + 招唤光柱 + 名称横幅 + 震屏（非阻塞，约 1.4 秒）
func _boss_intro(boss_name: String, pos: Vector2) -> void:
	FxBank.play(fx_air, "fx_summon", pos, {"scale": 2.4})
	FxBank.play(fx_air, "rx_overload", pos, {"scale": 1.6})
	Sfx.play("boss_intro", -1.0)
	_shake(7.0)
	var dim := ColorRect.new()
	dim.color = Color(0.5, 0.05, 0.05, 0.0)
	dim.size = Vector2(1280, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var banner := Label.new()
	banner.text = "⚠ BOSS 出场 · %s" % boss_name
	banner.add_theme_font_size_override("font_size", 44)
	banner.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	banner.add_theme_constant_override("outline_size", 10)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.position = Vector2(140, 240)
	banner.size = Vector2(1000, 70)
	banner.pivot_offset = Vector2(500, 35)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	banner.scale = Vector2(0.3, 0.3)
	banner.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(dim, "color:a", 0.28, 0.18)
	tw.tween_property(banner, "modulate:a", 1.0, 0.18)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.9)
	tw.chain().tween_property(dim, "color:a", 0.0, 0.3)
	tw.parallel().tween_property(banner, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(func() -> void:
		dim.queue_free()
		banner.queue_free()
	)


## 暴击金色飘字
func _crit_float(pos: Vector2, dmg: int) -> void:
	var l := Label.new()
	l.text = "暴击 %d!" % dmg
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	l.add_theme_color_override("font_outline_color", Color(0.35, 0.2, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.position = pos + Vector2(randf_range(-30, -10), -46)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 20
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 44.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)


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
	tw_info.visible = show_sel
	next_wave_button.disabled = modal or (state != "planning" and (state != "wave" or spawn_queue.is_empty()))
	if state == "wave":
		next_wave_button.text = "⏩ 提前召唤 +%d金" % _early_call_bonus()
	else:
		next_wave_button.text = "开始第 %d 波" % (wave_idx + 1)
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
	# 技能按钮状态
	for id in skill_buttons:
		var sb := skill_buttons[id] as Button
		var unlocked := _skill_unlocked(id)
		sb.visible = unlocked and not modal
		if not unlocked:
			continue
		var cd_left := _skill_cd_left(id)
		var sd: Dictionary = SKILLS[id]
		if cd_left > 0.0:
			sb.text = "%s %s\n%.0fs" % [sd["icon"], sd["name"], cd_left]
			sb.disabled = true
		else:
			sb.text = "%s %s\n就绪" % [sd["icon"], sd["name"]]
			sb.disabled = state == "over"
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
		# ESC：取消技能瞄准 / 取消拖拽 / 取消选塔（桌面快捷键，触屏用取消按钮）
		if targeting != "":
			targeting = ""
			log_msg("已取消技能释放")
			return
		_cancel_drag()
		shop_sel = ""
		sel_tower = null
		_render()
		return
	if event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_M:
		var m := Sfx.toggle_mute()
		log_msg("声音已%s" % ("关闭" if m else "开启"))
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
	# 技能瞄准优先：点地释放
	if targeting != "":
		var t := targeting
		targeting = ""
		_cast_skill(t, pos)
		return
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
	# 属性进选中面板（信息层级：决策数据在面板，日志只放事件流）
	tw_info.visible = true
	tw_info.text = "%s Lv%d★\n伤%d 速%.1f 程%d%s" % [
		_tw_name(t), t.level, int(t.stat("dmg")), t.stat("rate"), int(t.stat("range")),
		"\n高台+程" if t.is_high else "",
	]
	log_msg("拖拽：同类同星→合成 / 空位→移动 / 有塔→交换")


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
	Sfx.play("ui_click", -4.0)
	if tut_step == 0 and fid != "":
		_tutorial_next()
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
	FxBank.play(fx_ground, "fx_merge", t.position, {"scale": 0.6, "speed": 2.0})
	FxBank.play(fx_air, "death_poof", t.position, {"scale": 0.8})
	Sfx.play("build", -2.0)
	if tut_step == 1:
		_tutorial_next()
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
	var at: Vector2 = sel_tower.position
	gold += v
	var slot := slots[sel_tower.slot_index] as Dictionary
	slot["tower"] = null
	sel_tower.queue_free()
	sel_tower = null
	FxBank.play(fx_air, "death_poof", at, {"scale": 0.7})
	Sfx.play("sell", -3.0)
	_gold_float(at, v)
	log_msg("卖出塔 +%d金" % v)
	_render()


## 金币飘字（卖出/奖励通用）
func _gold_float(pos: Vector2, amount: int) -> void:
	var l := Label.new()
	l.text = "+%d 金" % amount
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	l.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.position = pos + Vector2(-30, -60)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 20
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 36.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)


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
		Sfx.play("evolve", -1.0)
	else:
		b._refresh_visual()
		FxBank.play(fx_air, "fx_merge", b.position)
		Sfx.play("merge", -3.0)
		log_msg("⬆️ 合成 %s → Lv%d" % [_tw_name(b), b.level])
	sel_tower = b
	if tut_step == 2:
		_tutorial_next()
	_render()
	return true


# ---------- 波次循环 ----------

func _on_next_wave() -> void:
	# 波内点按钮 = 提前召唤下一波（KR 式奖励）
	if state == "wave":
		_early_call()
		return
	if state != "planning" or _modal_open():
		return
	wave_idx += 1
	state = "wave"
	spawn_queue = _build_queue(wave_idx)
	wave_clock = 0.0
	_boss_shown = {}
	# 开波全屏转场：像素溶解扫过战场（减弱动效时跳过）
	if not FxBank.reduced_motion:
		FxBank.play(fx_air, "fx_screen", Vector2(640, 360), {"z": 5, "priority": true})
	Sfx.play("wave_start", -2.0)
	if tut_step == 3:
		_tutorial_next()
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
	# 技能冷却走秒（受加速影响，符合直觉）
	for id in skill_cd:
		skill_cd[id] = maxf(0.0, float(skill_cd[id]) - delta)
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
	Sfx.play("wave_clear", -3.0)
	if tut_step == 4:
		_tutorial_next()
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
	if tut_step == 5:
		_tutorial_finish()
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
	Sfx.play("castle_hit", 0.0)
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
	if FxBank.reduced_motion:
		return
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(strength, -strength * 0.6), 0.05)
	tw.tween_property(self, "position", Vector2(-strength, strength * 0.4), 0.05)
	tw.tween_property(self, "position", Vector2.ZERO, 0.06)


## 顿帧（hit-stop）：暴击/Boss 命中的重量感。带 0.25s 全局冷却防叠；
## 自动测试（time_scale 10）与减弱动效模式下跳过。
var _stop_until_ms := 0

func request_hit_stop(strong: bool) -> void:
	if FxBank.reduced_motion:
		return
	var now := Time.get_ticks_msec()  # 真实时钟，不受 time_scale 影响
	if now < _stop_until_ms:
		return
	_stop_until_ms = now + 250
	var prev := Engine.time_scale
	Engine.time_scale = 0.08 if strong else 0.2
	var t := get_tree().create_timer(0.06 if strong else 0.04, true, false, true)
	t.timeout.connect(func() -> void: Engine.time_scale = prev)


func on_enemy_died(e: Enemy) -> void:
	var gain := int(round(float(e.bounty) * (1.0 + get_mod("bounty", 0.0))))
	gold += gain
	Sfx.play("coin", -6.0)
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
	Sfx.play("victory", 0.0)
	end_label.text = "🎉 王国守住了！\n15 波全部击退，剩余耐久 %d" % lives
	end_overlay.visible = true
	_render()


func _game_over(reason: String) -> void:
	state = "over"
	var c: Array = DataLoader.rules.get("castle", [1200, 600])
	FxBank.play(fx_air, "rx_overload", Vector2(float(c[0]), float(c[1])), {"scale": 1.5})
	Sfx.play("defeat", 0.0)
	_shake(8.0)
	end_label.text = "💀 王国陷落……\n止步第 %d/%d 波" % [wave_idx, DataLoader.waves.size()]
	end_overlay.visible = true
	_render()


# ---------- 技能/阶段/提前召唤 专项测试：--skilltest ----------

var _st_checks := 0
var _st_fails := 0


func _st(chk: bool, name: String) -> void:
	_st_checks += 1
	if not chk:
		_st_fails += 1
		print("SKILLTEST FAIL: %s" % name)


func _st_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _st_wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _st_find(id: String) -> Enemy:
	for e in alive_enemies():
		var en := e as Enemy
		if en.id == id:
			return en
	return null


func _skilltest() -> void:
	# 解锁三技能
	mods["skill_meteor"] = 1
	mods["skill_slow"] = 1
	mods["skill_militia"] = 1
	_st(_skill_unlocked("skill_meteor") and _skill_unlocked("skill_slow") and _skill_unlocked("skill_militia"), "解锁检测")

	# 陨星：伤害+点燃+冷却
	var p := Vector2(250, 150)
	spawn_enemy_at("shield", p, 1.0)
	var shield := _st_find("shield") as Enemy
	_st(shield != null, "盾卫生成")
	var hp0 := shield.hp
	_cast_skill("skill_meteor", p + Vector2(6, 0))
	_st(shield.hp < hp0, "陨星伤害")
	_st(shield.burn_timer > 0.0, "陨星点燃")
	_st(_skill_cd_left("skill_meteor") > 0.0, "陨星冷却")

	# 时滞
	_cast_skill("skill_slow", Vector2.ZERO)
	_st(shield.slow_timer > 0.0, "时滞减速")

	# 民兵：生成 → 纠缠 → 消散释放
	_cast_skill("skill_militia", p + Vector2(28, 0))
	var mili: Militia = null
	for c in get_children():
		if c is Militia:
			mili = c
	_st(mili != null, "民兵生成")
	spawn_enemy_at("orc", p + Vector2(55, 0), 1.0)
	await _st_wait(0.9)
	var orc := _st_find("orc") as Enemy
	_st(orc != null, "兽人生成")
	if orc != null and mili != null:
		_st(orc.position.distance_to(mili.position) <= 34.0, "兽人被阻停在纠缠圈")
		_st(orc.hold_by == mili, "兽人被纠缠")
	_st(mili.hp < mili.max_hp, "民兵承伤")
	# 民兵被打死 → 释放纠缠
	mili.hp = 0.01
	mili.life = 99.0
	await _st_wait(0.3)
	_st(not is_instance_valid(mili) or not mili.alive, "民兵阵亡")
	_st(not is_instance_valid(shield) or shield.hold_by == null, "盾卫获释")
	_st(not is_instance_valid(orc) or orc.hold_by == null, "兽人获释")

	# 点地释放流程：瞄准 → 点击 → 冷却
	skill_cd["skill_meteor"] = 0.0
	_on_skill_pressed("skill_meteor")
	_st(targeting == "skill_meteor", "进入瞄准")
	_handle_click(Vector2(600, 300))
	_st(targeting == "" and _skill_cd_left("skill_meteor") > 0.0, "点地释放")

	# 提前召唤：金币奖励 + 队列并入 + 波号推进
	gold += 100
	var g0 := gold
	wave_idx = 1
	state = "wave"
	spawn_queue = _build_queue(1)
	_early_call()
	_st(wave_idx == 2, "提前召唤推进波号")
	_st(gold > g0, "提前召唤奖励")
	_st(spawn_queue.size() > 0, "两波队列合并")

	# Boss 阶段：石像鬼增甲 / 暗影国王召唤
	var gar_armor := float(DataLoader.enemy("gargoyle").armor)
	spawn_enemy_at("gargoyle", Vector2(500, 300), 1.0)
	var gar := _st_find("gargoyle") as Enemy
	gar.hp = gar.max_hp * 0.5
	await _st_wait(0.3)
	_st(gar.armor > gar_armor, "石像鬼增甲阶段")
	var n0 := alive_enemies().size()
	spawn_enemy_at("shadowking", Vector2(700, 320), 1.0)
	var sk := _st_find("shadowking") as Enemy
	sk.hp = sk.max_hp * 0.4
	await _st_wait(0.4)
	_st(alive_enemies().size() >= n0 + 2, "暗影国王召唤座狼")
	_st(_bestiary.size() > 0 or test_mode, "图鉴记录")

	print("SKILLTEST_RESULT checks=%d fails=%d" % [_st_checks, _st_fails])
	get_tree().quit()


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
		# 老档迁移：一个技能都没有的旧档补发陨星术 Lv1（与新档开局保底对齐）
		var has_skill := false
		for sid in SKILLS:
			if get_mod(sid, 0.0) > 0.0:
				has_skill = true
				break
		if not has_skill:
			mods["skill_meteor"] = 1
			log_msg("📋 老档补发开援助：☄️ 陨星术 Lv1 已就绪")
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
