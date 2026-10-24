extends Node2D
## Match conductor: input → match rules → RPC → MatchBoard / MatchHud.
## Grid rules live in scripts/match/. This script owns the running dictionaries
## and is the only place in a match that sends @rpc.
##
## PlayerStats — caps, pickup, stat packs.
## BombRecord — bomb dictionary shape.
## PowerupDrop — soft-wall drops.
## MatchEnd — win, draw, rematch, forfeit decisions.
## MatchSession — leave, kick, disconnect, forfeit apply, empty dedicated room.
## BlastRules / SuddenDeath / KickRules / Arena / MatchBot / MatchFill / MovePredict — as before.
## MatchFill adds bots at setup time. The authority ticks them; clients only render.
## MatchBoard paints tiles and entities. MatchHud paints labels.
## ClientPredict stores the local move chain and bomb ghost.

const TILE := 48
const COLS := 13
const ROWS := 11
const BOMB_FUSE := 2.0
const BASE_BLAST := 2
const BASE_BOMBS := 1
const MAX_BOMBS := 5
const MAX_RANGE := 6
const MAX_SPEED_LVL := 4
const KICK_SLIDE_INTERVAL := 0.07

enum Cell { EMPTY = 0, HARD = 1, SOFT = 2 }
enum PKind { BOMB = 0, RANGE = 1, SPEED = 2, KICK = 3, PIERCE = 4 }

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
var map_id: int = 0
## peer_id -> player node
var player_nodes: Dictionary = {}
## bomb_id -> BombRecord
var bombs: Dictionary = {}
var next_bomb_id: int = 1
## powerup_id -> {x,y,kind}
var powerups: Dictionary = {}
var next_powerup_id: int = 1
## peer_id -> PlayerStats
var player_stats: Dictionary = {}
var alive: Dictionary = {} # peer_id -> bool
var match_over: bool = false
## Client-side input cooldown; server also tracks per-player move_cd
var _local_move_cd: float = 0.0
var sudden: SuddenDeath = SuddenDeath.new()
## Cells hit by blasts during the current move, so stepping into that flame kills.
var _blast_hits: Array[Vector2i] = []
## Seconds until the next authority clock sync during the countdown window.
var _clock_sync_wait: float = 0.0
var _board := MatchBoard.new()
var _hud := MatchHud.new()
var _predict := ClientPredict.new()
var _session := MatchSession.new()
## Set from MatchHost before this node enters the tree. Empty for offline solo.
var room_code: String = ""
## Fighters for this round, including bots. Lobby GameState keeps humans only.
var match_roster: Dictionary = {}
var _sfx: Node

## Forwarded so existing checks can read the board's fire polygons.
var _sd_visuals: Dictionary:
	get:
		return _board.sd_visuals

## Forwarded so existing checks can read the ghost the predictor is showing.
var _ghost_node: Node2D:
	get:
		return _predict.ghost


func _ready() -> void:
	if has_meta("room_code"):
		room_code = str(get_meta("room_code"))
	_board.bind(map_layer, entities, powerups_layer, fx_layer, COLS, ROWS)
	_hud.bind(
		status_label, stats_label, spec_label, help_label, sd_label,
		end_panel, end_title, rematch_btn, back_btn, lobby_btn
	)
	back_btn.pressed.connect(_on_back)
	rematch_btn.pressed.connect(_on_rematch)
	lobby_btn.pressed.connect(_on_back)
	_hud.prepare(Net.is_dedicated())
	if not Net.peer_disconnected.is_connected(_on_match_peer_out):
		Net.peer_disconnected.connect(_on_match_peer_out)
	if not Net.disconnected.is_connected(_on_net_disconnected):
		Net.disconnected.connect(_on_net_disconnected)
	if not GameState.kicked.is_connected(_on_kicked_out):
		GameState.kicked.connect(_on_kicked_out)
	if not GameState.player_list_changed.is_connected(_on_roster_changed):
		GameState.player_list_changed.connect(_on_roster_changed)
	_sfx = preload("res://scripts/sfx.gd").new()
	add_child(_sfx)
	if Net.is_dedicated():
		visible = false
		hud.visible = false
	map_id = Arena.resolve_map_id(_room_map_id())
	grid = Arena.build_base_grid(map_id)
	if Net.is_authority():
		map_id = Arena.resolve_map_id(_room_map_id())
		soft_seed = _resolve_seed()
		_publish_seed()
		var roster := _roster().duplicate(true)
		if Net.is_online():
			_notify_room("_rpc_setup_match", [soft_seed, roster, map_id])
		else:
			_rpc_setup_match(soft_seed, roster, map_id)
	else:
		_hud.set_status("等待主机同步地图…")
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
			_tick_bot(delta)
	elif not match_over:
		# HUD clock only. Lethal cells arrive from the host.
		sudden.advance_elapsed(delta)
		sudden.advance_pulse_display(delta)
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
	if Input.is_action_pressed("move_up"):
		dir = Vector2i(0, -1)
	elif Input.is_action_pressed("move_down"):
		dir = Vector2i(0, 1)
	elif Input.is_action_pressed("move_left"):
		dir = Vector2i(-1, 0)
	elif Input.is_action_pressed("move_right"):
		dir = Vector2i(1, 0)
	if dir != Vector2i.ZERO and _local_move_cd <= 0.0:
		_local_move_cd = _cooldown_for(my_id)
		if Net.is_authority():
			_apply_move(my_id, dir.x, dir.y)
		else:
			_predict_step(dir)
			_rpc_request_move.rpc_id(1, dir.x, dir.y)
	if Input.is_action_just_pressed("place_bomb"):
		if Net.is_authority():
			_try_place_bomb(my_id)
		else:
			_show_bomb_ghost(_pred_tip())
			_rpc_request_bomb.rpc_id(1)


func _local_control_id() -> int:
	if not Net.is_online():
		return 1
	var id := Net.get_peer_id()
	if _roster().has(id):
		return id
	return 0


func _cooldown_for(peer_id: int) -> float:
	return PlayerStats.cooldown(player_stats.get(peer_id, {}))


func _default_stats() -> Dictionary:
	return PlayerStats.default_stats()


func _init_all_stats() -> void:
	player_stats.clear()
	for raw in MatchFill.seat_order(_participants()):
		player_stats[int(raw)] = _default_stats()


func _roster() -> Dictionary:
	if room_code != "" and GameState.rooms.has(room_code):
		return GameState.rooms[room_code].players
	return GameState.players


## Match fighters. Falls back to the human roster before the first setup RPC.
func _participants() -> Dictionary:
	if not match_roster.is_empty():
		return match_roster
	return _roster()


func _room_map_id() -> int:
	if room_code != "" and GameState.rooms.has(room_code):
		return int(GameState.rooms[room_code].map_id)
	return GameState.map_id


func _resolve_seed() -> int:
	if room_code != "" and GameState.rooms.has(room_code):
		return GameState.resolve_room_seed(room_code)
	return GameState.resolve_soft_seed()


func _publish_seed() -> void:
	# Keep lobby RANDOM preference so rematch can roll a new layout.
	var preferred := _room_map_id()
	if room_code != "" and GameState.rooms.has(room_code):
		if not Arena.is_random_map(preferred):
			GameState.rooms[room_code].map_id = map_id
		GameState.rooms[room_code].soft_seed = soft_seed
	if room_code == "" or GameState.room_code == room_code:
		if not Arena.is_random_map(preferred):
			GameState.map_id = map_id
		GameState.soft_seed = soft_seed


func _host_id() -> int:
	if room_code != "" and GameState.rooms.has(room_code):
		return int(GameState.rooms[room_code].host_peer_id)
	return GameState.host_peer_id


func _sorted_roster() -> Array:
	return MatchFill.seat_order(_participants())


func _color_for(peer_id: int) -> Color:
	var info: Dictionary = _participants().get(peer_id, {})
	var idx := int(info.get("color_idx", 0)) % GameState.PLAYER_COLORS.size()
	return GameState.PLAYER_COLORS[idx]


func _status_line(prefix: String) -> String:
	var map_label := Arena.map_name(map_id)
	var names := MatchFill.bot_names(_participants())
	if names.is_empty():
		return "%s · 地图：%s" % [prefix, map_label]
	return "%s · %s · 地图：%s" % [prefix, "、".join(names), map_label]


## Authority-only. Runs locally and on peers who are in this room.
func _notify_room(method: StringName, args: Array = []) -> void:
	if not Net.is_online():
		callv(method, args)
		return
	callv(method, args)
	var me := multiplayer.get_unique_id()
	for raw in _roster().keys():
		var pid := int(raw)
		if pid <= 0 or pid == me:
			continue
		multiplayer.rpc(pid, self, method, args)


@rpc("authority", "call_local", "reliable")
func _rpc_setup_match(seed: int, players_snap: Dictionary, p_map_id: int = 0) -> void:
	# Bots are match fighters only. install_roster keeps the lobby seat list human.
	match_roster = MatchFill.fill(players_snap)
	GameState.install_roster(room_code, MatchFill.humans(match_roster))
	soft_seed = seed
	map_id = Arena.clamp_map_id(p_map_id)
	_publish_seed()
	match_over = false
	_hud.hide_end()
	sudden.reset()
	_clear_sd_visuals()
	_clear_powerups()
	_clear_bomb_visuals()
	bombs.clear()
	next_bomb_id = 1
	next_powerup_id = 1
	_hud.invalidate_sudden_death()
	_clock_sync_wait = 0.0
	alive.clear()
	grid = Arena.build_match_grid(map_id, soft_seed)
	_init_all_stats()
	_draw_map()
	_spawn_all_players()
	if not Net.is_authority():
		_hud.set_status(_status_line("对局进行中"))
	else:
		_hud.set_status(_status_line("对局进行中（主机权威）"))
	for id in _participants().keys():
		alive[id] = true
	_predict.clear_chain()
	_clear_bomb_ghost()
	var me := _local_control_id()
	if _uses_prediction() and player_nodes.has(me):
		_predict.seed(player_nodes[me].get_meta("cell"))
	_refresh_stats_hud()
	_refresh_sudden_death_hud()


func _spawn_all_players() -> void:
	_board.clear_players()
	player_nodes.clear()
	var ids := _sorted_roster()
	var spawns := Arena.spawn_cells()
	var i := 0
	for peer_id in ids:
		if i >= spawns.size():
			break
		var cell: Vector2i = spawns[i]
		var p := _make_player_visual(peer_id, cell)
		p.set_meta("bot", MatchFill.is_bot_id(int(peer_id)))
		entities.add_child(p)
		player_nodes[peer_id] = p
		alive[peer_id] = true
		if not player_stats.has(peer_id):
			player_stats[peer_id] = _default_stats()
		i += 1


func _make_player_visual(peer_id: int, cell: Vector2i) -> Node2D:
	var display := str(_participants().get(peer_id, {}).get("name", peer_id))
	return _board.make_player(peer_id, cell, _color_for(peer_id), display)


func _draw_map() -> void:
	_board.draw_map(grid, self)


func _repaint_cells(cells: Array) -> void:
	_board.repaint_cells(grid, cells, self)


func _cell_to_pos(cell: Vector2i) -> Vector2:
	return _board.cell_to_pos(cell)


@rpc("any_peer", "reliable")
func _rpc_request_move(dx: int, dy: int) -> void:
	if not Net.is_authority() or match_over:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var step := _unit_step(dx, dy)
	if step == Vector2i.ZERO:
		return
	var before := Vector2i.ZERO
	var had := player_nodes.has(sender)
	if had:
		before = player_nodes[sender].get_meta("cell")
	_apply_move(sender, step.x, step.y)
	# Rejected steps still echo the host cell so a predicted pawn snaps back.
	if had and player_nodes.has(sender) and player_nodes[sender].get_meta("cell") == before:
		_notify_room("_rpc_set_player_cell", [sender, before.x, before.y])


## One orthogonal tile. Anything else (including diagonals and teleports) is ignored.
func _unit_step(dx: int, dy: int) -> Vector2i:
	if absi(dx) + absi(dy) != 1:
		return Vector2i.ZERO
	return Vector2i(clampi(dx, -1, 1), clampi(dy, -1, 1))


func _apply_move(peer_id: int, dx: int, dy: int) -> void:
	var step := _unit_step(dx, dy)
	if step == Vector2i.ZERO:
		return
	dx = step.x
	dy = step.y
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
		_notify_room("_rpc_set_player_cell", [peer_id, cell.x, cell.y])
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
		_notify_room("_rpc_set_bomb_cell", [bid, cell.x, cell.y])
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
	_board.move_bomb(bid, cell)


@rpc("authority", "call_local", "reliable")
func _rpc_set_player_cell(peer_id: int, x: int, y: int) -> void:
	if not player_nodes.has(peer_id):
		return
	var node: Node2D = player_nodes[peer_id]
	var cell := Vector2i(x, y)
	node.set_meta("cell", cell)
	if _uses_prediction() and peer_id == _local_control_id():
		node.position = _cell_to_pos(_predict.ack_cell(cell))
	else:
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
	return BombRecord.count_owned(bombs, peer_id)


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
	# Snapshot pierce at place time. A later pickup must not change this bomb.
	var pierce: int = 1 if int(st.get("pierce", 0)) > 0 else 0
	var bid := next_bomb_id
	next_bomb_id += 1
	# solid=false → owner may walk off; becomes solid once they leave
	bombs[bid] = BombRecord.make(cell.x, cell.y, peer_id, blast, pierce)
	if Net.is_online():
		_notify_room("_rpc_spawn_bomb", [bid, cell.x, cell.y, peer_id, blast, pierce])
	else:
		_spawn_bomb_visual(bid, cell)
	_refresh_stats_hud()


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_bomb(bid: int, x: int, y: int, owner: int, blast: int = BASE_BLAST, pierce: int = 0) -> void:
	if not Net.is_authority():
		bombs[bid] = BombRecord.make(x, y, owner, blast, pierce)
	_spawn_bomb_visual(bid, Vector2i(x, y))
	if owner == _local_control_id():
		_clear_bomb_ghost()
	_refresh_stats_hud()


func _spawn_bomb_visual(bid: int, cell: Vector2i) -> void:
	_board.spawn_bomb(bid, cell)


func _clear_bomb_visuals() -> void:
	_board.clear_bombs()


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
	var pierce: bool = int(bombs[bid].get("pierce", 0)) > 0
	bombs.erase(bid)
	var computed := BlastRules.compute_rays(grid, Vector2i(bx, by), blast, COLS, ROWS, pierce)
	var hit_cells: Array[Vector2i] = computed.hit
	_blast_hits.append_array(hit_cells)
	var cleared_soft: Array[Vector2i] = computed.cleared_soft
	for c in cleared_soft:
		grid[c.y][c.x] = Cell.EMPTY
	var spawned: Array = []
	if Net.is_authority():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var drop: Dictionary = PowerupDrop.roll(cleared_soft, powerups, sudden.lethal, rng, next_powerup_id)
		spawned = drop.spawned
		next_powerup_id = int(drop.next_id)
	# Chain reaction when blast hits another bomb
	var chained: Array = []
	for other_id in bombs.keys():
		var oc := Vector2i(int(bombs[other_id].x), int(bombs[other_id].y))
		if oc in hit_cells:
			chained.append(other_id)
	var clear_pack := BlastRules.cells_to_packed(cleared_soft)
	var spawn_pack := _powerups_to_packed(spawned)
	if Net.is_online():
		_notify_room("_rpc_bomb_boom", [bid, BlastRules.cells_to_packed(hit_cells), clear_pack, spawn_pack])
	else:
		_apply_boom_visual(bid, hit_cells, cleared_soft)
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
	return PowerupDrop.pack(spawned)


@rpc("authority", "call_local", "reliable")
func _rpc_bomb_boom(bid: int, hit_xy: PackedInt32Array, clear_xy: PackedInt32Array, spawn_xy: PackedInt32Array = PackedInt32Array()) -> void:
	bombs.erase(bid)
	var hit_cells: Array[Vector2i] = BlastRules.packed_to_cells(hit_xy)
	for i in range(0, clear_xy.size(), 2):
		var x: int = clear_xy[i]
		var y: int = clear_xy[i + 1]
		if y >= 0 and y < ROWS and x >= 0 and x < COLS:
			grid[y][x] = Cell.EMPTY
	var cleared_soft: Array[Vector2i] = BlastRules.packed_to_cells(clear_xy)
	_apply_boom_visual(bid, hit_cells, cleared_soft)
	_repaint_cells(cleared_soft)
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
			_notify_room("_rpc_remove_powerup", [pid])


func _apply_boom_visual(bid: int, hit_cells: Array[Vector2i], cleared_soft: Array = []) -> void:
	_board.play_boom(bid, hit_cells, _sfx, cleared_soft)


func _spawn_powerup_visual(pid: int, cell: Vector2i, kind: int) -> void:
	_board.spawn_powerup(pid, cell, kind)


func _clear_powerups() -> void:
	powerups.clear()
	_board.clear_powerup_nodes()


func _remove_powerup(pid: int) -> void:
	powerups.erase(pid)
	_board.remove_powerup(pid)


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
		_notify_room("_rpc_pickup", [peer_id, found, kind, _stats_pack(peer_id)])
	else:
		_refresh_stats_hud()
		if _sfx:
			_sfx.play_pickup()


func _stats_pack(peer_id: int) -> PackedInt32Array:
	return PlayerStats.pack(player_stats.get(peer_id, _default_stats()))


func _apply_powerup(peer_id: int, kind: int) -> void:
	var st: Dictionary = player_stats.get(peer_id, _default_stats())
	player_stats[peer_id] = PlayerStats.apply(st, kind)


@rpc("authority", "call_local", "reliable")
func _rpc_pickup(peer_id: int, powerup_id: int, kind: int, stats: PackedInt32Array) -> void:
	_remove_powerup(powerup_id)
	var prev: Dictionary = player_stats.get(peer_id, {})
	player_stats[peer_id] = PlayerStats.merge_pack(prev, kind, stats)
	_refresh_stats_hud()
	if _sfx:
		_sfx.play_pickup()
	if player_nodes.has(peer_id):
		var n: Node2D = player_nodes[peer_id]
		_board.pulse_player(n, func() -> bool: return alive.get(peer_id, false))


func _tick_sudden_death(delta: float) -> void:
	var r: Dictionary = sudden.tick(delta, COLS, ROWS, grid, Cell.HARD)
	if r.just_activated:
		if Net.is_online():
			_notify_room("_rpc_sudden_death_start", [sudden.elapsed])
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
		_notify_room("_rpc_sudden_death_add", [BlastRules.cells_to_packed(new_cells), bomb_ids, powerup_ids, sudden.elapsed, sudden.next_pulse_in()])
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
		_board.free_bomb(bid)
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
	_notify_room("_rpc_sync_match_clock", [sudden.elapsed, sudden.active, sudden.next_pulse_in()])


func _kill_players_on_lethal() -> void:
	for peer_id in player_nodes.keys():
		if not alive.get(peer_id, false):
			continue
		var cell: Vector2i = player_nodes[peer_id].get_meta("cell")
		if sudden.is_lethal(cell):
			_kill_player(peer_id)


func _kill_player(peer_id: int, reason: String = "") -> void:
	if not alive.get(peer_id, false):
		return
	alive[peer_id] = false
	if Net.is_online():
		_notify_room("_rpc_player_died", [peer_id, reason])
	else:
		_show_death(peer_id)
		if reason != "":
			_hud.set_status(reason)
		_refresh_spectator_hud()
	_check_winner()


@rpc("authority", "call_local", "reliable")
func _rpc_sudden_death_start(elapsed: float) -> void:
	sudden.elapsed = elapsed
	_on_sudden_death_started()


func _on_sudden_death_started() -> void:
	sudden.active = true
	_hud.invalidate_sudden_death()
	_hud.set_status("⚠ 突然死亡！")
	_refresh_sudden_death_hud()


@rpc("authority", "reliable")
func _rpc_sync_match_clock(elapsed: float, is_active: bool, pulse_left: float = -1.0) -> void:
	sudden.elapsed = elapsed
	if is_active:
		sudden.active = true
	if pulse_left >= 0.0:
		sudden.set_pulse_left(pulse_left)
	_hud.invalidate_sudden_death()
	_refresh_sudden_death_hud()


@rpc("authority", "call_local", "reliable")
func _rpc_sudden_death_add(xy: PackedInt32Array, bomb_ids: PackedInt32Array, powerup_ids: PackedInt32Array, elapsed: float, pulse_left: float = -1.0) -> void:
	sudden.elapsed = elapsed
	if pulse_left >= 0.0:
		sudden.set_pulse_left(pulse_left)
	_apply_sudden_ring(BlastRules.packed_to_cells(xy), bomb_ids, powerup_ids)


func _add_sd_visuals(cells: Array) -> void:
	_board.add_sudden_death(cells)


func _clear_sd_visuals() -> void:
	_board.clear_sudden_death()


func _refresh_sudden_death_hud() -> void:
	_hud.refresh_sudden_death(
		sudden.active, sudden.elapsed, SuddenDeath.START_AT, match_over, sudden.next_pulse_in()
	)


func _kill_players_in(hit_cells: Array[Vector2i]) -> void:
	for peer_id in player_nodes.keys():
		if not alive.get(peer_id, false):
			continue
		var cell: Vector2i = player_nodes[peer_id].get_meta("cell")
		if cell in hit_cells:
			_kill_player(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_player_died(peer_id: int, reason: String = "") -> void:
	alive[peer_id] = false
	_show_death(peer_id)
	if reason != "" and not match_over:
		_hud.set_status(reason)
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
	var result: Dictionary = MatchEnd.outcome(alive, _participants())
	if not bool(result.finished):
		return
	match_over = true
	var winner_name := str(result.winner_name)
	if Net.is_online():
		_notify_room("_rpc_match_over", [winner_name])
	else:
		_show_end_screen(winner_name)


func _show_end_screen(winner_name: String) -> void:
	_hud.show_end(winner_name)
	_refresh_spectator_hud()
	_refresh_rematch_button()


func _refresh_rematch_button() -> void:
	var me := _local_control_id()
	var allowed := can_request_rematch(Net.is_online(), me, _host_id(), _roster().size())
	_hud.refresh_rematch(allowed)


static func can_request_rematch(is_online: bool, peer_id: int, host_id: int, player_count: int) -> bool:
	return MatchEnd.can_request_rematch(is_online, peer_id, host_id, player_count)


@rpc("authority", "call_local", "reliable")
func _rpc_match_over(winner_name: String) -> void:
	match_over = true
	_show_end_screen(winner_name)


func _on_rematch() -> void:
	var me := _local_control_id()
	if not can_request_rematch(Net.is_online(), me, _host_id(), _roster().size()):
		return
	if Net.is_online() and not Net.is_authority():
		_rpc_request_rematch.rpc_id(1)
		return
	_restart_match()


@rpc("any_peer", "reliable")
func _rpc_request_rematch() -> void:
	if not Net.is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	if not can_request_rematch(true, sender, _host_id(), _roster().size()):
		return
	_restart_match()


func _restart_match() -> void:
	if not Net.is_authority():
		return
	var roster := _roster()
	if roster.is_empty():
		return
	if Net.is_online() and roster.size() < 2:
		return
	# RANDOM preference re-rolls layout; fixed map stays. Soft seed always new.
	map_id = Arena.resolve_map_id(_room_map_id())
	soft_seed = randi() & 0x7fffffff
	_publish_seed()
	bombs.clear()
	next_bomb_id = 1
	next_powerup_id = 1
	sudden.reset()
	_clear_sd_visuals()
	_clear_powerups()
	_clear_bomb_visuals()
	_init_all_stats()
	var snap := roster.duplicate(true)
	if Net.is_online():
		_notify_room("_rpc_setup_match", [soft_seed, snap, map_id])
	else:
		_rpc_setup_match(soft_seed, snap, map_id)
	_hud.set_status(_status_line("再来一局"))


func _on_back() -> void:
	_session.on_back(get_tree())


func _on_kicked_out(message: String) -> void:
	_session.on_kicked(get_tree(), message)


func _on_net_disconnected() -> void:
	_session.on_disconnected(get_tree())


func _on_roster_changed() -> void:
	if match_over:
		_refresh_rematch_button()


func _on_match_peer_out(id: int) -> void:
	_session.on_peer_out(id, _forfeit_peer)


## Drop a peer who left mid-match. Kill them before erasing the roster entry so a
## 2-player game still counts as a win, not as the solo "don't end" case.
func _forfeit_peer(id: int) -> void:
	_session.forfeit_peer(
		get_tree(), id, alive, match_over, _kill_player, _refresh_rematch_button,
		_roster(), room_code, _on_room_empty
	)


func _on_room_empty() -> void:
	GameState.dissolve_room(room_code)


func _refresh_stats_hud() -> void:
	var my_id := _local_control_id()
	if my_id != 0 and not player_stats.has(my_id):
		player_stats[my_id] = _default_stats()
	var placed := 0
	if my_id != 0:
		placed = _count_bombs_owned(my_id)
	_hud.refresh_stats(my_id, player_stats.get(my_id, {}), placed)


func _refresh_spectator_hud() -> void:
	var my_id := _local_control_id()
	var is_alive := true
	if my_id != 0:
		is_alive = bool(alive.get(my_id, true))
	_hud.refresh_spectator(my_id, match_over, is_alive)


func _uses_prediction() -> bool:
	return Net.is_online() and not Net.is_authority()


func _pred_tip() -> Vector2i:
	var fallback := Vector2i.ZERO
	var my_id := _local_control_id()
	if player_nodes.has(my_id):
		fallback = player_nodes[my_id].get_meta("cell")
	return _predict.tip(fallback)


func _predict_step(dir: Vector2i) -> void:
	var my_id := _local_control_id()
	if not player_nodes.has(my_id):
		return
	var origin: Vector2i = player_nodes[my_id].get_meta("cell")
	if not _predict.push_step(dir, origin, _can_predict_step):
		return
	player_nodes[my_id].position = _cell_to_pos(_predict.tip(origin))


## Empty tiles only. Kicks and other bombs wait for the host, then snap.
func _can_predict_step(dst: Vector2i) -> bool:
	if not _walkable(dst) or sudden.is_lethal(dst) or _bomb_id_at(dst) >= 0:
		return false
	var me := _local_control_id()
	for pid in player_nodes.keys():
		if int(pid) == me or not alive.get(pid, false):
			continue
		if player_nodes[pid].get_meta("cell") == dst:
			return false
	return true


func _show_bomb_ghost(cell: Vector2i) -> void:
	if not _can_predict_bomb(cell):
		return
	_predict.show_ghost(self, entities, cell, TILE)


func _can_predict_bomb(cell: Vector2i) -> bool:
	var my_id := _local_control_id()
	if my_id == 0:
		return false
	var st: Dictionary = player_stats.get(my_id, _default_stats())
	var max_b := clampi(int(st.get("bombs", BASE_BOMBS)), 1, MAX_BOMBS)
	if _count_bombs_owned(my_id) >= max_b or _bomb_id_at(cell) >= 0:
		return false
	return true


func _clear_bomb_ghost() -> void:
	_predict.clear_ghost()


## Authority only. One deterministic pass per bot, in seat order, from the same tick view.
func _tick_bot(_delta: float) -> void:
	if match_over:
		return
	for raw in MatchFill.bot_ids(_participants()):
		_tick_one_bot(int(raw))


func _tick_one_bot(id: int) -> void:
	if not alive.get(id, false) or not player_nodes.has(id):
		return
	var st: Dictionary = player_stats.get(id, _default_stats())
	if float(st.get("move_cd", 0.0)) > 0.0:
		return
	var decision := MatchBot.decide(_bot_view(id))
	var action := int(decision.get("action", MatchBot.Action.WAIT))
	if action == MatchBot.Action.BOMB:
		_try_place_bomb(id)
	elif action == MatchBot.Action.MOVE:
		_apply_move(id, int(decision.get("dx", 0)), int(decision.get("dy", 0)))


func _bot_view(bot_id: int) -> Dictionary:
	var cell: Vector2i = player_nodes[bot_id].get_meta("cell")
	var st: Dictionary = player_stats.get(bot_id, _default_stats())
	var max_b := clampi(int(st.get("bombs", BASE_BOMBS)), 1, MAX_BOMBS)
	var bomb_list: Array = []
	for b in bombs.values():
		bomb_list.append({
			"x": int(b.x),
			"y": int(b.y),
			"timer": float(b.get("timer", BOMB_FUSE)),
			"range": int(b.get("range", BASE_BLAST)),
			"pierce": int(b.get("pierce", 0)) > 0,
		})
	var others: Array[Vector2i] = []
	for pid in player_nodes.keys():
		if int(pid) == bot_id or not alive.get(pid, false):
			continue
		others.append(player_nodes[pid].get_meta("cell"))
	var lethal: Array[Vector2i] = []
	for key in sudden.lethal.keys():
		lethal.append(key)
	var drops: Array[Vector2i] = []
	for p in powerups.values():
		drops.append(Vector2i(int(p.x), int(p.y)))
	drops.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	return {
		"grid": grid,
		"cols": COLS,
		"rows": ROWS,
		"cell": cell,
		"blast_range": clampi(int(st.get("range", BASE_BLAST)), 1, MAX_RANGE),
		"pierce": int(st.get("pierce", 0)) > 0,
		"can_place": _count_bombs_owned(bot_id) < max_b and _bomb_id_at(cell) < 0,
		"bombs": bomb_list,
		"others": others,
		"lethal": lethal,
		"powerups": drops,
	}
