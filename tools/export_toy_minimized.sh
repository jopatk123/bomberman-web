#!/usr/bin/env bash
# 正式 Toy 包：Godot Web 导出 + Minimize Web Build（gzip+pako）+ pack_toy。
# 产物：build/toy-minimized/bomberman-toy.zip（以后上线一律用这个，不要用未压缩 build/toy）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
WEB_OUT="$ROOT/build/web-minimized"
TOY_OUT="$ROOT/build/toy-minimized"
mkdir -p "$WEB_OUT"
"$GODOT" --headless --path "$ROOT" --export-release "Web" "$WEB_OUT/index.html"
TOY_WEB_SRC="$WEB_OUT" TOY_WEB_DEST="$TOY_OUT" "$ROOT/tools/pack_toy.sh"
ls -lh "$TOY_OUT/bomberman-toy.zip"
