# 音频出处与许可

## 总览

2026-10-31 起，**BGM 与 SFX 均**为本机 **Stable Audio 3 MLX**（`./sa3`，BGM 用 `sm-music`、SFX 用 `sm-sfx`，解码 `same-s`）按水彩气质生成的候选，再经 `ffmpeg`（libvorbis）压成 Ogg Vorbis。候选源 wav / 预览与 `manifest.json` 见 `/workspace/_audio_candidates_bomberman_watercolor_2026-10-31/`（**勿提交进仓**；gitignore / 导出排除同旧 BGM 候选约定）。

许可以 Stable Audio 3 / 所用权重条款为准；仅用于本项目摸鱼炸弹人。旧芯片乐脚本 `tools/gen_audio.py` 仍保留，**不再作为线上 BGM/SFX 来源**。

## BGM（`bgm/*.ogg`）

| 文件 | 候选源 | 内容 | 备注 |
|------|--------|------|------|
| `bgm/lobby.ogg` | `02_lobby_b.wav` | 大厅循环，约 32s，水彩明亮菜单感 | `loop=true` |
| `bgm/match.ogg` | `04_match_b.wav` | 对局循环，约 34s，水彩对战 | `loop=true` |
| `bgm/sudden_death.ogg` | `06_sudden_b.wav` | 缩圈循环，约 28s，加快但仍偏欢乐 | `loop=true` |
| `bgm/win.ogg` | `07_win.wav` | 胜利短句，约 8s | 不循环 |
| `bgm/lose.ogg` | `08_lose.wav` | 失败 / 平局短句，约 8s | 不循环 |

生成负向提示统一排除人声。种子 / CFG / 时长见该目录 `manifest.json`。

## 音效（`sfx/*.ogg`）

同批 SA3 `sm-sfx` 水彩气质生成后压成 Ogg（主文件；`boom`/`pickup` 等未采用 `_b` 备选）。

| 文件 | 用途 |
|------|------|
| `place_bomb.ogg` | 放弹 |
| `boom.ogg` | 爆炸 |
| `soft_break.ogg` | 软墙碎裂（与 boom 并存，每次爆炸最多一次） |
| `kick.ogg` | 踢弹 |
| `death.ogg` | 阵亡 |
| `pickup.ogg` | 拾取道具 |
| `airdrop_land.ogg` | 空投落地 |
| `ui_click.ogg` | 界面点击 |
| `enter_room.ogg` | 进房 |
| `ready.ogg` | 准备 |

没有使用 OpenGameArt / Freesound / Kenney 的成品音效。
