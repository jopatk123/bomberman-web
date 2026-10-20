extends Node
## WebSocket multiplayer: dedicated server or thin client.
## Browser-compatible (no ENet).

signal server_started(port: int)
signal connected_to_server
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal disconnected

const DEFAULT_PORT := 9080
const DEFAULT_HOST := "127.0.0.1"
## Production reverse-proxy path (nginx → dedicated server).
const WEB_WS_PATH := "/ws"

var peer: WebSocketMultiplayerPeer
var is_server: bool = false
var is_client: bool = false
var listen_port: int = DEFAULT_PORT


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_maybe_start_from_cmdline()


func _maybe_start_from_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	var want_server := false
	var port := DEFAULT_PORT
	for a in args:
		if a == "--server" or a == "--dedicated":
			want_server = true
		elif a.begins_with("--port="):
			port = int(a.get_slice("=", 1))
	# Also honor plain --headless launch with -- --server
	if want_server:
		var err := host(port)
		if err != OK:
			push_error("Dedicated server failed to bind port %d: %s" % [port, error_string(err)])
			get_tree().quit(1)
		else:
			print("[Net] Dedicated WebSocket server on port %d" % port)


## Desktop: host:port. Web (HTTPS page): wss://same-host/ws
func get_default_join_address() -> String:
	if OS.has_feature("web"):
		return _web_default_ws_url()
	return "%s:%d" % [DEFAULT_HOST, DEFAULT_PORT]


func _web_default_ws_url() -> String:
	# JavaScriptBridge is only available on the web platform.
	if not OS.has_feature("web"):
		return "wss://localhost%s" % WEB_WS_PATH
	var js := '(() => { const p = location.protocol === "https:" ? "wss:" : "ws:"; return p + "//" + location.host + "%s"; })()' % WEB_WS_PATH
	var result = JavaScriptBridge.eval(js, true)
	if result == null:
		return "wss://localhost%s" % WEB_WS_PATH
	var url := str(result)
	if url.is_empty() or url == "null" or url == "undefined":
		return "wss://localhost%s" % WEB_WS_PATH
	return url


func host(port: int = DEFAULT_PORT) -> Error:
	close()
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	is_client = false
	listen_port = port
	server_started.emit(port)
	print("[Net] Hosting on ws://0.0.0.0:%d (peer_id=%d)" % [port, multiplayer.get_unique_id()])
	return OK


func join(address: String = "") -> Error:
	close()
	if address.is_empty():
		address = get_default_join_address()
	var url := address.strip_edges()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://" + url
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	is_client = true
	print("[Net] Connecting to %s ..." % url)
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	peer = null
	is_server = false
	is_client = false


## Cmdline `--server` / `--dedicated`. The listen-server player is not this.
func is_dedicated() -> bool:
	if not is_server:
		return false
	for a in OS.get_cmdline_user_args():
		if a == "--server" or a == "--dedicated":
			return true
	return false


## Drop a client. Peer 1 is the server itself and is never kicked.
func disconnect_peer(peer_id: int) -> void:
	if peer == null or not is_server:
		return
	if peer_id <= 1:
		return
	if not multiplayer.get_peers().has(peer_id):
		return
	peer.disconnect_peer(peer_id)


func get_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null


func is_authority() -> bool:
	## Dedicated server (peer 1) or offline solo.
	if not is_online():
		return true
	return multiplayer.is_server()


func _on_peer_connected(id: int) -> void:
	print("[Net] Peer connected: %d" % id)
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[Net] Peer disconnected: %d" % id)
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	print("[Net] Connected to server as %d" % multiplayer.get_unique_id())
	connected_to_server.emit()


func _on_connection_failed() -> void:
	print("[Net] Connection failed")
	close()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[Net] Server disconnected")
	close()
	disconnected.emit()
