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
    """Strip trailing slashes and a trailing /ws so the client can append /ws once."""
    u = url.strip().rstrip("/")
    if u.endswith("/ws"):
        u = u[: -len("/ws")].rstrip("/")
    return u


def websocket_public_base() -> Optional[str]:
    """If set, the HTML UI opens WebSockets to this origin (ws:// or wss://) instead of the browser host."""
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
