extends Node
## 自动加载单例：读取 data/*.json，全局数据源。改表即改玩法。

var rules: Dictionary = {}
var towers: Array = []
var enemies: Array = []
var waves: Array = []
var reactions: Array = []
var upgrades: Array = []

var _tower_map: Dictionary = {}
var _enemy_map: Dictionary = {}


func _ready() -> void:
	rules = _load_json("res://data/rules.json")
	towers = _load_array("res://data/towers.json")
	enemies = _load_array("res://data/enemies.json")
	waves = _load_array("res://data/waves.json")
	reactions = _load_array("res://data/reactions.json")
	upgrades = _load_array("res://data/upgrades.json")
	for t in towers:
		_tower_map[String(t.get("id"))] = t
	for e in enemies:
		_enemy_map[String(e.get("id"))] = e


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法打开 %s（错误码 %d）" % [path, FileAccess.get_open_error()])
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data == null:
		push_error("JSON 解析失败 %s" % path)
		return {}
	return data


func _load_array(path: String) -> Array:
	var data: Variant = _load_json(path)
	if data is Array:
		return data
	return []


func tower(id: String) -> Dictionary:
	return _tower_map.get(id, {})


func enemy(id: String) -> Dictionary:
	return _enemy_map.get(id, {})


func level_def(id: String, lvl: int) -> Dictionary:
	var t := tower(id)
	var levels: Array = t.get("levels", [])
	if lvl >= 1 and lvl <= levels.size():
		return levels[lvl - 1] as Dictionary
	return {}


func branch_def(id: String, branch: String) -> Dictionary:
	var t := tower(id)
	for b in t.get("branches", []):
		if String((b as Dictionary).get("id")) == branch:
			return b as Dictionary
	return {}
