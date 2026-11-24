extends CPUParticles2D
## 全程氛围粒子："王国余烬"。mode=fall 余烬飘落（顶部）；mode=rise 火星升腾（底部）。
## 纹理运行时生成（2×2 白块），零素材依赖。

@export var mode := "fall"


func _ready() -> void:
	# 减弱动效模式下不开氛围粒子（设置在菜单里已先于本节点应用）
	if FxBank.reduced_motion:
		emitting = false
		return
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(img)
	# 用户反馈"满屏星星过于花哨"：整体调到低密度低亮度，只留一点余烬氛围
	amount = 10
	lifetime = 12.0
	local_coords = false
	scale_amount_min = 0.5
	scale_amount_max = 1.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	if mode == "fall":
		# 余烬：橙→灰，缓慢飘落，微微斜
		position = Vector2(640, -30)
		emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emission_rect_extents = Vector2(700, 6)
		direction = Vector2(0.18, 1.0)
		spread = 14.0
		gravity = Vector2(0, 6)
		initial_velocity_min = 16.0
		initial_velocity_max = 40.0
		grad.colors = PackedColorArray([
			Color(1.0, 0.55, 0.25, 0.0),
			Color(1.0, 0.62, 0.3, 0.3),
			Color(0.55, 0.5, 0.48, 0.0),
		])
	else:
		# 火星：底部升起，稀疏
		position = Vector2(640, 660)
		amount = 6
		emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emission_rect_extents = Vector2(640, 10)
		direction = Vector2(-0.1, -1.0)
		spread = 18.0
		gravity = Vector2(0, -4)
		initial_velocity_min = 10.0
		initial_velocity_max = 26.0
		scale_amount_max = 0.8
		grad.colors = PackedColorArray([
			Color(1.0, 0.4, 0.15, 0.0),
			Color(1.0, 0.75, 0.35, 0.32),
			Color(0.9, 0.35, 0.1, 0.0),
		])
	color_ramp = grad
	emitting = true


func _process(_delta: float) -> void:
	# 跟随"减弱动效"开关实时启停
	var should := not FxBank.reduced_motion
	if emitting != should:
		emitting = should
