# 音频出处与许可

## BGM（`bgm/*.ogg`）

2026-10-29 起，大厅 / 对局 / 缩圈循环与胜负短句改用本机 **Stable Audio 3 MLX**（`./sa3`，`sm-music` + `same-s`）生成的候选曲，再经 `ffmpeg`（libvorbis）压成 Ogg。源 wav / 预览与提示词见仓库旁目录 `_bgm_candidates/2026-10-29/`（已 gitignore，不入库）。

| 文件 | 候选源 | 内容 | 备注 |
|------|--------|------|------|
| `bgm/lobby.ogg` | `01_lobby_bright.wav` | 大厅循环，约 30s，明亮街机菜单感 | `loop=true` |
| `bgm/match.ogg` | `08_match_funky.wav` | 对局循环，约 32s，funky 街机对战 | `loop=true` |
| `bgm/sudden_death.ogg` | `04_sudden_death_up.wav` | 缩圈循环，约 30s，加快但仍偏欢乐 | `loop=true` |
| `bgm/win.ogg` | `05_win_fanfare.wav` | 胜利短句，约 7s | 不循环 |
| `bgm/lose.ogg` | `06_lose_soft.wav` | 失败 / 平局短句，约 7s | 不循环 |

生成负向提示统一排除人声。种子 / CFG / 时长见该目录 `manifest.json`。许可以 Stable Audio 3 / 所用权重条款为准；仅用于本项目摸鱼炸弹人。

旧版芯片乐脚本仍保留：`tools/gen_audio.py`（不再作为线上 BGM 来源）。

## 音效（`sfx/*.ogg`）

仍为本项目 `tools/gen_audio.py` 写的原创芯片音效（放弹、爆炸、踢弹、死亡、拾取、界面点击、进房、准备），作者贡献到公有领域，**CC0 1.0**：<https://creativecommons.org/publicdomain/zero/1.0/>。

可再分发、修改、商用，不要求署名。没有使用 OpenGameArt / Freesound / Kenney 的成品音效。
