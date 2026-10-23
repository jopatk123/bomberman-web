class_name MatchEnd
extends RefCounted
## Win, draw, rematch permission, and mid-match forfeit decisions.
## Scene changes stay in MatchSession. Death RPCs stay in game_root.


## {finished, winner_name}. A one-player match does not end when that player is still alive.
## An empty winner_name on a finished match is a draw.
static func outcome(alive: Dictionary, players: Dictionary) -> Dictionary:
	var living: Array = []
	for id in alive.keys():
		if alive[id] and players.has(int(id)):
			living.append(id)
	if living.size() > 1 or players.size() < 1:
		return {"finished": false, "winner_name": ""}
	if players.size() == 1 and living.size() == 1:
		return {"finished": false, "winner_name": ""}
	var winner_name := ""
	if living.size() == 1:
		var wid: int = int(living[0])
		winner_name = str(players.get(wid, {}).get("name", wid))
	return {"finished": true, "winner_name": winner_name}


## Offline solo can rematch alone. Online only the host can, and only with 2+ players left.
## A dedicated server has no local player (peer_id 0), so its own button stays hidden.
static func can_request_rematch(is_online: bool, peer_id: int, host_id: int, player_count: int) -> bool:
	if peer_id <= 0:
		return false
	if not is_online:
		return player_count >= 1
	return peer_id == host_id and player_count >= 2


## {skip, empty, kill, reason}. `empty` means this peer was the last one in the room.
static func forfeit_plan(players: Dictionary, alive: Dictionary, id: int) -> Dictionary:
	if id <= 0 or (not players.has(id) and not alive.get(id, false)):
		return {"skip": true, "empty": false, "kill": false, "reason": ""}
	var others := 0
	for pid in players.keys():
		if int(pid) != id:
			others += 1
	var nick := str(players.get(id, {}).get("name", "玩家"))
	return {
		"skip": false,
		"empty": others <= 0,
		"kill": bool(alive.get(id, false)),
		"reason": "%s 已离开" % nick,
	}
