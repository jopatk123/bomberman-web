class_name MatchSession
extends RefCounted
## 离开、被踢、断线、中途弃权，以及专用服空房回大厅。
## 死亡 RPC 留在对局编排脚本。这个类型自己不声明 @rpc。

const LOBBY := "res://scenes/lobby.tscn"

var leaving: bool = false
## 专用服已经因为空房离开了对局场景。
var left_for_lobby: bool = false


func on_back(tree: SceneTree) -> void:
	if Net.is_dedicated() or leaving:
		return
	if not Net.is_online():
		leaving = true
		GameState.in_match = false
		tree.change_scene_to_file(LOBBY)
		return
	leave(tree, "已离开房间")


func on_kicked(tree: SceneTree, message: String) -> void:
	leave(tree, message if not message.is_empty() else "你已被请出房间")


func on_disconnected(tree: SceneTree) -> void:
	if leaving or Net.is_dedicated() or Net.is_server:
		return
	leave(tree, "与服务器断开")


func leave(tree: SceneTree, notice: String) -> void:
	if leaving or Net.is_dedicated():
		return
	leaving = true
	var code := GameState.room_code
	if Net.is_online():
		Net.close()
	MatchHost.close_room(code)
	GameState.reset_lobby()
	GameState.pending_notice = notice
	tree.change_scene_to_file(LOBBY)


func on_peer_out(id: int, forfeit: Callable) -> void:
	if leaving or left_for_lobby or not Net.is_authority():
		return
	forfeit.call(int(id))


## `kill` 的参数是 (peer_id, reason)。对局已经结束时才调用 `refresh_rematch`。
## `roster` 为空时用扁平的 GameState.players（离线测试和单机）。
func forfeit_peer(
	tree: SceneTree,
	id: int,
	alive: Dictionary,
	match_over: bool,
	kill: Callable,
	refresh_rematch: Callable,
	roster: Dictionary = {},
	code: String = "",
	on_empty: Callable = Callable()
) -> void:
	var players: Dictionary = GameState.players if roster.is_empty() else roster
	var plan: Dictionary = MatchEnd.forfeit_plan(players, alive, id)
	if bool(plan.skip):
		return
	if bool(plan.empty):
		players.erase(id)
		alive.erase(id)
		GameState.finish_forfeit(players, code, false)
		if Net.is_dedicated():
			if on_empty.is_valid():
				on_empty.call()
			else:
				return_dedicated(tree)
		return
	if bool(plan.kill):
		kill.call(id, str(plan.reason))
	players.erase(id)
	alive.erase(id)
	GameState.finish_forfeit(players, code, true)
	if match_over:
		refresh_rematch.call()


func return_dedicated(tree: SceneTree) -> void:
	if left_for_lobby:
		return
	left_for_lobby = true
	leaving = true
	GameState.reset_lobby()
	print("[Game] 专用服这间房已空，回到等待房间")
	tree.call_deferred("change_scene_to_file", LOBBY)
