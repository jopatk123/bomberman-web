#!/usr/bin/env python3
"""从定稿预览切片水彩贴图到 assets/art/watercolor/（及 UI / icon）。注释中文。"""
from __future__ import annotations

import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "art" / "watercolor"
UI = ROOT / "assets" / "ui"
SCRATCH = Path("/workspace/_scratch/wc-batch-inspect")
AGENT = Path("/home/box/agent-data/agents/ffb181b0-6022-4416-9d2e-a2c7e4603038/assets")
STORE = Path(
    "/cursor/stores/store-518ef264-8a8b-41ba-a3b7-0778be9e9e91"
    "/grok-bot/agents/ffb181b0-6022-4416-9d2e-a2c7e4603038/assets"
)
PREVIEW = ROOT / "build" / "preview-art-options"


def load(p: Path) -> Image.Image:
    return Image.open(p).convert("RGBA")


def paper_to_alpha(im: Image.Image, thr: int = 238) -> Image.Image:
    """近白纸底转透明，保留水彩笔触。"""
    a = np.asarray(im).astype(np.int16)
    rgb = a[:, :, :3]
    # 近白且低饱和
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    near_white = (mx >= thr) & ((mx - mn) < 28)
    out = a.copy()
    out[near_white, 3] = 0
    # 边缘半透明软化
    alpha = out[:, :, 3].astype(np.float32)
    soft = (mx.astype(np.float32) - 210).clip(0, 45)
    fade = (1.0 - soft / 45.0)
    alpha = np.where(near_white, 0, alpha * fade)
    out[:, :, 3] = alpha.clip(0, 255).astype(np.uint8)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def trim(im: Image.Image, pad: int = 2) -> Image.Image:
    bbox = im.split()[-1].getbbox()
    if not bbox:
        return im
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(im.width, x1 + pad)
    y1 = min(im.height, y1 + pad)
    return im.crop((x0, y0, x1, y1))


def fit_square(im: Image.Image, size: int = 48) -> Image.Image:
    im = trim(im)
    if im.width == 0 or im.height == 0:
        return Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # 等比放入 size，居中
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    scale = min(size / im.width, size / im.height)
    nw = max(1, int(round(im.width * scale)))
    nh = max(1, int(round(im.height * scale)))
    resized = im.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2), resized)
    return canvas


def save_png(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG")
    print("wrote", path.relative_to(ROOT), im.size)


def grid_cells(im: Image.Image, cols: int, rows: int, mx=0.04, my=0.06, gx=0.01, gy=0.02):
    """按等分网格切（带边距）。"""
    w, h = im.size
    left = int(w * mx)
    top = int(h * my)
    right = int(w * (1 - mx))
    bottom = int(h * (1 - my))
    cw = (right - left) / cols
    ch = (bottom - top) / rows
    gapx = cw * gx
    gapy = ch * gy
    cells = []
    for r in range(rows):
        row = []
        for c in range(cols):
            x0 = int(left + c * cw + gapx)
            y0 = int(top + r * ch + gapy)
            x1 = int(left + (c + 1) * cw - gapx)
            y1 = int(top + (r + 1) * ch - gapy)
            row.append(im.crop((x0, y0, x1, y1)))
        cells.append(row)
    return cells


def sheet_horizontal(frames: list[Image.Image], size: int = 48) -> Image.Image:
    out = Image.new("RGBA", (size * len(frames), size), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        out.paste(fr, (i * size, 0), fr)
    return out


def main() -> None:
    # ---- 角色：wc-b1-chars 5×4；取蓝/浣熊/绿鸟/黄蝾螈 ----
    chars = load(AGENT / "wc-b1-chars.jpg")
    cells = grid_cells(chars, 5, 4, mx=0.03, my=0.05, gx=0.03, gy=0.04)
    # col map: 0 blue, 1 red(raccoon), 2 green, 3 skip, 4 yellow
    col_map = {"blue": 0, "red": 1, "green": 2, "yellow": 4}
    for color, col in col_map.items():
        frames48 = []
        for r in range(4):
            cell = paper_to_alpha(cells[r][col])
            frames48.append(fit_square(cell, 48))
        # idle = 第 0 帧；walk = 0..3 再补第 0 凑满 5
        idle = frames48[0]
        walk_frames = [frames48[0], frames48[1], frames48[2], frames48[3], frames48[0]]
        save_png(idle, OUT / "entities" / f"player_{color}.png")
        save_png(sheet_horizontal(walk_frames), OUT / "entities" / "anim" / f"player_{color}_sheet.png")

    # ---- 地砖 / 硬软墙 / 碎箱：n01 ----
    tiles = load(SCRATCH / "n01_094508.jpg")
    tcells = grid_cells(tiles, 5, 3, mx=0.05, my=0.08, gx=0.04, gy=0.06)
    # 顶行 A B hard A B；中 soft 在右；底 soft_break×3
    floor_a = fit_square(tcells[0][0].convert("RGBA"), 48)  # 草地可保留不透明
    floor_b = fit_square(tcells[0][1].convert("RGBA"), 48)
    hard = fit_square(paper_to_alpha(tcells[0][2]), 48)
    soft = fit_square(paper_to_alpha(tcells[1][4]), 48)
    # 若 soft 空则用中排其他
    if soft.getextrema()[3][1] == 0:
        soft = fit_square(paper_to_alpha(tcells[1][3]), 48)
    save_png(floor_a, OUT / "tiles" / "floor_a.png")
    save_png(floor_b, OUT / "tiles" / "floor_b.png")
    save_png(hard, OUT / "tiles" / "hard.png")
    save_png(soft, OUT / "tiles" / "soft.png")
    for i in range(3):
        br = fit_square(paper_to_alpha(tcells[2][i]), 48)
        save_png(br, OUT / "fx" / f"soft_break_{i}.png")

    # ---- 炸弹 / 爆炸：n03 ----
    bomb_sheet = load(SCRATCH / "n03_094822.jpg")
    bcells = grid_cells(bomb_sheet, 6, 4, mx=0.04, my=0.06, gx=0.02, gy=0.04)
    bomb = fit_square(paper_to_alpha(bcells[0][0]), 48)
    save_png(bomb, OUT / "entities" / "bomb.png")
    # 爆炸中心取第三行中间帧
    blast_c = fit_square(paper_to_alpha(bcells[2][2]), 48)
    save_png(blast_c, OUT / "fx" / "blast_center.png")
    # 横/竖焰：从爆炸帧做拉伸裁切
    src = paper_to_alpha(bcells[2][3])
    src = trim(src)
    # 横臂：取中部水平带
    if src.height > 8 and src.width > 8:
        mid_y = src.height // 2
        band = src.crop((0, max(0, mid_y - src.height // 5), src.width, min(src.height, mid_y + src.height // 5)))
        blast_h = fit_square(band, 48)
        mid_x = src.width // 2
        vband = src.crop((max(0, mid_x - src.width // 5), 0, min(src.width, mid_x + src.width // 5), src.height))
        blast_v = fit_square(vband, 48)
    else:
        blast_h = blast_c.copy()
        blast_v = blast_c.copy()
    save_png(blast_h, OUT / "fx" / "blast_h.png")
    save_png(blast_v, OUT / "fx" / "blast_v.png")

    # ---- 道具：n04 五格；pierce 用 n16 箭矢语义 ----
    pu = load(SCRATCH / "n04_094827.jpg")
    # 2×3 布局但只有 5：上3 下2
    pcells = grid_cells(pu, 3, 2, mx=0.08, my=0.10, gx=0.06, gy=0.08)
    names = [
        ("powerup_bomb", pcells[0][0]),
        ("powerup_range", pcells[0][1]),
        ("powerup_speed", pcells[0][2]),
        ("powerup_kick", pcells[1][0]),
    ]
    for name, cell in names:
        save_png(fit_square(paper_to_alpha(cell), 48), OUT / "entities" / f"{name}.png")
    # pierce：n16 粉箭
    pierce_src = load(SCRATCH / "n16_100216.jpg")
    # 取中央偏上箭矢区域
    w, h = pierce_src.size
    crop = pierce_src.crop((int(w * 0.15), int(h * 0.25), int(w * 0.85), int(h * 0.75)))
    save_png(fit_square(paper_to_alpha(crop, thr=230), 48), OUT / "entities" / "powerup_pierce.png")

    # ---- 空投标记 + 缩圈焰：n06 ----
    fx6 = load(SCRATCH / "n06_095246.jpg")
    fcells = grid_cells(fx6, 3, 2, mx=0.12, my=0.12, gx=0.06, gy=0.08)
    save_png(fit_square(paper_to_alpha(fcells[0][0]), 48), OUT / "fx" / "airdrop_mark.png")
    for i in range(3):
        save_png(fit_square(paper_to_alpha(fcells[1][i]), 48), OUT / "fx" / f"sd_hazard_{i}.png")

    # ---- 大厅背景：styles-detail watercolor-lobby ----
    lobby = Image.open(PREVIEW / "styles-detail" / "watercolor-lobby.jpg").convert("RGB")
    lobby = lobby.resize((960, 720), Image.Resampling.LANCZOS)
    lobby_path = OUT / "lobby_bg.jpg"
    lobby_path.parent.mkdir(parents=True, exist_ok=True)
    lobby.save(lobby_path, "JPEG", quality=88)
    print("wrote", lobby_path.relative_to(ROOT), lobby.size)

    # ---- 结算面板 ----
    end = load(SCRATCH / "n18_100231.jpg")
    half = end.width // 2
    win = end.crop((0, 0, half, end.height))
    lose = end.crop((half, 0, end.width, end.height))
    save_png(win.resize((480, 540), Image.Resampling.LANCZOS), OUT / "ui" / "end_win.png")
    save_png(lose.resize((480, 540), Image.Resampling.LANCZOS), OUT / "ui" / "end_lose.png")

    # ---- splash ----
    splash = Image.open(SCRATCH / "n13_095951.jpg").convert("RGB")
    splash = splash.resize((960, 540), Image.Resampling.LANCZOS)
    splash.save(OUT / "splash.png", "PNG")
    print("wrote", (OUT / "splash.png").relative_to(ROOT))

    # ---- UI 九宫：n15 石质按钮；备份旧像素到 ui/pixel_backup 不强制 ----
    ui_sheet = load(SCRATCH / "n15_100215.jpg")
    # 顶行 5 按钮：normal hover pressed disabled focus
    ucells = grid_cells(ui_sheet, 5, 3, mx=0.06, my=0.08, gx=0.03, gy=0.08)
    btn_names = ["btn_normal", "btn_hover", "btn_pressed", "btn_disabled", "btn_focus"]
    for i, name in enumerate(btn_names):
        cell = ucells[0][i].convert("RGBA")
        # 做成可九宫的 48×48（留边）
        btn = fit_square(cell, 48)
        # 略不透明底板：对近白做保留以便主题九宫
        save_png(btn, UI / f"{name}.png")
    # panel：中左大格
    panel_src = ui_sheet.crop((int(ui_sheet.width * 0.05), int(ui_sheet.height * 0.42),
                               int(ui_sheet.width * 0.42), int(ui_sheet.height * 0.92)))
    panel = panel_src.resize((48, 48), Image.Resampling.LANCZOS).convert("RGBA")
    save_png(panel, UI / "panel_nine.png")
    # edit bars：底中 pill → 做 48×24 再扩
    edit = ucells[2][0] if False else ui_sheet.crop(
        (int(ui_sheet.width * 0.42), int(ui_sheet.height * 0.48),
         int(ui_sheet.width * 0.72), int(ui_sheet.height * 0.62))
    )
    for name, thr in [("edit_normal", 0), ("edit_focus", 1), ("edit_disabled", 2)]:
        e = edit.resize((64, 24), Image.Resampling.LANCZOS).convert("RGBA")
        save_png(e, UI / f"{name}.png")

    # arrow
    arrow_crop = ui_sheet.crop(
        (int(ui_sheet.width * 0.78), int(ui_sheet.height * 0.70),
         int(ui_sheet.width * 0.95), int(ui_sheet.height * 0.95))
    )
    save_png(fit_square(paper_to_alpha(arrow_crop), 24), UI / "arrow_down.png")

    # ---- icon：n19 ----
    icon = load(SCRATCH / "n19_100625.jpg")
    icon_sq = icon.resize((512, 512), Image.Resampling.LANCZOS)
    icon_path = ROOT / "icon.png"
    icon_sq.save(icon_path, "PNG")
    print("wrote icon.png")
    # 同步写一个简易 SVG 引用说明：Godot 用 config/icon 指 PNG
    # 保留 icon.svg 但改成指向水彩图不方便；直接换 project 配置

    # 空投箱静帧（可选 P1）
    air = load(SCRATCH / "n14_100011.jpg")
    ac = grid_cells(air, 6, 1, mx=0.03, my=0.20, gx=0.02, gy=0.1)[0]
    save_png(fit_square(paper_to_alpha(ac[2]), 48), OUT / "entities" / "airdrop_crate.png")

    print("DONE")


if __name__ == "__main__":
    main()
