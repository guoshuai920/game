extends Control
## 《职场大逃杀》核心原型：卡牌战斗主循环。
## 精力=生命、压力=第二失败条、行动点=费用、工作量=敌人血量；卡牌/敌人/节点全部 JSON 驱动。

const CARDS_PATH := "res://data/cards.json"
const ENEMIES_PATH := "res://data/enemies.json"
const NODES_PATH := "res://data/nodes.json"

const START_HP := 80
const STRESS_MAX := 100
const ENERGY_PER_TURN := 3
const HAND_SIZE := 5
const NODE_HEAL := 8
const REWARD_NODES := [3, 6, 9]
const STARTER_DECK := {
	"moyu": 3, "coffee": 2, "shuaiguo": 2, "laqun": 2, "ppt": 1,
}

@onready var node_label: Label = $TopBar/NodeLabel
@onready var hp_label: Label = $TopBar/HpLabel
@onready var stress_label: Label = $TopBar/StressLabel
@onready var energy_label: Label = $TopBar/EnergyLabel
@onready var block_label: Label = $TopBar/BlockLabel
@onready var piles_label: Label = $TopBar/PilesLabel
@onready var enemy_name_label: Label = $EnemyPanel/EnemyName
@onready var enemy_hp_label: Label = $EnemyPanel/EnemyHp
@onready var enemy_intent_label: Label = $EnemyPanel/EnemyIntent
@onready var log_label: Label = $LogLabel
@onready var hand_box: HFlowContainer = $HandBox
@onready var end_turn_button: Button = $EndTurnButton
@onready var reward_overlay: Control = $RewardOverlay
@onready var reward_box: HBoxContainer = $RewardOverlay/RewardBox
@onready var end_overlay: Control = $EndOverlay
@onready var end_label: Label = $EndOverlay/EndLabel
@onready var restart_button: Button = $EndOverlay/RestartButton

var card_pool: Array = []
var enemies: Dictionary = {}
var nodes: Array = []
var total_nodes := 12

var node_idx := 1
var turn := 1
var hp := START_HP
var stress := 0
var energy := ENERGY_PER_TURN
var block := 0
var deck: Array = []
var hand: Array = []
var draw_pile: Array = []
var discard_pile: Array = []
var enemy: Dictionary = {}
var enemy_name := ""
var enemy_hp := 0
var enemy_max_hp := 0
var enemy_intents: Array = []
var ended := false
var pending_reward := false


func _ready() -> void:
	_load_data()
	end_turn_button.pressed.connect(_end_turn)
	restart_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	restart_button.focus_mode = Control.FOCUS_NONE
	_start_run()


# ---------- 数据 ----------

func _load_data() -> void:
	var cards: Variant = _load_json(CARDS_PATH)
	var foes: Variant = _load_json(ENEMIES_PATH)
	var ns: Variant = _load_json(NODES_PATH)
	if cards is Array:
		card_pool = cards
	if foes is Array:
		for f in foes:
			enemies[String(f.get("id"))] = f
	if ns is Array:
		nodes = ns
	if not nodes.is_empty():
		total_nodes = nodes.size()


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法打开 %s（错误码 %d）" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if data == null:
		push_error("JSON 解析失败 %s" % path)
	return data


func _card_by_id(id: String) -> Dictionary:
	for c in card_pool:
		if String(c.get("id")) == id:
			return c
	return {}


# ---------- 单局流程 ----------

func _start_run() -> void:
	node_idx = 1
	hp = START_HP
	stress = 0
	energy = ENERGY_PER_TURN
	block = 0
	deck = []
	for id in STARTER_DECK:
		for i in int(STARTER_DECK[id]):
			var card := _card_by_id(String(id))
			if not card.is_empty():
				deck.append(card)
	draw_pile = deck.duplicate()
	draw_pile.shuffle()
	discard_pile = []
	hand = []
	enemy = {}
	ended = false
	pending_reward = false
	_start_node(1)


func _start_node(idx: int) -> void:
	node_idx = idx
	var ndef: Dictionary = nodes[idx - 1] if idx <= nodes.size() else {}
	enemy = enemies.get(String(ndef.get("enemy", "")), {})
	enemy_name = String(enemy.get("name", "？？？"))
	if ndef.has("suffix"):
		enemy_name += "·" + String(ndef["suffix"])
	var hp_mul := float(ndef.get("hpMul", 1.0))
	var mul := float(ndef.get("mul", 1.0))
	enemy_max_hp = int(round(float(enemy.get("hp", 1)) * hp_mul))
	enemy_hp = enemy_max_hp
	enemy_intents = []
	for it in enemy.get("intents", []):
		var scaled: Dictionary = (it as Dictionary).duplicate()
		scaled["value"] = int(round(float(scaled.get("value", 0)) * mul))
		enemy_intents.append(scaled)
	turn = 1
	_log("进入节点 %d/%d：%s（工作量 %d）" % [node_idx, total_nodes, enemy_name, enemy_hp])
	_start_turn()


func _end_node() -> void:
	_log("完成「%s」！" % enemy_name)
	if node_idx >= total_nodes:
		_victory()
		return
	hp = mini(START_HP, hp + NODE_HEAL)
	stress = maxi(0, stress - NODE_HEAL)
	if REWARD_NODES.has(node_idx):
		pending_reward = true
		_show_reward()
		return
	_start_node(node_idx + 1)


func _victory() -> void:
	ended = true
	end_label.text = "🎉 升职成功！\n你熬过了 %d 个节点，成为职场赢家" % total_nodes
	end_overlay.visible = true
	_render()


func _game_over(reason: String) -> void:
	ended = true
	end_label.text = "💀 失败：%s\n止步于节点 %d/%d" % [reason, node_idx, total_nodes]
	end_overlay.visible = true
	_render()


# ---------- 回合流程 ----------

func _start_turn() -> void:
	energy = ENERGY_PER_TURN
	block = 0
	hand = []
	_draw_cards(HAND_SIZE)
	_render()


func _play_card(index: int) -> void:
	if ended or pending_reward or index >= hand.size():
		return
	var card: Dictionary = hand[index]
	var cost := int(card.get("cost", 0))
	if energy < cost:
		return
	energy -= cost
	hand.remove_at(index)
	for e in card.get("effects", []):
		_apply_effect(e as Dictionary)
	discard_pile.append(card)
	_log("打出《%s》" % String(card.get("name", "")))
	if _check_fail():
		return
	if enemy_hp <= 0:
		_end_node()
		return
	_render()


func _end_turn() -> void:
	if ended or pending_reward:
		return
	if energy > 0 and not hand.is_empty():
		_log("回合结束：弃掉 %d 张手牌（还剩 %d 行动点没用）" % [hand.size(), energy])
	for card in hand:
		discard_pile.append(card)
	hand = []
	_enemy_turn()
	if _check_fail():
		return
	turn += 1
	_start_turn()


func _enemy_turn() -> void:
	var intent := _current_intent()
	if intent.is_empty():
		return
	var v := int(intent.get("value", 0))
	match String(intent.get("type", "")):
		"damage":
			# 护盾只挡精力伤害，不挡压力
			var dmg := maxi(0, v - block)
			hp = maxi(0, hp - dmg)
			block = 0
			_log("%s 造成 %d 点精力伤害（护盾抵消 %d）" % [enemy_name, dmg, v - dmg])
		"stress":
			stress = clampi(stress + v, 0, STRESS_MAX)
			_log("%s：压力 +%d" % [enemy_name, v])
	_render()


func _current_intent() -> Dictionary:
	if enemy_intents.is_empty():
		return {}
	return enemy_intents[(turn - 1) % enemy_intents.size()]


func _intent_text(intent: Dictionary) -> String:
	if intent.is_empty():
		return "无"
	var v := int(intent.get("value", 0))
	if String(intent.get("type", "")) == "damage":
		return "造成 %d 点精力伤害" % v
	return "压力 +%d" % v


# ---------- 卡牌效果 ----------

func _apply_effect(e: Dictionary) -> void:
	var v := int(e.get("value", 0))
	match String(e.get("type", "")):
		"progress":
			enemy_hp = maxi(0, enemy_hp - v)
		"block":
			block += v
		"heal":
			hp = mini(START_HP, hp + v)
		"stress":
			stress = clampi(stress + v, 0, STRESS_MAX)
		"draw":
			_draw_cards(v)
		"energy":
			energy += v


func _draw_cards(n: int) -> void:
	for i in n:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				return
			draw_pile = discard_pile.duplicate()
			draw_pile.shuffle()
			discard_pile = []
		hand.append(draw_pile.pop_back())


func _check_fail() -> bool:
	if hp <= 0:
		_game_over("精力耗尽，倒在工位上…")
		return true
	if stress >= STRESS_MAX:
		_game_over("压力爆表，提桶跑路…")
		return true
	return false


# ---------- 奖励三选一 ----------

func _show_reward() -> void:
	for c in reward_box.get_children():
		c.queue_free()
	var pool: Array = card_pool.duplicate()
	pool.shuffle()
	for card in pool.slice(0, 3):
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 130)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "%s（%d 行动点）\n%s" % [String(card.get("name", "")), int(card.get("cost", 0)), String(card.get("desc", ""))]
		b.pressed.connect(_on_reward_chosen.bind(card))
		reward_box.add_child(b)
	reward_overlay.visible = true
	_render()


func _on_reward_chosen(card: Dictionary) -> void:
	deck.append(card)
	draw_pile.append(card)
	pending_reward = false
	reward_overlay.visible = false
	_log("获得新卡《%s》，加入牌组" % String(card.get("name", "")))
	_start_node(node_idx + 1)


# ---------- 渲染 ----------

func _render() -> void:
	node_label.text = "节点 %d/%d" % [node_idx, total_nodes]
	hp_label.text = "精力 %d/%d" % [hp, START_HP]
	stress_label.text = "压力 %d/%d" % [stress, STRESS_MAX]
	energy_label.text = "行动点 %d" % energy
	block_label.text = "护盾 %d" % block
	piles_label.text = "牌库 %d · 弃牌 %d" % [draw_pile.size(), discard_pile.size()]
	hp_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45) if hp <= 20 else Color(0.9, 0.92, 0.95))
	stress_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5) if stress >= 70 else Color(0.9, 0.92, 0.95))
	if enemy.is_empty():
		enemy_name_label.text = ""
		enemy_hp_label.text = ""
		enemy_intent_label.text = ""
	else:
		enemy_name_label.text = "🧑‍💼 %s" % enemy_name
		enemy_hp_label.text = "工作量 %d/%d" % [enemy_hp, enemy_max_hp]
		enemy_intent_label.text = "意图：%s" % _intent_text(_current_intent())
	_render_hand()
	end_turn_button.disabled = ended or pending_reward


func _render_hand() -> void:
	for c in hand_box.get_children():
		c.queue_free()
	for i in hand.size():
		var card: Dictionary = hand[i]
		var cost := int(card.get("cost", 0))
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 120)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "%s（%d）\n%s" % [String(card.get("name", "")), cost, String(card.get("desc", ""))]
		b.disabled = ended or pending_reward or energy < cost
		if not ended and not pending_reward and energy < cost:
			b.text += "\n⚡ 行动点不足"
		b.pressed.connect(_play_card.bind(i))
		hand_box.add_child(b)


func _log(text: String) -> void:
	log_label.text = text
	print(text)


func _unhandled_input(event: InputEvent) -> void:
	if ended and event is InputEventKey and event.is_pressed():
		var key := event as InputEventKey
		if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
			get_tree().reload_current_scene()
