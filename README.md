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

网页端大厅默认加入 `wss://bomberman.jopatk.top/ws`，不跟当前页面域名走，所以静态页可以挂在 B 站小玩具上。本机打开的页面（`localhost` / `127.0.0.1`）仍连当前主机的 `/ws`。见 `Net.get_default_join_address()` 与 [docs/DEPLOY-TOY.md](docs/DEPLOY-TOY.md)。

## 目录

```
bomberman-web/
  autoload/Net.gd          # WebSocket 开房/加入 + 网页默认 WSS
  autoload/GameState.gd
  assets/art/pixel/        # 大厅背景、地块、角色 / 炸弹 / 道具图标
  assets/audio/            # BGM（SA3）+ CC0 芯片音效（见 CREDITS.md）
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
  tools/pack_toy.sh        # 把 build/web 打成小玩具 zip
  docs/DEPLOY-TOY.md       # 小玩具托管说明
  project.godot
  README.md
```

## 本地怎么跑（桌面 / 无界面）

```bash
GODOT=/home/box/.local/bin/godot   # 或你的 godot 路径
PROJECT=/workspace/bomberman-web
```

### 单机

进大厅点 **「单机试试」**。不足 4 名真人时，开局会补「人机1」「人机2」…直到满员。WASD 移动，空格放雷。

联机：填昵称后点 **「进入房间」**。房间码留空会新开一间，把码发给同事即可加入；填了码就进那一间。房主（该房玩家中编号最小的人）选地图，全员点 **「准备」** 后由房主 **「开始对局」**。不再满 2 人自动开局。同一台专用服上可以同时有多间房。网页端没有「本机开房」，默认连 `wss://bomberman.jopatk.top/ws`。

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
./tools/pack_toy.sh          # 可选：打成 build/toy/bomberman-toy.zip，见 docs/DEPLOY-TOY.md
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

浏览器打开 `https://bomberman.jopatk.top/`，大厅默认加入 `wss://bomberman.jopatk.top/ws`。房间码留空会新开一间，把码发给同事；填了码就进那一间。全员准备后由房主开始。这间房对局中再来的人会看到「对局中，请稍后再来」，别的房间码不受影响。

### 容器角色

| 服务 | 镜像 | 作用 |
|------|------|------|
| `game` | `bomberman-game` | Linux 专用服，内网 `9080` |
| `web` | `bomberman-web` | Nginx 静态页 + `/ws` → `game:9080` |

## 操作

| 键 | 作用 |
|----|------|
| WASD / 方向键 | 按格移动 |
| 空格 | 放炸弹 |

开局每人 1 颗炸弹、火力 2 格，引信约 2 秒。炸开软墙有机会掉落：炸弹+（最多同时 5 颗）、火力+（最多 6 格）、移速、踢弹、穿透。踢弹把炸弹沿直线滑出去；穿透让爆炸穿过软墙。地图 15×13，四选一（经典 / 开阔 / 十字 / 迷宫），最多 4 人。90 秒后安全区开始收缩。阵亡后留在局里观战。

联机时，移动和放炸弹会先在自己屏幕上显示，主机确认后再对齐；对不上就拉回主机那一格。

## 音频

BGM（大厅 / 对局 / 突然死亡循环，以及胜负短句）和音效都在 `assets/audio/`，出处与许可见 [assets/audio/CREDITS.md](assets/audio/CREDITS.md)。BGM 现为 Stable Audio 3 MLX 生成后压成 Ogg；`sfx/` 仍是 `tools/gen_audio.py` 的 CC0 芯片音效。

大厅有「音乐 / 音效」开关，选择记在 `user://audio.cfg`，默认开。网页要先点一下或按一下键才会出声，避免一打开就触发浏览器自动播放失败。

本地试听：进大厅后点任意处听大厅循环；「单机试试」切到对局；约 90 秒后突然死亡换成同一风格、稍快一点的明亮循环；结算播胜/负短句，回大厅再接大厅曲。

```bash
python3 tools/gen_audio.py   # 仅重新生成 sfx（及旧芯片 BGM 脚本，线上 BGM 已换）
godot --headless --path . -s res://scripts/verify_audio.gd
```

## 已知限制

- 大厅、地块、角色、炸弹和五种道具都是像素贴图（`assets/art/pixel`）。真人不足 4 人时，对局开始由权威端补人机（头顶标「人机1」等），人机不出现在大厅名单里
- 无账号、无断线重连，也不能重连回正在进行的对局
- 房主是该房间玩家里最小的 peer。专用服进程本身不是玩家；一间房的人走光后这间房消失，其它房间继续
- 对局中或房间已满（4 人）时拒绝登记，并在客户端提示原因
- 网页端隐藏「本机开房」（由专用服托管）。主机端口和加入地址收在「高级」里

## 大厅冒烟

```bash
godot --headless --path . -s res://scripts/verify_lobby.gd
```

没有 Godot 时，手工看两件事：登录页是「进入房间 / 单机试试 / 高级」，连上后要全员准备才出现可点的「开始对局」；对局中再登记应提示「对局中，请稍后再来」，而不是停在「登记中」。

## 后续可加

- 断线重连

## 开发约定

项目分层与提交规则见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。新玩法逻辑优先放 `scripts/match/`，场景脚本只做编排与 RPC。
