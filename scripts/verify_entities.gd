extends SceneTree
## Headless: player/bomb pixel sprites load and attach under MatchBoard entities.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tex_names := [
		"player_blue.png", "player_red.png", "player_green.png", "player_yellow.png", "bomb.png",
	]
	for n in tex_names:
		var path := "res://assets/art/pixel/entities/%s" % n
		var tex: Texture2D = load(path)
		if tex == null:
			push_error("[verify_entities] FAIL: missing %s" % path)
			quit(1)
			return
		if tex.get_width() != 48 or tex.get_height() != 48:
			push_error("[verify_entities] FAIL: %s size %dx%d" % [n, tex.get_width(), tex.get_height()])
			quit(1)
			return

	var gs = root.get_node("GameState")
	gs.players = {
		1: {"name": "蓝", "color_idx": 0},
		2: {"name": "红", "color_idx": 1},
	}
	gs.in_match = true

	var ps: PackedScene = load("res://scenes/game.tscn")
	var game = ps.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	if not game.player_nodes.has(1):
		push_error("[verify_entities] FAIL: no player 1")
		quit(1)
		return
	var pnode: Node2D = game.player_nodes[1]
	var body := pnode.get_node_or_null("Body")
	if body == null or not (body is Sprite2D):
		push_error("[verify_entities] FAIL: player Body not Sprite2D")
		quit(1)
		return
	if (body as Sprite2D).texture == null:
		push_error("[verify_entities] FAIL: player texture null")
		quit(1)
		return

	game._try_place_bomb(1)
	await process_frame
	if game.bombs.is_empty():
		push_error("[verify_entities] FAIL: no bomb placed")
		quit(1)
		return
	var bid: int = int(game.bombs.keys()[0])
	var bnode: Node = game.entities.get_node_or_null("Bomb_%d" % bid)
	if bnode == null:
		bnode = _find_named(game, "Bomb_%d" % bid)
	if bnode == null:
		push_error("[verify_entities] FAIL: bomb node missing")
		quit(1)
		return
	var bbody := bnode.get_node_or_null("Body")
	if bbody == null or not (bbody is Sprite2D):
		push_error("[verify_entities] FAIL: bomb Body not Sprite2D")
		quit(1)
		return

	print("[verify_entities] OK")
	quit(0)


func _find_named(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for c in n.get_children():
		var f := _find_named(c, want)
		if f:
			return f
	return null
