extends SceneTree
## 无界面：网页默认加入地址。桌面仍是 127.0.0.1:9080；本机页面同主机，其余连杭州。
## 运行：godot --headless --path . -s res://scripts/verify_net.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var net := root.get_node("Net")
	if not _check_desktop(net):
		quit(1)
		return
	if not _check_web_branches(net):
		quit(1)
		return
	if not _check_source():
		quit(1)
		return
	print("[verify_net] 成功")
	quit(0)


func _check_desktop(net) -> bool:
	if OS.has_feature("web"):
		push_error("[verify_net] 失败：这个脚本要在桌面无界面下跑")
		return false
	var addr := str(net.get_default_join_address())
	var want := "%s:%d" % [net.DEFAULT_HOST, net.DEFAULT_PORT]
	if addr != want:
		push_error("[verify_net] 失败：桌面默认地址 %s，期望 %s" % [addr, want])
		return false
	# 非网页平台读不到 location，函数本身应退回杭州，而不是旧的 wss://localhost/ws。
	if str(net._web_default_ws_url()) != str(net.PRODUCTION_WS_URL):
		push_error("[verify_net] 失败：非网页的 _web_default_ws_url 应是生产地址")
		return false
	print("[verify_net] 桌面默认地址通过：", addr)
	return true


func _check_web_branches(net) -> bool:
	var prod := str(net.PRODUCTION_WS_URL)
	if prod != "wss://bomberman.jopatk.top/ws":
		push_error("[verify_net] 失败：生产地址被改掉了 %s" % prod)
		return false
	var locals := [
		["localhost", false, "ws://localhost/ws"],
		["localhost:8060", true, "wss://localhost:8060/ws"],
		["  LOCALHOST:9  ", false, "ws://LOCALHOST:9/ws"],
		["127.0.0.1", false, "ws://127.0.0.1/ws"],
		["127.0.0.1:8000", true, "wss://127.0.0.1:8000/ws"],
		["[::1]", false, "ws://[::1]/ws"],
		["[::1]:8080", true, "wss://[::1]:8080/ws"],
		["::1", false, "ws://::1/ws"],
	]
	for row in locals:
		if not _expect(net, str(row[0]), bool(row[1]), str(row[2])):
			return false
	var remote := [
		"",
		"   ",
		"bilibili.com",
		"www.bilibili.com",
		"toy.bilibili.com",
		"bomberman.jopatk.top",
		"localhost.evil.com",
		"127.0.0.1.nip.io",
		"127.0.0.2",
		"notlocalhost",
	]
	for host in remote:
		if not _expect(net, host, true, prod):
			return false
		if net.is_local_web_host(host):
			push_error("[verify_net] 失败：%s 不应算本机" % host)
			return false
	print("[verify_net] 网页地址分支通过")
	return true


func _expect(net, host: String, https: bool, want: String) -> bool:
	var got := str(net.resolve_web_join_url(host, https))
	if got != want:
		push_error("[verify_net] 失败：host=%s https=%s -> %s，期望 %s" % [host, https, got, want])
		return false
	return true


func _check_source() -> bool:
	var src := FileAccess.get_file_as_string("res://autoload/Net.gd")
	if src.find("PRODUCTION_WS_URL") < 0 or src.find("wss://bomberman.jopatk.top/ws") < 0:
		push_error("[verify_net] 失败：Net.gd 缺少固定生产地址")
		return false
	if src.find("location.host") < 0:
		push_error("[verify_net] 失败：应仍读取 location.host，用来识别本机页面")
		return false
	if src.find('location.host + "%s"') >= 0 or src.find('p + "//" + location.host') >= 0:
		push_error("[verify_net] 失败：还在用当前页面主机拼默认地址")
		return false
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	if preset.find("variant/thread_support=false") < 0:
		push_error("[verify_net] 失败：Web 导出线程应保持关闭")
		return false
	print("[verify_net] 源码约定通过")
	return true
