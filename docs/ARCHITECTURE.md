# 摸鱼炸弹人 — 项目结构约定

后续开发**必须**按本文件分层，避免再把逻辑堆进单个大脚本。

## 目标

- 联机权威模拟可单测、可扩展（道具 / 模式 / 地图）
- 场景脚本只做编排（输入 → 模拟 → RPC → 表现）
- 部署与玩法解耦

## 目录职责

| 路径 | 放什么 | 不放什么 |
|------|--------|----------|
| `autoload/` | 跨场景单例：`Net.gd`、`GameState.gd` | 格子模拟、爆炸、HUD 细节 |
| `scripts/match/` | **纯逻辑**模块（`RefCounted` / `class_name`）：爆炸规则、突然死亡、踢炸弹、地图生成等 | 节点树、`rpc`、UI 控件 |
| `scripts/`（根下） | 场景编排与表现：`game_root.gd`、`lobby.gd`、`player.gd`、`bomb.gd`、`powerup.gd` | 大段可抽离的规则算法 |
| `scenes/` | `.tscn` 场景与节点布局 | 业务规则（规则写脚本） |
| `assets/` | 字体、主题、贴图。像素街机在 `assets/art/pixel/`（大厅背景、地块、角色/炸弹、爆炸碎裂） | 逻辑代码 |
| `deploy/` | Docker / nginx / systemd | 游戏逻辑 |
| `scripts/verify_*.gd` | headless 冒烟（`-s`） | 正式运行入口 |
| `docs/` | 架构与设计说明 | — |

## 硬性规则

1. **新玩法规则先落在 `scripts/match/`**  
   写好纯函数 / 小类后，再由 `game_root.gd` 调用。禁止直接在 `game_root` 里新增长篇 `if` 规则树。

2. **`game_root.gd` 只做编排，不设行数上限**  
   它是对局里唯一发送 `@rpc` 的脚本，并拥有运行时字典和每帧顺序。主机判定与客机套用都写在这里，行数随同步事件增长。  
   允许增加：输入轮询、调用 match 模块、维护运行时字典、新的 `@rpc`、驱动 `MatchBoard` / `MatchHud`。  
   规则算法仍按第 1 条放进 `scripts/match/`。画面、预演和离房继续放在 `MatchBoard`、`MatchHud`、`ClientPredict`、`MatchSession`。

3. **RPC 留在拥有 multiplayer 的场景脚本**  
   `match/*` **禁止** `@rpc`。网络边界：`lobby.gd` / `game_root.gd`（或未来的 `match_net.gd` 编排层）。

4. **表现脚本保持笨**  
   `player.gd` / `bomb.gd` / `powerup.gd` 只负责外观与本地动画，不写胜负、不写权威判定。

5. **Autoload 保持瘦**  
   只放真正跨场景的状态与连接；不要把 Match 模拟塞进 Autoload。

6. **中文 UI**  
   使用 `assets/fonts/GameCJK.ttf` + `assets/ui/default_theme.tres`；新增 Label 走主题或显式挂该字体。

7. **验证**  
   每加一块核心规则，补或改一个 `scripts/verify_*.gd`，用  
   `godot --headless --path . -s res://scripts/verify_xxx.gd` 跑通再提交。

8. **提交与部署**  
   默认：改完 `git commit`（及按需 push）。**未经用户明确要求，不部署杭州 / 不碰 nginx·rsync·systemd。**

## 推荐依赖方向

```
scenes (lobby/game)
    ↓
scripts/lobby.gd  /  scripts/game_root.gd   ← RPC + 节点
    ↓
scripts/match/*   ← 纯逻辑（可单测）
    ↓
autoload Net / GameState   ← 仅连接与大厅快照
```

禁止反向依赖：`match/*` 不得 `load` 场景或依赖 HUD 节点。

## 已有 match 模块

- `Arena` — 13×11 多地图硬墙布局 + 软墙种子。`MapId`：经典 / 开阔 / 十字 / 迷宫；`build_base_grid` / `build_match_grid(map_id, soft_seed)`；同 `map_id+soft_seed` 软墙一致；四角出生及正交邻格永不硬墙/软墙
- `BlastRules` — 爆炸射线、软墙清除打包。`compute_rays(..., pierce=false)`：软墙被命中并清除；未穿透时射线停在软墙，穿透时继续，直到射程用尽或碰到硬墙。硬墙始终挡住射线，格子本身不被命中
- `SuddenDeath` — 90s 后首次缩圈致死格，之后每 `INTERVAL`（15s）向内一圈。各端只前进 `elapsed` 做倒计时；致死格只由主机 `tick` 扩展
- `KickRules` — 穿弹 / 踢弹判定、滑行阻挡。踢进已有火圈由 `game_root` 立即引爆，走进这场爆炸的人会阵亡；缩圈盖住的炸弹被吞掉，不额外爆炸
- `MatchBot` — 单机对手。只在 `GameState.solo_bot` 且离线权威端由 `game_root` 调用；危险格上先逃走，有退路才炸软墙或对手，否则走向软墙 / 玩家。联机对局不生成电脑
- `MovePredict` — 客机移动预演的确认链。下标 0 是主机已确认的格子，后面是提前画出的步；主机重复确认链头表示这几步被拒绝，Pawn 拉回
- `PlayerStats` — 属性默认值、拾取加减、上限、冷却、封包。短包保留本地穿透
- `BombRecord` — 炸弹字典的字段形状与持有数量
- `PowerupDrop` — 软墙掉落（概率、占格、致死格）。随机数由调用方传入
- `MatchEnd` — 胜负 / 平局 / 再来一局资格 / 中途退出是否判负。场景切换在 `MatchSession`

画面不进 `match/`：`MatchBoard` 画格子和实体，`MatchHud` 画文字和结算面板，`ClientPredict` 保存客机预演链和影子炸弹。`MatchSession` 管离开、被踢、断线、中途弃权和专用服空房回大厅。`@rpc` 仍只在 `game_root`。

像素街机贴图在 `assets/art/pixel/`：`lobby_bg.jpg` 铺满大厅；`tiles/` 地块；`entities/` 四色角色与炸弹；`fx/` 爆炸中心/横竖焰与软墙碎裂三帧。`MatchBoard.play_boom` 用 `Sprite2D` 播爆炸与碎裂，软墙炸开后 `repaint_cells` 换地板。缩圈致死格用 `fx/sd_hazard_*.png` 像素焰脉贴图（出现动画 + 循环闪烁）；道具仍是色块。

## 大厅 / 房间

专用服和本机听服可以同时有多间房。房间码是 4 位（去掉 0/O/1/I/L）。留空房间码会新开一间，填了就加入那一间。密码仍然只是这间房的锁。

- 房间表在 `GameState.rooms`。扁平的 `players` / `host_peer_id` / `map_id` 只镜像本机玩家所在的那一间；专用服进程自己不进任何一间
- 对局节点挂在自动加载 `MatchHost` 下，路径是 `/root/MatchHost/<房间码>`，客机和主机一致，RPC 不会串房。单机试试仍直接切到 `game.tscn`
- 一间房对局中时，别的房间码照样能开新局。房满、密码错、码不对、对局中，都只拒绝这一次登记

- 界面在 `scenes/lobby.tscn` + `scripts/lobby.gd`：登录页（昵称、连接服务器后房间列表最多约 3 行可见可滚动、新建房间、密码、单机试试、高级端口/地址）和等待房间（房间码、准备、房主开始、离开、密码、地图）
- 房间快照在 `GameState`：`room_code`、`players[*].ready`、`host_peer_id`、`room_password`、`map_id`、`seed_input`、`soft_seed`、`in_match`。广播只发给这间房里的人
- 同步仍走 `GameState._rpc_sync_players`。快照是带 `players` 字段的字典；旧的「纯玩家字典」仍能被 `apply_snapshot` 读入
- 房主是该房 `players` 里最小的 peer id。专用服进程是 peer 1，但自己不占玩家位；有人离开就重算这间房的房主
- 地图和软墙种子只有房主能改，经 `GameState._rpc_sync_map_settings` 写到权威端再广播。种子空或非数字时，开局由 `resolve_soft_seed()` 随机；整数则固定。再来一局保留 `map_id`，重新随机 `soft_seed`
- 连上专用服后、进房前，权威端广播 `lobby_directory`（房间码/人数/对局中/是否加密，不含密码明文）；登记失败不踢线，可继续选房
- 登记被拒（对局中、密码错、已满 4 人、房间码不对）会 RPC 回客户端并显示原因，不会停在「登记中」
- 开始条件：房主操作，且至少 2 人、全员已准备。没有满员自动开局
- 这些 RPC 放在 `GameState` 自动加载上，专用服留在大厅里照样能拒绝新连接。`scripts/match/` 里仍然禁止 `@rpc` 和房间状态

## 道具

- 种类：炸弹+ `0`、火力+ `1`、移速+ `2`、踢弹 `3`、穿透 `4`（黄 P）。软墙掉落 `0..4`
- 穿透与踢弹一样是 `0|1`，拾取后保持到本局结束
- 放炸弹时把拥有者当前的 `pierce` 拷进该炸弹；爆炸只读炸弹上的值。之后再捡穿透，不会让已经放下去的炸弹变成穿透
- 属性包 `_stats_pack` 为 `[bombs, range, speed, kick, pierce]`。客机按包覆盖；包里没有 pierce 时保留本地已有值
- 外观只在 `powerup.gd`（金色菱形、字母 P）

## 联机与表现约定

- 突然死亡新增格、被吞掉的炸弹 id、被烧掉的道具 id，由主机一次 RPC 发给所有端（含自己）
- 倒计时最后 30 秒及缩圈阶段，主机每秒把 `elapsed` / 是否已开始 / 距下次缩圈同步给客机
- 软墙被炸开或被火圈清掉时，只重绘变化的格子，不重建整张地图
- 炸弹数 HUD 在放置、爆炸、吞弹、捡道具时刷新，不在每帧重写 Label
- 客机移动先按本地格子预演，放炸弹先放一个影子；主机格子对不上时拉回。踢弹不预演，等主机把炸弹推走再对齐
- 爆炸、拾取播放程序生成的短音效（`scripts/sfx.gd`），无界面时不播

## 改动检查清单（PR / 提交前）

- [ ] 新规则是否在 `match/`？`game_root` 只增加 RPC、每帧顺序或模块调用（该文件不设行数上限）
- [ ] 是否引入了新的 `@rpc` 在纯逻辑文件里？（不应）
- [ ] 是否更新了 `verify_*.gd`？
- [ ] 中文是否仍走 GameCJK 主题？
- [ ] 是否误触部署脚本？

