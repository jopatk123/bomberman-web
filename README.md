# 摸鱼炸弹人（Bomberman Web）

Godot **4.7.2**：2D 炸弹人 + **WebSocket** 联机（浏览器）+ **专用服务器权威**。

适合同事上班摸鱼。生产域名：`https://bomberman.jopatk.top`（杭州机部署）。

仓库：https://github.com/jopatk123/bomberman-web

## 架构

- **传输**：`WebSocketMultiplayerPeer`（不用 ENet）
- **权威**：专用服务器模拟格子 / 炸弹 / 死亡
- **客户端**：发输入 RPC，收状态同步
- **渲染**：GL Compatibility；Web 导出 **关闭线程**（无需 COOP/COEP）
- **本地端口**：`9080` → `ws://host:9080`
- **生产**：`wss://bomberman.jopatk.top/ws`（Nginx `/ws` → 游戏服 9080）

网页端大厅默认加入地址会自动变成 `wss://当前域名/ws`（见 `Net.get_default_join_address()`）。

## 目录

```
bomberman-web/
  autoload/Net.gd          # WebSocket host/join + Web 默认 WSS
  autoload/GameState.gd
  scenes/lobby.tscn        # 大厅（主场景）
  scenes/game.tscn
  scripts/…
  export_presets.cfg       # Web + Linux Server
  build/                   # 本地导出产物（gitignore）
    web/                   # HTML5
    server/                # Linux 专用服二进制
  deploy/
    Dockerfile             # targets: game | web
    docker-compose.yml
    nginx.conf             # 静态站 + /ws 反代
    build-images.sh
  project.godot
  README.md
```

## 本地怎么跑（桌面 / 无界面）

```bash
GODOT=/home/box/.local/bin/godot   # 或你的 godot 路径
PROJECT=/workspace/bomberman-web
```

### 单机

进大厅点 **「单机测试（无 AI）」**。WASD 移动，空格放雷。

### 无界面专用服 + 客户端

```bash
$GODOT --headless --path "$PROJECT" -- --server --port=9080
$GODOT --path "$PROJECT"   # 加入 127.0.0.1:9080（开两个）
```

## 导出（在云电脑 / 新加坡构建机）

已装官方模板目录：`~/.local/share/godot/export_templates/4.7.2.stable/`  
（来源：`Godot_v4.7.2-stable_export_templates.tpz`）

```bash
cd /workspace/bomberman-web
godot --headless --path . --export-release "Web" build/web/index.html
godot --headless --path . --export-release "Linux Server" build/server/bomberman-server.x86_64
chmod +x build/server/bomberman-server.x86_64
```

产物量级（约）：

| 路径 | 大小 |
|------|------|
| `build/web/index.wasm` | ~38 MB |
| `build/web/` 合计 | ~39 MB |
| `build/server/bomberman-server.x86_64` | ~71 MB |

## Docker 部署（推荐）

**原则**：在本机/新加坡导出 + 打镜像；杭州只 `docker load` / `compose up`，不在杭州编 Godot。

### 1）本机构建镜像

```bash
cd /workspace/bomberman-web
# 先完成上一节 Web + Linux Server 导出
./deploy/build-images.sh
# 或保存 tar 给杭州：
./deploy/build-images.sh --save
# → build/docker/bomberman-images.tar
```

手动等价：

```bash
docker compose -f deploy/docker-compose.yml build
docker save bomberman-web:latest bomberman-game:latest -o build/docker/bomberman-images.tar
```

### 2）杭州加载并启动

```bash
docker load -i bomberman-images.tar
# 仓库文件也要有（至少 deploy/docker-compose.yml）；或只用已 load 的镜像名
docker compose -f deploy/docker-compose.yml up -d
# 默认宿主机 HTTP：18080 → 容器 80
```

环境变量：`BOMBERMAN_HTTP_PORT=18080`（可改）。

### 3）外层 TLS（bomberman.jopatk.top）

DNS：`bomberman.jopatk.top` → 杭州公网 IP。

外层 Nginx/Caddy 终止 HTTPS，反代到 `127.0.0.1:18080`，并确保 **WebSocket Upgrade** 传到后端（若外层直接反代 `/ws` 到游戏容器亦可）。推荐整站反代到 compose 的 `web` 服务，由容器内 nginx 处理 `/` 与 `/ws`。

Caddy 示例：

```
bomberman.jopatk.top {
    reverse_proxy 127.0.0.1:18080
}
```

浏览器打开 `https://bomberman.jopatk.top/`，大厅默认加入 `wss://bomberman.jopatk.top/ws`。满 2 人后专用服自动开局。

### 容器角色

| 服务 | 镜像 | 作用 |
|------|------|------|
| `game` | `bomberman-game` | Linux 专用服，内网 `9080` |
| `web` | `bomberman-web` | Nginx 静态页 + `/ws` → `game:9080` |

## 操作

| 键 | 作用 |
|----|------|
| WASD / 方向键 | 按格移动 |
| 空格 | 放炸弹（每人同时最多 1 颗） |

地图 13×11；最多 4 人；引信约 2 秒，爆炸范围 2 格。

## 已知限制（v1）

- 无 AI、无道具
- 色块美术
- 未做断线重连 / 房间列表
- 网页端隐藏「创建房间」（由杭州专用服托管）

## 后续可加

- 道具与多雷
- 房间码
- 观战
