extends SceneTree
## Headless smoke: confirm autoloads + scripts load, then quit.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[verify] Godot ", Engine.get_version_info())
	print("[verify] Main scene: ", ProjectSettings.get_setting("application/run/main_scene"))
	var tree_root := root
	var net_node := tree_root.get_node_or_null("Net")
	var gs := tree_root.get_node_or_null("GameState")
	if net_node == null or gs == null:
		push_error("[verify] FAIL: autoloads missing (Net/GameState)")
		quit(1)
		return
	print("[verify] Net OK, peer_id=", net_node.get_peer_id(), " authority=", net_node.is_authority())
	print("[verify] GameState OK, max_players=", gs.MAX_PLAYERS)

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
			push_error("[verify] FAIL: cannot load %s" % path)
			quit(1)
			return
		# GDScript load may return a script that failed to compile — check
		if path.ends_with(".gd") and res is GDScript:
			var src: GDScript = res
			if src.get_instance_base_type() == "" and src.get_script_method_list().is_empty():
				# still might be valid empty; rely on reload
				pass
		print("[verify] loaded ", path)

	var game_script: GDScript = load("res://scripts/game_root.gd")
	if game_script == null:
		push_error("[verify] FAIL: game_root.gd null")
		quit(1)
		return
	# Force compile check by instantiating via PackedScene
	var lobby_ps: PackedScene = load("res://scenes/lobby.tscn")
	var lobby := lobby_ps.instantiate()
	if lobby == null:
		push_error("[verify] FAIL: lobby instantiate")
		quit(1)
		return
	tree_root.add_child(lobby)
	await process_frame
	print("[verify] lobby instance: ", lobby.name)
	var bg := lobby.get_node_or_null("Bg")
	if bg == null or not (bg is TextureRect):
		push_error("[verify] FAIL: lobby Bg is not a TextureRect")
		quit(1)
		return
	var bg_tex: Texture2D = (bg as TextureRect).texture
	if bg_tex == null or bg_tex.get_width() != 960 or bg_tex.get_height() != 720:
		push_error("[verify] FAIL: lobby background missing or not 960x720")
		quit(1)
		return
	if (bg as TextureRect).stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		push_error("[verify] FAIL: lobby background stretch is not keep-aspect covered")
		quit(1)
		return
	if (bg as TextureRect).expand_mode != TextureRect.EXPAND_IGNORE_SIZE:
		push_error("[verify] FAIL: lobby background expand is not ignore size")
		quit(1)
		return
	var title := lobby.get_node_or_null("Center/Panel/Margin/Stack/Title")
	if title == null or str((title as Label).text) != "摸鱼炸弹人":
		push_error("[verify] FAIL: lobby title missing")
		quit(1)
		return
	print("[verify] lobby pixel background OK")
	lobby.queue_free()
	await process_frame

	var game_ps: PackedScene = load("res://scenes/game.tscn")
	var game := game_ps.instantiate()
	if game == null:
		push_error("[verify] FAIL: game instantiate")
		quit(1)
		return
	tree_root.add_child(game)
	await process_frame
	if game.get("COLS") == null:
		push_error("[verify] FAIL: game_root script not attached / failed to parse")
		quit(1)
		return
	print("[verify] game instance: ", game.name, " cols=", game.COLS, " rows=", game.ROWS)
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
			push_error("[verify] FAIL: cannot load %s" % path)
			quit(1)
			return
		if (tex as Texture2D).get_width() != 48 or (tex as Texture2D).get_height() != 48:
			push_error("[verify] FAIL: %s is not 48x48" % path)
			quit(1)
			return
		print("[verify] loaded ", path)

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
		push_error("[verify] FAIL: expected 4 tile sprites, got %d" % map.get_child_count())
		quit(1)
		return
	for child in map.get_children():
		if not (child is Sprite2D) or child is Polygon2D:
			push_error("[verify] FAIL: map cell is not a Sprite2D")
			quit(1)
			return
	var hard: Sprite2D = map.get_child(0)
	var floor_b: Sprite2D = map.get_child(1)
	var soft: Sprite2D = map.get_child(2)
	var floor_a: Sprite2D = map.get_child(3)
	if hard.texture != MatchBoard.TEX_HARD or soft.texture != MatchBoard.TEX_SOFT:
		push_error("[verify] FAIL: hard/soft tile texture mismatch")
		quit(1)
		return
	if floor_b.texture != MatchBoard.TEX_FLOOR_B or floor_a.texture != MatchBoard.TEX_FLOOR_A:
		push_error("[verify] FAIL: empty floor checker mismatch")
		quit(1)
		return
	if hard.centered or hard.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
		push_error("[verify] FAIL: tile sprite is not top-left nearest")
		quit(1)
		return
	if hard.position != Vector2.ZERO or floor_a.position != Vector2(48, 48):
		push_error("[verify] FAIL: tile sprite position")
		quit(1)
		return
	grid[1][0] = Arena.CELL_EMPTY
	var tiles_before: int = map.get_child_count()
	board.repaint_cells(grid, [Vector2i(0, 1)], host)
	var painted: Sprite2D = map.get_child(2)
	if map.get_child_count() != tiles_before or painted.texture != MatchBoard.TEX_FLOOR_B:
		push_error("[verify] FAIL: soft→empty did not swap to floor_b in place")
		quit(1)
		return
	for child in map.get_children():
		if child is Polygon2D:
			push_error("[verify] FAIL: map still has a color polygon")
			quit(1)
			return
	print("[verify] pixel tiles OK")
	host.queue_free()
	print("[verify] SUCCESS")
	quit(0)
