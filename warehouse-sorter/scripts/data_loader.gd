class_name DataLoader
## data/ 下三张配置表的读取与缓存（数据驱动，改表即改玩法）。

const PARCELS_PATH := "res://data/parcels.json"
const WAVES_PATH := "res://data/waves.json"
const RULES_PATH := "res://data/game_rules.json"

static var parcels: Array = []
static var waves: Array = []
static var rules: Dictionary = {}
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	var p: Variant = load_json(PARCELS_PATH)
	var w: Variant = load_json(WAVES_PATH)
	var r: Variant = load_json(RULES_PATH)
	if p is Array:
		parcels = p
	if w is Array:
		waves = w
	if r is Dictionary:
		rules = r
	_loaded = true


static func load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataLoader: 无法打开 %s（错误码 %d）" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if data == null:
		push_error("DataLoader: JSON 解析失败 %s" % path)
	return data
