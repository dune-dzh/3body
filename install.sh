#!/usr/bin/env bash
set -euo pipefail

START_DOCKER=0
SKIP_PYTHON=0
REFRESH_ENV=0
INSTALL_DOCKER=0
SKIP_DOCKER_INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --start) START_DOCKER=1 ;;
    --skip-python) SKIP_PYTHON=1 ;;
    --refresh-env) REFRESH_ENV=1 ;;
    --install-docker) INSTALL_DOCKER=1 ;;
    --skip-docker-install) SKIP_DOCKER_INSTALL=1 ;;
  esac
done

detect_lan_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')
  fi
  if [[ -z "${ip}" ]] && command -v hostname >/dev/null 2>&1; then
    ip=$(hostname -I 2>/dev/null | awk '{ print $1 }')
  fi
  if [[ -z "${ip}" ]]; then
    ip="127.0.0.1"
  fi
  printf '%s' "${ip}"
}

run_privileged() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

python3_usable() {
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null
}

ensure_python_apt() {
  export DEBIAN_FRONTEND=noninteractive
  echo "Python 3.9+ not found — installing via apt (Ubuntu/Debian). Sudo password may be required."
  run_privileged apt-get update -qq
  run_privileged apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip
}

ensure_python_for_distro() {
  if [[ "${SKIP_PYTHON}" -eq 1 ]]; then
    echo "Skipping Python check (--skip-python)."
    return 0
  fi
  if python3_usable; then
    echo "Python: $(python3 --version 2>&1)"
    return 0
  fi
  if [[ ! -r /etc/os-release ]]; then
    echo "Warning: no usable python3 and /etc/os-release not found — install Python 3.9+ manually." >&2
    return 0
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
  local debian_like=0
  case "${ID:-}" in
    ubuntu|debian|linuxmint|pop) debian_like=1 ;;
    *)
      [[ "${ID_LIKE:-}" == *debian* ]] && debian_like=1
      ;;
  esac
  if [[ "${debian_like}" -eq 1 ]]; then
    ensure_python_apt
  else
    echo "Warning: no usable python3; auto-install is only implemented for Debian-based distros (e.g. Ubuntu). Install Python 3.9+, then re-run." >&2
    return 0
  fi
  if ! python3_usable; then
    echo "Error: python3 still missing or below 3.9 after apt install." >&2
    exit 1
  fi
  echo "Python: $(python3 --version 2>&1)"
}

docker_compose_usable() {
  command -v docker >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 || return 1
  return 0
}

debian_like_distro() {
  if [[ ! -r /etc/os-release ]]; then
    return 1
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian|linuxmint|pop) return 0 ;;
    *)
      [[ "${ID_LIKE:-}" == *debian* ]] && return 0
      ;;
  esac
  return 1
}

install_docker_compose_plugin_binary() {
  local arch=""
  case "$(uname -m)" in
    x86_64 | amd64) arch="x86_64" ;;
    aarch64 | arm64) arch="aarch64" ;;
    armv7l | armv6l) arch="armv7" ;;
    *)
      echo "Error: no apt docker-compose-plugin and unsupported arch for Compose binary: $(uname -m)" >&2
      return 1
      ;;
  esac
  local ver="v2.29.7"
  local url="https://github.com/docker/compose/releases/download/${ver}/docker-compose-linux-${arch}"
  export DEBIAN_FRONTEND=noninteractive
  echo "Installing Docker Compose plugin binary ${ver} for ${arch} (official release)."
  run_privileged apt-get install -y --no-install-recommends curl ca-certificates
  run_privileged mkdir -p /usr/local/lib/docker/cli-plugins
  run_privileged sh -c "curl -fsSL '${url}' -o /usr/local/lib/docker/cli-plugins/docker-compose && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose"
}

ensure_docker_apt() {
  export DEBIAN_FRONTEND=noninteractive
  echo "Installing Docker via apt — sudo may be required."
  run_privileged apt-get update -qq

  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" == "ubuntu" ]]; then
      echo "Ensuring Ubuntu 'universe' is enabled (docker-compose-plugin lives there on many mirrors, including ARM)."
      run_privileged apt-get install -y --no-install-recommends software-properties-common
      run_privileged add-apt-repository -y universe 2>/dev/null || true
      run_privileged apt-get update -qq
    fi
  fi

  echo "Installing docker.io (engine)…"
  run_privileged apt-get install -y --no-install-recommends docker.io

  echo "Installing Compose v2 (apt plugin, or GitHub fallback)…"
  if ! run_privileged apt-get install -y --no-install-recommends docker-compose-plugin; then
    echo "Note: package docker-compose-plugin was not available from apt; using Compose release binary." >&2
    if ! install_docker_compose_plugin_binary; then
      echo "Error: could not install docker-compose-plugin or Compose binary." >&2
      return 1
    fi
  fi

  if run_privileged systemctl is-system-running >/dev/null 2>&1; then
    run_privileged systemctl enable docker 2>/dev/null || true
    run_privileged systemctl start docker 2>/dev/null || true
  fi
}

ensure_docker_for_use() {
  local try_apt=0
  local cv=""
  if [[ "${INSTALL_DOCKER}" -eq 1 ]] || [[ "${START_DOCKER}" -eq 1 ]]; then
    try_apt=1
  fi
  if [[ "${SKIP_DOCKER_INSTALL}" -eq 1 ]]; then
    try_apt=0
  fi

  if docker_compose_usable; then
    cv=$(docker compose version 2>/dev/null | head -n 1) || true
    [[ -z "${cv}" ]] && cv="(docker compose version unavailable)"
    echo "Docker: $(docker --version 2>&1); compose: ${cv}"
    return 0
  fi

  if [[ "${try_apt}" -eq 1 ]] && debian_like_distro; then
    ensure_docker_apt
  elif [[ "${try_apt}" -eq 1 ]]; then
    echo "Error: Docker is not usable and automatic install is only implemented on Debian/Ubuntu-style systems." >&2
    echo "Install Docker manually, then re-run with --start. See README.md." >&2
    exit 1
  fi

  if ! docker_compose_usable; then
    if [[ "${START_DOCKER}" -eq 1 ]] || [[ "${INSTALL_DOCKER}" -eq 1 ]]; then
      echo "Error: Docker CLI, 'docker compose' plugin, or daemon access failed after install attempt." >&2
      echo "Often fixes: sudo systemctl start docker   OR   sudo usermod -aG docker \"$USER\" (then log out and back in)." >&2
      echo "Verify with: docker compose version && docker info" >&2
      exit 1
    fi
    return 0
  fi

  cv=$(docker compose version 2>/dev/null | head -n 1) || true
  [[ -z "${cv}" ]] && cv="(docker compose version unavailable)"
  echo "Docker: $(docker --version 2>&1); compose: ${cv}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${PUBLIC_PORT:=8000}"
: "${PUBLIC_TLS:=0}"
: "${PUBLIC_WS_URL:=}"

if [[ -n "${PUBLIC_WS_URL}" ]]; then
  PUBLIC_HOST=""
elif [[ -z "${PUBLIC_HOST+set}" ]]; then
  PUBLIC_HOST="$(detect_lan_ip)"
fi

echo "Creating 3-body solution files..."

ensure_python_for_distro

mkdir -p app/static

if [[ ! -f .env ]] || [[ "${REFRESH_ENV}" -eq 1 ]]; then
  cat > .env <<EOF
# Used by docker compose for \${...} substitution when this file exists (optional for compose).
# Clear PUBLIC_HOST to use the browser's current host for WebSockets.
# Or set PUBLIC_WS_URL for reverse-proxy / TLS.
PUBLIC_HOST=${PUBLIC_HOST}
PUBLIC_PORT=${PUBLIC_PORT}
PUBLIC_TLS=${PUBLIC_TLS}
PUBLIC_WS_URL=${PUBLIC_WS_URL}
EOF
  echo "Wrote .env (PUBLIC_HOST=${PUBLIC_HOST:-<empty>} PUBLIC_PORT=${PUBLIC_PORT})"
else
  echo "Keeping existing .env (use --refresh-env to regenerate with current LAN detection / env)"
fi

if [[ -f "${SCRIPT_DIR}/app/main.py" ]]; then
  cp "${SCRIPT_DIR}/app/main.py" app/main.py
else
  cat > app/main.py <<'PY'
import asyncio
import json
import math
import os
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

G = 1.0
SOFTENING = 1e-2
DT = 0.01


@dataclass
class Body:
    x: float
    y: float
    vx: float
    vy: float
    m: float


def initial_bodies() -> List[Body]:
    return [
        Body(-0.8, 0.0, 0.0, -0.35, 1.0),
        Body(0.8, 0.0, 0.0, 0.35, 1.0),
        Body(0.0, 1.1, 0.45, 0.0, 1.0),
    ]


def step(bodies: List[Body], dt: float) -> None:
    ax = [0.0, 0.0, 0.0]
    ay = [0.0, 0.0, 0.0]

    for i in range(3):
        for j in range(3):
            if i == j:
                continue
            dx = bodies[j].x - bodies[i].x
            dy = bodies[j].y - bodies[i].y
            r2 = dx * dx + dy * dy + SOFTENING
            inv_r3 = 1.0 / (r2 * math.sqrt(r2))
            a = G * bodies[j].m * inv_r3
            ax[i] += a * dx
            ay[i] += a * dy

    for i in range(3):
        bodies[i].vx += ax[i] * dt
        bodies[i].vy += ay[i] * dt
        bodies[i].x += bodies[i].vx * dt
        bodies[i].y += bodies[i].vy * dt


def _normalize_ws_origin(url: str) -> str:
    u = url.strip().rstrip("/")
    if u.endswith("/ws"):
        u = u[: -len("/ws")].rstrip("/")
    return u


def websocket_public_base() -> Optional[str]:
    full = os.environ.get("PUBLIC_WS_URL", "").strip()
    if full:
        return _normalize_ws_origin(full)

    host = os.environ.get("PUBLIC_HOST", "").strip()
    if not host:
        return None

    port = os.environ.get("PUBLIC_PORT", "8000").strip()
    tls_flag = os.environ.get("PUBLIC_TLS", "0").strip().lower()
    use_tls = tls_flag in ("1", "true", "yes", "on")
    scheme = "wss" if use_tls else "ws"

    if ":" in host and not host.startswith("["):
        return f"{scheme}://{host}"

    return f"{scheme}://{host}:{port}"


def build_index_html() -> str:
    path = Path("app/static/index.html")
    if not path.is_file():
        return (
            "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Missing UI</title></head>"
            "<body><p>Missing app/static/index.html</p></body></html>"
        )
    html = path.read_text(encoding="utf-8")
    base = websocket_public_base()
    if base:
        snippet = f"<script>window.__WS_BASE__={json.dumps(base)};</script>"
        if "</head>" in html:
            html = html.replace("</head>", f"{snippet}</head>", 1)
    return html


app = FastAPI(title="3-Body Simulation")
app.mount("/static", StaticFiles(directory="app/static"), name="static")


@app.get("/")
async def index():
    return HTMLResponse(build_index_html())


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket):
    await websocket.accept()
    bodies = initial_bodies()
    try:
        while True:
            for _ in range(4):
                step(bodies, DT)
            payload = {
                "bodies": [
                    {"x": b.x, "y": b.y, "m": b.m}
                    for b in bodies
                ]
            }
            await websocket.send_text(json.dumps(payload))
            await asyncio.sleep(1 / 60)
    except WebSocketDisconnect:
        pass
PY
fi

if [[ -f "${SCRIPT_DIR}/app/static/index.html" ]]; then
  cp "${SCRIPT_DIR}/app/static/index.html" app/static/index.html
else
  cat > app/static/index.html <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>3-Body Problem</title>
</head>
<body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#06080f;color:#e6ecff;font-family:system-ui,sans-serif;padding:1.5rem;text-align:center;">
  <div>
    <h1 style="font-size:1.1rem;font-weight:600;">Web UI not found beside this script</h1>
    <p style="max-width:36rem;opacity:0.85;line-height:1.5;">
      Run <code style="background:#1a2440;padding:0.15rem 0.4rem;border-radius:4px;">install.sh</code> from the full repository checkout so
      <code style="background:#1a2440;padding:0.15rem 0.4rem;border-radius:4px;">app/static/index.html</code> can be copied, or place that file there manually.
    </p>
  </div>
</body>
</html>
HTML
fi

cat > requirements.txt <<'REQ'
fastapi
uvicorn[standard]
REQ

cat > Dockerfile <<'DOCKER'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
DOCKER

if [[ -f "${SCRIPT_DIR}/docker-compose.yml" ]]; then
  cp "${SCRIPT_DIR}/docker-compose.yml" docker-compose.yml
else
  cat > docker-compose.yml <<'COMPOSE'
version: "3.9"
services:
  threebody:
    build: .
    environment:
      PUBLIC_HOST: ${PUBLIC_HOST:-}
      PUBLIC_PORT: ${PUBLIC_PORT:-8000}
      PUBLIC_TLS: ${PUBLIC_TLS:-0}
      PUBLIC_WS_URL: ${PUBLIC_WS_URL:-}
    ports:
      - "${PUBLIC_PORT:-8000}:8000"
COMPOSE
fi

if [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
  cp "${SCRIPT_DIR}/.env.example" .env.example
fi

if [[ -f "${SCRIPT_DIR}/.gitignore" ]]; then
  cp "${SCRIPT_DIR}/.gitignore" .gitignore
fi

if [[ -f "${SCRIPT_DIR}/README.md" ]]; then
  cp "${SCRIPT_DIR}/README.md" README.md
else
  cat > README.md <<'MD'
# 3-Body Problem (Python + WebSocket + Docker)

Run `./install.sh` then `docker compose up --build`. Open http://127.0.0.1:8000 or the URL printed by the installer.
MD
fi

echo "Created: .env, app/main.py, app/static/index.html, requirements.txt, Dockerfile, docker-compose.yml"

if [[ "${START_DOCKER}" -eq 1 ]] || [[ "${INSTALL_DOCKER}" -eq 1 ]]; then
  ensure_docker_for_use
fi

if [[ "$START_DOCKER" -eq 1 ]]; then
  echo "Starting Docker build/run..."
  docker compose up --build
else
  echo "Install complete."
  echo "Run: docker compose up --build"
  if [[ -n "${PUBLIC_HOST}" ]]; then
    echo "From the network: http://${PUBLIC_HOST}:${PUBLIC_PORT}"
  fi
  echo "On this machine: http://127.0.0.1:${PUBLIC_PORT}"
  if ! docker_compose_usable; then
    echo "" >&2
    echo "Note: Docker is not available to this user (install: ./install.sh --install-docker on Ubuntu/Debian, or see README)." >&2
    echo "      Until then, 'docker compose up --build' will fail; use local Python + uvicorn if you prefer." >&2
  fi
fi
