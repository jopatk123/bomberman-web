class_name RoomCodes
extends RefCounted
## 短房间码。不发 RPC，也不碰场景。


const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LEN := 4
const MAX_ROOMS := 16


static func fresh(code: String, password: String) -> Dictionary:
	return {
		"code": code,
		"players": {},
		"host_peer_id": 0,
		"room_password": password.strip_edges(),
		"map_id": Arena.MAP_RANDOM,
		"seed_input": "",
		"soft_seed": -1,
		"in_match": false,
	}


## 凑不满 4 个不含歧义的字符时返回空串（多余的杂字先忽略，
## 直到收齐 4 个合法字符）。
static func normalize(raw: String) -> String:
	var up := raw.strip_edges().to_upper()
	var out := ""
	for i in up.length():
		var ch := up.substr(i, 1)
		if not ALPHABET.contains(ch):
			continue
		out += ch
		if out.length() == CODE_LEN:
			break
	if out.length() != CODE_LEN:
		return ""
	return out


static func allocate(existing: Dictionary) -> String:
	for _attempt in 64:
		var code := ""
		for _i in CODE_LEN:
			code += ALPHABET[randi() % ALPHABET.length()]
		if not existing.has(code):
			return code
	return ""
