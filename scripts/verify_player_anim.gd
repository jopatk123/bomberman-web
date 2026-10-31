extends SceneTree
## 无界面：角色精灵表、AnimatedSprite2D、走路/静止切换与轻量动效。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var colors := ["blue", "red", "green", "yellow"]
	for c in colors:
		var path := "res://assets/art/watercolor/entities/anim/player_%s_sheet.png" % c
		var tex: Texture2D = load(path)
		if tex == null:
			push_error("[verify_player_anim] 失败：缺少 %s" % path)
			quit(1)
			return
		if tex.get_width() != 48 * 5 or tex.get_height() != 48:
			push_error("[verify_player_anim] 失败：%s 尺寸 %dx%d，期望 240x48" % [c, tex.get_width(), tex.get_height()])
			quit(1)
			return

	var gs = root.get_node("GameState")
	gs.players = {
		1: {"name": "蓝蛙", "color_idx": 0},
		2: {"name": "红浣", "color_idx": 1},
		3: {"name": "绿鸟", "color_idx": 2},
		4: {"name": "黄螈", "color_idx": 3},
	}
	gs.in_match = true

	var ps: PackedScene = load("res://scenes/game.tscn")
	var game = ps.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	if not game.player_nodes.has(1):
		push_error("[verify_player_anim] 失败：没有 1 号玩家")
		quit(1)
		return

	var pnode: Node2D = game.player_nodes[1]
	var body = pnode.get_node_or_null("Body")
	if body == null or not (body is AnimatedSprite2D):
		push_error("[verify_player_anim] 失败：Body 不是 AnimatedSprite2D")
		quit(1)
		return
	var anim: AnimatedSprite2D = body
	if anim.sprite_frames == null:
		push_error("[verify_player_anim] 失败：sprite_frames 为空")
		quit(1)
		return
	if not anim.sprite_frames.has_animation(&"idle") or not anim.sprite_frames.has_animation(&"walk"):
		push_error("[verify_player_anim] 失败：缺少 idle/walk 动画")
		quit(1)
		return
	if anim.sprite_frames.get_frame_count(&"walk") < 2:
		push_error("[verify_player_anim] 失败：walk 帧数不足")
		quit(1)
		return
	if anim.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
		push_error("[verify_player_anim] 失败：未使用 Linear 采样")
		quit(1)
		return

	# 静止：应播 idle
	if pnode.has_method("set_moving"):
		pnode.set_moving(false)
	await process_frame
	await process_frame
	if str(anim.animation) != "idle":
		push_error("[verify_player_anim] 失败：静止时应为 idle，实际 %s" % anim.animation)
		quit(1)
		return

	# 模拟格子移动：改 position，应由 _process 检测为在走
	var tile: int = int(game.TILE) if "TILE" in game else 48
	var cell: Vector2i = pnode.get_meta("cell")
	var next := cell + Vector2i(1, 0)
	pnode.position = Vector2(next.x * tile + tile * 0.5, next.y * tile + tile * 0.5)
	pnode.set_meta("cell", next)
	# 多等几帧让 _process 跑到
	for _i in 4:
		await process_frame
	if not pnode.is_moving_visual():
		push_error("[verify_player_anim] 失败：位置变化后未进入走路态")
		quit(1)
		return
	if str(anim.animation) != "walk":
		push_error("[verify_player_anim] 失败：走路时应为 walk，实际 %s" % anim.animation)
		quit(1)
		return
	if not anim.flip_h:
		# 向 +x 走不应 flip；再测向左
		pass
	else:
		push_error("[verify_player_anim] 失败：向右走不应 flip_h")
		quit(1)
		return

	# 向左走应 flip
	var left := next + Vector2i(-1, 0)
	pnode.position = Vector2(left.x * tile + tile * 0.5, left.y * tile + tile * 0.5)
	for _i in 4:
		await process_frame
	if not anim.flip_h:
		push_error("[verify_player_anim] 失败：向左走应 flip_h")
		quit(1)
		return

	# 轻量动效：scale/offset 在呼吸或 bob 下会偏离 1/0（允许极小误差）
	var scale_ok := absf(anim.scale.x - 1.0) > 0.001 or absf(anim.scale.y - 1.0) > 0.001 or absf(anim.offset.y) > 0.01
	if not scale_ok:
		# 可能刚好在相位零点，再等一会儿
		for _i in 10:
			await process_frame
		scale_ok = absf(anim.scale.x - 1.0) > 0.001 or absf(anim.scale.y - 1.0) > 0.001 or absf(anim.offset.y) > 0.01
	if not scale_ok:
		push_error("[verify_player_anim] 失败：轻量动效未改变 scale/offset")
		quit(1)
		return

	# 四色都能建出 Body
	for pid in [2, 3, 4]:
		if not game.player_nodes.has(pid):
			push_error("[verify_player_anim] 失败：缺少玩家 %d" % pid)
			quit(1)
			return
		var b = game.player_nodes[pid].get_node_or_null("Body")
		if b == null or not (b is AnimatedSprite2D):
			push_error("[verify_player_anim] 失败：玩家 %d Body 异常" % pid)
			quit(1)
			return

	print("[verify_player_anim] 通过")
	quit(0)
