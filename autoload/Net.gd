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
## 网页导出的默认联机地址。页面挂在小玩具或别的 CDN 上时也走杭州，不跟 location.host。
const PRODUCTION_WS_URL := "wss://bomberman.jopatk.top/ws"

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


## 桌面端是 127.0.0.1:9080。网页导出默认连杭州；本机页面仍连当前主机的 /ws。
func get_default_join_address() -> String:
	if OS.has_feature("web"):
		return _web_default_ws_url()
	return "%s:%d" % [DEFAULT_HOST, DEFAULT_PORT]


## 纯判断，方便无界面脚本覆盖本机 / 线上两条分支。page_host 用 location.host（可带端口）。
func resolve_web_join_url(page_host: String, https: bool) -> String:
	var host := page_host.strip_edges()
	if not is_local_web_host(host):
		return PRODUCTION_WS_URL
	var scheme := "wss" if https else "ws"
	return "%s://%s%s" % [scheme, host, WEB_WS_PATH]


## localhost、127.0.0.1、::1（可带端口）算本机页面。其它域名，包括小玩具，都不是。
func is_local_web_host(page_host: String) -> bool:
	var name := _web_page_hostname(page_host)
	return name == "localhost" or name == "127.0.0.1" or name == "::1"


func _web_page_hostname(page_host: String) -> String:
	var host := page_host.strip_edges().to_lower()
	if host.begins_with("["):
		var end := host.find("]")
		if end <= 1:
			return ""
		return host.substr(1, end - 1)
	# 只有「一个冒号 + 端口」才切开，避免把裸 IPv6 切坏。
	var colon := host.find(":")
	if colon >= 0 and host.find(":", colon + 1) < 0:
		var port := host.substr(colon + 1)
		if port.is_empty() or port.is_valid_int():
			return host.substr(0, colon)
	return host


func _web_default_ws_url() -> String:
	# 读不到页面地址时连杭州。小玩具上比误连 localhost 安全。
	if not OS.has_feature("web"):
		return PRODUCTION_WS_URL
	# JavaScriptBridge 只有网页导出才有。这里只取 host 和协议，地址由 resolve_web_join_url 决定。
	var js := "(() => { var loc = (typeof location !== 'undefined') ? location : null; var host = (loc && loc.host) ? String(loc.host) : ''; var https = !!(loc && loc.protocol === 'https:'); return host + '\\n' + (https ? '1' : '0'); })()"
	var result = JavaScriptBridge.eval(js, true)
	if result == null:
		return PRODUCTION_WS_URL
	var raw := str(result)
	if raw.is_empty() or raw == "null" or raw == "undefined":
		return PRODUCTION_WS_URL
	var nl := raw.find("\n")
	if nl < 0:
		return PRODUCTION_WS_URL
	return resolve_web_join_url(raw.substr(0, nl), raw.substr(nl + 1) == "1")


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
