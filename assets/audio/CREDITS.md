# 音频出处与许可

本目录下的 `.ogg` 全部是为本项目写的原创芯片乐和音效，不是从素材包里拆出来的。

| 文件 | 内容 | 许可 |
|------|------|------|
| `bgm/lobby.ogg` | 大厅循环，A 小调五声，约 96 BPM，8 小节 | CC0 1.0 |
| `bgm/match.ogg` | 对局循环，同一调性，约 128 BPM | CC0 1.0 |
| `bgm/sudden_death.ogg` | 缩圈循环，对局动机加快并加告警音 | CC0 1.0 |
| `bgm/win.ogg` | 胜利短句，不循环 | CC0 1.0 |
| `bgm/lose.ogg` | 失败 / 平局短句，不循环 | CC0 1.0 |
| `sfx/*.ogg` | 放弹、爆炸、踢弹、死亡、拾取、界面点击、进房、准备 | CC0 1.0 |

生成脚本：`tools/gen_audio.py`（方波 / 三角波 / 噪声，Python 标准库 + ffmpeg libvorbis）。重新生成：

```bash
python3 tools/gen_audio.py
```

作者把这些录音和脚本贡献到公有领域。CC0 1.0 全文：<https://creativecommons.org/publicdomain/zero/1.0/>。

可以再分发、修改、商用，不要求署名。没有使用 OpenGameArt / Freesound / Kenney 的成品，因此也不夹带那些站点上个别音效的非商用条款。
