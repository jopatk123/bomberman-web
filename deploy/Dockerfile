# Bomberman Web deploy image(s).
# Build on box/Singapore (artifacts already exported); Hangzhou only runs the image.
# Context must be the project root: docker build -f deploy/Dockerfile ...

# ---------- dedicated game server ----------
FROM debian:bookworm-slim AS game
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY build/server/bomberman-server.x86_64 /app/bomberman-server.x86_64
RUN chmod +x /app/bomberman-server.x86_64
EXPOSE 9080
# User args after "--": Net.gd starts WebSocket dedicated server
CMD ["/app/bomberman-server.x86_64", "--headless", "--", "--server", "--port=9080"]

# ---------- static web + nginx reverse proxy ----------
FROM nginx:1.27-alpine AS web
COPY build/web/ /usr/share/nginx/html/
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
