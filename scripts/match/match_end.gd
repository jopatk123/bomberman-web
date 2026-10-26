class_name MatchEnd
extends RefCounted
## 胜负、平局、再来一局资格，以及中途退出怎么判。
## 切场景留在 MatchSession。死亡 RPC 留在 game_root。


## 返回 {finished, winner_name}。只剩一个人且还活着时，这局不结束。
## 已经结束但 winner_name 为空，就是平局。
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


## 单机可以一个人再来。联机只有房主能再来，而且房间里还得剩至少 2 人。
## 专用服没有本地玩家（peer_id 为 0），所以它自己的按钮一直藏着。
static func can_request_rematch(is_online: bool, peer_id: int, host_id: int, player_count: int) -> bool:
	if peer_id <= 0:
		return false
	if not is_online:
		return player_count >= 1
	return peer_id == host_id and player_count >= 2


## 返回 {skip, empty, kill, reason}。`empty` 表示这个人是房间里最后一个。
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
