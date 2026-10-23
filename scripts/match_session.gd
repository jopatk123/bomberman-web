class_name MatchSession
extends RefCounted
## Leave, kick, disconnect, mid-match forfeit, and empty dedicated-room return.
## Death RPCs stay on the match conductor. This type does not declare @rpc.

const LOBBY := "res://scenes/lobby.tscn"

var leaving: bool = false
## Dedicated server already left the match scene for an empty room.
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
	if Net.is_online():
		Net.close()
	GameState.reset_lobby()
	GameState.pending_notice = notice
	tree.change_scene_to_file(LOBBY)


func on_peer_out(id: int, forfeit: Callable) -> void:
	if leaving or left_for_lobby or not Net.is_authority():
		return
	forfeit.call(int(id))


## `kill` is (peer_id, reason). `refresh_rematch` runs when the match had already ended.
func forfeit_peer(tree: SceneTree, id: int, alive: Dictionary, match_over: bool, kill: Callable, refresh_rematch: Callable) -> void:
	var plan: Dictionary = MatchEnd.forfeit_plan(GameState.players, alive, id)
	if bool(plan.skip):
		return
	if bool(plan.empty):
		GameState.players.erase(id)
		alive.erase(id)
		GameState.recompute_host()
		if Net.is_dedicated():
			return_dedicated(tree)
		return
	if bool(plan.kill):
		kill.call(id, str(plan.reason))
	GameState.players.erase(id)
	alive.erase(id)
	GameState.recompute_host()
	if Net.is_online():
		GameState.broadcast_room()
	if match_over:
		refresh_rematch.call()


func return_dedicated(tree: SceneTree) -> void:
	if left_for_lobby:
		return
	left_for_lobby = true
	leaving = true
	GameState.reset_lobby()
	print("[Game] Dedicated room empty, returning to waiting room")
	tree.call_deferred("change_scene_to_file", LOBBY)
