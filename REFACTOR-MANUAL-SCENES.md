# 手工搭建重构方案

目标：在**不改变联机协议、玩法规则、美术资产和部署方式**的前提下，把当前“场景只有骨架、画面全靠运行时生成”的实现，改造成“场景与资源在编辑器里可见、可调、可预览”的手工搭建结构。

本文原是施工方案；第 0 节记录实施结果与方案的差异，其余章节保留原设计与步骤，供回溯。

## 0. 实施记录

分支 `refactor/manual-scenes`，基线 tag `baseline-manual-refactor`。已完成 Phase 1–8，`verify_*` 共 16 个脚本全绿。

与方案有出入、需要知道的四点：

1. **地图预览用 `@tool` 画样例**：没有人工在 TileMap 面板刷图，而是给 `board.gd` 加 `@tool`，编辑器里 `_ready()` 画一张经典图；运行时仍 `clear()` 后按 `grid` 重画。
2. **HUD 没有改成容器布局**：`HUD/Status`、`HUD/BackBtn` 等路径是既有验证与脚本的契约，继续保留绝对 offset，只把结算面板拆成 `scenes/game/end_panel.tscn`。
3. **大厅没有拆成 login/room 两个面板场景**：只做了样式 `.tres`、`room_row.tscn`、`Timer` 节点化；倾斜与居中仍在 `lobby.gd`，因为 `verify_lobby` 断言的是 `ActionBand.rotation` 与按钮同排同宽。
4. **HUD/结算面板的专用服隐藏逻辑**保留在 `hud.gd` 的 `prepare()`，没有挪回场景。


---

## 1. 当前项目现状

### 1.1 规模

| 项 | 数值 |
|---|---|
| GDScript 总行数（不含 addons） | 约 9,800 行 |
| `scripts/game_root.gd` | 1,366 行（对局编排 + 唯一 RPC 出口） |
| `scripts/lobby.gd` | 1,082 行（大厅编排 + 运行时拼样式） |
| `autoload/GameState.gd` | 877 行（大厅/房间状态 + 大厅 RPC） |
| `scripts/match/*.gd` | 12 个纯逻辑模块（RefCounted） |
| `scripts/verify_*.gd` | 15 个 headless 冒烟脚本 |
| 场景 | `scenes/lobby.tscn`（84 个节点，12 个外部资源）、`scenes/game.tscn`（110 行，只有空容器） |
| 美术/音频 | `assets/art/watercolor/` 3.8 MB、`assets/audio/` 2.0 MB、`assets/ui/` 156 KB |

### 1.2 表现层现在是怎么来的

- `game.tscn` 里只有 `Game(Node2D)` + `Map / Entities / Powerups / FX`（四个空 `Node2D`）+ `HUD(CanvasLayer)`。编辑器 2D 视图除 HUD 文字外全空。
- 地图：`Arena.build_base_grid()` 产出二维数组；`MatchBoard._make_tile()` 为每格 `Sprite2D.new()`，贴图取自 `MatchBoard` 顶部的 `preload` 常量，并用 `scale = 49/48` 补白缝。
- 实体：`MatchBoard.make_player()` / `spawn_bomb()` / `spawn_powerup()` 用 `Node2D.new()` + `set_script(load(...))` + `setup()`，没有 `PackedScene`。
- 角色动画：`player.gd` 运行时用 `AtlasTexture` 拼 `SpriteFrames`（每色 5 帧），名牌 `Label` 也是运行时创建。
- 特效：爆炸、碎墙、缩圈危险格、空投预告全部由 `MatchBoard` 运行时建节点，并提供内部数组 `map_sprites` / 字典 `sd_visuals`。
- HUD：文字、属性栏、结算面板由 `MatchHud` 直接写 Label；面板尺寸/位置写死在 `.tscn` 的绝对 offset。
- 大厅：`lobby.tscn` 节点树本身已较完整，但按钮/面板样式由 `lobby.gd` 的 `_clay_style()` / `_style_button()` / `_apply_main_button_styles()` 在运行时组装 `StyleBoxTexture`，倾斜布局由 `_apply_tilt_layout()` 算 pivot。

### 1.3 不能动的东西（重构红线）

1. **专用服务器**：`--headless -- --server` 用同一套场景，表现层不得依赖“编辑期预置内容一定存在”。
2. **权威模型**：格子、炸弹、死亡判定在主机；客机只发输入、收状态。
3. **RPC 位置**：`@rpc` 只允许在 `lobby.gd` / `game_root.gd` / `GameState`（大厅），`scripts/match/*` 永不联网。
4. **房间机制**：`GameState.rooms`、每房一个 `/root/MatchHost/<房间码>` 节点、`RoomCodes` 规则不变。
5. **协议与端口**：`ws://host:9080`、`wss://bomberman.jopatk.top/ws`、网页端默认地址不变。
6. **资产路径**：`assets/art/watercolor/**`、`assets/audio/**`、`assets/fonts/GameCJK.ttf` 不改名（`.import` 已入库）。
7. **导出**：Web（960×720、GL Compatibility、无线程）+ Linux Server，`export_filter="all_resources"`，新增资源自动打进包。

### 1.4 现有测试的耦合点（重构必须一起改）

| 脚本 | 现在依赖的内部实现 |
|---|---|
| `verify_project.gd` | `MatchBoard.TEX_FLOOR_A/B`、`TEX_HARD/SOFT`、`board.draw_map()`、`map.get_child_count()`、`painted.texture` |
| `verify_feel.gd` | `_spawn_bomb_visual()`、`_repaint_cells()`、`_sd_visuals` |
| `verify_powerups.gd` | `_spawn_powerup_visual()` |
| `verify_bot.gd` | `game._ghost_node` 且要求节点名 `BombGhost` |
| `verify_entities.gd` | 实体挂在 `MatchBoard` 的实体层下 |

`scripts/match/*` 的 12 个模块与 `verify_rules` / `verify_maps` / `verify_airdrop` / `verify_bot` 的逻辑部分不受表现层改造影响。

### 1.5 当前工作区

未提交改动：`README.md`、`assets/ui/default_theme.tres`、`scenes/lobby.tscn`（另有未跟踪的 `scripts/.DS_Store`）。开工前必须先落盘，否则重构分支无法干净回滚。

---

## 2. “手工搭建”到底指什么

### 2.1 定义

- **场景即布局**：节点树写在 `.tscn` 里，打开编辑器就能看见成品；编辑器负责摆位、锚点、层级、样式。
- **资源即配置**：贴图集、动画帧、按钮/面板样式、字体主题做成 `.tres`，在检查器里调，而不是脚本里的常量表和 `Color()` 字面量。
- **代码只做三件事**：规则计算（`scripts/match/`）、网络同步（RPC）、把运行时数据映射到场景节点（`set_cell` / `instantiate` / Label 文本）。
- **手工搭建 ≠ 逻辑回场景**：本方案不把胜负、爆炸、人机写进节点；这些仍在 `scripts/match/`。

### 2.2 逐层对照

| 维度 | 当前（代码生成） | 手工搭建目标 |
|---|---|---|
| `game.tscn` | 4 个空 `Node2D` 占位 | 完整对局树：`Board(TileMapLayer)`、实体层、FX 层、结构化 HUD、编辑器可见样例 |
| 地图 | `grid` 数组 + 每格 `Sprite2D` | `TileMapLayer` + `TileSet`（4 个 tile：floor_a/floor_b/hard/soft），`set_cell()` 绘制 |
| 角色 | `Node2D.new()` + `set_script()` | `scenes/game/player.tscn`（`AnimatedSprite2D` + `Label`），`instantiate()` |
| 角色动画 | 运行时拼 `SpriteFrames` | `assets/anim/player_*_frames.tres`（idle 1 帧 + walk 4 帧） |
| 炸弹 / 道具 | 运行时 `new()` + 内部 `Sprite2D` | `bomb.tscn` / `powerup.tscn`；道具图标仍由 `kind` 查表（5 种不建 5 个场景） |
| 特效 | `MatchBoard` 运行时建节点 + 计时删除 | `blast.tscn` / `soft_break.tscn` / `sd_hazard.tscn` / `airdrop_mark.tscn`，`animation_finished` 自毁 |
| HUD | 绝对 offset + 代码写 Label | 容器布局（`MarginContainer`/`VBoxContainer`）+ 主题样式；值仍由脚本填 |
| 结算面板 | 写在 `game.tscn` 里、由 `MatchHud` 找节点 | `scenes/game/end_panel.tscn` 独立实例 |
| 大厅样式 | `_clay_style()` 运行时组 `StyleBoxTexture` | `assets/ui/styles/*.tres` + `default_theme.tres` |
| 倾斜/居中 | `_apply_tilt_layout()` 算 pivot | 直接写进场景 `transform`，必要时用 `AnimationPlayer` |
| 调参 | 改脚本常量（`TILE`、`MOVE_HOLD_MS`…） | `@export` 变量 + 检查器 |

### 2.3 必须保留的“代码生成”部分

- 地图格子内容由权威 `grid` 决定，运行时必然要 `set_cell()` 刷一遍（编辑器里的预置图纸只是预览）。
- 角色颜色、名字、炸弹 id / 道具种类是运行时数据，必须由 `setup()` 注入。
- 人机、突然死亡、空投产生的节点同样只能运行时创建。

### 2.4 手工搭建的代价（提前接受）

- 改布局、换图标、加特效需要开编辑器，review 只能看截图或 `.tscn` diff，可读性比数组差。
- `.tscn` 手工编辑易产生冲突与 `ext_resource` id 冲突，必须小步提交、避免多人同时改同一场景。
- 编辑器里“能看见”的代价是**双份状态**（场景预置 + 运行时重绘）。必须约定“进入对局先清空再按 grid 重绘”，否则会出现幽灵格。
- 现有 5 个 `verify_*` 需要重写断言，这部分工作量不比场景改造小。

---

## 3. 目标结构

```
scenes/
  lobby.tscn                    # 主壳：背景、立绘、标题、状态角、Center
  lobby/login_panel.tscn        # 登录/房间列表/更多选项
  lobby/room_panel.tscn         # 等待房间
  lobby/room_row.tscn           # 单条房间行（带 code 信号）
  game.tscn                     # 对局装配（含固定 Camera2D）
  game/board.tscn               # Node2D(Board) + TileMapLayer（用下条 TileSet）
  game/player.tscn
  game/bomb.tscn
  game/powerup_bomb.tscn        # 道具一种一个场景
  game/powerup_range.tscn
  game/powerup_speed.tscn
  game/powerup_kick.tscn
  game/powerup_pierce.tscn
  game/blast.tscn
  game/soft_break.tscn
  game/sd_hazard.tscn
  game/airdrop_mark.tscn
  game/airdrop_crate.tscn
  game/end_panel.tscn
assets/
  tilesets/arena_tileset.tres
  anim/player_blue_frames.tres (+ red / green / yellow)
  ui/styles/btn_primary_normal.tres … (normal/hover/pressed/focus/disabled)
scripts/
  board.gd                      # 由 MatchBoard 迁移，只负责绘制
  hud.gd                        # 由 MatchHud 迁移，只负责显示
  player.gd / bomb.gd / powerup.gd   # 改 @onready + @export
  match/*                       # 不动
```

约束：`scenes/` 仍不放业务规则；`scripts/match/*` 仍禁止 `load` 场景、禁止 `@rpc`。

### 3.1 脚本挂载约定

当前 `player.gd` / `bomb.gd` / `powerup.gd` 都挂在运行时 `new()` 出来的 `Node2D` 根节点上，因为整个实体就是“一个根节点 + 脚本即时创建子节点”。`game_root.gd` 同样挂在 `Game` 根节点。

“脚本挂根节点”本身**不是**问题：Godot 里场景脚本挂在根节点是标准做法，根节点脚本就是场景编排者。要改的是根脚本的职责边界，不是挂载位置：

- 根节点脚本保留：生命周期、`setup()` 注入、对外接口（`set_cell`、`mark_dead`）。
- 子节点只在**有独立行为**时才挂脚本（如需要自己收输入的组件）；纯装饰的 `Sprite2D` / `Label` 不挂脚本。
- 表现脚本不再在 `setup()` 里 `new()` 子节点，改为 `@onready` 取场景里已有节点。

注意区分两种“可见”：编辑器只显示**场景里写死的默认外观**；`setup()` 注入的格子坐标、角色颜色、名牌文本、引信着色、道具种类都不会出现在编辑器预览里。因此每个场景都要给一套合理的默认值（默认帧、默认动画、占位名牌、默认贴图），否则打开 `.tscn` 仍看不出样子。

按此约定：`player.tscn` 根挂 `player.gd`，`AnimatedSprite2D(Body)` 与 `Label(Name)` 无脚本；`bomb.tscn` 根挂 `bomb.gd`，`Body` 无脚本；5 个道具场景各自根挂 `scripts/powerup.gd`，图标作为 `Sprite2D` 子节点直接指定贴图。

### 3.2 两点已定选择

- **地图布局**：不移动 `Board` 节点坐标，改由 `game.tscn` 里一个固定 `Camera2D`（位置 `(480, 360)`、无跟随、无缩放）对准 960×720 视口；`board_origin()` 的运行时位移删除，棋盘原点固定在 `Board` 场景坐标里。专用服 `visible = false`，Camera2D 不参与逻辑。
- **道具场景**：`powerup_bomb/range/speed/kick/pierce.tscn` 五个独立场景，贴图写在场景里，不再由 `kind` 运行时查表；`board.gd` 用 `const POWERUP_SCENES: Array[PackedScene]` 按 `PKind` 取场景，`powerup.gd` 只保留 `setup(pid, cell, kind, tile)` 的 meta 约定与呼吸动画。

---

## 4. 重构步骤

每阶段独立可发布、可回滚；上一阶段验收通过再进下一阶段。

### Phase 0 — 固化基线

- 建分支 `refactor/manual-scenes`；先提交当前 3 个改动文件，打 tag（如 `baseline-manual-refactor`）。
- 跑全部 15 个验证脚本并记录通过情况：
  `godot --headless --path . -s res://scripts/verify_xxx.gd`
- 存 3 张基线截图：大厅、单机对局开局、突然死亡。放 `docs/baseline/` 只供对比，不进导出。

**验收**：基线全绿；之后任一步失败都能用 tag 回滚。

### Phase 1 — 资源基座（不碰逻辑）

- `assets/tilesets/arena_tileset.tres`：4 个 atlas source（`floor_a`、`floor_b`、`hard`、`soft`），tile 48×48；顺带把白缝问题在 TileSet 里解决（相邻 tile 留 1px 或设置纹理过滤），替代 `49/48` 缩放。
- `assets/anim/player_*_frames.tres`：idle=1 帧、walk=4 帧（`AtlasTexture`，region 48×48）。
- `assets/ui/styles/`：按钮、输入框、面板的 `StyleBoxTexture` 五态，从 `lobby.gd` 的 `_clay_style()` 固化出来。
- `default_theme.tres` 增加 Button / LineEdit / CheckBox / Panel 的默认项。

**验收**：资源在编辑器里能预览；`godot --headless --path . -s res://scripts/verify_cjk_font.gd` 仍通过；未改任何 `.gd` 行为。

### Phase 2 — 地图静态化

- 新建 `scenes/game/board.tscn`（`Node2D` + `TileMapLayer`，挂 `scripts/board.gd`），`game.tscn` 的 `Map` 改为其实例。
- `scripts/board.gd`：`draw_map(grid)` / `repaint_cells(grid, cells)` 保留原签名，改用 `set_cell()`；`draw_map` 先 `clear()`。
- 原点位置不再运行时计算：`Board` 坐标在场景里摆好，`game.tscn` 加固定 `Camera2D`（位置 `(480, 360)`、无跟随、无缩放）；删除 `host.position = board_origin(...)` 与 `board_origin()`。
- 编辑器里用 TileMap 面板刷一张 15×13 示例图（进入对局会被 `clear()` 覆盖），保证 2D 视图能看见地图。

**验收**：`verify_maps` 通过；F6 开局地图与截图一致、无白缝；炸软墙只重绘变化格；缩圈危险格视觉不变。

### Phase 3 — 实体场景化

- `player.tscn`（`AnimatedSprite2D` + 名牌 `Label`）、`bomb.tscn`、5 个道具场景（`powerup_bomb/range/speed/kick/pierce.tscn`，图标直接写在场景里）；脚本改 `@onready`，暴露 `@export` 动画参数。
- `board.gd` 用 `const PLAYER_SCENE := preload(...)`，`instantiate()` 后调 `setup(peer_id, cell, color, name, tile)`；`spawn_bomb` 同理；`spawn_powerup` 按 `PKind` 从 `POWERUP_SCENES` 数组取场景。
- `ClientPredict.show_ghost()` 里的 `Node2D.new()` + `set_script()` 改为 `BOMB_SCENE.instantiate()`，节点名仍为 `BombGhost`（`verify_bot` 依赖该名字）。
- `game.tscn` 加一个 `Preview` 分组（1 玩家 + 1 炸弹 + 5 种道具各 1，或至少 1 个），`_ready()` 最早 `queue_free()`，只服务编辑器预览。
- 保留 `set_meta("cell")` 契约，`ClientPredict` 与拉回逻辑不改。

**验收**：`verify_entities`、`verify_player_anim` 通过；4 色角色、走路帧、变灰、名牌与当前一致；专用服 headless 下 `Preview` 已释放。

### Phase 4 — 特效场景化

- `blast.tscn`（中心/横/竖 3 种贴图）、`soft_break.tscn`（3 帧动画 + `animation_finished` 自毁）、`sd_hazard.tscn`（3 帧闪烁）、`airdrop_mark.tscn`、`airdrop_crate.tscn`。
- `board.gd` 里删掉对应计时 `query_free` 逻辑；`sd_visuals` 字典可保留为查表，但值改为场景实例。
- 空投预告闪烁改 `AnimationPlayer` 或 `Tween`，保留“只改透明度”约定。

**验收**：`verify_fx`、`verify_feel` 通过；爆炸 4 方向、碎墙、缩圈闪烁时序与基线一致。

### Phase 5 — HUD 与结算

- `game.tscn` HUD 改容器布局（`MarginContainer` + `VBoxContainer`），删绝对 offset；字号/颜色走主题。
- 新建 `end_panel.tscn`（`PanelContainer` + 插画 + 标题 + 两按钮）。
- `scripts/hud.gd` 接管 `MatchHud` 的显示逻辑；`MatchHud` 若只剩文本格式化可并入 `scripts/match/` 或删除。
- 专用服隐藏 HUD 仍由 `Net.is_dedicated()` 控制。

**验收**：960×720 无重叠、文字不截断；胜利/失败/平局插画与文案不变；`verify_project` 中 HUD 相关断言改路径后通过。

### Phase 6 — 大厅拆场景

- `lobby.tscn` 保留外壳；`login_panel.tscn`、`room_panel.tscn`、`room_row.tscn` 拆出，用信号与 `lobby.gd` 通信。
- 删除 `_clay_style` / `_style_button` / `_apply_main_button_styles`（样式进 `.tres`）。
- `_apply_tilt_layout` / `_refresh_tilt_pivots` 改为场景内固定 `transform`。
- 房间列表行改用 `room_row.tscn` 实例化，删掉 `_refresh_room_list()` 里的 `Button.new()` / `Label.new()` / `HBoxContainer.new()`。
- `Timer.new()`（房间目录刷新、登记超时）改为场景里的 `Timer` 节点。
- `_center_panel` 改锚点居中；入场淡入可保留为 `Tween`。

**验收**：`verify_lobby` 通过；房间列表最多 3 房、空槽无字；密码、地图、音频开关、专用服/网页差异行为不变。

### Phase 7 — 测试与场景契约

- 新增 `scripts/verify_scenes.gd`：headless 逐个 `load` + `instantiate` 所有 `.tscn`，断言关键节点路径与类型（如 `Board/TileMapLayer`、`HUD/Status`、`HUD/EndPanel/RematchBtn`）。
- 改 `verify_project`：改读 `TileMapLayer.get_cell_atlas_coords()` / `tile_set`，不再引用 `MatchBoard.TEX_*`。
- 改 `verify_feel` / `verify_powerups` / `verify_bot`：只走公开方法或 `unique_name_in_owner` 的稳定路径；`BombGhost` 改为场景里的固定子节点。
- `scripts/match/*` 的单测保持不变。
- 更新 `ARCHITECTURE.md`：目录职责增加 `scenes/game/*`、`assets/tilesets|anim|ui/styles`；明确“表现层可以是节点场景”。重写其中已过时的段落（目录表、`MatchBoard`/`MatchHud` 描述），保留硬性规则（RPC 位置、`match/*` 纯度、Autoload 瘦、中文主题、验证要求）。
- `docs/DEPLOY-TOY.md` 与场景结构无关，保持原文不动；README 对两份文档的引用保留。

**验收**：15 个旧脚本 + 1 个新脚本全绿；`godot --headless --check-only` 无解析错误。

### Phase 8 — 清理与回归

- 删死代码：`_make_tile`、`_build_frames`、`map_sprites`、`board_origin`（若已改用场景坐标）、`_clay_style`。
- 常量单源：`TILE` 现在在 `game_root.gd` 与 `match_board.gd` 各写一份 48，统一到 `Arena.TILE`（或新建 `scripts/match/map_metrics.gd`）。
- 回归清单：
  1. 单机 F6 开局 → 放雷 → 炸软墙 → 捡道具 → 90 秒缩圈 → 结算 → 再来一局；
  2. 两个桌面客户端 + `--headless -- --server`：开房、准备、开局、客机拉回、断线回大厅；
  3. Web 导出后在浏览器：大厅、单机、音量开关、`/ws` 联机；
  4. 音频（BGM 切换、SFX 重叠、静音记忆）；
  5. 4 张地图 + 随机地图 + 人机补位。

**验收**：以上全过；README 目录表与 `ARCHITECTURE.md` 已同步；导出产物大小无异常增长。

---

## 5. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 去掉 `49/48` 补缝后出现白缝 | 视觉回归 | 在 TileSet 层解决；Phase 2 先做截图对比再继续 |
| `TileMapLayer` 在 headless 专用服下行为差异 | 服务器崩溃/绘制异常 | 绘制只由主机/客机客户端调用；专用服本来就 `visible=false`，用 `verify_net` 回归 |
| 编辑器预置 + 运行时重绘双份状态 | 幽灵格、错位 | 约定 `draw_map()` 首行 `clear()`；`Preview` 节点在 `_ready()` 第一行释放 |
| `verify_*` 断言大面积失效 | 失去回归保护 | Phase 7 与各阶段同步改，不留到最后；先加 `verify_scenes` 兜底 |
| `.tscn` 手工冲突 | 合并困难 | 每阶段单 PR；同一场景同时只允许一人编辑；提交粒度按场景 |
| 场景资源漏出导出包 | 线上缺图 | `all_resources` 已覆盖；Phase 8 用导出产物实跑一次网页 |
| 重构中途协议被误改 | 联机不可用 | 红线清单第 1.3 节；`verify_net` 每阶段必跑 |

---

## 6. 明确不做的事

- 不重写联机层、不改 `@rpc` 列表、不改端口/域名/房间码规则。
- 不重做美术：现成水彩贴图与音频全部复用，只做切片/资源封装。
- 不调平衡：炸弹、火力、移速、缩圈、人机参数保持现值。
- 不引入新框架或插件；不新增第三方依赖。
- 不为了“手工”把规则逻辑搬进场景脚本。

---

## 7. 完成定义（DoD）

- [ ] `game.tscn` 在编辑器 2D 视图能看到地图、四色角色样例、炸弹、道具、HUD 布局。
- [ ] 地图由 `TileMapLayer + TileSet` 绘制；角色/炸弹/道具/特效均由 `.tscn` 实例化。
- [ ] 大厅样式全部来自 `.tres`，`lobby.gd` 不再运行时拼 `StyleBoxTexture`。
- [ ] 15 个原有验证脚本 + `verify_scenes.gd` 全绿。
- [ ] 单机、双客户端联机、专用服 headless、Web 导出四条路径回归通过。
- [ ] `README.md` 与 `docs/ARCHITECTURE.md` 已按新结构更新。
- [ ] 无死代码残留；`TILE` 等常量单一来源。
