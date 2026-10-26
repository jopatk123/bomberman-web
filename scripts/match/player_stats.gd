class_name PlayerStats
extends RefCounted
## 每人的炸弹容量、火力、移速、踢弹、穿透。
## 纯数据。拾取 RPC 留在 game_root。


const BASE_BLAST := 2
const BASE_BOMBS := 1
const MAX_BOMBS := 5
const MAX_RANGE := 6
const MAX_SPEED_LVL := 4
## 下标是移速等级，值是移动冷却秒数。
const SPEED_COOLDOWNS := [0.14, 0.115, 0.095, 0.078, 0.062]

enum Kind { BOMB = 0, RANGE = 1, SPEED = 2, KICK = 3, PIERCE = 4 }


static func default_stats() -> Dictionary:
	return {
		"bombs": BASE_BOMBS,
		"range": BASE_BLAST,
		"speed": 0,
		"kick": 0,
		"pierce": 0,
		"move_cd": 0.0,
	}


static func cooldown(stats: Dictionary) -> float:
	var lvl: int = clampi(int(stats.get("speed", 0)), 0, MAX_SPEED_LVL)
	return float(SPEED_COOLDOWNS[lvl])


## 返回一份新的属性字典。踢弹和穿透拿到后本局保持为 1。
static func apply(stats: Dictionary, kind: int) -> Dictionary:
	var st := stats.duplicate()
	if not st.has("bombs"):
		st = default_stats()
	match kind:
		Kind.BOMB:
			st.bombs = mini(int(st.get("bombs", BASE_BOMBS)) + 1, MAX_BOMBS)
		Kind.RANGE:
			st.range = mini(int(st.get("range", BASE_BLAST)) + 1, MAX_RANGE)
		Kind.SPEED:
			st.speed = mini(int(st.get("speed", 0)) + 1, MAX_SPEED_LVL)
		Kind.KICK:
			st.kick = 1
		Kind.PIERCE:
			st.pierce = 1
	return st


static func pack(stats: Dictionary) -> PackedInt32Array:
	return PackedInt32Array([
		int(stats.get("bombs", BASE_BOMBS)),
		int(stats.get("range", BASE_BLAST)),
		int(stats.get("speed", 0)),
		int(stats.get("kick", 0)),
		int(stats.get("pierce", 0)),
	])


## 主机快照覆盖客机。短于 5 项的包保留本地穿透
##（短于 4 项时连踢弹也保留），避免旧主机把新属性抹掉。
static func merge_pack(prev: Dictionary, kind: int, stats: PackedInt32Array) -> Dictionary:
	if stats.size() >= 4:
		var pierce := int(prev.get("pierce", 0))
		if stats.size() >= 5:
			pierce = int(stats[4])
		return {
			"bombs": int(stats[0]),
			"range": int(stats[1]),
			"speed": int(stats[2]),
			"kick": int(stats[3]),
			"pierce": pierce,
			"move_cd": float(prev.get("move_cd", 0.0)),
		}
	if stats.size() >= 3:
		return {
			"bombs": int(stats[0]),
			"range": int(stats[1]),
			"speed": int(stats[2]),
			"kick": int(prev.get("kick", 0)),
			"pierce": int(prev.get("pierce", 0)),
			"move_cd": float(prev.get("move_cd", 0.0)),
		}
	var base := prev
	if not base.has("bombs"):
		base = default_stats()
		base.move_cd = float(prev.get("move_cd", 0.0))
	return apply(base, kind)


static func format_hud(stats: Dictionary, placed: int) -> String:
	var kick_txt := "开" if int(stats.get("kick", 0)) > 0 else "关"
	var pierce_txt := "开" if int(stats.get("pierce", 0)) > 0 else "关"
	return "炸弹 %d/%d  ·  火力 %d  ·  移速 Lv%d  ·  踢弹 %s  ·  穿透 %s" % [
		placed,
		int(stats.get("bombs", BASE_BOMBS)),
		int(stats.get("range", BASE_BLAST)),
		int(stats.get("speed", 0)),
		kick_txt,
		pierce_txt,
	]
