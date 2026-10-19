extends Node2D
## Authority-side match simulation + client visuals.
## Grid: 13×11, hard walls on odd-odd, soft walls random, 4 corner spawns.
## Power-ups: Bomb+ / Range+ / Speed+ / Kick from soft walls.
##
## See BlastRules for blast/chain/powerup destruction rules.
## See SuddenDeath for shrinking lethal zone.
## See KickRules for bomb-pass / kick. See Arena for the 13×11 layout.

const TILE := 48
const COLS := 13
const ROWS := 11
const BOMB_FUSE := 2.0
const BASE_BLAST := 2
const BASE_BOMBS := 1
const MAX_BOMBS := 5
const MAX_RANGE := 6
const MAX_SPEED_LVL := 4
const POWERUP_CHANCE := 0.38
const KICK_SLIDE_INTERVAL := 0.07
## Index = speed level → move cooldown seconds
const SPEED_COOLDOWNS := [0.14, 0.115, 0.095, 0.078, 0.062]

enum Cell { EMPTY = 0, HARD = 1, SOFT = 2 }
enum PKind { BOMB = 0, RANGE = 1, SPEED = 2, KICK = 3 }

@onready var map_layer: Node2D = $Map
@onready var entities: Node2D = $Entities
@onready var powerups_layer: Node2D = $Powerups
@onready var fx_layer: Node2D = $FX
@onready var hud: CanvasLayer = $HUD
@onready var status_label: Label = $HUD/Status
@onready var stats_label: Label = $HUD/Stats
@onready var spec_label: Label = $HUD/SpecLabel
@onready var help_label: Label = $HUD/Help
@onready var sd_label: Label = $HUD/SuddenDeathLabel
@onready var back_btn: Button = $HUD/BackBtn
@onready var end_panel: PanelContainer = $HUD/EndPanel
@onready var end_title: Label = $HUD/EndPanel/VBox/EndTitle
@onready var rematch_btn: Button = $HUD/EndPanel/VBox/RematchBtn
@onready var lobby_btn: Button = $HUD/EndPanel/VBox/LobbyBtn

## grid[y][x] -> Cell
var grid: Array = []
var soft_seed: int = 0
## peer_id -> player node
var player_nodes: Dictionary = {}
## bomb_id -> {x,y,owner,timer,range,solid,slide_dx,slide_dy,slide_cd}
var bombs: Dictionary = {}
var next_bomb_id: int = 1
## powerup_id -> {x,y,kind}
var powerups: Dictionary = {}
var next_powerup_id: int = 1
## peer_id -> {bombs, range, speed, kick, move_cd}
var player_stats: Dictionary = {}
var alive: Dictionary = {} # peer_id -> bool
var match_over: bool = false
## Client-side input cooldown; server also tracks per-player move_cd
var _local_move_cd: float = 0.0
var sudden: SuddenDeath = SuddenDeath.new()
## Permanent sudden-death fire visuals: cell key "x,y" -> Polygon2D
var _sd_visuals: Dictionary = {}
## map_polys[y][x] -> Polygon2D. Repaint changed cells instead of rebuilding the map.
var _map_polys: Array = []
## Last sudden-death HUD key, so the label is rewritten only when the second changes.
var _sd_hud_key: String = ""
## Cells hit by blasts during the current move, so stepping into that flame kills.
var _blast_hits: Array[Vector2i] = []
## Seconds until the next authority clock sync during the countdown window.
var _clock_sync_wait: float = 0.0


func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	rematch_btn.pressed.connect(_on_rematch)
	lobby_btn.pressed.connect(_on_back)
	end_panel.visible = false
	spec_label.visible = false
	if sd_label:
		sd_label.visible = false
	if help_label:
		help_label.text = "WASD/方向键移动 · 空格放炸弹 · 道具：蓝B+炸弹 / 红R+火力 / 青S+移速 / 紫K踢弹"
	grid = Arena.empty_grid()
	if Net.is_authority():
		soft_seed = randi()
		if Net.is_online():
			_rpc_setup_match.rpc(soft_seed, GameState.players)
		else:
			_rpc_setup_match(soft_seed, GameState.players)
	else:
		status_label.text = "等待主机同步地图…"
	_refresh_stats_hud()
	set_process(true)


func _process(delta: float) -> void:
	_local_move_cd = maxf(0.0, _local_move_cd - delta)
	if Net.is_authority():
		_tick_move_cds(delta)
		if not match_over:
			_tick_bomb_slides(delta)
			_tick_bombs(delta)
			_tick_sudden_death(delta)
			_kill_players_on_lethal()
			_sync_match_clock(delta)
	elif not match_over:
		# HUD clock only. Lethal cells arrive from the host.
		sudden.advance_elapsed(delta)
	if not match_over:
		_poll_local_input()
	_refresh_sudden_death_hud()


func _tick_move_cds(delta: float) -> void:
	for pid in player_stats.keys():
		var st: Dictionary = player_stats[pid]
		st.move_cd = maxf(0.0, float(st.get("move_cd", 0.0)) - delta)


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
		_local_move_cd = _cooldown_for(my_id)
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
	var id := Net.get_peer_id()
	if GameState.players.has(id):
		return id
	return 0


func _cooldown_for(peer_id: int) -> float:
	var st: Dictionary = player_stats.get(peer_id, {})
	var lvl: int = clampi(int(st.get("speed", 0)), 0, MAX_SPEED_LVL)
	return float(SPEED_COOLDOWNS[lvl])


func _default_stats() -> Dictionary:
	return {"bombs": BASE_BOMBS, "range": BASE_BLAST, "speed": 0, "kick": 0, "move_cd": 0.0}


func _init_all_stats() -> void:
	player_stats.clear()
	for id in GameState.players.keys():
		player_stats[id] = _default_stats()


@rpc("authority", "call_local", "reliable")
func _rpc_setup_match(seed: int, players_snap: Dictionary) -> void:
	GameState.players = players_snap.duplicate(true)
	soft_seed = seed
	match_over = false
	end_panel.visible = false
	spec_label.visible = false
	sudden.reset()
	_clear_sd_visuals()
	_clear_powerups()
	_clear_bomb_visuals()
	bombs.clear()
	next_bomb_id = 1
	next_powerup_id = 1
	_sd_hud_key = ""
	_clock_sync_wait = 0.0
	grid = Arena.empty_grid()
	Arena.place_soft_walls(grid, soft_seed)
	_init_all_stats()
	_draw_map()
	_spawn_all_players()
	if not Net.is_authority():
		status_label.text = "对局进行中"
	else:
		status_label.text = "对局进行中（主机权威）"
	for id in GameState.players.keys():
		alive[id] = true
	_refresh_stats_hud()
	_refresh_sudden_death_hud()


func _spawn_all_players() -> void:
	for c in entities.get_children():
		var n := c as Node
		if n.name.begins_with("Player_"):
			n.queue_free()
	player_nodes.clear()
	var ids := GameState.get_sorted_peer_ids()
	var spawns := Arena.spawn_cells()
	var i := 0
	for peer_id in ids:
		if i >= spawns.size():
			break
		var cell: Vector2i = spawns[i]
		var p := _make_player_visual(peer_id, cell)
		entities.add_child(p)
		player_nodes[peer_id] = p
		alive[peer_id] = true
		if not player_stats.has(peer_id):
			player_stats[peer_id] = _default_stats()
		i += 1


func _make_player_visual(peer_id: int, cell: Vector2i) -> Node2D:
	var root := Node2D.new()
	root.set_script(load("res://scripts/player.gd"))
	var display := str(GameState.players.get(peer_id, {}).get("name", peer_id))
	root.setup(peer_id, cell, GameState.color_for_peer(peer_id), display, TILE)
	return root


func _tile_color(x: int, y: int) -> Color:
	match int(grid[y][x]):
		Cell.HARD:
			return Color(0.25, 0.28, 0.35)
		Cell.SOFT:
			return Color(0.7, 0.45, 0.25)
		_:
			return Color(0.15, 0.55, 0.25) if (x + y) % 2 == 0 else Color(0.12, 0.48, 0.22)


func _draw_map() -> void:
	for c in map_layer.get_children():
		(c as Node).queue_free()
	_map_polys.clear()
	for y in ROWS:
		var row: Array = []
		for x in COLS:
			var poly := Polygon2D.new()
			poly.polygon = PackedVector2Array([
				Vector2(0, 0), Vector2(TILE, 0), Vector2(TILE, TILE), Vector2(0, TILE)
			])
			poly.position = Vector2(x * TILE, y * TILE)
			poly.color = _tile_color(x, y)
			map_layer.add_child(poly)
			row.append(poly)
		_map_polys.append(row)
	var map_w := COLS * TILE
	var map_h := ROWS * TILE
	position = Vector2((960 - map_w) * 0.5, (720 - map_h) * 0.5 - 20)


## Recolor tiles that changed. Falls back to a full draw if the tile cache is missing.
func _repaint_cells(cells: Array) -> void:
	if _map_polys.size() != ROWS:
		_draw_map()
		return
	for c in cells:
		var x: int = int(c.x)
		var y: int = int(c.y)
		if y < 0 or y >= ROWS or x < 0 or x >= COLS:
			continue
		var poly: Polygon2D = _map_polys[y][x]
		if is_instance_valid(poly):
			poly.color = _tile_color(x, y)


func _cell_to_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)


@rpc("any_peer", "reliable")
func _rpc_request_move(dx: int, dy: int) -> void:
	if not Net.is_authority() or match_over:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_apply_move(sender, dx, dy)


func _apply_move(peer_id: int, dx: int, dy: int) -> void:
	if not alive.get(peer_id, false):
		return
	if not player_nodes.has(peer_id):
		return
	var st: Dictionary = player_stats.get(peer_id, _default_stats())
	if float(st.get("move_cd", 0.0)) > 0.0:
		return
	_blast_hits.clear()
	var node: Node2D = player_nodes[peer_id]
	var cell: Vector2i = node.get_meta("cell")
	var next := cell + Vector2i(dx, dy)
	if not _walkable(next):
		return
	# Sudden-death fire: walking onto lethal kills after move resolves
	var bid := _bomb_id_at(next)
	if bid >= 0:
		var has_kick := int(st.get("kick", 0)) > 0
		var enter := KickRules.classify_enter(
			bid, bombs, peer_id, has_kick, dx, dy, _can_bomb_slide_to
		)
		match enter:
			KickRules.Enter.BLOCKED:
				return
			KickRules.Enter.KICK:
				if not _try_kick_bomb(bid, dx, dy):
					return
				if not alive.get(peer_id, false):
					return
			KickRules.Enter.WALK:
				pass
	st.move_cd = _cooldown_for(peer_id)
	player_stats[peer_id] = st
	var prev := cell
	cell = next
	node.set_meta("cell", cell)
	# After owner leaves bomb cell → bomb becomes solid for everyone
	_solidify_bombs_left_by(peer_id, prev)
	if Net.is_online():
		_rpc_set_player_cell.rpc(peer_id, cell.x, cell.y)
	else:
		node.position = _cell_to_pos(cell)
	_try_pickup_at(peer_id, cell)
	if sudden.is_lethal(cell) or cell in _blast_hits:
		_kill_player(peer_id)


func _solidify_bombs_left_by(peer_id: int, left_cell: Vector2i) -> void:
	for bid in bombs.keys():
		var bd: Dictionary = bombs[bid]
		if int(bd.owner) != peer_id:
			continue
		if int(bd.x) == left_cell.x and int(bd.y) == left_cell.y:
			bd.solid = true
			bombs[bid] = bd


func _bomb_id_at(cell: Vector2i) -> int:
	return KickRules.bomb_id_at(bombs, cell)


## Kick: slide bomb one step immediately; keep sliding each tick until blocked.
## Soft / hard / bomb / player / powerup / edge → stop (soft NOT destroyed by kick).
func _try_kick_bomb(bid: int, dx: int, dy: int) -> bool:
	if not bombs.has(bid):
		return false
	var bd: Dictionary = bombs[bid]
	var dest := Vector2i(int(bd.x) + dx, int(bd.y) + dy)
	var blockers := _slide_blockers()
	if not _can_bomb_slide_to(dest, blockers[0], blockers[1]):
		return false
	_move_bomb_to(bid, dest)
	# Entering existing fire detonates immediately and removes the bomb.
	if not bombs.has(bid):
		return true
	bd = bombs[bid]
	bd.slide_dx = dx
	bd.slide_dy = dy
	bd.slide_cd = KICK_SLIDE_INTERVAL
	bd.solid = true
	bombs[bid] = bd
	return true


func _slide_blockers() -> Array:
	var player_cells: Dictionary = {}
	for peer_id in player_nodes.keys():
		if not alive.get(peer_id, false):
			continue
		player_cells[player_nodes[peer_id].get_meta("cell")] = true
	var powerup_cells: Dictionary = {}
	for p in powerups.values():
		powerup_cells[Vector2i(int(p.x), int(p.y))] = true
	return [player_cells, powerup_cells]


func _can_bomb_slide_to(cell: Vector2i, player_cells = null, powerup_cells = null) -> bool:
	if player_cells == null or powerup_cells == null:
		var blockers := _slide_blockers()
		player_cells = blockers[0]
		powerup_cells = blockers[1]
	return not KickRules.slide_blocked(
		cell, COLS, ROWS, grid, Cell.HARD, Cell.SOFT, bombs, player_cells, powerup_cells
	)


func _move_bomb_to(bid: int, cell: Vector2i) -> void:
	if not bombs.has(bid):
		return
	var bd: Dictionary = bombs[bid]
	bd.x = cell.x
	bd.y = cell.y
	bombs[bid] = bd
	if Net.is_online():
		_rpc_set_bomb_cell.rpc(bid, cell.x, cell.y)
	else:
		_apply_bomb_cell_visual(bid, cell)
	if sudden.is_lethal(cell):
		_explode(bid)


func _tick_bomb_slides(delta: float) -> void:
	var ids: Array = bombs.keys()
	var blockers := _slide_blockers()
	for bid in ids:
		if not bombs.has(bid):
			continue
		var bd: Dictionary = bombs[bid]
		var sdx: int = int(bd.get("slide_dx", 0))
		var sdy: int = int(bd.get("slide_dy", 0))
		if sdx == 0 and sdy == 0:
			continue
		bd.slide_cd = float(bd.get("slide_cd", 0.0)) - delta
		if float(bd.slide_cd) > 0.0:
			bombs[bid] = bd
			continue
		var dest := Vector2i(int(bd.x) + sdx, int(bd.y) + sdy)
		if not _can_bomb_slide_to(dest, blockers[0], blockers[1]):
			bd.slide_dx = 0
			bd.slide_dy = 0
			bd.slide_cd = 0.0
			bombs[bid] = bd
			continue
		bd.slide_cd = KICK_SLIDE_INTERVAL
		bombs[bid] = bd
		_move_bomb_to(bid, dest)
		if not bombs.has(bid):
			# Detonation can remove players, powerups, and other bombs.
			blockers = _slide_blockers()


@rpc("authority", "call_local", "reliable")
func _rpc_set_bomb_cell(bid: int, x: int, y: int) -> void:
	if bombs.has(bid):
		bombs[bid].x = x
		bombs[bid].y = y
	_apply_bomb_cell_visual(bid, Vector2i(x, y))


func _apply_bomb_cell_visual(bid: int, cell: Vector2i) -> void:
	var node := entities.get_node_or_null("Bomb_%d" % bid)
	if node and node.has_method("set_cell"):
		node.set_cell(cell)
	elif node:
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


func _count_bombs_owned(peer_id: int) -> int:
	var n := 0
	for b in bombs.values():
		if int(b.owner) == peer_id:
			n += 1
	return n


func _try_place_bomb(peer_id: int) -> void:
	if not alive.get(peer_id, false):
		return
	if not player_nodes.has(peer_id):
		return
	var st: Dictionary = player_stats.get(peer_id, _default_stats())
	var max_b: int = clampi(int(st.get("bombs", BASE_BOMBS)), 1, MAX_BOMBS)
	if _count_bombs_owned(peer_id) >= max_b:
		return
	var cell: Vector2i = player_nodes[peer_id].get_meta("cell")
	for b in bombs.values():
		if int(b.x) == cell.x and int(b.y) == cell.y:
			return
	var blast: int = clampi(int(st.get("range", BASE_BLAST)), 1, MAX_RANGE)
	var bid := next_bomb_id
	next_bomb_id += 1
	# solid=false → owner may walk off; becomes solid once they leave
	bombs[bid] = {
		"x": cell.x, "y": cell.y, "owner": peer_id,
		"timer": BOMB_FUSE, "range": blast, "solid": false,
		"slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
	}
	if Net.is_online():
		_rpc_spawn_bomb.rpc(bid, cell.x, cell.y, peer_id, blast)
	else:
		_spawn_bomb_visual(bid, cell)
	_refresh_stats_hud()


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_bomb(bid: int, x: int, y: int, owner: int, blast: int = BASE_BLAST) -> void:
	if not Net.is_authority():
		bombs[bid] = {
			"x": x, "y": y, "owner": owner,
			"timer": BOMB_FUSE, "range": blast, "solid": false,
			"slide_dx": 0, "slide_dy": 0, "slide_cd": 0.0,
		}
	_spawn_bomb_visual(bid, Vector2i(x, y))
	_refresh_stats_hud()


func _spawn_bomb_visual(bid: int, cell: Vector2i) -> void:
	var existing := entities.get_node_or_null("Bomb_%d" % bid)
	if existing:
		return
	var root := Node2D.new()
	root.set_script(load("res://scripts/bomb.gd"))
	root.setup(bid, cell, TILE)
	entities.add_child(root)


func _clear_bomb_visuals() -> void:
	for c in entities.get_children():
		var n := c as Node
		if n.name.begins_with("Bomb_"):
			n.queue_free()


func _tick_bombs(delta: float) -> void:
	_blast_hits.clear()
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
	var blast: int = clampi(int(bombs[bid].get("range", BASE_BLAST)), 1, MAX_RANGE)
	bombs.erase(bid)
	var computed := BlastRules.compute_rays(grid, Vector2i(bx, by), blast, COLS, ROWS)
	var hit_cells: Array[Vector2i] = computed.hit
	_blast_hits.append_array(hit_cells)
	var cleared_soft: Array[Vector2i] = computed.cleared_soft
	for c in cleared_soft:
		grid[c.y][c.x] = Cell.EMPTY
	# Spawn power-ups on authority for cleared soft walls
	var spawned: Array = [] # [{id,x,y,kind}, ...]
	if Net.is_authority():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for c in cleared_soft:
			if rng.randf() > POWERUP_CHANCE:
				continue
			var blocked := false
			for p in powerups.values():
				if int(p.x) == c.x and int(p.y) == c.y:
					blocked = true
					break
			if blocked:
				continue
			if sudden.is_lethal(c):
				continue
			var kind: int = rng.randi_range(0, 3) # BOMB / RANGE / SPEED / KICK
			var pid := next_powerup_id
			next_powerup_id += 1
			powerups[pid] = {"x": c.x, "y": c.y, "kind": kind}
			spawned.append({"id": pid, "x": c.x, "y": c.y, "kind": kind})
	# Chain reaction when blast hits another bomb
	var chained: Array = []
	for other_id in bombs.keys():
		var oc := Vector2i(int(bombs[other_id].x), int(bombs[other_id].y))
		if oc in hit_cells:
			chained.append(other_id)
	var clear_pack := BlastRules.cells_to_packed(cleared_soft)
	var spawn_pack := _powerups_to_packed(spawned)
	if Net.is_online():
		_rpc_bomb_boom.rpc(bid, BlastRules.cells_to_packed(hit_cells), clear_pack, spawn_pack)
	else:
		_apply_boom_visual(bid, hit_cells)
		_repaint_cells(cleared_soft)
		for s in spawned:
			_spawn_powerup_visual(int(s.id), Vector2i(int(s.x), int(s.y)), int(s.kind))
		_refresh_stats_hud()
	_kill_players_in(hit_cells)
	# Destroy powerups in blast (except freshly spawned from this explosion)
	_destroy_powerups_in(hit_cells, spawned)
	for cid in chained:
		_explode(cid)


func _powerups_to_packed(spawned: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in spawned:
		out.append(int(s.id))
		out.append(int(s.x))
		out.append(int(s.y))
		out.append(int(s.kind))
	return out


@rpc("authority", "call_local", "reliable")
func _rpc_bomb_boom(bid: int, hit_xy: PackedInt32Array, clear_xy: PackedInt32Array, spawn_xy: PackedInt32Array = PackedInt32Array()) -> void:
	bombs.erase(bid)
	var hit_cells: Array[Vector2i] = BlastRules.packed_to_cells(hit_xy)
	for i in range(0, clear_xy.size(), 2):
		var x: int = clear_xy[i]
		var y: int = clear_xy[i + 1]
		if y >= 0 and y < ROWS and x >= 0 and x < COLS:
			grid[y][x] = Cell.EMPTY
	_apply_boom_visual(bid, hit_cells)
	_repaint_cells(BlastRules.packed_to_cells(clear_xy))
	for i in range(0, spawn_xy.size(), 4):
		var pid: int = spawn_xy[i]
		var px: int = spawn_xy[i + 1]
		var py: int = spawn_xy[i + 2]
		var pk: int = spawn_xy[i + 3]
		if not powerups.has(pid):
			powerups[pid] = {"x": px, "y": py, "kind": pk}
		_spawn_powerup_visual(pid, Vector2i(px, py), pk)
	if not Net.is_authority():
		var just_spawned: Dictionary = {}
		for i in range(0, spawn_xy.size(), 4):
			just_spawned[spawn_xy[i]] = true
		var to_rm: Array = []
		for pid in powerups.keys():
			if just_spawned.has(pid):
				continue
			var p: Dictionary = powerups[pid]
			var pc := Vector2i(int(p.x), int(p.y))
			if pc in hit_cells:
				to_rm.append(pid)
		for pid in to_rm:
			_remove_powerup(pid)
	_refresh_stats_hud()


func _destroy_powerups_in(hit_cells: Array[Vector2i], just_spawned: Array) -> void:
	if not Net.is_authority():
		return
	var keep: Dictionary = {}
	for s in just_spawned:
		keep[int(s.id)] = true
	var to_rm: Array = []
	for pid in powerups.keys():
		if keep.has(pid):
			continue
		var p: Dictionary = powerups[pid]
		var pc := Vector2i(int(p.x), int(p.y))
		if pc in hit_cells:
			to_rm.append(pid)
	for pid in to_rm:
		_remove_powerup(pid)
		if Net.is_online():
			_rpc_remove_powerup.rpc(pid)


func _apply_boom_visual(bid: int, hit_cells: Array[Vector2i]) -> void:
	var node := entities.get_node_or_null("Bomb_%d" % bid)
	if node:
		node.queue_free()
	for c in hit_cells:
		var flash := Polygon2D.new()
		flash.polygon = PackedVector2Array([
			Vector2(4, 4), Vector2(TILE - 4, 4), Vector2(TILE - 4, TILE - 4), Vector2(4, TILE - 4)
		])
		flash.position = Vector2(c.x * TILE, c.y * TILE)
		flash.color = Color(1.0, 0.75, 0.2, 0.9)
		fx_layer.add_child(flash)
		var core := Polygon2D.new()
		core.polygon = PackedVector2Array([
			Vector2(14, 14), Vector2(TILE - 14, 14), Vector2(TILE - 14, TILE - 14), Vector2(14, TILE - 14)
		])
		core.position = Vector2(c.x * TILE, c.y * TILE)
		core.color = Color(1.0, 0.95, 0.6, 0.95)
		fx_layer.add_child(core)
		var t := get_tree().create_timer(0.28)
		t.timeout.connect(func():
			if is_instance_valid(flash):
				flash.queue_free()
			if is_instance_valid(core):
				core.queue_free()
		)


# --- Power-ups ----------------------------------------------------------------

func _spawn_powerup_visual(pid: int, cell: Vector2i, kind: int) -> void:
	if powerups_layer.get_node_or_null("Powerup_%d" % pid):
		return
	var root := Node2D.new()
	root.set_script(load("res://scripts/powerup.gd"))
	root.setup(pid, cell, kind, TILE)
	powerups_layer.add_child(root)


func _clear_powerups() -> void:
	powerups.clear()
	if powerups_layer:
		for c in powerups_layer.get_children():
			(c as Node).queue_free()


func _remove_powerup(pid: int) -> void:
	powerups.erase(pid)
	var n := powerups_layer.get_node_or_null("Powerup_%d" % pid)
	if n:
		n.queue_free()


@rpc("authority", "call_local", "reliable")
func _rpc_remove_powerup(pid: int) -> void:
	_remove_powerup(pid)


func _try_pickup_at(peer_id: int, cell: Vector2i) -> void:
	if not Net.is_authority():
		return
	var found := -1
	for pid in powerups.keys():
		var p: Dictionary = powerups[pid]
		if int(p.x) == cell.x and int(p.y) == cell.y:
			found = pid
			break
	if found < 0:
		return
	var kind: int = int(powerups[found].kind)
	_apply_powerup(peer_id, kind)
	_remove_powerup(found)
	if Net.is_online():
		_rpc_pickup.rpc(peer_id, found, kind, _stats_pack(peer_id))
	else:
		_refresh_stats_hud()


func _stats_pack(peer_id: int) -> PackedInt32Array:
	var st: Dictionary = player_stats.get(peer_id, _default_stats())
	return PackedInt32Array([
		int(st.get("bombs", BASE_BOMBS)),
		int(st.get("range", BASE_BLAST)),
		int(st.get("speed", 0)),
		int(st.get("kick", 0)),
	])


func _apply_powerup(peer_id: int, kind: int) -> void:
	if not player_stats.has(peer_id):
		player_stats[peer_id] = _default_stats()
	var st: Dictionary = player_stats[peer_id]
	match kind:
		PKind.BOMB:
			st.bombs = mini(int(st.get("bombs", BASE_BOMBS)) + 1, MAX_BOMBS)
		PKind.RANGE:
			st.range = mini(int(st.get("range", BASE_BLAST)) + 1, MAX_RANGE)
		PKind.SPEED:
			st.speed = mini(int(st.get("speed", 0)) + 1, MAX_SPEED_LVL)
		PKind.KICK:
			st.kick = 1
	player_stats[peer_id] = st


@rpc("authority", "call_local", "reliable")
func _rpc_pickup(peer_id: int, powerup_id: int, kind: int, stats: PackedInt32Array) -> void:
	_remove_powerup(powerup_id)
	if stats.size() >= 4:
		player_stats[peer_id] = {
			"bombs": stats[0],
			"range": stats[1],
			"speed": stats[2],
			"kick": stats[3],
			"move_cd": float(player_stats.get(peer_id, {}).get("move_cd", 0.0)),
		}
	elif stats.size() >= 3:
		player_stats[peer_id] = {
			"bombs": stats[0],
			"range": stats[1],
			"speed": stats[2],
			"kick": int(player_stats.get(peer_id, {}).get("kick", 0)),
			"move_cd": float(player_stats.get(peer_id, {}).get("move_cd", 0.0)),
		}
	else:
		_apply_powerup(peer_id, kind)
	_refresh_stats_hud()
	if player_nodes.has(peer_id):
		var n: Node2D = player_nodes[peer_id]
		n.modulate = Color(1.4, 1.4, 1.2, 1.0)
		var t := get_tree().create_timer(0.15)
		t.timeout.connect(func():
			if is_instance_valid(n) and alive.get(peer_id, false):
				n.modulate = Color.WHITE
		)


# --- Sudden death -------------------------------------------------------------

func _tick_sudden_death(delta: float) -> void:
	var r: Dictionary = sudden.tick(delta, COLS, ROWS, grid, Cell.HARD)
	if r.just_activated:
		if Net.is_online():
			_rpc_sudden_death_start.rpc(sudden.elapsed)
		else:
			_on_sudden_death_started()
	var new_cells: Array = r.new_cells
	if new_cells.is_empty():
		return
	var bomb_ids := PackedInt32Array()
	var powerup_ids := PackedInt32Array()
	for c in new_cells:
		var bid := _bomb_id_at(c)
		if bid >= 0:
			bomb_ids.append(bid)
		for pid in powerups.keys():
			var p: Dictionary = powerups[pid]
			if int(p.x) == c.x and int(p.y) == c.y:
				powerup_ids.append(int(pid))
	if Net.is_online():
		_rpc_sudden_death_add.rpc(BlastRules.cells_to_packed(new_cells), bomb_ids, powerup_ids, sudden.elapsed)
	else:
		_apply_sudden_ring(new_cells, bomb_ids, powerup_ids)


## One path for host and clients: clear soft walls, swallow bombs and powerups, paint fire.
## The shrink ring consumes bombs; it does not detonate them.
func _apply_sudden_ring(cells: Array, bomb_ids: PackedInt32Array, powerup_ids: PackedInt32Array) -> void:
	var cleared: Array[Vector2i] = []
	for c in cells:
		sudden.lethal[c] = true
		if c.y < 0 or c.y >= ROWS or c.x < 0 or c.x >= COLS:
			continue
		if grid[c.y][c.x] == Cell.SOFT:
			grid[c.y][c.x] = Cell.EMPTY
			cleared.append(c)
	for i in bomb_ids.size():
		var bid := int(bomb_ids[i])
		bombs.erase(bid)
		var bn := entities.get_node_or_null("Bomb_%d" % bid)
		if bn:
			bn.queue_free()
	for i in powerup_ids.size():
		_remove_powerup(int(powerup_ids[i]))
	if not cleared.is_empty():
		_repaint_cells(cleared)
	_add_sd_visuals(cells)
	if bomb_ids.size() > 0:
		_refresh_stats_hud()


func _sync_match_clock(delta: float) -> void:
	if not Net.is_online() or match_over:
		return
	if sudden.elapsed < SuddenDeath.START_AT - 30.0:
		return
	_clock_sync_wait -= delta
	if _clock_sync_wait > 0.0:
		return
	_clock_sync_wait = 1.0
	_rpc_sync_match_clock.rpc(sudden.elapsed, sudden.active)


func _kill_players_on_lethal() -> void:
	for peer_id in player_nodes.keys():
		if not alive.get(peer_id, false):
			continue
		var cell: Vector2i = player_nodes[peer_id].get_meta("cell")
		if sudden.is_lethal(cell):
			_kill_player(peer_id)


func _kill_player(peer_id: int) -> void:
	if not alive.get(peer_id, false):
		return
	alive[peer_id] = false
	if Net.is_online():
		_rpc_player_died.rpc(peer_id)
	else:
		_show_death(peer_id)
		_refresh_spectator_hud()
	_check_winner()


@rpc("authority", "call_local", "reliable")
func _rpc_sudden_death_start(elapsed: float) -> void:
	sudden.elapsed = elapsed
	_on_sudden_death_started()


func _on_sudden_death_started() -> void:
	sudden.active = true
	_sd_hud_key = ""
	if status_label:
		status_label.text = "⚠ 突然死亡！"
	_refresh_sudden_death_hud()


@rpc("authority", "reliable")
func _rpc_sync_match_clock(elapsed: float, is_active: bool) -> void:
	sudden.elapsed = elapsed
	if is_active:
		sudden.active = true
	_sd_hud_key = ""
	_refresh_sudden_death_hud()


@rpc("authority", "call_local", "reliable")
func _rpc_sudden_death_add(xy: PackedInt32Array, bomb_ids: PackedInt32Array, powerup_ids: PackedInt32Array, elapsed: float) -> void:
	sudden.elapsed = elapsed
	_apply_sudden_ring(BlastRules.packed_to_cells(xy), bomb_ids, powerup_ids)


func _add_sd_visuals(cells: Array) -> void:
	for c in cells:
		var key := "%d,%d" % [c.x, c.y]
		if _sd_visuals.has(key):
			continue
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(2, 2), Vector2(TILE - 2, 2), Vector2(TILE - 2, TILE - 2), Vector2(2, TILE - 2)
		])
		poly.position = Vector2(c.x * TILE, c.y * TILE)
		poly.color = Color(0.95, 0.25, 0.1, 0.72)
		poly.z_index = 2
		fx_layer.add_child(poly)
		_sd_visuals[key] = poly


func _clear_sd_visuals() -> void:
	for key in _sd_visuals.keys():
		var n: Node = _sd_visuals[key]
		if is_instance_valid(n):
			n.queue_free()
	_sd_visuals.clear()


func _refresh_sudden_death_hud() -> void:
	if sd_label == null:
		return
	var key := "hide"
	var text := ""
	if not match_over:
		if sudden.active:
			key = "active"
			text = "突然死亡 · 安全区收缩中"
		else:
			var left: float = maxf(0.0, SuddenDeath.START_AT - sudden.elapsed)
			if left <= 30.0 and left > 0.0:
				key = "cd:%d" % int(ceili(left))
				text = "突然死亡倒计时 %d 秒" % int(ceili(left))
	if key == _sd_hud_key:
		return
	_sd_hud_key = key
	sd_label.visible = key != "hide"
	if key != "hide":
		sd_label.text = text


# --- Combat / end -------------------------------------------------------------

func _kill_players_in(hit_cells: Array[Vector2i]) -> void:
	for peer_id in player_nodes.keys():
		if not alive.get(peer_id, false):
			continue
		var cell: Vector2i = player_nodes[peer_id].get_meta("cell")
		if cell in hit_cells:
			_kill_player(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_player_died(peer_id: int) -> void:
	alive[peer_id] = false
	_show_death(peer_id)
	_refresh_spectator_hud()


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
		if GameState.players.size() == 1 and living.size() == 1:
			return
		match_over = true
		var winner_name := "平局 / 全灭"
		if living.size() == 1:
			var wid: int = living[0]
			winner_name = str(GameState.players.get(wid, {}).get("name", wid))
		if Net.is_online():
			_rpc_match_over.rpc(winner_name)
		else:
			_show_end_screen(winner_name)


func _show_end_screen(winner_name: String) -> void:
	status_label.text = "对局结束：%s 获胜！" % winner_name
	end_title.text = "对局结束\n%s 获胜！" % winner_name
	end_panel.visible = true
	rematch_btn.disabled = false
	_refresh_spectator_hud()
	if Net.is_online() and Net.is_client:
		rematch_btn.text = "再来一局（请求主机）"
	else:
		rematch_btn.text = "再来一局"


@rpc("authority", "call_local", "reliable")
func _rpc_match_over(winner_name: String) -> void:
	match_over = true
	_show_end_screen(winner_name)


func _on_rematch() -> void:
	if Net.is_online() and not Net.is_authority():
		_rpc_request_rematch.rpc_id(1)
		status_label.text = "已请求再来一局…"
		return
	_restart_match()


@rpc("any_peer", "reliable")
func _rpc_request_rematch() -> void:
	if not Net.is_authority():
		return
	_restart_match()


func _restart_match() -> void:
	if not Net.is_authority():
		return
	if GameState.players.is_empty():
		return
	soft_seed = randi()
	bombs.clear()
	next_bomb_id = 1
	next_powerup_id = 1
	sudden.reset()
	_clear_sd_visuals()
	_clear_powerups()
	_clear_bomb_visuals()
	_init_all_stats()
	if Net.is_online():
		_rpc_setup_match.rpc(soft_seed, GameState.players)
	else:
		_rpc_setup_match(soft_seed, GameState.players)
	status_label.text = "再来一局！"


func _on_back() -> void:
	if Net.is_online() and Net.is_client:
		Net.close()
	GameState.in_match = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _refresh_stats_hud() -> void:
	if stats_label == null:
		return
	var my_id := _local_control_id()
	if my_id == 0 or not player_stats.has(my_id):
		if my_id == 0:
			stats_label.text = ""
			return
		player_stats[my_id] = _default_stats()
	var st: Dictionary = player_stats[my_id]
	var b: int = int(st.get("bombs", BASE_BOMBS))
	var r: int = int(st.get("range", BASE_BLAST))
	var s: int = int(st.get("speed", 0))
	var k: int = int(st.get("kick", 0))
	var placed := _count_bombs_owned(my_id)
	var kick_txt := "开" if k > 0 else "关"
	stats_label.text = "炸弹 %d/%d  ·  火力 %d  ·  移速 Lv%d  ·  踢弹 %s" % [placed, b, r, s, kick_txt]


func _refresh_spectator_hud() -> void:
	if spec_label == null:
		return
	var my_id := _local_control_id()
	if my_id == 0:
		spec_label.visible = false
		return
	if match_over:
		spec_label.visible = false
		return
	if alive.get(my_id, true):
		spec_label.visible = false
		return
	spec_label.visible = true
	spec_label.text = "已阵亡 · 观战中"
