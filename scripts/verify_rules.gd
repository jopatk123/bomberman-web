extends SceneTree
## 无界面：不建场景，只测属性、掉落和终局判定。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _stats() or not _drops() or not _ending():
		quit(1)
		return
	print("[verify_rules] 成功")
	quit(0)


func _stats() -> bool:
	var st := PlayerStats.default_stats()
	if int(st.pierce) != 0 or int(st.bombs) != 1:
		push_error("[verify_rules] 失败：默认属性不对")
		return false
	for _i in 10:
		st = PlayerStats.apply(st, PlayerStats.Kind.BOMB)
		st = PlayerStats.apply(st, PlayerStats.Kind.RANGE)
		st = PlayerStats.apply(st, PlayerStats.Kind.SPEED)
		st = PlayerStats.apply(st, PlayerStats.Kind.PIERCE)
	if int(st.bombs) != PlayerStats.MAX_BOMBS or int(st.range) != PlayerStats.MAX_RANGE:
		push_error("[verify_rules] 失败：上限不对")
		return false
	if int(st.speed) != PlayerStats.MAX_SPEED_LVL or int(st.pierce) != 1:
		push_error("[verify_rules] 失败：移速或穿透上限不对")
		return false
	var packed := PlayerStats.pack(st)
	var short := PackedInt32Array([int(packed[0]), int(packed[1]), int(packed[2]), int(packed[3])])
	var kept := PlayerStats.merge_pack(st, PlayerStats.Kind.BOMB, short)
	if int(kept.pierce) != 1:
		push_error("[verify_rules] 失败：短包把穿透清掉了")
		return false
	var cleared := PlayerStats.merge_pack(st, PlayerStats.Kind.PIERCE, PackedInt32Array([2, 3, 0, 0, 0]))
	if int(cleared.pierce) != 0:
		push_error("[verify_rules] 失败：完整包没有清掉穿透")
		return false
	var legacy := PlayerStats.merge_pack({"pierce": 1, "kick": 1, "move_cd": 0.2}, 0, PackedInt32Array([2, 3, 1]))
	if int(legacy.kick) != 1 or int(legacy.pierce) != 1:
		push_error("[verify_rules] 失败：三项包丢掉了踢弹或穿透")
		return false
	if not PlayerStats.format_hud(cleared, 1).contains("穿透 关"):
		push_error("[verify_rules] 失败：界面文字不对")
		return false
	print("[verify_rules] 属性通过")
	return true


func _drops() -> bool:
	var powerups := {}
	var lethal := {Vector2i(1, 1): true}
	if PowerupDrop.consider(Vector2i(2, 2), powerups, lethal, 0.99, 0, 1) != -1:
		push_error("[verify_rules] 失败：高抽样应该不掉落")
		return false
	if PowerupDrop.consider(Vector2i(1, 1), powerups, lethal, 0.0, 4, 1) != -1:
		push_error("[verify_rules] 失败：致死格上掉了道具")
		return false
	var pid := PowerupDrop.consider(Vector2i(3, 3), powerups, lethal, 0.0, PlayerStats.Kind.PIERCE, 7)
	if pid != 7 or int(powerups[7].kind) != PlayerStats.Kind.PIERCE:
		push_error("[verify_rules] 失败：掉落没有写进去")
		return false
	if PowerupDrop.consider(Vector2i(3, 3), powerups, lethal, 0.0, 0, 8) != -1:
		push_error("[verify_rules] 失败：已有道具的格子又掉了一次")
		return false
	var packed := PowerupDrop.pack([{"id": 7, "x": 3, "y": 3, "kind": 4}])
	if packed.size() != 4 or int(packed[0]) != 7 or int(packed[3]) != 4:
		push_error("[verify_rules] 失败：掉落封包不对")
		return false
	print("[verify_rules] 掉落通过")
	return true


func _ending() -> bool:
	var players := {1: {"name": "甲"}, 2: {"name": "乙"}}
	var both := {1: true, 2: true}
	if bool(MatchEnd.outcome(both, players).finished):
		push_error("[verify_rules] 失败：还有两人活着却结束了")
		return false
	var one := MatchEnd.outcome({1: true, 2: false}, players)
	if not bool(one.finished) or str(one.winner_name) != "甲":
		push_error("[verify_rules] 失败：胜者不对")
		return false
	var draw := MatchEnd.outcome({1: false, 2: false}, players)
	if not bool(draw.finished) or not str(draw.winner_name).is_empty():
		push_error("[verify_rules] 失败：平局判定不对")
		return false
	var solo := {1: {"name": "甲"}}
	if bool(MatchEnd.outcome({1: true}, solo).finished):
		push_error("[verify_rules] 失败：单人局不该结束")
		return false
	var last := MatchEnd.forfeit_plan(solo, {1: true}, 1)
	if bool(last.skip) or not bool(last.empty):
		push_error("[verify_rules] 失败：最后一人离开应清空房间")
		return false
	var leave := MatchEnd.forfeit_plan(players, both, 2)
	if bool(leave.skip) or bool(leave.empty) or not bool(leave.kill) or str(leave.reason) != "乙 已离开":
		push_error("[verify_rules] 失败：弃权方案 %s" % leave)
		return false
	if not bool(MatchEnd.forfeit_plan(players, both, 0).skip):
		push_error("[verify_rules] 失败：peer 0 应跳过")
		return false
	print("[verify_rules] 终局通过")
	return true
