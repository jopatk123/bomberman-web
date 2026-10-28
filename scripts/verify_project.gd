extends SceneTree
## 无界面冒烟：确认自动加载和脚本能载入，然后退出。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[verify] Godot ", Engine.get_version_info())
	print("[verify] 主场景：", ProjectSettings.get_setting("application/run/main_scene"))
	var tree_root := root
	var net_node := tree_root.get_node_or_null("Net")
	var gs := tree_root.get_node_or_null("GameState")
	if net_node == null or gs == null:
		push_error("[verify] 失败：缺少自动加载（Net/GameState）")
		quit(1)
		return
	print("[verify] 网络通过，peer_id=", net_node.get_peer_id(), " 权威=", net_node.is_authority())
	print("[verify] GameState 通过，最多人数=", gs.MAX_PLAYERS)

	var paths := [
		"res://scripts/lobby.gd",
		"res://scripts/game_root.gd",
		"res://autoload/Net.gd",
		"res://autoload/GameState.gd",
		"res://scenes/lobby.tscn",
		"res://scenes/game.tscn",
	]
	for path in paths:
		var res = load(path)
		if res == null:
			push_error("[verify] 失败：无法加载 %s" % path)
			quit(1)
			return
		# load 可能返回一份没编译过的 GDScript，这里再看一眼。
		if path.ends_with(".gd") and res is GDScript:
			var src: GDScript = res
			if src.get_instance_base_type() == "" and src.get_script_method_list().is_empty():
				# 空脚本也可能合法，真正编译靠后面重新加载。
				pass
		print("[verify] 已加载 ", path)

	var game_script: GDScript = load("res://scripts/game_root.gd")
	if game_script == null:
		push_error("[verify] 失败：game_root.gd 为空")
		quit(1)
		return
	# 用 PackedScene 实例化，逼它真正编译。
	var lobby_ps: PackedScene = load("res://scenes/lobby.tscn")
	var lobby := lobby_ps.instantiate()
	if lobby == null:
		push_error("[verify] 失败：大厅实例化失败")
		quit(1)
		return
	tree_root.add_child(lobby)
	await process_frame
	print("[verify] 大厅实例：", lobby.name)
	var bg := lobby.get_node_or_null("Bg")
	if bg == null or not (bg is TextureRect):
		push_error("[verify] 失败：大厅背景不是 TextureRect")
		quit(1)
		return
	var bg_tex: Texture2D = (bg as TextureRect).texture
	if bg_tex == null or bg_tex.get_width() != 960 or bg_tex.get_height() != 720:
		push_error("[verify] 失败：大厅背景缺失或不是 960x720")
		quit(1)
		return
	if (bg as TextureRect).stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		push_error("[verify] 失败：大厅背景拉伸不是保持比例铺满")
		quit(1)
		return
	if (bg as TextureRect).expand_mode != TextureRect.EXPAND_IGNORE_SIZE:
		push_error("[verify] 失败：大厅背景扩展不是忽略尺寸")
		quit(1)
		return
	var title := lobby.get_node_or_null("Center/Panel/Margin/Stack/Title")
	if title == null or str((title as Label).text) != "摸鱼炸弹人":
		push_error("[verify] 失败：大厅标题缺失")
		quit(1)
		return
	print("[verify] 大厅像素背景通过")
	lobby.queue_free()
	await process_frame

	var game_ps: PackedScene = load("res://scenes/game.tscn")
	var game := game_ps.instantiate()
	if game == null:
		push_error("[verify] 失败：对局实例化失败")
		quit(1)
		return
	tree_root.add_child(game)
	await process_frame
	if game.get("COLS") == null:
		push_error("[verify] 失败：game_root 脚本没挂上，或解析失败")
		quit(1)
		return
	print("[verify] 对局实例：", game.name, " 列=", game.COLS, " 行=", game.ROWS)
	game.queue_free()

	var tile_paths := [
		"res://assets/art/pixel/tiles/floor_a.png",
		"res://assets/art/pixel/tiles/floor_b.png",
		"res://assets/art/pixel/tiles/hard.png",
		"res://assets/art/pixel/tiles/soft.png",
	]
	for path in tile_paths:
		var tex = load(path)
		if tex == null or not (tex is Texture2D):
			push_error("[verify] 失败：无法加载 %s" % path)
			quit(1)
			return
		if (tex as Texture2D).get_width() != 48 or (tex as Texture2D).get_height() != 48:
			push_error("[verify] 失败：%s 不是 48x48" % path)
			quit(1)
			return
		print("[verify] 已加载 ", path)
	for grass_path in ["res://assets/art/pixel/tiles/floor_a.png", "res://assets/art/pixel/tiles/floor_b.png"]:
		var grass: Texture2D = load(grass_path)
		var gimg := grass.get_image()
		if gimg == null or not _looks_like_grass(gimg):
			push_error("[verify] 失败：%s 不像草地" % grass_path)
			quit(1)
			return
	var powerup_paths := [
		"res://assets/art/pixel/entities/powerup_bomb.png",
		"res://assets/art/pixel/entities/powerup_range.png",
		"res://assets/art/pixel/entities/powerup_speed.png",
		"res://assets/art/pixel/entities/powerup_kick.png",
		"res://assets/art/pixel/entities/powerup_pierce.png",
	]
	for path in powerup_paths:
		var tex = load(path)
		if tex == null or not (tex is Texture2D):
			push_error("[verify] 失败：无法加载 %s" % path)
			quit(1)
			return
		if (tex as Texture2D).get_width() != 48 or (tex as Texture2D).get_height() != 48:
			push_error("[verify] 失败：%s 不是 48x48" % path)
			quit(1)
			return
		print("[verify] 已加载 ", path)

	var host := Node2D.new()
	var map := Node2D.new()
	var ents := Node2D.new()
	var drops := Node2D.new()
	var fx := Node2D.new()
	host.add_child(map)
	host.add_child(ents)
	host.add_child(drops)
	host.add_child(fx)
	tree_root.add_child(host)
	var board := MatchBoard.new()
	board.bind(map, ents, drops, fx, 2, 2)
	var grid: Array = [
		[Arena.CELL_HARD, Arena.CELL_EMPTY],
		[Arena.CELL_SOFT, Arena.CELL_EMPTY],
	]
	board.draw_map(grid, host)
	await process_frame
	if map.get_child_count() != 4:
		push_error("[verify] 失败：应有 4 张地块精灵，实际 %d" % map.get_child_count())
		quit(1)
		return
	for child in map.get_children():
		if not (child is Sprite2D) or child is Polygon2D:
			push_error("[verify] 失败：地图格子不是 Sprite2D")
			quit(1)
			return
	var hard: Sprite2D = map.get_child(0)
	var floor_b: Sprite2D = map.get_child(1)
	var soft: Sprite2D = map.get_child(2)
	var floor_a: Sprite2D = map.get_child(3)
	if hard.texture != MatchBoard.TEX_HARD or soft.texture != MatchBoard.TEX_SOFT:
		push_error("[verify] 失败：硬墙或软墙贴图对不上")
		quit(1)
		return
	if floor_b.texture != MatchBoard.TEX_FLOOR_B or floor_a.texture != MatchBoard.TEX_FLOOR_A:
		push_error("[verify] 失败：空地棋盘格贴图对不上")
		quit(1)
		return
	if hard.centered or hard.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
		push_error("[verify] 失败：地块精灵不是左上角就近采样")
		quit(1)
		return
	if hard.position != Vector2.ZERO or floor_a.position != Vector2(48, 48):
		push_error("[verify] 失败：地块精灵位置不对")
		quit(1)
		return
	grid[1][0] = Arena.CELL_EMPTY
	var tiles_before: int = map.get_child_count()
	board.repaint_cells(grid, [Vector2i(0, 1)], host)
	var painted: Sprite2D = map.get_child(2)
	if map.get_child_count() != tiles_before or painted.texture != MatchBoard.TEX_FLOOR_B:
		push_error("[verify] 失败：软墙变空地时没有就地换成 floor_b")
		quit(1)
		return
	for child in map.get_children():
		if child is Polygon2D:
			push_error("[verify] 失败：地图上还留着色块")
			quit(1)
			return
	print("[verify] 像素地块通过")
	host.queue_free()
	print("[verify] 成功")
	quit(0)


func _looks_like_grass(img: Image) -> bool:
	var pts: Array[Vector2i] = [
		Vector2i(2, 2), Vector2i(40, 4), Vector2i(4, 40), Vector2i(44, 44),
	]
	var green := 0
	for p in pts:
		var c: Color = img.get_pixel(p.x, p.y)
		if c.a > 0.9 and c.g > 0.35 and c.g > c.r and c.g > c.b:
			green += 1
	return green >= 3
