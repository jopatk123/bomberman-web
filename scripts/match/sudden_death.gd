class_name SuddenDeath
extends RefCounted
## 安全区收缩：过了 START_AT 秒后，最外圈可走格变成永久致死火。
## 第一圈落地之后，每隔 INTERVAL 秒再向里缩一圈。再来一局必须调用 reset()。
## 新致死格上的软墙由调用方清掉。

const START_AT := 90.0
## 第一圈之后，两圈之间隔多少秒（第一圈在激活当帧落下）。
const INTERVAL := 15.0

var elapsed: float = 0.0
var active: bool = false
## 当前缩了几圈。-1 表示还没开始；0 是第一圈可走环，以此类推。
var margin: int = -1
## 致死格集合：Vector2i → true
var lethal: Dictionary = {}
var _pulse_left: float = 0.0


func reset() -> void:
	elapsed = 0.0
	active = false
	margin = -1
	lethal.clear()
	_pulse_left = 0.0


## 只推进共用的对局时钟。客机用它刷新界面倒计时。
## 致死格仍由权威端的 tick() 扩展。
func advance_elapsed(delta: float) -> void:
	elapsed += delta


## 距下一圈还有多少秒。未开始或即将扩展时为 0。
func next_pulse_in() -> float:
	if not active:
		return 0.0
	return maxf(0.0, _pulse_left)


func set_pulse_left(seconds: float) -> void:
	_pulse_left = maxf(0.0, seconds)


## 仅客机：两次权威同步之间，把界面倒计时往前走（不扩圈）。
func advance_pulse_display(delta: float) -> void:
	if not active:
		return
	_pulse_left = maxf(0.0, _pulse_left - delta)


## 对局进行时，权威端每帧调用。
## 返回 { "just_activated": bool, "new_cells": Array[Vector2i],
##        "countdown": float, "active": bool }
func tick(delta: float, cols: int, rows: int, grid: Array, cell_hard: int) -> Dictionary:
	var result := {
		"just_activated": false,
		"new_cells": [] as Array[Vector2i],
		"countdown": maxf(0.0, START_AT - elapsed),
		"active": active,
	}
	advance_elapsed(delta)
	result.countdown = maxf(0.0, START_AT - elapsed)
	if elapsed < START_AT:
		return result
	if not active:
		active = true
		result.just_activated = true
		result.active = true
		_pulse_left = 0.0
	_pulse_left -= delta
	if _pulse_left > 0.0:
		return result
	_pulse_left = INTERVAL
	var next_margin: int = margin + 1
	var max_m: int = mini((cols - 3) / 2, (rows - 3) / 2)
	if next_margin > max_m:
		return result
	margin = next_margin
	var added: Array[Vector2i] = []
	for c in ring_cells(margin, cols, rows):
		if lethal.has(c):
			continue
		# 跳过最外圈硬墙柱；只标可走格和软墙这类能玩的格子
		if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
			continue
		if int(grid[c.y][c.x]) == cell_hard:
			continue
		lethal[c] = true
		added.append(c)
	result.new_cells = added
	return result


## 给定圈深上的可玩环（0 是硬墙边框内侧的第一圈）。
static func ring_cells(m: int, cols: int, rows: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0: int = 1 + m
	var y0: int = 1 + m
	var x1: int = cols - 2 - m
	var y1: int = rows - 2 - m
	if x0 > x1 or y0 > y1:
		return out
	for x in range(x0, x1 + 1):
		out.append(Vector2i(x, y0))
		if y1 != y0:
			out.append(Vector2i(x, y1))
	for y in range(y0 + 1, y1):
		out.append(Vector2i(x0, y))
		if x1 != x0:
			out.append(Vector2i(x1, y))
	return out


func is_lethal(cell: Vector2i) -> bool:
	return lethal.has(cell)


func lethal_packed() -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in lethal.keys():
		out.append(int(c.x))
		out.append(int(c.y))
	return out
