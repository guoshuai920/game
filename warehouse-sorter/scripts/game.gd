extends Control
## 《爆仓分拣员》主循环：波次、生成、打包连击、特殊规则（易碎/生鲜/加急）、胜负判定。
## 全部数值来自 data/*.json，改表即改玩法。

const PARCEL_SCENE := preload("res://scenes/Parcel.tscn")
const TAG_NAMES := {
	"normal": "普通件",
	"fragile": "易碎件",
	"fresh": "生鲜件",
	"urgent": "加急件",
	"big": "大件",
}

@onready var belt: Belt = $Belt
@onready var grid: GameGrid = $Grid
@onready var score_label: Label = $HUD/ScoreLabel
@onready var wave_label: Label = $HUD/WaveLabel
@onready var target_label: Label = $HUD/TargetLabel
@onready var belt_label: Label = $BeltLabel
@onready var combo_label: Label = $ComboLabel
@onready var wave_banner: Label = $WaveBanner
@onready var overlay: Control = $Overlay
@onready var result_label: Label = $Overlay/ResultLabel
@onready var restart_button: Button = $Overlay/RestartButton

var score := 0
var wave_index := 0
var wave_def: Dictionary = {}
var spawn_timer := 0.0
var scan_timer := 0.0
var combo_timer := 0.0
var combo_count := 0
var ended := false


func _ready() -> void:
	DataLoader.load_all()
	belt.setup(int(DataLoader.rules.get("beltCapacity", 6)))
	grid.setup(
		int(DataLoader.rules.get("gridWidth", 6)),
		int(DataLoader.rules.get("gridHeight", 4)),
		Parcel.CELL
	)
	grid.parcel_placed.connect(_on_parcel_placed)
	restart_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	restart_button.focus_mode = Control.FOCUS_NONE
	overlay.visible = false
	start_wave(1)


func _process(delta: float) -> void:
	if ended:
		return
	# 1) 生成：到点出件；传送带已满 => 爆仓失败
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		if belt.is_full():
			_lose()
			return
		_spawn_parcel()
		spawn_timer = float(wave_def.get("spawnInterval", 2.0))
	# 2) 计时类包裹（fresh / urgent），只在背包内计时
	for p in grid.parcels():
		if p.timer_left >= 0.0:
			p.tick(delta)
			if p.timer_left <= 0.0:
				_fail_parcel(p, "超时" if p.tag() == "urgent" else "变质")
	# 3) 易碎件：每 0.5s 扫描一次相邻包裹数
	scan_timer += delta
	if scan_timer >= 0.5:
		_scan_fragile(scan_timer)
		scan_timer = 0.0
	# 4) 连击窗口
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo_count = 0
			combo_label.visible = false
	# 5) HUD 与波次推进
	_update_hud()
	if score >= int(wave_def.get("targetScore", 0)):
		if wave_index >= DataLoader.waves.size():
			_win()
		else:
			start_wave(wave_index + 1)


func start_wave(index: int) -> void:
	wave_index = index
	wave_def = DataLoader.waves[index - 1]
	spawn_timer = float(wave_def.get("spawnInterval", 2.0))
	_show_banner("第 %d 波" % index)


func _spawn_parcel() -> void:
	var def := _pick_def()
	if def.is_empty():
		return
	var p := PARCEL_SCENE.instantiate() as Parcel
	p.setup(def)
	belt.push_parcel(p)


func _pick_def() -> Dictionary:
	var tag := _pick_tag()
	var pool: Array = []
	for d in DataLoader.parcels:
		if String(d.get("tag", "")) == tag:
			pool.append(d)
	if pool.is_empty():
		for d in DataLoader.parcels:
			if String(d.get("tag", "")) == "normal":
				pool.append(d)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]


func _pick_tag() -> String:
	var weights: Dictionary = wave_def.get("weights", {})
	var total := 0
	for k in weights:
		total += int(weights[k])
	if total <= 0:
		return "normal"
	var r := randi() % total
	for k in weights:
		r -= int(weights[k])
		if r < 0:
			return String(k)
	return "normal"


func _on_parcel_placed(p) -> void:
	belt.remove_parcel(p)
	_check_packs()


func _check_packs() -> void:
	var match_count := int(DataLoader.rules.get("matchCount", 4))
	var tags: Array = []
	for p in grid.parcels():
		if not tags.has(p.tag()):
			tags.append(p.tag())
	for tag in tags:
		if grid.tag_area(String(tag)) >= match_count:
			_pack_tag(String(tag))


func _pack_tag(tag: String) -> void:
	var removed: Array = grid.tag_parcels(tag)
	var base := 0
	var center := Vector2.ZERO
	for p in removed:
		base += p.score_value()
		center += p.position + p.size * 0.5
		grid.remove_parcel(p)
		var tw := p.create_tween()
		tw.tween_property(p, "scale", Vector2(0.1, 0.1), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(p.queue_free)
	center /= maxf(1.0, float(removed.size()))
	# 连击：comboWindow 秒内再次打包则倍率递增
	if combo_timer > 0.0:
		combo_count += 1
	else:
		combo_count = 0
	var mult := 1.0 + float(DataLoader.rules.get("comboMultiplier", 0.2)) * combo_count
	combo_timer = float(DataLoader.rules.get("comboWindow", 3.0))
	var gain := int(round(base * mult))
	score += gain
	_float_text("打包 %s +%d" % [TAG_NAMES.get(tag, tag), gain], Color(0.5, 1.0, 0.65), center)
	if combo_count > 0:
		combo_label.text = "COMBO ×%d" % (combo_count + 1)
		combo_label.visible = true


func _scan_fragile(dt: float) -> void:
	for p in grid.parcels():
		if p.tag() != "fragile" or p.break_threshold <= 0:
			continue
		var n := grid.neighbor_parcels(p).size()
		if n >= p.break_threshold:
			p.break_timer += dt
			p.update_visual()
			if p.break_timer >= 3.0:
				_fail_parcel(p, "破损")
		elif p.break_timer > 0.0:
			p.break_timer = 0.0
			p.update_visual()


func _fail_parcel(p, reason: String) -> void:
	var penalty := int(DataLoader.rules.get("baseScoreFail", -50))
	score += penalty
	grid.remove_parcel(p)
	var pos: Vector2 = p.position + p.size * 0.5
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.25)
	tw.tween_callback(p.queue_free)
	_float_text("%s %d" % [reason, penalty], Color(1.0, 0.45, 0.45), pos)


func _float_text(text: String, color: Color, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.z_index = 10
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("outline_size", 6)
	l.position = pos - Vector2(70, 18)
	add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 48.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)


func _show_banner(text: String) -> void:
	wave_banner.text = text
	wave_banner.modulate.a = 0.0
	wave_banner.visible = true
	var tw := wave_banner.create_tween()
	tw.tween_property(wave_banner, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.2)
	tw.tween_property(wave_banner, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: wave_banner.visible = false)


func _update_hud() -> void:
	score_label.text = "分数 %d" % score
	wave_label.text = "第 %d/%d 波" % [wave_index, DataLoader.waves.size()]
	target_label.text = "目标 %d" % int(wave_def.get("targetScore", 0))
	var occ := belt.occupied()
	belt_label.text = "传送带 %d/%d" % [occ, belt.capacity]
	belt_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.4, 0.4) if occ >= belt.capacity - 1 else Color(0.85, 0.87, 0.92)
	)


func _win() -> void:
	_end("🎉 分拣完成！\n最终分数 %d" % score)


func _lose() -> void:
	_end("💥 传送带爆仓！\n最终分数 %d" % score)


func _end(title: String) -> void:
	if ended:
		return
	ended = true
	result_label.text = title
	overlay.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if ended and event is InputEventKey and event.is_pressed():
		var key := event as InputEventKey
		if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
			get_tree().reload_current_scene()
