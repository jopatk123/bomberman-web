extends SceneTree
## 无界面：爆炸和软墙碎裂贴图能载入；play_boom 会生成 Sprite2D 特效。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for n in [
		"blast_center.png", "blast_h.png", "blast_v.png",
		"soft_break_0.png", "soft_break_1.png", "soft_break_2.png",
		"sd_hazard_0.png", "sd_hazard_1.png", "sd_hazard_2.png",
		"airdrop_mark.png",
	]:
		var path := "res://assets/art/pixel/fx/%s" % n
		var tex: Texture2D = load(path)
		if tex == null or tex.get_width() != 48 or tex.get_height() != 48:
			push_error("[verify_fx] 失败：%s" % path)
			quit(1)
			return

	var gs = root.get_node("GameState")
	gs.players = {1: {"name": "测", "color_idx": 0}}
	gs.in_match = true
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	# 在玩家旁边放一块软墙，再把炸弹炸过去。
	var pid := 1
	var cell: Vector2i = game.player_nodes[pid].get_meta("cell")
	var soft := cell + Vector2i(1, 0)
	if soft.x >= game.COLS:
		soft = cell + Vector2i(-1, 0)
	game.grid[soft.y][soft.x] = game.Cell.SOFT
	game.player_stats[pid].move_cd = 0.0
	# 先把炸弹放在玩家脚下，再把人走开，炸弹才能留在起始格。
	game._try_place_bomb(pid)
	if game.bombs.is_empty():
		push_error("[verify_fx] 失败：没有炸弹")
		quit(1)
		return
	var bid := -1
	for k in game.bombs.keys():
		if int(game.bombs[k].get("owner", -1)) == pid and int(k) > bid:
			bid = int(k)
	if bid < 0:
		push_error("[verify_fx] 失败：真人的炸弹不见了")
		quit(1)
		return
	# 强制爆炸时让软墙落在射线上：把炸弹放到软墙旁边。
	game.bombs[bid].x = soft.x - 1 if soft.x > cell.x else soft.x + 1
	game.bombs[bid].y = soft.y
	game.bombs[bid].timer = 0.0
	# 炸弹那一格必须是空的，软墙还得是软墙。
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
		push_error("[verify_fx] 失败：爆炸后没有特效精灵")
		quit(1)
		return

	print("[verify_fx] 通过 精灵=%d" % sprites)
	quit(0)
