extends SceneTree
## Headless: blast / soft-break textures load; play_boom spawns Sprite2D FX.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for n in [
		"blast_center.png", "blast_h.png", "blast_v.png",
		"soft_break_0.png", "soft_break_1.png", "soft_break_2.png",
	]:
		var path := "res://assets/art/pixel/fx/%s" % n
		var tex: Texture2D = load(path)
		if tex == null or tex.get_width() != 48 or tex.get_height() != 48:
			push_error("[verify_fx] FAIL: %s" % path)
			quit(1)
			return

	var gs = root.get_node("GameState")
	gs.players = {1: {"name": "测", "color_idx": 0}}
	gs.in_match = true
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	# Place a soft wall next to player and explode a bomb into it.
	var pid := 1
	var cell: Vector2i = game.player_nodes[pid].get_meta("cell")
	var soft := cell + Vector2i(1, 0)
	if soft.x >= game.COLS:
		soft = cell + Vector2i(-1, 0)
	game.grid[soft.y][soft.x] = game.Cell.SOFT
	game.player_stats[pid].move_cd = 0.0
	# Move player away so bomb can sit on start cell? Place bomb on player cell then move.
	game._try_place_bomb(pid)
	if game.bombs.is_empty():
		push_error("[verify_fx] FAIL: no bomb")
		quit(1)
		return
	var bid: int = int(game.bombs.keys()[0])
	# Force explode with soft in ray: set bomb next to soft
	game.bombs[bid].x = soft.x - 1 if soft.x > cell.x else soft.x + 1
	game.bombs[bid].y = soft.y
	game.bombs[bid].timer = 0.0
	# Ensure bomb cell empty and soft still soft
	var bx: int = int(game.bombs[bid].x)
	var by: int = int(game.bombs[bid].y)
	game.grid[by][bx] = game.Cell.EMPTY
	game.grid[soft.y][soft.x] = game.Cell.SOFT
	game._explode(bid)
	await process_frame
	await process_frame

	var fx: Node2D = game.fx_layer
	var sprites := 0
	for c in fx.get_children():
		if c is Sprite2D:
			sprites += 1
	if sprites < 1:
		push_error("[verify_fx] FAIL: no FX sprites after boom")
		quit(1)
		return

	print("[verify_fx] OK sprites=%d" % sprites)
	quit(0)
