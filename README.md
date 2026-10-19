# 摸鱼炸弹人（Bomberman Web）

Godot **4.7.2** 起步工程：2D 炸弹人 + **WebSocket** 联机（浏览器可用）+ **专用服务器权威**。

适合同事上班摸鱼：一局几分钟，浏览器打开就能进。主机可跑在杭州服务器上。

## 架构

- **传输**：`WebSocketMultiplayerPeer`（**不用 ENet**，HTML5 导出可用）
- **权威**：专用服务器（或本地「创建房间」的 listen-server）模拟格子 / 炸弹 / 死亡
- **客户端**：发输入 RPC，收状态同步
- **渲染**：GL Compatibility（Web 友好）
- **默认端口**：`9080`（`ws://host:9080`）

## 目录

```
bomberman-web/
  autoload/Net.gd          # WebSocket host/join
  autoload/GameState.gd    # 房间玩家列表
  scenes/lobby.tscn        # 大厅（主场景）
  scenes/game.tscn         # 对局
  scripts/lobby.gd
  scripts/game_root.gd     # 13×11 地图、权威模拟
  scripts/player.gd        # 玩家色块视觉
  scripts/bomb.gd          # 炸弹视觉
  scripts/verify_project.gd
  project.godot
  README.md
```

## 本地怎么跑

Godot 二进制（本机云电脑）：

```bash
GODOT=/home/box/.local/bin/godot
PROJECT=/workspace/bomberman-web
```

### 1）编辑器里随便点点

```bash
$GODOT --path "$PROJECT" --editor
```

或直接运行：

```bash
$GODOT --path "$PROJECT"
```

### 2）单机冒烟（无网络）

进大厅点 **「单机测试（无 AI）」**。WASD 移动，空格放雷。

### 3）双窗口联机（listen-server）

终端 A（主机，也当玩家）：

```bash
$GODOT --path "$PROJECT"
# 大厅：昵称 → 创建房间（端口 9080）→ 等人 → 开始对局
```

终端 B（客户端）：

```bash
$GODOT --path "$PROJECT"
# 大厅：加入 127.0.0.1:9080 → 主机点开始（或客户端点「请求开始对局」）
```

### 4）无界面专用服务器 + 图形客户端

```bash
# 服务器（权威，不占玩家位；≥2 客户端后自动开局）
$GODOT --headless --path "$PROJECT" -- --server --port=9080

# 客户端 ×2（另开两个进程/窗口）
$GODOT --path "$PROJECT"
# 加入 127.0.0.1:9080
```

用户参数在 `--` 之后：`--server`、`--port=9080`。

### 5）校验脚本能否加载

```bash
$GODOT --headless --path "$PROJECT" --script res://scripts/verify_project.gd
# 或
$GODOT --headless --path "$PROJECT" --check-only
```

## 操作

| 键 | 作用 |
|----|------|
| WASD / 方向键 | 按格移动 |
| 空格 | 放炸弹（每人同时最多 1 颗，炸完再放） |

地图：13×11；边框 + 间隔硬墙；随机软墙；四角出生点（最多 4 人）。引信约 2 秒，十字爆炸范围 2 格，可炸软墙、可连锁。

## 杭州部署大纲（本任务不实际部署）

1. **静态网页**：用 Godot 导出 **Web**（HTML5）到例如 `/var/www/bomberman/`，Nginx 托管。
2. **专用服**：同一台机（或内网）跑：
   ```bash
   godot --headless --path /opt/bomberman-web -- --server --port=9080
   ```
3. **反代 WebSocket**（示例）：
   ```nginx
   location /ws/ {
       proxy_pass http://127.0.0.1:9080/;
       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection "upgrade";
   }
   ```
   客户端加入地址改为 `wss://your.domain/ws/`（需在导出/大厅默认地址里配置；本地仍用 `ws://IP:9080`）。
4. **防火墙**：放行 80/443；若直连 WS 则放行 `9080`。
5. **注意**：浏览器页面若是 **HTTPS**，WebSocket 须用 **WSS**（否则混合内容会被拦）。

## 导出模板（可能尚未安装）

本环境若未装 Web 导出模板，编辑器里导出会失败。Godot **4.7.2** 官方模板：

- 发布页：https://github.com/godotengine/godot/releases/tag/4.7.2-stable  
- 文件名类似：`Godot_v4.7.2-stable_export_templates.tpz`  
- 安装：编辑器 → 编辑器设置 → Export → 下载，或把 tpz 解到  
  `~/.local/share/godot/export_templates/4.7.2.stable/`

未装模板前：仍可用 **桌面/无界面** 在本机联机测玩；浏览器导出等模板就绪后再做。

## 已知限制（v1）

- 无 AI、无道具（火焰鞋/多雷等）
- 美术为色块 / Polygon2D
- 未做断线重连、观战、房间列表
- 移动为「按一下走一格」，便于同步，手感偏棋盘
- 未在本任务中部署到杭州；未强制下载导出模板

## 后续可加

- 道具与多雷、更长爆炸
- 房间码 / 大厅列表
- WebRTC 数据通道（可减少对自建 WS 的依赖，复杂度更高）
