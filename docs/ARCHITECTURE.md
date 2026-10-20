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
| `assets/` | 字体、主题、贴图 | 逻辑代码 |
| `deploy/` | Docker / nginx / systemd | 游戏逻辑 |
| `scripts/verify_*.gd` | headless 冒烟（`-s`） | 正式运行入口 |
| `docs/` | 架构与设计说明 | — |

## 硬性规则

1. **新玩法规则先落在 `scripts/match/`**  
   写好纯函数 / 小类后，再由 `game_root.gd` 调用。禁止直接在 `game_root` 里新增长篇 `if` 规则树。

2. **`game_root.gd` 只做编排**  
   允许：输入轮询、调用 match 模块、维护轻量运行时字典、发 RPC、驱动视觉节点。  
   单文件建议控制在 **~600 行以内**；超过就继续拆 match / ui。

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
- `SuddenDeath` — 90s 后缩圈致死格。各端只前进 `elapsed` 做倒计时；致死格只由主机 `tick` 扩展
- `KickRules` — 穿弹 / 踢弹判定、滑行阻挡。踢进已有火圈由 `game_root` 立即引爆，走进这场爆炸的人会阵亡；缩圈盖住的炸弹被吞掉，不额外爆炸

## 地图与种子

- 大厅主机可选地图（OptionButton）与软墙种子（空/非数字=开局随机；整数=固定）
- 开局权威端 `GameState.resolve_soft_seed()`，经 `_rpc_start_match` / `_rpc_setup_match(seed, players, map_id)` 同步
- 再来一局：保留 `map_id`，重新随机 `soft_seed`
- 客机大厅地图/种子只读，由主机 `_rpc_sync_map_settings` 同步

## 道具

- 种类：炸弹+ `0`、火力+ `1`、移速+ `2`、踢弹 `3`、穿透 `4`（黄 P）。软墙掉落 `0..4`
- 穿透与踢弹一样是 `0|1`，拾取后保持到本局结束
- 放炸弹时把拥有者当前的 `pierce` 拷进该炸弹；爆炸只读炸弹上的值。之后再捡穿透，不会让已经放下去的炸弹变成穿透
- 属性包 `_stats_pack` 为 `[bombs, range, speed, kick, pierce]`。客机按包覆盖；包里没有 pierce 时保留本地已有值
- 外观只在 `powerup.gd`（金色菱形、字母 P）

## 联机与表现约定

- 突然死亡新增格、被吞掉的炸弹 id、被烧掉的道具 id，由主机一次 RPC 发给所有端（含自己）
- 倒计时最后 30 秒，主机每秒把 `elapsed` / 是否已开始同步给客机
- 软墙被炸开或被火圈清掉时，只重绘变化的格子，不重建整张地图
- 炸弹数 HUD 在放置、爆炸、吞弹、捡道具时刷新，不在每帧重写 Label

## 改动检查清单（PR / 提交前）

- [ ] 新规则是否在 `match/` 而不是只写在 `game_root`？
- [ ] 是否引入了新的 `@rpc` 在纯逻辑文件里？（不应）
- [ ] 是否更新了 `verify_*.gd`？
- [ ] 中文是否仍走 GameCJK 主题？
- [ ] 是否误触部署脚本？

