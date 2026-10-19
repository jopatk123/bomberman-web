extends Node2D
## Authority-side match simulation + client visuals.
## Grid: 13×11, hard walls on odd-odd, soft walls random, 4 corner spawns.

const TILE := 48
const COLS := 13
const ROWS := 11
const BLAST_RANGE := 2
const BOMB_FUSE := 2.0
const MOVE_COOLDOWN := 0.14

enum Cell { EMPTY = 0, HARD = 1, SOFT = 2 }

@onready var map_layer: Node2D = $Map
@onready var entities: Node2D = $Entities
@onready var fx_layer: Node2D = $FX
@onready var hud: CanvasLayer = $HUD
@onready var status_label: Label = $HUD/Status
@onready var back_btn: Button = $HUD/BackBtn

## grid[y][x] -> Cell
var grid: Array = []
var soft_seed: int = 0
## peer_id -> player node
var player_nodes: Dictionary = {}
## bomb_id -> {x,y,owner,timer}
var bombs: Dictionary = {}
var next_bomb_id: int = 1
var alive: Dictionary = {} # peer_id -> bool
var match_over: bool = false
## Client-side input cooldown display only; server owns move timing
var _local_move_cd: float = 0.0


func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	_build_empty_grid()
	if Net.is_authority():
		soft_seed = randi()
		_place_soft_walls(soft_seed)
		_rpc_setup_match.rpc(soft_seed, GameState.players)
		_spawn_all_players()
		_draw_map()
		status_label.text = "对局进行中（主机权威）"
	else:
		status_label.text = "等待主机同步地图…"
	# Clients still need map drawn after RPC
	set_process(true)


func _process(delta: float) -> void:
	_local_move_cd = maxf(0.0, _local_move_cd - delta)
	if match_over:
		return
	if Net.is_authority():
		_tick_bombs(delta)
	_poll_local_input()


func _poll_local_input() -> void:
	if match_over:
		return
	var my_id := _local_control_id()
	if my_id == 0:
		return
	if not alive.get(my_id, false):
		return
	var dir := Vector2i.ZERO
	if Input.is_action_just_pressed("move_up"):
		dir = Vector2i(0, -1)
	elif Input.is_action_just_pressed("move_down"):
		dir = Vector2i(0, 1)
	elif Input.is_action_just_pressed("move_left"):
		dir = Vector2i(-1, 0)
	elif Input.is_action_just_pressed("move_right"):
		dir = Vector2i(1, 0)
	if dir != Vector2i.ZERO and _local_move_cd <= 0.0:
		_local_move_cd = MOVE_COOLDOWN
		if Net.is_authority():
			_apply_move(my_id, dir.x, dir.y)
		else:
			_rpc_request_move.rpc_id(1, dir.x, dir.y)
	if Input.is_action_just_pressed("place_bomb"):
		if Net.is_authority():
			_try_place_bomb(my_id)
		else:
			_rpc_request_bomb.rpc_id(1)


func _local_control_id() -> int:
	if not Net.is_online():
		return 1
	# Dedicated server (peer 1) with no local player entry: no control
	var id := Net.get_peer_id()
	if GameState.players.has(id):
		return id
	return 0


@rpc("authority", "call_local", "reliable")
func _rpc_setup_match(seed: int, players_snap: Dictionary) -> void:
	GameState.players = players_snap.duplicate(true)
	soft_seed = seed
	_build_empty_grid()
	_place_soft_walls(soft_seed)
	_draw_map()
	if not Net.is_authority():
		_spawn_all_players()
		status_label.text = "对局进行中"
	for id in GameState.players.keys():
		alive[id] = true


func _build_empty_grid() -> void:
	grid.clear()
	for y in ROWS:
		var row: Array = []
		for x in COLS:
			var cell := Cell.EMPTY
			if x == 0 or y == 0 or x == COLS - 1 or y == ROWS - 1:
				cell = Cell.HARD
			elif x % 2 == 0 and y % 2 == 0:
				# odd-odd in 1-based interior → even-even in 0-based with border: hard pillars
				cell = Cell.HARD
			row.append(cell)
		grid.append(row)


func _place_soft_walls(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var spawns := _spawn_cells()
	var keep_clear: Dictionary = {}
	for s in spawns:
		keep_clear[s] = true
		# clear adjacent so players can move out
		var adj: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for d in adj:
			keep_clear[s + d] = true
	for y in range(1, ROWS - 1):
		for x in range(1, COLS - 1):
			if grid[y][x] != Cell.EMPTY:
				continue
			if keep_clear.has(Vector2i(x, y)):
				continue
			if rng.randf() < 0.55:
				grid[y][x] = Cell.SOFT


func _spawn_cells() -> Array[Vector2i]:
	return [
		Vector2i(1, 1),
		Vector2i(COLS - 2, 1),
		Vector2i(1, ROWS - 2),
		Vector2i(COLS - 2, ROWS - 2),
	]


func _spawn_all_players() -> void:
	for c in entities.get_children():
		(c as Node).queue_free()
	player_nodes.clear()
	bombs.clear()
	var ids := GameState.get_sorted_peer_ids()
	var spawns := _spawn_cells()
	var i := 0
	for peer_id in ids:
		if i >= spawns.size():
			break
		var cell: Vector2i = spawns[i]
		var p := _make_player_visual(peer_id, cell)
		entities.add_child(p)
		player_nodes[peer_id] = p
		alive[peer_id] = true
		i += 1


func _make_player_visual(peer_id: int, cell: Vector2i) -> Node2D:
	var root := Node2D.new()
	root.set_script(load("res://scripts/player.gd"))
	var display := str(GameState.players.get(peer_id, {}).get("name", peer_id))
	root.setup(peer_id, cell, GameState.color_for_peer(peer_id), display, TILE)
	return root


func _draw_map() -> void:
	for c in map_layer.get_children():
		(c as Node).queue_free()
	for y in ROWS:
		for x in COLS:
			var cell: int = grid[y][x]
			var poly := Polygon2D.new()
			poly.polygon = PackedVector2Array([
				Vector2(0, 0), Vector2(TILE, 0), Vector2(TILE, TILE), Vector2(0, TILE)
			])
			poly.position = Vector2(x * TILE, y * TILE)
			match cell:
				Cell.HARD:
					poly.color = Color(0.25, 0.28, 0.35)
				Cell.SOFT:
					poly.color = Color(0.7, 0.45, 0.25)
				_:
					poly.color = Color(0.15, 0.55, 0.25) if (x + y) % 2 == 0 else Color(0.12, 0.48, 0.22)
			map_layer.add_child(poly)
	# Center camera-ish: shift map so it fits viewport
	var map_w := COLS * TILE
	var map_h := ROWS * TILE
	position = Vector2((960 - map_w) * 0.5, (720 - map_h) * 0.5 - 20)


func _cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)


@rpc("any_peer", "reliable")
func _rpc_request_move(dx: int, dy: int) -> void:
	if not Net.is_authority() or match_over:
		return
	var sender := multiplayer.get_remote_sender_id()
	# Offline / listen host calling locally: sender 0
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_apply_move(sender, dx, dy)


func _apply_move(peer_id: int, dx: int, dy: int) -> void:
	if not alive.get(peer_id, false):
		return
	if not player_nodes.has(peer_id):
		return
	var node: Node2D = player_nodes[peer_id]
	var cell: Vector2i = node.get_meta("cell")
	var next := cell + Vector2i(dx, dy)
	if not _walkable(next):
		return
	# Block walking onto bombs
	for b in bombs.values():
		var bd: Dictionary = b
		if int(bd.x) == next.x and int(bd.y) == next.y:
			return
	cell = next
	node.set_meta("cell", cell)
	if Net.is_online():
		_rpc_set_player_cell.rpc(peer_id, cell.x, cell.y)
	else:
		node.position = _cell_to_pos(cell)


@rpc("authority", "call_local", "reliable")
func _rpc_set_player_cell(peer_id: int, x: int, y: int) -> void:
	if not player_nodes.has(peer_id):
		return
	var node: Node2D = player_nodes[peer_id]
	var cell := Vector2i(x, y)
	node.set_meta("cell", cell)
	node.position = _cell_to_pos(cell)


func _walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= COLS or cell.y >= ROWS:
		return false
	var t: int = grid[cell.y][cell.x]
	return t == Cell.EMPTY


@rpc("any_peer", "reliable")
func _rpc_request_bomb() -> void:
	if not Net.is_authority() or match_over:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_try_place_bomb(sender)


func _try_place_bomb(peer_id: int) -> void:
	if not alive.get(peer_id, false):
		return
	if not player_nodes.has(peer_id):
		return
	# Max 1 bomb per player until explode
	for b in bombs.values():
		var bd: Dictionary = b
		if int(bd.owner) == peer_id:
			return
	var cell: Vector2i = player_nodes[peer_id].get_meta("cell")
	var bid := next_bomb_id
	next_bomb_id += 1
	bombs[bid] = {"x": cell.x, "y": cell.y, "owner": peer_id, "timer": BOMB_FUSE}
	if Net.is_online():
		_rpc_spawn_bomb.rpc(bid, cell.x, cell.y, peer_id)
	else:
		_spawn_bomb_visual(bid, cell)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_bomb(bid: int, x: int, y: int, owner: int) -> void:
	if not Net.is_authority():
		bombs[bid] = {"x": x, "y": y, "owner": owner, "timer": BOMB_FUSE}
	_spawn_bomb_visual(bid, Vector2i(x, y))


func _spawn_bomb_visual(bid: int, cell: Vector2i) -> void:
	var existing := entities.get_node_or_null("Bomb_%d" % bid)
	if existing:
		return
	var root := Node2D.new()
	root.set_script(load("res://scripts/bomb.gd"))
	root.setup(bid, cell, TILE)
	entities.add_child(root)


func _tick_bombs(delta: float) -> void:
	var to_explode: Array = []
	for bid in bombs.keys():
		bombs[bid].timer = float(bombs[bid].timer) - delta
		if float(bombs[bid].timer) <= 0.0:
			to_explode.append(bid)
	for bid in to_explode:
		_explode(bid)


func _explode(bid: int) -> void:
	if not bombs.has(bid):
		return
	var bx: int = int(bombs[bid].x)
	var by: int = int(bombs[bid].y)
	bombs.erase(bid)
	var hit_cells: Array[Vector2i] = [Vector2i(bx, by)]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in dirs:
		for dist in range(1, BLAST_RANGE + 1):
			var c: Vector2i = Vector2i(bx, by) + dir * dist
			if c.x < 0 or c.y < 0 or c.x >= COLS or c.y >= ROWS:
				break
			var t: int = grid[c.y][c.x]
			if t == Cell.HARD:
				break
			hit_cells.append(c)
			if t == Cell.SOFT:
				grid[c.y][c.x] = Cell.EMPTY
				break
	# Chain reaction
	var chained: Array = []
	for other_id in bombs.keys():
		var oc := Vector2i(int(bombs[other_id].x), int(bombs[other_id].y))
		if oc in hit_cells:
			chained.append(other_id)
	if Net.is_online():
		_rpc_bomb_boom.rpc(bid, _cells_to_packed(hit_cells), _soft_cleared_packed(hit_cells))
	else:
		_apply_boom_visual(bid, hit_cells)
		_redraw_soft_from_grid()
	_kill_players_in(hit_cells)
	for cid in chained:
		_explode(cid)


func _cells_to_packed(cells: Array[Vector2i]) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in cells:
		out.append(c.x)
		out.append(c.y)
	return out


func _soft_cleared_packed(hit_cells: Array[Vector2i]) -> PackedInt32Array:
	## After explosion, soft cells in hit that are now EMPTY
	var out := PackedInt32Array()
	for c in hit_cells:
		if grid[c.y][c.x] == Cell.EMPTY:
			out.append(c.x)
			out.append(c.y)
	return out


@rpc("authority", "call_local", "reliable")
func _rpc_bomb_boom(bid: int, hit_xy: PackedInt32Array, clear_xy: PackedInt32Array) -> void:
	bombs.erase(bid)
	var hit_cells: Array[Vector2i] = []
	for i in range(0, hit_xy.size(), 2):
		hit_cells.append(Vector2i(hit_xy[i], hit_xy[i + 1]))
	for i in range(0, clear_xy.size(), 2):
		var x: int = clear_xy[i]
		var y: int = clear_xy[i + 1]
		if y >= 0 and y < ROWS and x >= 0 and x < COLS:
			grid[y][x] = Cell.EMPTY
	_apply_boom_visual(bid, hit_cells)
	_redraw_soft_from_grid()
	if Net.is_authority():
		pass # kills already applied on authority before rpc; clients get kill rpc separately
	# Clients: also apply kills from overlapping cells via separate sync — authority sends kill rpc


func _apply_boom_visual(bid: int, hit_cells: Array[Vector2i]) -> void:
	var node := entities.get_node_or_null("Bomb_%d" % bid)
	if node:
		node.queue_free()
	for c in hit_cells:
		var flash := Polygon2D.new()
		flash.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(TILE, 0), Vector2(TILE, TILE), Vector2(0, TILE)
		])
		flash.position = Vector2(c.x * TILE, c.y * TILE)
		flash.color = Color(1.0, 0.7, 0.2, 0.85)
		fx_layer.add_child(flash)
		var t := get_tree().create_timer(0.25)
		t.timeout.connect(flash.queue_free)


func _redraw_soft_from_grid() -> void:
	_draw_map()
	# Redraw keeps players/bombs in entities; map_layer cleared and rebuilt


func _kill_players_in(hit_cells: Array[Vector2i]) -> void:
	for peer_id in player_nodes.keys():
		if not alive.get(peer_id, false):
			continue
		var cell: Vector2i = player_nodes[peer_id].get_meta("cell")
		if cell in hit_cells:
			alive[peer_id] = false
			if Net.is_online():
				_rpc_player_died.rpc(peer_id)
			else:
				_show_death(peer_id)
			_check_winner()


@rpc("authority", "call_local", "reliable")
func _rpc_player_died(peer_id: int) -> void:
	alive[peer_id] = false
	_show_death(peer_id)
	if not Net.is_authority():
		_check_winner_client()


func _show_death(peer_id: int) -> void:
	if not player_nodes.has(peer_id):
		return
	var node: Node2D = player_nodes[peer_id]
	if node.has_method("mark_dead"):
		node.mark_dead()
	else:
		node.modulate = Color(0.3, 0.3, 0.3, 0.5)


func _check_winner() -> void:
	if match_over:
		return
	var living: Array = []
	for id in alive.keys():
		if alive[id]:
			living.append(id)
	if living.size() <= 1 and GameState.players.size() >= 1:
		match_over = true
		var winner_name := "平局/全灭"
		if living.size() == 1:
			var wid: int = living[0]
			winner_name = str(GameState.players.get(wid, {}).get("name", wid))
		if Net.is_online():
			_rpc_match_over.rpc(winner_name)
		else:
			status_label.text = "对局结束：%s 获胜（单机）" % winner_name


func _check_winner_client() -> void:
	# Authority already broadcasts match over
	pass


@rpc("authority", "call_local", "reliable")
func _rpc_match_over(winner_name: String) -> void:
	match_over = true
	status_label.text = "对局结束：%s 获胜！" % winner_name


func _on_back() -> void:
	if Net.is_online() and Net.is_client:
		Net.close()
	GameState.in_match = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
