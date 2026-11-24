extends SceneTree
## 视觉验证：窗口模式进入战斗 → 摆塔 → 放第一波 + 塔边空降哥布林 → 截图 review/shot_main.png。
## 用法（必须非 headless，GL 才真的渲染）：
##   Godot_v4.3-stable_win64_console.exe --path . --script res://tools/shot.gd -- --shot
## 改了美术资产后先跑 `--headless --import` 刷新导入缓存再执行本脚本。

const OUT_PATH := "D:/ycharmProjects/game/realm-of-embers/review/shot_main.png"


func _initialize() -> void:
	change_scene_to_file.call_deferred("res://scenes/Main.tscn")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await create_timer(1.2).timeout
	var game: Node = current_scene
	if game == null:
		push_error("shot: 战斗场景未就绪")
		quit(1)
		return
	game._build_tower("arrow", 4)
	game._build_tower("thunder", 8)
	game._build_tower("frost", 6)
	game._on_next_wave()
	for i in 5:
		game.spawn_enemy_at("goblin", Vector2(300 + i * 16.0, 380), 1.0)
	await create_timer(2.2).timeout
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	var img := root.get_texture().get_image()
	img.save_png(OUT_PATH)
	print("SHOT_SAVED ", img.get_width(), "x", img.get_height())
	quit(0)
