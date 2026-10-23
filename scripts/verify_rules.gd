extends SceneTree
## Headless: stats, drops, and match-end decisions without a scene.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _stats() or not _drops() or not _ending():
		quit(1)
		return
	print("[verify_rules] SUCCESS")
	quit(0)


func _stats() -> bool:
	var st := PlayerStats.default_stats()
	if int(st.pierce) != 0 or int(st.bombs) != 1:
		push_error("[verify_rules] FAIL: default stats")
		return false
	for _i in 10:
		st = PlayerStats.apply(st, PlayerStats.Kind.BOMB)
		st = PlayerStats.apply(st, PlayerStats.Kind.RANGE)
		st = PlayerStats.apply(st, PlayerStats.Kind.SPEED)
		st = PlayerStats.apply(st, PlayerStats.Kind.PIERCE)
	if int(st.bombs) != PlayerStats.MAX_BOMBS or int(st.range) != PlayerStats.MAX_RANGE:
		push_error("[verify_rules] FAIL: caps")
		return false
	if int(st.speed) != PlayerStats.MAX_SPEED_LVL or int(st.pierce) != 1:
		push_error("[verify_rules] FAIL: speed/pierce cap")
		return false
	var packed := PlayerStats.pack(st)
	var short := PackedInt32Array([int(packed[0]), int(packed[1]), int(packed[2]), int(packed[3])])
	var kept := PlayerStats.merge_pack(st, PlayerStats.Kind.BOMB, short)
	if int(kept.pierce) != 1:
		push_error("[verify_rules] FAIL: short pack cleared pierce")
		return false
	var cleared := PlayerStats.merge_pack(st, PlayerStats.Kind.PIERCE, PackedInt32Array([2, 3, 0, 0, 0]))
	if int(cleared.pierce) != 0:
		push_error("[verify_rules] FAIL: full pack did not clear pierce")
		return false
	var legacy := PlayerStats.merge_pack({"pierce": 1, "kick": 1, "move_cd": 0.2}, 0, PackedInt32Array([2, 3, 1]))
	if int(legacy.kick) != 1 or int(legacy.pierce) != 1:
		push_error("[verify_rules] FAIL: 3-field pack dropped kick/pierce")
		return false
	if not PlayerStats.format_hud(cleared, 1).contains("穿透 关"):
		push_error("[verify_rules] FAIL: hud text")
		return false
	print("[verify_rules] stats OK")
	return true


func _drops() -> bool:
	var powerups := {}
	var lethal := {Vector2i(1, 1): true}
	if PowerupDrop.consider(Vector2i(2, 2), powerups, lethal, 0.99, 0, 1) != -1:
		push_error("[verify_rules] FAIL: high roll should miss")
		return false
	if PowerupDrop.consider(Vector2i(1, 1), powerups, lethal, 0.0, 4, 1) != -1:
		push_error("[verify_rules] FAIL: lethal cell dropped")
		return false
	var pid := PowerupDrop.consider(Vector2i(3, 3), powerups, lethal, 0.0, PlayerStats.Kind.PIERCE, 7)
	if pid != 7 or int(powerups[7].kind) != PlayerStats.Kind.PIERCE:
		push_error("[verify_rules] FAIL: drop not inserted")
		return false
	if PowerupDrop.consider(Vector2i(3, 3), powerups, lethal, 0.0, 0, 8) != -1:
		push_error("[verify_rules] FAIL: occupied cell dropped again")
		return false
	var packed := PowerupDrop.pack([{"id": 7, "x": 3, "y": 3, "kind": 4}])
	if packed.size() != 4 or int(packed[0]) != 7 or int(packed[3]) != 4:
		push_error("[verify_rules] FAIL: drop pack")
		return false
	print("[verify_rules] drops OK")
	return true


func _ending() -> bool:
	var players := {1: {"name": "甲"}, 2: {"name": "乙"}}
	var both := {1: true, 2: true}
	if bool(MatchEnd.outcome(both, players).finished):
		push_error("[verify_rules] FAIL: two living players ended")
		return false
	var one := MatchEnd.outcome({1: true, 2: false}, players)
	if not bool(one.finished) or str(one.winner_name) != "甲":
		push_error("[verify_rules] FAIL: winner")
		return false
	var draw := MatchEnd.outcome({1: false, 2: false}, players)
	if not bool(draw.finished) or not str(draw.winner_name).is_empty():
		push_error("[verify_rules] FAIL: draw")
		return false
	var solo := {1: {"name": "甲"}}
	if bool(MatchEnd.outcome({1: true}, solo).finished):
		push_error("[verify_rules] FAIL: solo match ended")
		return false
	var last := MatchEnd.forfeit_plan(solo, {1: true}, 1)
	if bool(last.skip) or not bool(last.empty):
		push_error("[verify_rules] FAIL: last player should empty the room")
		return false
	var leave := MatchEnd.forfeit_plan(players, both, 2)
	if bool(leave.skip) or bool(leave.empty) or not bool(leave.kill) or str(leave.reason) != "乙 已离开":
		push_error("[verify_rules] FAIL: forfeit plan %s" % leave)
		return false
	if not bool(MatchEnd.forfeit_plan(players, both, 0).skip):
		push_error("[verify_rules] FAIL: peer 0 should skip")
		return false
	print("[verify_rules] ending OK")
	return true
