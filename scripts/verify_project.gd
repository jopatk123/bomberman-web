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
	print("[verify] SUCCESS")
	quit(0)
