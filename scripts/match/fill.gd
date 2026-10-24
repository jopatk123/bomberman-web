class_name MatchFill
extends RefCounted
## Fill a match to 4 fighters when fewer than 4 humans are seated.
## Pure data: no nodes, no RPC. Lobby rosters stay human-only.
## Bot peer ids are negative and outside Godot's peer range, so they never
## become host, never receive input RPCs, and never occupy a lobby seat.

const SLOTS := 4
## Bot n (1-based) is BOT_ID_ORIGIN - n, i.e. -1001, -1002, -1003, -1004.
const BOT_ID_ORIGIN := -1000
const BOT_LABEL := "人机"


static func bot_peer_id(ordinal: int) -> int:
	return BOT_ID_ORIGIN - ordinal


static func bot_ordinal(peer_id: int) -> int:
	# -1001 -> 1, -1002 -> 2. Positive peer ids fall outside 1..SLOTS.
	return -peer_id + BOT_ID_ORIGIN


static func is_bot_id(peer_id: int) -> bool:
	var n := bot_ordinal(peer_id)
	return n >= 1 and n <= SLOTS and bot_peer_id(n) == peer_id


static func is_bot_entry(peer_id: int, entry: Dictionary) -> bool:
	return is_bot_id(peer_id) or bool(entry.get("bot", false))


## Humans only, copied. Bot rows are dropped. Input is not modified.
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


## Copy humans, then append bots into the unused corners until SLOTS fighters.
## Calling again on the result yields the same ids, names, and colors.
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


## Humans in ascending peer id (the order spawn corners already use), then bots
## in 人机1, 人机2, … order. Bots therefore take the corners humans did not.
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
	# Bot ids decrease with ordinal (-1001, -1002, …), so reverse id order is 人机1 first.
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
