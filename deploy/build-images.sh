#!/usr/bin/env bash
# Build Docker images on box/Singapore after Godot export.
# Usage (from repo root):
#   ./deploy/build-images.sh
#   ./deploy/build-images.sh --save   # also write tar for Hangzhou rsync
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f build/web/index.html ]]; then
  echo "Missing build/web/index.html — export Web first:" >&2
  echo "  godot --headless --path . --export-release Web build/web/index.html" >&2
  exit 1
fi
if [[ ! -x build/server/bomberman-server.x86_64 ]]; then
  echo "Missing build/server/bomberman-server.x86_64 — export Linux Server first:" >&2
  echo "  godot --headless --path . --export-release \"Linux Server\" build/server/bomberman-server.x86_64" >&2
  exit 1
fi

docker compose -f deploy/docker-compose.yml build

if [[ "${1:-}" == "--save" ]]; then
  mkdir -p build/docker
  OUT="build/docker/bomberman-images.tar"
  echo "Saving bomberman-web:latest + bomberman-game:latest → $OUT"
  docker save bomberman-web:latest bomberman-game:latest -o "$OUT"
  ls -lh "$OUT"
  echo "On Hangzhou: docker load -i bomberman-images.tar && docker compose -f deploy/docker-compose.yml up -d"
fi

echo "OK. Local smoke: docker compose -f deploy/docker-compose.yml up -d"
echo "Then open http://127.0.0.1:${BOMBERMAN_HTTP_PORT:-18080}/"
