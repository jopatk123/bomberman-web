extends Node
## WebSocket 联机：专用服，或只发输入的瘦客户端。
## 浏览器能用（不用 ENet）。

signal server_started(port: int)
signal connected_to_server
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal disconnected

const DEFAULT_PORT := 9080
const DEFAULT_HOST := "127.0.0.1"
## 生产环境反代路径（nginx 转到专用服）。
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
	# 无界面启动时，同样认 `-- --server`。
	if want_server:
		var err := host(port)
		if err != OK:
			push_error("专用服绑定端口 %d 失败：%s" % [port, error_string(err)])
			get_tree().quit(1)
		else:
			print("[Net] 专用 WebSocket 服已监听端口 %d" % port)


## 桌面端是主机:端口。网页（HTTPS）是同主机的 wss://…/ws。
func get_default_join_address() -> String:
	if OS.has_feature("web"):
		return _web_default_ws_url()
	return "%s:%d" % [DEFAULT_HOST, DEFAULT_PORT]


func _web_default_ws_url() -> String:
	# JavaScriptBridge 只有网页平台才有。
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
	print("[Net] 正在监听 ws://0.0.0.0:%d（peer_id=%d）" % [port, multiplayer.get_unique_id()])
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
	print("[Net] 正在连接 %s ……" % url)
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	peer = null
	is_server = false
	is_client = false


## 命令行 `--server` / `--dedicated`。本机听服的玩家不算这种。
func is_dedicated() -> bool:
	if not is_server:
		return false
	for a in OS.get_cmdline_user_args():
		if a == "--server" or a == "--dedicated":
			return true
	return false


## 踢掉一个客户端。Peer 1 是服务器自己，永远不踢。
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
	# 默认装着 OfflineMultiplayerPeer，那不算一场联机会话。
	return is_server or is_client


func is_authority() -> bool:
	# 专用服（peer 1）或离线单机。
	if not is_online():
		return true
	return multiplayer.is_server()


func _on_peer_connected(id: int) -> void:
	print("[Net] 对端已连接：%d" % id)
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[Net] 对端已断开：%d" % id)
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	print("[Net] 已连上服务器，本机编号 %d" % multiplayer.get_unique_id())
	connected_to_server.emit()


func _on_connection_failed() -> void:
	print("[Net] 连接失败")
	close()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[Net] 服务器已断开")
	close()
	disconnected.emit()
