#!/usr/bin/env python3
"""自绘摸鱼炸弹人的草地与道具图标。

硬像素：调色板着色，最近邻放大，alpha 只有 0 或 255。
不使用模糊、抗锯齿或软阴影。输出可直接覆盖仓库贴图。
"""

from __future__ import annotations

import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TILE = 48

# 两色草地。对比比旧棋盘柔，但隔一格仍能分开。
A_BASE = (104, 176, 54, 255)
A_ALT = (96, 166, 48, 255)
A_LITE = (136, 202, 76, 255)
A_DARK = (68, 136, 36, 255)
A_BLADE = (42, 108, 28, 255)
A_BLADE_HI = (158, 214, 90, 255)

B_BASE = (74, 146, 44, 255)
B_ALT = (66, 136, 40, 255)
B_LITE = (108, 174, 60, 255)
B_DARK = (46, 112, 30, 255)
B_BLADE = (32, 92, 24, 255)
B_BLADE_HI = (132, 190, 68, 255)

PETAL = (248, 248, 240, 255)
PETAL_SHADE = (214, 220, 200, 255)
CENTER = (236, 188, 48, 255)
STEM = (36, 102, 26, 255)
DIRT = (138, 86, 46, 255)
DIRT_D = (96, 56, 32, 255)
DIRT_L = (176, 120, 68, 255)


def new_canvas(w: int, h: int, fill) -> Image.Image:
    return Image.new("RGBA", (w, h), fill)


def put(px, x: int, y: int, c, w: int, h: int) -> None:
    if 0 <= x < w and 0 <= y < h:
        px[x, y] = c


def fill_rect(px, x0, y0, x1, y1, c, w, h) -> None:
    for y in range(y0, y1):
        for x in range(x0, x1):
            put(px, x, y, c, w, h)


def disc(px, cx, cy, r, c, w, h) -> None:
    r2 = r * r
    for y in range(cy - r - 1, cy + r + 2):
        for x in range(cx - r - 1, cx + r + 2):
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2:
                put(px, x, y, c, w, h)


def stamp(dst: Image.Image, src: Image.Image, ox: int, oy: int, only_if=None) -> None:
    """把 src 非透明像素盖到 dst。only_if(x, y) 为假时跳过该像素。"""
    sp = src.load()
    dp = dst.load()
    sw, sh = src.size
    dw, dh = dst.size
    for y in range(sh):
        for x in range(sw):
            c = sp[x, y]
            if c[3] == 0:
                continue
            tx, ty = ox + x, oy + y
            if not (0 <= tx < dw and 0 <= ty < dh):
                continue
            if only_if is not None and not only_if(tx, ty):
                continue
            dp[tx, ty] = c


def add_outline(im: Image.Image, color) -> None:
    src = im.copy()
    sp = src.load()
    dp = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if sp[x, y][3] != 0:
                continue
            hit = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h and sp[xx, yy][3] == 255:
                    hit = True
                    break
            if hit:
                dp[x, y] = color


def assert_hard_pixels(im: Image.Image, name: str) -> None:
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            a = px[x, y][3]
            if a not in (0, 255):
                raise SystemExit(f"{name} 出现半透明像素 ({x},{y}) a={a}")


def flower_sprite() -> Image.Image:
    im = new_canvas(10, 12, (0, 0, 0, 0))
    px = im.load()
    # 小雏菊：2 像素花瓣，硬边。
    petals = [
        (3, 0), (4, 0), (5, 0),
        (2, 1), (3, 1), (4, 1), (5, 1), (6, 1),
        (1, 2), (2, 2), (6, 2), (7, 2),
        (1, 3), (7, 3),
        (1, 4), (7, 4),
        (1, 5), (2, 5), (6, 5), (7, 5),
        (2, 6), (3, 6), (4, 6), (5, 6), (6, 6),
        (3, 7), (4, 7), (5, 7),
    ]
    for x, y in petals:
        px[x, y] = PETAL if y < 4 else PETAL_SHADE
    for x in range(3, 6):
        for y in range(3, 6):
            px[x, y] = CENTER
    px[4, 2] = CENTER
    px[4, 8] = STEM
    px[4, 9] = STEM
    px[3, 10] = STEM
    px[4, 10] = STEM
    px[5, 10] = STEM
    px[4, 11] = STEM
    return im


def tuft_sprite(dark, hi, heights=(7, 5, 8, 4)) -> Image.Image:
    width = 2 * len(heights) - 1
    tall = max(heights)
    im = new_canvas(width, tall, (0, 0, 0, 0))
    px = im.load()
    for i, hgt in enumerate(heights):
        bx = i * 2
        for k in range(hgt):
            y = tall - 1 - k
            px[bx, y] = hi if k == hgt - 1 or k == hgt - 3 else dark
    return im


def dirt_sprite() -> Image.Image:
    im = new_canvas(8, 6, (0, 0, 0, 0))
    px = im.load()
    blob = [
        "  DDDD  ",
        " DDDLDD ",
        "DDLLLDDD",
        "DDDLDDDD",
        " DDDDDD ",
        "  DDDD  ",
    ]
    pal = {"D": DIRT, "L": DIRT_L, "X": DIRT_D}
    for y, row in enumerate(blob):
        for x, ch in enumerate(row):
            if ch == " ":
                continue
            px[x, y] = pal[ch]
    px[1, 3] = DIRT_D
    px[6, 2] = DIRT_D
    px[5, 4] = DIRT_D
    return im


def paint_specks(px, lite, dark, alt, points_lite, points_dark, points_alt, w, h) -> None:
    for x, y in points_alt:
        put(px, x, y, alt, w, h)
        put(px, x + 1, y, alt, w, h)
    for x, y in points_lite:
        put(px, x, y, lite, w, h)
    for x, y in points_dark:
        put(px, x, y, dark, w, h)


def make_floor(base, alt, lite, dark, blade, blade_hi, with_flower: bool, with_dirt: bool) -> Image.Image:
    im = new_canvas(TILE, TILE, base)
    px = im.load()
    if with_flower:
        lites = [(6, 6), (18, 8), (40, 10), (30, 18), (8, 28), (42, 26), (16, 40), (36, 42), (44, 36), (22, 34)]
        darks = [(12, 14), (28, 8), (38, 20), (10, 36), (32, 30), (44, 16), (20, 22)]
        alts = [(4, 20), (26, 12), (14, 32), (40, 40)]
    else:
        lites = [(8, 10), (20, 6), (36, 12), (14, 22), (42, 24), (28, 28), (6, 34), (18, 40), (40, 38), (32, 18)]
        darks = [(16, 8), (30, 14), (10, 26), (38, 30), (22, 36), (44, 18), (8, 42)]
        alts = [(6, 16), (24, 8), (36, 22), (12, 38)]
    paint_specks(px, lite, dark, alt, lites, darks, alts, TILE, TILE)
    if with_flower:
        stamp(im, tuft_sprite(blade, blade_hi, (6, 4, 7)), 30, 34)
        stamp(im, tuft_sprite(blade, blade_hi, (4, 3, 5)), 16, 26)
        stamp(im, flower_sprite(), 6, 8)
    else:
        stamp(im, tuft_sprite(blade, blade_hi, (7, 5, 8, 4)), 6, 30)
        stamp(im, tuft_sprite(blade, blade_hi, (5, 3, 6)), 34, 12)
        stamp(im, dirt_sprite(), 22, 20)
    assert_hard_pixels(im, "floor")
    return im


def _recolor_disc_shade(px, cx, cy, r, x_cut, shade, w, h) -> None:
    r2 = r * r
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, x_cut):
            if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2:
                put(px, x, y, shade, w, h)


def icon_bomb() -> Image.Image:
    im = new_canvas(TILE, TILE, (0, 0, 0, 0))
    px = im.load()
    navy = (8, 26, 84, 255)
    blue = (36, 112, 232, 255)
    shade = (16, 62, 176, 255)
    lite = (156, 214, 255, 255)
    white = (255, 255, 255, 255)
    metal = (188, 192, 202, 255)
    fuse = (78, 82, 94, 255)
    spark = (255, 136, 32, 255)
    hot = (255, 226, 80, 255)
    disc(px, 24, 30, 15, navy, TILE, TILE)
    disc(px, 24, 30, 13, blue, TILE, TILE)
    _recolor_disc_shade(px, 24, 30, 13, 20, shade, TILE, TILE)
    disc(px, 18, 24, 4, lite, TILE, TILE)
    # 白加号，两像素粗，放在弹体下半。
    fill_rect(px, 15, 30, 34, 33, white, TILE, TILE)
    fill_rect(px, 23, 24, 26, 39, white, TILE, TILE)
    fill_rect(px, 22, 16, 27, 19, metal, TILE, TILE)
    for x, y in ((26, 15), (28, 13), (30, 11), (32, 9)):
        fill_rect(px, x, y, x + 2, y + 2, fuse, TILE, TILE)
    disc(px, 35, 7, 2, hot, TILE, TILE)
    for x, y in ((33, 5), (37, 5), (33, 9), (37, 9), (35, 4), (35, 10)):
        put(px, x, y, spark, TILE, TILE)
    add_outline(im, (4, 14, 44, 255))
    return im


def icon_range() -> Image.Image:
    im = new_canvas(TILE, TILE, (0, 0, 0, 0))
    px = im.load()
    # (y, x0, x1) 含端点。上窄下宽再收尖，避免画成菱形。
    spans = [
        (3, 23, 25),
        (4, 22, 27),
        (5, 21, 29),
        (6, 20, 31),
        (7, 19, 33),
        (8, 18, 34),
        (9, 17, 35),
        (10, 16, 36),
        (11, 16, 36),
        (12, 15, 37),
        (13, 15, 37),
        (14, 14, 37),
        (15, 14, 36),
        (16, 15, 36),
        (17, 15, 35),
        (18, 16, 35),
        (19, 17, 34),
        (20, 17, 34),
        (21, 18, 33),
        (22, 18, 32),
        (23, 19, 32),
        (24, 20, 31),
        (25, 20, 30),
        (26, 21, 29),
        (27, 22, 28),
        (28, 23, 27),
        (29, 24, 26),
    ]
    dark = (120, 16, 8, 255)
    red = (214, 48, 16, 255)
    orange = (255, 132, 24, 255)
    yellow = (255, 204, 48, 255)
    white = (255, 252, 236, 255)
    for y, x0, x1 in spans:
        for x in range(x0, x1 + 1):
            edge = min(x - x0, x1 - x)
            if edge <= 0:
                c = dark
            elif edge <= 2:
                c = red
            elif edge <= 4:
                c = orange
            elif edge <= 6:
                c = yellow
            else:
                c = white
            # 焰心偏上，把中部再提亮一档。
            if 18 <= x <= 30 and 8 <= y <= 16 and edge >= 4:
                c = white if edge >= 6 else yellow
            put(px, x, y, c, TILE, TILE)
    # 右上跳出来的一小簇火星，打破对称。
    for x, y, c in (
        (33, 5, orange), (34, 4, yellow), (35, 6, red),
        (20, 2, yellow), (24, 1, orange),
        (38, 8, orange), (38, 9, red),
    ):
        put(px, x, y, c, TILE, TILE)
    # 左侧咬掉一块，让轮廓更像火舌而不是菱形。
    for y in range(12, 17):
        for x in range(14, 19):
            if px[x, y][3]:
                px[x, y] = (0, 0, 0, 0)
    add_outline(im, (72, 8, 4, 255))
    return im


def icon_speed() -> Image.Image:
    im = new_canvas(TILE, TILE, (0, 0, 0, 0))
    px = im.load()
    body = (32, 198, 208, 255)
    shade = (12, 132, 154, 255)
    sole = (236, 246, 248, 255)
    stripe = (255, 255, 255, 255)
    motion = (132, 230, 236, 255)
    # 鞋底、鞋跟、鞋头。鞋头用硬圆，鞋跟是直块。
    fill_rect(px, 10, 30, 40, 36, sole, TILE, TILE)
    fill_rect(px, 12, 16, 26, 31, body, TILE, TILE)
    disc(px, 30, 26, 9, body, TILE, TILE)
    fill_rect(px, 14, 27, 34, 31, shade, TILE, TILE)
    fill_rect(px, 16, 20, 34, 23, stripe, TILE, TILE)
    fill_rect(px, 18, 25, 36, 28, stripe, TILE, TILE)
    # 鞋口：挖掉左上角，让它不像一块梯形。
    for i in range(5):
        fill_rect(px, 12, 16, 14 + i, 17 + i, (0, 0, 0, 0), TILE, TILE)
    fill_rect(px, 1, 18, 8, 20, motion, TILE, TILE)
    fill_rect(px, 3, 23, 9, 25, motion, TILE, TILE)
    fill_rect(px, 2, 28, 8, 30, motion, TILE, TILE)
    add_outline(im, (4, 48, 64, 255))
    return im


def icon_kick() -> Image.Image:
    im = new_canvas(TILE, TILE, (0, 0, 0, 0))
    px = im.load()
    boot = (156, 72, 216, 255)
    shade = (96, 32, 140, 255)
    lite = (216, 164, 255, 255)
    sole = (58, 16, 96, 255)
    blue = (36, 112, 232, 255)
    blue_d = (16, 62, 176, 255)
    spark = (255, 196, 48, 255)
    hot = (255, 244, 160, 255)
    # 靴筒在右上，鞋头朝左下，踢向小炸弹。
    fill_rect(px, 26, 8, 40, 28, boot, TILE, TILE)
    fill_rect(px, 16, 22, 40, 32, boot, TILE, TILE)
    disc(px, 18, 27, 6, boot, TILE, TILE)
    fill_rect(px, 14, 31, 40, 36, sole, TILE, TILE)
    fill_rect(px, 28, 10, 33, 22, lite, TILE, TILE)
    fill_rect(px, 18, 28, 36, 31, shade, TILE, TILE)
    for x, y in ((11, 22), (9, 26), (12, 30), (7, 28)):
        put(px, x, y, spark, TILE, TILE)
        put(px, x + 1, y, hot, TILE, TILE)
    # 小炸弹贴着鞋头左侧，读成「踢出去」。
    disc(px, 7, 29, 5, blue_d, TILE, TILE)
    disc(px, 7, 29, 4, blue, TILE, TILE)
    put(px, 5, 27, lite, TILE, TILE)
    put(px, 6, 27, lite, TILE, TILE)
    fill_rect(px, 6, 24, 8, 26, (90, 94, 104, 255), TILE, TILE)
    put(px, 7, 23, spark, TILE, TILE)
    add_outline(im, (32, 8, 52, 255))
    return im


def icon_pierce() -> Image.Image:
    im = new_canvas(TILE, TILE, (0, 0, 0, 0))
    px = im.load()
    mortar = (86, 48, 28, 255)
    brick = (176, 104, 56, 255)
    hi = (220, 152, 90, 255)
    shade = (128, 68, 36, 255)
    gold = (255, 204, 40, 255)
    gold_d = (176, 112, 16, 255)
    spark = (255, 236, 140, 255)
    ox, oy = 22, 12
    bw, bh = 7, 6
    for row in range(4):
        for col in range(3):
            x = ox + col * (bw + 1)
            y = oy + row * (bh + 1)
            fill_rect(px, x, y, x + bw, y + bh, brick, TILE, TILE)
            put(px, x, y, hi, TILE, TILE)
            put(px, x + 1, y, hi, TILE, TILE)
            put(px, x + bw - 1, y + bh - 1, shade, TILE, TILE)
            # 砖缝。
            if col < 2:
                fill_rect(px, x + bw, y, x + bw + 1, y + bh, mortar, TILE, TILE)
            if row < 3:
                fill_rect(px, x, y + bh, x + bw, y + bh + 1, mortar, TILE, TILE)
    # 箭杆穿过砖墙，箭头从右侧穿出。
    fill_rect(px, 6, 24, 44, 28, gold_d, TILE, TILE)
    fill_rect(px, 8, 25, 40, 27, gold, TILE, TILE)
    for i, y in enumerate(range(20, 32)):
        half = 6 - abs(y - 25)
        if half <= 0:
            continue
        x1 = 40 + (5 - abs(i - 5))
        fill_rect(px, 36, y, x1, y + 1, gold, TILE, TILE)
    # 箭羽。
    fill_rect(px, 4, 21, 10, 24, gold, TILE, TILE)
    fill_rect(px, 4, 28, 10, 31, gold, TILE, TILE)
    for x, y in ((45, 22), (46, 25), (44, 30), (47, 28)):
        put(px, x, y, spark, TILE, TILE)
    add_outline(im, (48, 24, 8, 255))
    return im


def build_powerups() -> dict[str, Image.Image]:
    icons = {
        "powerup_bomb.png": icon_bomb(),
        "powerup_range.png": icon_range(),
        "powerup_speed.png": icon_speed(),
        "powerup_kick.png": icon_kick(),
        "powerup_pierce.png": icon_pierce(),
    }
    for name, im in icons.items():
        if im.size != (48, 48):
            raise SystemExit(f"{name} 尺寸 {im.size}")
        assert_hard_pixels(im, name)
    return icons


def grassish(r: int, g: int, b: int) -> bool:
    return g >= 72 and g >= r + 22 and g >= b + 10


def in_corner_prop(x: int, y: int) -> bool:
    boxes = (
        (70, 70, 200, 175),
        (720, 70, 910, 175),
        (70, 520, 270, 655),
        (700, 520, 910, 655),
    )
    for x0, y0, x1, y1 in boxes:
        if x0 <= x < x1 and y0 <= y < y1:
            return True
    return False


def stoneish(r: int, g: int, b: int) -> bool:
    mx, mn = max(r, g, b), min(r, g, b)
    return mx >= 70 and mx - mn <= 48 and abs(r - g) <= 28 and g <= r + 18


def make_lobby(floor_a: Image.Image, floor_b: Image.Image) -> Image.Image:
    src = Image.open(os.path.join(ROOT, "assets/art/pixel/lobby_bg.jpg")).convert("RGB")
    w, h = src.size
    if (w, h) != (960, 720):
        raise SystemExit(f"大厅背景尺寸应为 960x720，实际 {w}x{h}")
    sp = src.load()
    replace = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b = sp[x, y]
            if not grassish(r, g, b):
                continue
            if in_corner_prop(x, y):
                # 角上的草也换成新草地；炸弹、土堆、火星不是草，会留下来。
                replace[y][x] = True
                continue
            replace[y][x] = True
    # 补上棋盘里被 JPEG 噪点打断的洞，但不吃石墙和角落道具。
    for _ in range(3):
        extra = []
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                if replace[y][x]:
                    continue
                r, g, b = sp[x, y]
                if stoneish(r, g, b):
                    continue
                if in_corner_prop(x, y) and not grassish(r, g, b):
                    continue
                n = 0
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if replace[y + dy][x + dx]:
                            n += 1
                if n >= 6:
                    extra.append((x, y))
        for x, y in extra:
            replace[y][x] = True

    out = src.copy()
    op = out.load()
    ap = floor_a.load()
    bp = floor_b.load()
    for y in range(h):
        for x in range(w):
            if not replace[y][x]:
                continue
            tile = ap if ((x // TILE) + (y // TILE)) % 2 == 0 else bp
            c = tile[x % TILE, y % TILE]
            op[x, y] = (c[0], c[1], c[2])

    def can(x, y) -> bool:
        return replace[y][x]

    # 大厅额外散点，打破两张地块的重复。坐标避开四角炸弹。
    extras = [
        ("flower", 230, 140),
        ("flower", 520, 180),
        ("flower", 410, 300),
        ("flower", 640, 260),
        ("flower", 300, 430),
        ("flower", 560, 480),
        ("flower", 180, 360),
        ("flower", 700, 400),
        ("dirt", 360, 160),
        ("dirt", 250, 250),
        ("dirt", 610, 360),
        ("dirt", 430, 450),
        ("dirt", 180, 470),
        ("tuft", 280, 200),
        ("tuft", 480, 220),
        ("tuft", 340, 360),
        ("tuft", 600, 160),
        ("tuft", 220, 420),
        ("tuft", 500, 400),
        ("tuft", 660, 470),
        ("tuft", 390, 180),
    ]
    fl = flower_sprite()
    dirt = dirt_sprite()
    tuft_a = tuft_sprite(A_BLADE, A_BLADE_HI, (6, 4, 7))
    tuft_b = tuft_sprite(B_BLADE, B_BLADE_HI, (7, 5, 8, 4))
    for i, (kind, x, y) in enumerate(extras):
        if kind == "flower":
            stamp(out, fl, x, y, can)
        elif kind == "dirt":
            stamp(out, dirt, x, y, can)
        else:
            stamp(out, tuft_a if i % 2 == 0 else tuft_b, x, y, can)
    return out.convert("RGB")


def save_png(im: Image.Image, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "PNG")


def main() -> None:
    floor_a = make_floor(A_BASE, A_ALT, A_LITE, A_DARK, A_BLADE, A_BLADE_HI, True, False)
    floor_b = make_floor(B_BASE, B_ALT, B_LITE, B_DARK, B_BLADE, B_BLADE_HI, False, True)
    save_png(floor_a, os.path.join(ROOT, "assets/art/pixel/tiles/floor_a.png"))
    save_png(floor_b, os.path.join(ROOT, "assets/art/pixel/tiles/floor_b.png"))
    icons = build_powerups()
    ent = os.path.join(ROOT, "assets/art/pixel/entities")
    for name, im in icons.items():
        save_png(im, os.path.join(ent, name))
    lobby = make_lobby(floor_a, floor_b)
    lobby_path = os.path.join(ROOT, "assets/art/pixel/lobby_bg.jpg")
    lobby.save(lobby_path, "JPEG", quality=95, subsampling=0, optimize=True)
    print("wrote floor_a floor_b lobby and", ", ".join(icons))


if __name__ == "__main__":
    main()
