extends SceneTree
## 无界面：所有场景能实例化，关键节点路径与类型没有被改坏。
## 场景结构变了就改这里，不要只靠别的 verify 间接覆盖。


const GAME := "res://scenes/game.tscn"
const BOARD := "res://scenes/game/board.tscn"
const PLAYER := "res://scenes/game/player.tscn"
const BOMB := "res://scenes/game/bomb.tscn"
const END_PANEL := "res://scenes/game/end_panel.tscn"
const LOBBY := "res://scenes/lobby.tscn"
const ROOM_ROW := "res://scenes/lobby/room_row.tscn"
const PLAYER_ROW := "res://scenes/lobby/player_row.tscn"
const PLAYER_EMPTY := "res://scenes/lobby/player_empty.tscn"
const POWERUPS := [
	"res://scenes/game/powerup_bomb.tscn",
	"res://scenes/game/powerup_range.tscn",
	"res://scenes/game/powerup_speed.tscn",
	"res://scenes/game/powerup_kick.tscn",
	"res://scenes/game/powerup_pierce.tscn",
]
const FX := [
	"res://scenes/game/blast_center.tscn",
	"res://scenes/game/blast_h.tscn",
	"res://scenes/game/blast_v.tscn",
	"res://scenes/game/soft_break.tscn",
	"res://scenes/game/sd_hazard.tscn",
	"res://scenes/game/airdrop_mark.tscn",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ok = _paths(GAME, ["Camera2D", "Board", "Board/Ground", "Board/Entities", "Board/Powerups", "Board/FX", "HUD", "HUD/Status", "HUD/Stats", "HUD/Help", "HUD/BackBtn", "HUD/EndPanel/VBox/RematchBtn"]) and ok
	ok = _paths(BOARD, ["Ground", "Entities", "Powerups", "FX"]) and ok
	ok = _paths(PLAYER, ["Body", "Name"]) and ok
	ok = _paths(BOMB, ["Body"]) and ok
	for p in POWERUPS:
		ok = _paths(p, ["Icon"]) and ok
	for p in FX:
		ok = _paths(p, []) and ok
	ok = _paths(END_PANEL, ["VBox", "VBox/EndArt", "VBox/EndTitle", "VBox/RematchBtn", "VBox/LobbyBtn"]) and ok
	ok = _paths(ROOM_ROW, []) and ok
	ok = _paths(PLAYER_ROW, ["NameLabel", "HostLabel", "ReadyLabel", "KickBtn"]) and ok
	ok = _paths(LOBBY, ["DirTimer", "RegisterTimer"]) and ok

	ok = _type(GAME, "Board/Ground", "TileMapLayer") and ok
	ok = _type(GAME, "Board", "Node2D") and ok
	ok = _type(PLAYER, "Body", "AnimatedSprite2D") and ok
	ok = _type(PLAYER, "Name", "Label") and ok
	ok = _type(BOMB, "Body", "Sprite2D") and ok
	for p in POWERUPS:
		ok = _type(p, "Icon", "Sprite2D") and ok
	for p in ["res://scenes/game/blast_center.tscn", "res://scenes/game/blast_h.tscn", "res://scenes/game/blast_v.tscn", "res://scenes/game/airdrop_mark.tscn"]:
		ok = _root_type(p, "Sprite2D") and ok
	for p in ["res://scenes/game/soft_break.tscn", "res://scenes/game/sd_hazard.tscn"]:
		ok = _root_type(p, "AnimatedSprite2D") and ok
	ok = _root_type(END_PANEL, "PanelContainer") and ok
	ok = _root_type(ROOM_ROW, "Button") and ok
	ok = _root_type(PLAYER_ROW, "HBoxContainer") and ok
	ok = _root_type(PLAYER_EMPTY, "Label") and ok

	var board: Node = load(BOARD).instantiate()
	var ground := board.get_node("Ground") as TileMapLayer
	if ground == null or ground.tile_set == null or ground.tile_set.tile_size != Vector2i(48, 48):
		push_error("[verify_scenes] 失败：Board/Ground 的 TileSet 不是 48x48")
		ok = false
	else:
		for i in 4:
			if ground.tile_set.has_source(i) == false:
				push_error("[verify_scenes] 失败：TileSet 缺少 source %d" % i)
				ok = false
	board.free()

	for p in POWERUPS:
		var n: Node = load(p).instantiate()
		var icon := n.get_node("Icon") as Sprite2D
		if icon == null or icon.texture == null:
			push_error("[verify_scenes] 失败：%s 图标贴图为空" % p)
			ok = false
		n.free()

	if ok:
		print("[verify_scenes] 通过")
		quit(0)
	else:
		quit(1)


func _paths(path: String, wants: Array) -> bool:
	var node: Node = load(path).instantiate()
	for w in wants:
		if node.get_node_or_null(w) == null:
			push_error("[verify_scenes] 失败：%s 缺少节点 %s" % [path, w])
			node.free()
			return false
	node.free()
	return true


func _type(path: String, node_path: String, want: String) -> bool:
	var node: Node = load(path).instantiate()
	var target: Node = node.get_node_or_null(node_path)
	var matched := false
	if target != null:
		matched = target.get_class() == want or target.is_class(want)
	if not matched:
		push_error("[verify_scenes] 失败：%s 的 %s 不是 %s" % [path, node_path, want])
	node.free()
	return matched


func _root_type(path: String, want: String) -> bool:
	var node: Node = load(path).instantiate()
	var matched := node.get_class() == want or node.is_class(want)
	if not matched:
		push_error("[verify_scenes] 失败：%s 根节点不是 %s" % [path, want])
	node.free()
	return matched
