extends SceneTree
## 无界面：角色和炸弹像素贴图能载入，并挂到 MatchBoard 的实体层下。


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
			push_error("[verify_entities] 失败：缺少 %s" % path)
			quit(1)
			return
		if tex.get_width() != 48 or tex.get_height() != 48:
			push_error("[verify_entities] 失败：%s 尺寸 %dx%d" % [n, tex.get_width(), tex.get_height()])
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
		push_error("[verify_entities] 失败：没有 1 号玩家")
		quit(1)
		return
	var pnode: Node2D = game.player_nodes[1]
	var body := pnode.get_node_or_null("Body")
	var ok_body := body is Sprite2D or body is AnimatedSprite2D
	if body == null or not ok_body:
		push_error("[verify_entities] 失败：玩家 Body 不是 Sprite2D/AnimatedSprite2D")
		quit(1)
		return
	if body is Sprite2D and (body as Sprite2D).texture == null:
		push_error("[verify_entities] 失败：玩家贴图为空")
		quit(1)
		return
	if body is AnimatedSprite2D and (body as AnimatedSprite2D).sprite_frames == null:
		push_error("[verify_entities] 失败：玩家 sprite_frames 为空")
		quit(1)
		return

	game._try_place_bomb(1)
	await process_frame
	if game.bombs.is_empty():
		push_error("[verify_entities] 失败：没有放下炸弹")
		quit(1)
		return
	var bid: int = int(game.bombs.keys()[0])
	var bnode: Node = game.entities.get_node_or_null("Bomb_%d" % bid)
	if bnode == null:
		bnode = _find_named(game, "Bomb_%d" % bid)
	if bnode == null:
		push_error("[verify_entities] 失败：炸弹节点缺失")
		quit(1)
		return
	var bbody := bnode.get_node_or_null("Body")
	if bbody == null or not (bbody is Sprite2D):
		push_error("[verify_entities] 失败：炸弹 Body 不是 Sprite2D")
		quit(1)
		return

	print("[verify_entities] 通过")
	quit(0)


func _find_named(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for c in n.get_children():
		var f := _find_named(c, want)
		if f:
			return f
	return null
