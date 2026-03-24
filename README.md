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

- **Docker Engine** and **`docker compose`** (v2 plugin), *or* **Python 3.9+** and `pip` for a local run (the container image uses Python 3.11).

Manual Docker install on **Ubuntu** (including **ARM / `ubuntu-ports`**, e.g. Hetzner): the **`docker-compose-plugin`** package is usually in **`universe`**. If you see **`Unable to locate package docker-compose-plugin`**, enable **`universe`** first; **`docker.io`** and **`systemctl`** only work after the engine package actually installs.

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y universe
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
```

If **`docker-compose-plugin`** is still missing after **`universe`** is on, install the **Compose v2 plugin binary** into **`/usr/local/lib/docker/cli-plugins/`** (same version as **`install.sh`**). Use the file name that matches **`uname -m`**: **`aarch64`** → `docker-compose-linux-aarch64`, **`x86_64`** → `docker-compose-linux-x86_64`, **`armv7l`** → `docker-compose-linux-armv7`.

```bash
sudo apt install -y curl ca-certificates
sudo mkdir -p /usr/local/lib/docker/cli-plugins
# Example for 64-bit ARM (many Hetzner / ubuntu-port servers):
sudo curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-aarch64" -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
```

For **amd64**, replace the URL basename with **`docker-compose-linux-x86_64`**. Other assets are listed on the [Compose releases](https://github.com/docker/compose/releases) page.

**Debian** (no `universe`): install **`docker.io`**, then use the same **curl** plugin install if **`apt install docker-compose-plugin`** is unavailable.

So **`docker info`** and **`docker compose version`** work **without** `sudo`, add your user to the `docker` group, then start a **new login session**:

```bash
sudo usermod -aG docker "$USER"
# log out and back in, or: newgrp docker
docker compose version
docker info
```

If those commands fail, `docker compose up` will fail too — **`./install.sh --start`** exits with a **non-zero status** and prints a hint.

On **Ubuntu/Debian**, **`./install.sh --install-docker`** (optionally with **`--start`**) tries the same **`apt`** packages and **`systemctl start docker`** for you; it still **exits with an error** if the daemon is unreachable (for example user not in **`docker`** group).

## Using `install.sh`

**Permission denied?** Run **`chmod +x install.sh`** once, or **`bash install.sh`** (no execute bit needed). After you **commit**, the file should be mode **`100755`** in Git so others can run **`./install.sh`** after clone—see [Git: keeping `install.sh` executable](#git-keeping-installsh-executable).

On **Ubuntu** and **Debian**, `./install.sh` checks for **Python 3.9+**. If `python3` is missing or too old, it runs `apt-get install` for `python3`, `python3-venv`, and `python3-pip` (uses `sudo` when not root). Other distributions print a short warning if Python is missing; install 3.9+ yourself or use Docker only.

To skip this step (e.g. Docker-only machine with no sudo), run:

```bash
./install.sh --skip-python
```

On a plain **`./install.sh`** the script does **not** install Docker; it only prints a **note** if `docker compose` is not ready. With **`--install-docker`** or **`--start`**, on **Debian/Ubuntu-like** systems it will **`apt install`** `docker.io` and **`docker-compose-plugin`** and start **`docker`** when needed, then **`--start` exits with status 1** if the CLI, Compose plugin, or **`docker info`** still fails (common fix: add your user to the **`docker`** group). Use **`--skip-docker-install`** with **`--start`** to **refuse** that automatic apt step and fail immediately when Docker is not already usable.

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

Install Docker via apt (Debian-like) then bring the stack up (stops with **non-zero exit** if Docker still is not usable):

```bash
./install.sh --install-docker --start
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
- **`--start` exits with code 1**: Docker is missing, **`docker compose`** is not installed, the daemon is stopped, or **`docker info`** fails (often: user not in **`docker`** group — see Prerequisites). The script prints a short reason on **stderr**.
- **`E: Unable to locate package docker-compose-plugin`** (common on minimal Ubuntu ARM): run **`sudo add-apt-repository -y universe`**, **`sudo apt update`**, then install again—or use **`./install.sh --install-docker`**, which enables **`universe`** on Ubuntu and falls back to the official Compose binary if apt has no plugin.
- **`Unit file docker.service does not exist`**: the **`docker.io`** package did not install (often because **`apt install`** failed on **`docker-compose-plugin`** before anything was installed). Install **`docker.io` alone first: **`sudo apt install -y docker.io`**, then add Compose as above.
- **`apt install docker.io` succeeds but compose still fails**: run **`sudo systemctl enable --now docker`**, then **`sudo usermod -aG docker "$USER"`** and log out/in.
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
