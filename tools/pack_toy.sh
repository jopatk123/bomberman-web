#!/usr/bin/env bash
# 把已经导出的 build/web 打成 B 站小玩具可上传的 zip。
# 用法：
#   godot --headless --path . --export-release "Web" build/web/index.html
#   ./tools/pack_toy.sh
# 环境变量 TOY_PCK_AS_DATA=1：把 .pck 改成 .data，并在 GODOT_CONFIG 里写 mainPack。
# 默认保留 .pck。小玩具若只放行 .data，再打开这个开关。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# 默认读 build/web、写 build/toy。TOY_WEB_SRC / TOY_WEB_DEST 只给本地试跑用。
SRC="${TOY_WEB_SRC:-$ROOT/build/web}"
DEST="${TOY_WEB_DEST:-$ROOT/build/toy}"

if [[ ! -f "$SRC/index.html" ]]; then
	echo "找不到 $SRC/index.html。先把 Web 导出到 build/web/。" >&2
	exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC"/. "$DEST"/
rm -f "$DEST/bomberman-toy.zip"

export TOY_PACK_DEST="$DEST"
export TOY_PCK_AS_DATA="${TOY_PCK_AS_DATA:-0}"

python3 - <<'PY'
import json
import os
import re
import sys
import zipfile

dest = os.environ["TOY_PACK_DEST"]
as_data = os.environ.get("TOY_PCK_AS_DATA", "0") == "1"
index_path = os.path.join(dest, "index.html")
limit = 1024 * 1024

# 引号里的根路径：'/foo' 或 "/foo"，不要误伤协议相对的 '//host'。
QUOTED_ROOT = re.compile(r"""(?P<q>["'])(?P<path>/(?!/)[^"']*)(?P=q)""")
PROTO_REL = re.compile(r"""(?P<q>["'])(?P<path>//[^"']*)(?P=q)""")
# 没加引号的 href=/foo 或 url(/foo)。
BARE_ATTR = re.compile(r"""(?P<prefix>\b(?:href|src|poster|data|action|manifest)\s*=\s*)(?P<path>/(?!/)[^\s>"']+)""", re.I)
BARE_URL = re.compile(r"""(?P<prefix>url\(\s*)(?P<path>/(?!/)[^"'()\s]+)""", re.I)


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    sys.exit(1)


def find_named(suffix: str) -> list[str]:
    found = []
    for dirpath, _dirs, files in os.walk(dest):
        for name in files:
            if name.endswith(suffix):
                found.append(os.path.join(dirpath, name))
    return found


def rewrite_roots(html: str) -> tuple[str, int]:
    proto = PROTO_REL.search(html)
    if proto:
        fail("index.html 含有协议相对路径 %s，小玩具子路径下会指错主机。请改成相对路径。" % proto.group("path"))

    count = 0

    def quoted(match: re.Match) -> str:
        nonlocal count
        path = match.group("path")
        if path == "/":
            fail("index.html 含有根路径 '/'，不能安全地改成相对路径。")
        count += 1
        rel = path[1:]
        print("相对路径：%s -> %s" % (path, rel))
        return match.group("q") + rel + match.group("q")

    def bare(match: re.Match) -> str:
        nonlocal count
        path = match.group("path")
        if path == "/":
            fail("index.html 含有根路径 '/'，不能安全地改成相对路径。")
        count += 1
        rel = path[1:]
        print("相对路径：%s -> %s" % (path, rel))
        return match.group("prefix") + rel

    html = QUOTED_ROOT.sub(quoted, html)
    html = BARE_ATTR.sub(bare, html)
    html = BARE_URL.sub(bare, html)
    if PROTO_REL.search(html) or QUOTED_ROOT.search(html) or BARE_ATTR.search(html) or BARE_URL.search(html):
        fail("改写后 index.html 仍有以 / 开头的资源路径。")
    return html, count


def inject_main_pack(html: str, pack_name: str) -> str:
    marker = "const GODOT_CONFIG = "
    pos = html.find(marker)
    if pos < 0:
        marker = "var GODOT_CONFIG = "
        pos = html.find(marker)
    if pos < 0:
        fail("index.html 里没有 GODOT_CONFIG，无法写入 mainPack。")
    start = pos + len(marker)
    if start >= len(html) or html[start] != "{":
        fail("GODOT_CONFIG 不是 JSON 对象，无法写入 mainPack。")
    try:
        config, end = json.JSONDecoder().raw_decode(html[start:])
    except json.JSONDecodeError as exc:
        fail("解析 GODOT_CONFIG 失败：%s" % exc)
    if not isinstance(config, dict):
        fail("GODOT_CONFIG 不是对象。")
    config["mainPack"] = pack_name
    sizes = config.get("fileSizes")
    if isinstance(sizes, dict):
        renamed = {}
        for key, value in sizes.items():
            if isinstance(key, str) and key.endswith(".pck"):
                renamed[key[: -len(".pck")] + ".data"] = value
            else:
                renamed[key] = value
        config["fileSizes"] = renamed
    dumped = json.dumps(config, ensure_ascii=False, separators=(",", ":"))
    return html[:start] + dumped + html[start + end :]


def replace_name(old: str, new: str) -> None:
    text_ext = {".html", ".js", ".json", ".css", ".webmanifest", ".txt", ".svg"}
    for dirpath, _dirs, files in os.walk(dest):
        for name in files:
            ext = os.path.splitext(name)[1].lower()
            if ext not in text_ext:
                continue
            path = os.path.join(dirpath, name)
            with open(path, "r", encoding="utf-8") as fh:
                original = fh.read()
            if old not in original:
                continue
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(original.replace(old, new))


if not find_named(".js"):
    fail("build/web 里没有 .js。")
if not find_named(".wasm"):
    fail("build/web 里没有 .wasm。")
pcks = find_named(".pck")
if not pcks:
    fail("build/web 里没有 .pck。")

with open(index_path, "r", encoding="utf-8") as fh:
    html = fh.read()
html, nrewrites = rewrite_roots(html)
with open(index_path, "w", encoding="utf-8", newline="") as fh:
    fh.write(html)
print("index.html 根路径改写 %d 处。" % nrewrites)

if as_data:
    if len(pcks) != 1:
        fail("TOY_PCK_AS_DATA 需要恰好一个 .pck，当前有 %d 个。" % len(pcks))
    pck = pcks[0]
    data = pck[: -len(".pck")] + ".data"
    os.replace(pck, data)
    old_name = os.path.basename(pck)
    new_name = os.path.basename(data)
    with open(index_path, "r", encoding="utf-8") as fh:
        html = fh.read()
    html = inject_main_pack(html, new_name)
    with open(index_path, "w", encoding="utf-8", newline="") as fh:
        fh.write(html)
    replace_name(old_name, new_name)
    if old_name in open(index_path, encoding="utf-8").read():
        fail("index.html 里还留着 %s。" % old_name)
    with open(index_path, "r", encoding="utf-8") as fh:
        html = fh.read()
    if '"mainPack":"%s"' % new_name not in html and '"mainPack": "%s"' % new_name not in html:
        fail("mainPack 没有写成 %s。" % new_name)
    print("已将 %s 改为 %s，并写入 mainPack。" % (old_name, new_name))

size = os.path.getsize(index_path)
if size > limit:
    fail("index.html 有 %d 字节，超过 1MB 上限。" % size)
print("index.html %d 字节（上限 %d）。" % (size, limit))

zip_path = os.path.join(dest, "bomberman-toy.zip")
stored = {".wasm", ".pck", ".data", ".png", ".jpg", ".ogg", ".wav", ".ttf", ".woff", ".woff2"}
with zipfile.ZipFile(zip_path, "w") as zf:
    for dirpath, _dirs, files in os.walk(dest):
        for name in files:
            if name == "bomberman-toy.zip":
                continue
            full = os.path.join(dirpath, name)
            arc = os.path.relpath(full, dest).replace(os.sep, "/")
            if arc.startswith("/") or arc.startswith("../"):
                fail("zip 内出现了非相对路径：%s" % arc)
            ext = os.path.splitext(name)[1].lower()
            mode = zipfile.ZIP_STORED if ext in stored else zipfile.ZIP_DEFLATED
            zf.write(full, arc, compress_type=mode)

with zipfile.ZipFile(zip_path) as zf:
    names = zf.namelist()
    if "index.html" not in names:
        fail("zip 根目录没有 index.html。")
    if any(n.startswith("/") or n.startswith("../") for n in names):
        fail("zip 里有绝对路径。")
print("已打包 %s（%d 个文件）。" % (zip_path, len(names)))
PY
