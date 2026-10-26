class_name MatchFill
extends RefCounted
## 真人不足 4 人时，把对局补到 4 个角色。
## 纯数据：没有节点，也不发 RPC。大厅名单始终只有真人。
## 人机的 peer id 是负数，落在 Godot 的 peer 范围之外，
## 所以不当房主、收不到输入 RPC，也不占大厅座位。

const SLOTS := 4
## 第 n 个人机（从 1 起）是 BOT_ID_ORIGIN - n，即 -1001、-1002、-1003、-1004。
const BOT_ID_ORIGIN := -1000
const BOT_LABEL := "人机"


static func bot_peer_id(ordinal: int) -> int:
	return BOT_ID_ORIGIN - ordinal


static func bot_ordinal(peer_id: int) -> int:
	# -1001 → 1，-1002 → 2。正数 peer id 不在 1..SLOTS 里。
	return -peer_id + BOT_ID_ORIGIN


static func is_bot_id(peer_id: int) -> bool:
	var n := bot_ordinal(peer_id)
	return n >= 1 and n <= SLOTS and bot_peer_id(n) == peer_id


static func is_bot_entry(peer_id: int, entry: Dictionary) -> bool:
	return is_bot_id(peer_id) or bool(entry.get("bot", false))


## 只复制真人。人机行丢掉。不改传入的名单。
static func humans(roster: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw in roster.keys():
		var id := int(raw)
		var entry = roster[raw]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if id <= 0 or is_bot_entry(id, entry):
			continue
		out[id] = {
			"name": str(entry.get("name", "玩家%d" % id)),
			"color_idx": int(entry.get("color_idx", 0)) % SLOTS,
			"ready": bool(entry.get("ready", false)),
			"bot": false,
		}
	return out


## 先复制真人，再往空着的角落补人机，直到满 SLOTS。
## 对结果再调一次，id、名字、颜色都不变。
static func fill(roster: Dictionary) -> Dictionary:
	var out := humans(roster)
	var used: Array = []
	for entry in out.values():
		used.append(int(entry.get("color_idx", 0)) % SLOTS)
	var ordinal := 1
	while out.size() < SLOTS and ordinal <= SLOTS:
		var color := 0
		while color < SLOTS and color in used:
			color += 1
		if color >= SLOTS:
			color = 0
		var id := bot_peer_id(ordinal)
		out[id] = {
			"name": "%s%d" % [BOT_LABEL, ordinal],
			"color_idx": color,
			"ready": true,
			"bot": true,
		}
		used.append(color)
		ordinal += 1
	return out


## 真人按 peer id 从小到大（出生角已经按这个顺序占），
## 然后是人机1、人机2……人机因此占真人没占的角。
static func seat_order(roster: Dictionary) -> Array:
	var people: Array = []
	var bots: Array = []
	for raw in roster.keys():
		var id := int(raw)
		var entry = roster[raw]
		var marked := typeof(entry) == TYPE_DICTIONARY and bool(entry.get("bot", false))
		if is_bot_id(id) or marked:
			if is_bot_id(id):
				bots.append(id)
			continue
		if id > 0:
			people.append(id)
	people.sort()
	# 人机 id 随序号变小（-1001、-1002……），倒序后才是人机1 在前。
	bots.sort()
	bots.reverse()
	people.append_array(bots)
	return people


static func bot_ids(roster: Dictionary) -> Array:
	var ids: Array = []
	for raw in seat_order(roster):
		var id := int(raw)
		if is_bot_id(id):
			ids.append(id)
	return ids


static func bot_names(roster: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for id in bot_ids(roster):
		names.append(str(roster[id].get("name", BOT_LABEL)))
	return names
