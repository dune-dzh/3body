# 3-Body Problem (Python + WebSocket + Docker)

Simulates a **planar three-body** system under **mutual Newtonian gravity**: the backend **numerically integrates** the equations of motion and streams positions over **WebSockets**; the browser **draws** the resulting trajectory (it does not run the physics).

## Web UI — explaining the solution

The interface is built to clarify what **“the solution”** means here: not a closed-form formula (which generically does not exist for arbitrary three-body problems), but a **computed orbit** produced by time-stepping the same force model implemented in `app/main.py`. You get:

- A **callout** and **header copy** that state this distinction up front.
- An expandable **“Model & integration (matches the server)”** block with the softened inverse-square acceleration and the **v ← v + a·Δt**, **x ← x + v·Δt** update used in code.
- A **guided tour** (seven steps, auto-advance with Back / Next / Replay) on the problem, equations, integration, chaos, what the server sends, how to read trails, and demo limits.
- A labeled **diagram** (pairwise attraction), **legend** tied to the numerical solution, **live WebSocket** status, and light motion **on the canvas** for readability.

Open the app after `docker compose up` or local `uvicorn` at `http://127.0.0.1:8000` (or your `PUBLIC_HOST` / port).

## Install & runtime (Ubuntu)

This repo targets **Linux / Ubuntu**. Run **`./install.sh`** to sync app files; **`docker compose up` does not require a `.env` file** — Compose only reads `.env` **when it exists** (for `${PUBLIC_HOST}` / port substitution). **`./install.sh` creates `.env` if it is missing** (detected LAN IP and defaults). To overwrite an existing `.env`, use **`./install.sh --refresh-env`**.

## Prerequisites (Ubuntu)

- **Docker Engine** and **`docker compose`** (v2 plugin), *or* **Python 3.9+** and `pip` for a local run (the container image uses Python 3.11)

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
# optional: add your user to the docker group, then log out/in
```

## Using `install.sh`

On **Ubuntu** and **Debian**, `./install.sh` checks for **Python 3.9+**. If `python3` is missing or too old, it runs `apt-get install` for `python3`, `python3-venv`, and `python3-pip` (uses `sudo` when not root). Other distributions print a short warning if Python is missing; install 3.9+ yourself or use Docker only.

To skip this step (e.g. Docker-only machine with no sudo), run:

```bash
./install.sh --skip-python
```

**Linux / macOS:** After cloning, `install.sh` should already be executable in Git (`100755`). If not, run `chmod +x install.sh` once.

**Windows (Git Bash):** `chmod +x` usually does **not** apply a real Unix executable bit on NTFS, and it does **not** change what Git stores. That is expected. To run the installer locally, use either:

```bash
bash install.sh
# or
sh install.sh
```

To **record** the executable bit in Git so Ubuntu clones get `./install.sh` working, use the Git commands in [Git: keeping `install.sh` executable](#git-keeping-installsh-executable) — do not rely on `chmod` on Windows.

Generate / refresh project files (Unix):

```bash
./install.sh
```

Optional — generate files and start Docker in one step (`--start` checks that `docker` and `docker compose` exist):

```bash
./install.sh --start
```

Combine flags when needed:

```bash
./install.sh --skip-python --start
```

Regenerate **only** `.env` (LAN detection / env vars), leaving other files as-is:

```bash
./install.sh --refresh-env
```

Then open the URL the script prints when **`PUBLIC_HOST`** is set in `.env`, or use `http://127.0.0.1:8000` by default.

## Run (Docker)

From the project directory:

```bash
docker compose up --build
```

Works **with or without** `.env`: with no file, **`PUBLIC_PORT`** defaults to **8000** and **`PUBLIC_HOST`** is empty (WebSocket uses the same host as the page). After **`./install.sh`**, a new **`.env`** usually sets **`PUBLIC_HOST`** to this machine’s LAN IPv4 so other devices can stream reliably. The server injects `window.__WS_BASE__` when `PUBLIC_HOST` or `PUBLIC_WS_URL` is set.

Override values when **creating or refreshing** `.env`:

```bash
PUBLIC_HOST=10.0.0.5 PUBLIC_PORT=8000 ./install.sh --refresh-env
```

First-time create with empty host (same-origin WebSocket only):

```bash
PUBLIC_HOST= ./install.sh
```

If **`.env` already exists**, `./install.sh` leaves it alone unless you pass **`--refresh-env`**.

For HTTPS or a reverse proxy, set **`PUBLIC_WS_URL`** in `.env` (for example `wss://example.com`). You may give either the origin only or include a trailing `/ws`; the app normalizes so the browser does not end up on `/ws/ws`. See `.env.example`.

## Run (local Python)

From the repository root, load `.env` into the shell so `PUBLIC_HOST` / `PUBLIC_WS_URL` match Docker behavior, then run uvicorn on the same port as `PUBLIC_PORT` (default 8000):

```bash
set -a
[ -f .env ] && . ./.env
set +a
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port "${PUBLIC_PORT:-8000}" --reload
```

## Troubleshooting

- **Want a `.env` but don’t need the full installer**: copy **`cp .env.example .env`** and edit, or run **`./install.sh`** once (creates `.env` if missing).
- **`--start` exits** with a Docker error: install Docker and the Compose v2 plugin (`docker compose version` should work).
- **WebSocket stays disconnected** from another device: check firewall for `${PUBLIC_PORT:-8000}`/TCP, ensure **`.env`** sets **`PUBLIC_HOST`** to the address clients use (run **`./install.sh --refresh-env`** after fixing the network), or open the UI with that same host.

## Git: keeping `install.sh` executable

Git tracks an **executable flag** separately from Windows file attributes. On Linux/macOS you can combine `chmod +x` with the commands below; on **Windows, use Git only** (see above — `chmod` in Git Bash is not enough).

**When staging `install.sh` for a commit**, use one of:

```bash
# Git 2.23+ (preferred): sets executable in index at add time
git add --chmod=+x install.sh

# Or: add first, then fix the index bit before commit
git add install.sh
git update-index --chmod=+x install.sh
```

Verify before commit:

```bash
git ls-files -s install.sh
# executable: 100755 … install.sh
# not executable: 100644 … install.sh
```

This records mode `100755` so clones on **Ubuntu** get `./install.sh` without extra steps.
