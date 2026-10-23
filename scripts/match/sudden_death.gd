class_name SuddenDeath
extends RefCounted
## Shrinking safe zone: after START_AT seconds, border playable cells become
## permanent lethal fire, expanding inward every INTERVAL seconds after the
## first ring. Rematch must call reset(). Soft walls in new lethal cells are
## cleared by caller.

const START_AT := 90.0
## Seconds between rings after the first shrink (first ring lands on activate).
const INTERVAL := 15.0

var elapsed: float = 0.0
var active: bool = false
## Current shrink depth; -1 = not yet expanded; 0 = first playable ring, …
var margin: int = -1
## Vector2i -> true
var lethal: Dictionary = {}
var _pulse_left: float = 0.0


func reset() -> void:
	elapsed = 0.0
	active = false
	margin = -1
	lethal.clear()
	_pulse_left = 0.0


## Advance the shared match clock only. Clients call this for the HUD.
## Lethal cells stay authority-owned via tick().
func advance_elapsed(delta: float) -> void:
	elapsed += delta


## Seconds until the next ring (0 when inactive or about to expand).
func next_pulse_in() -> float:
	if not active:
		return 0.0
	return maxf(0.0, _pulse_left)


func set_pulse_left(seconds: float) -> void:
	_pulse_left = maxf(0.0, seconds)


## Clients only: tick the HUD countdown between authority syncs (no ring expand).
func advance_pulse_display(delta: float) -> void:
	if not active:
		return
	_pulse_left = maxf(0.0, _pulse_left - delta)


## Call each authority frame while match is running.
## Returns { "just_activated": bool, "new_cells": Array[Vector2i],
##           "countdown": float, "active": bool }
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
		# Skip outer HARD border pillars; only mark walkable / soft playable cells
		if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
			continue
		if int(grid[c.y][c.x]) == cell_hard:
			continue
		lethal[c] = true
		added.append(c)
	result.new_cells = added
	return result


## Playable ring at the given margin (0 = first inner ring inside hard border).
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
