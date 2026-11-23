extends Node
## 音效库（autoload：Sfx）：惰性加载 assets/sfx/*.wav，8 路播放池轮转，
## 随机微变调避免机关枪效应；ambient() 循环环境音；M 键静音（main.gd 接线）。

const DIR := "res://assets/sfx/"
const POOL_SIZE := 10
# 高频音效限流（毫秒）：多塔齐射/成片命中时防"音墙"，按名最小间隔
const MIN_INTERVAL := {
	"hit": 90, "hit_crit": 90, "coin": 70,
	"fire_arrow": 110, "fire_frost": 110, "fire_thunder": 110,
	"fire_flame": 110, "fire_bomb": 110, "fire_venom": 110,
	"enemy_die": 70,
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambient: AudioStreamPlayer = null
var muted := false
var _last_ms: Dictionary = {}


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)


func _stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var s := load(DIR + name + ".wav") as AudioStream
	_streams[name] = s
	return s


## 播放一次；volume_db 负值更轻，pitch_jitter 随机变调幅度
func play(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if muted:
		return
	var now := Time.get_ticks_msec()
	var min_ms := int(MIN_INTERVAL.get(name, 0))
	if min_ms > 0 and now - int(_last_ms.get(name, -100000)) < min_ms:
		return
	_last_ms[name] = now
	var s := _stream(name)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## 环境低鸣（无缝循环，音量很低）
func ambient() -> void:
	if _ambient != null:
		return
	var s := _stream("ambient") as AudioStreamWAV
	if s == null:
		return
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = s.data.size() / 2  # 16bit mono → 帧数
	_ambient = AudioStreamPlayer.new()
	_ambient.stream = s
	_ambient.volume_db = -14.0
	add_child(_ambient)
	_ambient.play()


func toggle_mute() -> bool:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	return muted
