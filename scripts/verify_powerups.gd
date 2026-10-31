extends SceneTree
## 无界面：道具加减、上限，以及再来一局是否清掉。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.players = {1: {"name": "测试", "color_idx": 0}}
	gs.in_match = true

	var ps: PackedScene = load("res://scenes/game.tscn")
	var game = ps.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	if game.player_stats.is_empty():
		push_error("[verify_pu] 失败：就绪后没有 player_stats")
		quit(1)
		return
	var pid: int = int(game.player_stats.keys()[0])
	var st0: Dictionary = game.player_stats[pid].duplicate()
	print("[verify_pu] 基础属性 炸弹=", st0.bombs, " 火力=", st0.range, " 移速=", st0.speed)
	if int(st0.get("pierce", -1)) != 0:
		push_error("[verify_pu] 失败：初始穿透应为 0")
		quit(1)
		return
	if not str(game.help_label.text).contains("黄P穿透"):
		push_error("[verify_pu] 失败：帮助文字缺少「黄P穿透」")
		quit(1)
		return

	game._apply_powerup(pid, 0)
	game._apply_powerup(pid, 1)
	game._apply_powerup(pid, 2)
	game._apply_powerup(pid, game.PKind.PIERCE)
	var st1: Dictionary = game.player_stats[pid]
	if int(st1.bombs) != int(st0.bombs) + 1:
		push_error("[verify_pu] 失败：炸弹+未加上")
		quit(1)
		return
	if int(st1.range) != int(st0.range) + 1:
		push_error("[verify_pu] 失败：火力+未加上")
		quit(1)
		return
	if int(st1.speed) != int(st0.speed) + 1:
		push_error("[verify_pu] 失败：移速+未加上")
		quit(1)
		return
	if int(st1.pierce) != 1:
		push_error("[verify_pu] 失败：穿透+未加上")
		quit(1)
		return
	game._apply_powerup(pid, game.PKind.PIERCE)
	if int(game.player_stats[pid].pierce) != 1:
		push_error("[verify_pu] 失败：穿透应保持为 1")
		quit(1)
		return
	game._refresh_stats_hud()
	if not str(game.stats_label.text).contains("穿透 开"):
		push_error("[verify_pu] 失败：属性栏缺少「穿透 开」")
		quit(1)
		return
	var pack: PackedInt32Array = game._stats_pack(pid)
	if pack.size() != 5 or int(pack[4]) != 1:
		push_error("[verify_pu] 失败：属性包穿透 %s" % pack)
		quit(1)
		return
	print("[verify_pu] 道具套用通过 ->", st1)

	for i in 10:
		game._apply_powerup(pid, 0)
		game._apply_powerup(pid, 1)
		game._apply_powerup(pid, 2)
	st1 = game.player_stats[pid]
	if int(st1.bombs) != game.MAX_BOMBS or int(st1.range) != game.MAX_RANGE or int(st1.speed) != game.MAX_SPEED_LVL:
		push_error("[verify_pu] 失败：上限 炸弹=%s 火力=%s 移速=%s" % [st1.bombs, st1.range, st1.speed])
		quit(1)
		return
	print("[verify_pu] 上限通过")

	var soft := Vector2i(-1, -1)
	for y in game.ROWS:
		for x in game.COLS:
			if game.grid[y][x] == game.Cell.SOFT:
				soft = Vector2i(x, y)
				break
		if soft.x >= 0:
			break
	if soft.x < 0:
		push_error("[verify_pu] 失败：没有软墙")
		quit(1)
		return

	game.grid[soft.y][soft.x] = game.Cell.EMPTY
	var npid: int = int(game.next_powerup_id)
	game.next_powerup_id = npid + 1
	game.powerups[npid] = {"x": soft.x, "y": soft.y, "kind": 0}
	game._spawn_powerup_visual(npid, soft, 0)
	await process_frame
	if game.powerups_layer.get_child_count() < 1:
		push_error("[verify_pu] 失败：看不到道具")
		quit(1)
		return
	print("[verify_pu] 道具外观通过 数量=", game.powerups_layer.get_child_count())

	var icon_specs: Array = [
		[game.PKind.BOMB, "powerup_bomb.png", "蓝"],
		[game.PKind.RANGE, "powerup_range.png", "红"],
		[game.PKind.SPEED, "powerup_speed.png", "青"],
		[game.PKind.KICK, "powerup_kick.png", "紫"],
		[game.PKind.PIERCE, "powerup_pierce.png", "黄"],
	]
	for spec in icon_specs:
		var ikind: int = int(spec[0])
		var fname: String = str(spec[1])
		var tag: String = str(spec[2])
		var vid: int = 4200 + ikind
		game._spawn_powerup_visual(vid, soft, ikind)
		var vis: Node = game.powerups_layer.get_node_or_null("Powerup_%d" % vid)
		if vis == null:
			push_error("[verify_pu] 失败：看不到%s道具" % tag)
			quit(1)
			return
		if not _assert_powerup_icon(vis, fname, ikind):
			quit(1)
			return
		vis.queue_free()
	print("[verify_pu] 五种水彩道具图标通过")

	# 走上去捡起道具。
	game.player_nodes[pid].set_meta("cell", soft)
	game._try_pickup_at(pid, soft)
	if game.powerups.has(npid):
		push_error("[verify_pu] 失败：道具没有被捡走")
		quit(1)
		return
	print("[verify_pu] 拾取通过 属性=", game.player_stats[pid])

	game._restart_match()
	await process_frame
	if game.match_over:
		push_error("[verify_pu] 失败：再来一局后仍是终局")
		quit(1)
		return
	if not game.powerups.is_empty():
		push_error("[verify_pu] 失败：再来一局没有清掉道具")
		quit(1)
		return
	var st2: Dictionary = game.player_stats[pid]
	if int(st2.bombs) != game.BASE_BOMBS or int(st2.range) != game.BASE_BLAST:
		push_error("[verify_pu] 失败：再来一局没有重置属性 %s" % st2)
		quit(1)
		return
	if int(st2.get("pierce", -1)) != 0:
		push_error("[verify_pu] 失败：再来一局没有重置穿透 %s" % st2)
		quit(1)
		return
	if not str(game.stats_label.text).contains("穿透 关"):
		push_error("[verify_pu] 失败：再来一局后界面仍显示穿透开")
		quit(1)
		return
	var synced := PackedInt32Array([3, 4, 1, 1, 1])
	game._rpc_pickup(pid, 99999, game.PKind.PIERCE, synced)
	var st3: Dictionary = game.player_stats[pid]
	if int(st3.bombs) != 3 or int(st3.range) != 4 or int(st3.speed) != 1 or int(st3.kick) != 1 or int(st3.pierce) != 1:
		push_error("[verify_pu] 失败：穿透属性包没有套上 %s" % st3)
		quit(1)
		return
	game._rpc_pickup(pid, 99998, 0, PackedInt32Array([2, 3, 0, 0]))
	if int(game.player_stats[pid].get("pierce", 0)) != 1:
		push_error("[verify_pu] 失败：短属性包把穿透清掉了")
		quit(1)
		return
	game._rpc_pickup(pid, 99997, game.PKind.PIERCE, PackedInt32Array([2, 3, 0, 0, 0]))
	if int(game.player_stats[pid].get("pierce", 1)) != 0:
		push_error("[verify_pu] 失败：属性包没有清掉穿透")
		quit(1)
		return
	print("[verify_pu] 再来一局重置通过")
	print("[verify_pu] 成功")
	quit(0)


func _assert_powerup_icon(vis: Node, fname: String, ikind: int) -> bool:
	for child in vis.get_children():
		if child is Polygon2D or child is Label:
			push_error("[verify_pu] 失败：%s 仍是色块或字母" % fname)
			return false
	var icon := vis.get_node_or_null("Icon")
	if icon == null or not (icon is Sprite2D):
		push_error("[verify_pu] 失败：%s 没有 Icon 精灵" % fname)
		return false
	var spr := icon as Sprite2D
	if not spr.centered or spr.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
		push_error("[verify_pu] 失败：%s 不是居中就近采样" % fname)
		return false
	if spr.texture == null or spr.texture.get_width() != 48 or spr.texture.get_height() != 48:
		push_error("[verify_pu] 失败：%s 贴图不是 48x48" % fname)
		return false
	var path := str(spr.texture.resource_path)
	if not path.ends_with(fname):
		push_error("[verify_pu] 失败：%s 贴图路径是 %s" % [fname, path])
		return false
	var img := spr.texture.get_image()
	if img == null:
		push_error("[verify_pu] 失败：%s 读不出像素" % fname)
		return false
	var hits := 0
	var opaque := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.9:
				if c.a > 0.05:
					push_error("[verify_pu] 失败：%s 有半透明像素" % fname)
					return false
				continue
			opaque += 1
			if _pixel_matches_kind(c, ikind):
				hits += 1
	if opaque < 30 or hits < 6:
		push_error("[verify_pu] 失败：%s 主色不够（不透明 %d 命中 %d）" % [fname, opaque, hits])
		return false
	return true


func _pixel_matches_kind(c: Color, ikind: int) -> bool:
	match ikind:
		0:
			return c.b > 0.55 and c.b > c.r + 0.2 and c.g < 0.85
		1:
			return c.r > 0.7 and c.g < 0.65 and c.b < 0.35
		2:
			return c.g > 0.55 and c.b > 0.55 and c.r < 0.45
		3:
			return c.r > 0.35 and c.b > 0.45 and c.g < 0.55 and c.b > c.g
		_:
			return c.r > 0.75 and c.g > 0.45 and c.b < 0.45
