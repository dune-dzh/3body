# 3-Body Problem (Python + WebSocket + Docker)

Simulates a **planar three-body** system under **mutual Newtonian gravity**: the backend **numerically integrates** the equations of motion and streams positions over **WebSockets**; the browser **draws** the resulting trajectory (it does not run the physics).

## Web UI — explaining the solution

The interface is built to clarify what **“the solution”** means here: not a closed-form formula (which generically does not exist for arbitrary three-body problems), but a **computed orbit** produced by time-stepping the same force model implemented in `app/main.py`. You get:

- A **callout** and **header copy** that state this distinction up front.
- An expandable **“Model & integration (matches the server)”** block with the softened inverse-square acceleration and the **v ← v + a·Δt**, **x ← x + v·Δt** update used in code.
- A **guided tour** (seven steps, auto-advance with Back / Next / Replay) on the problem, equations, integration, chaos, what the server sends, how to read trails, and demo limits.
- A labeled **diagram** (pairwise attraction), **legend** tied to the numerical solution, **live WebSocket** status, and light motion **on the canvas** for readability.

Open the app after **`./install.sh`** (which runs **`docker compose`**) or local **`uvicorn`** at `http://127.0.0.1:8000` (or your `PUBLIC_HOST` / port).

## Install & runtime (Ubuntu)

This repo targets **Linux / Ubuntu**. **`./install.sh`** syncs app files, creates **`.env`** if it is missing (unless one exists — use **`--refresh-env`** to regenerate), then **reapplies the Compose stack**: **`docker compose down --remove-orphans`**, then **`docker compose up --build -d --force-recreate`** so each run matches the current files and config. Use **`--no-start`** for files only. **`docker compose`** does not require a **`.env`** file for substitution — Compose reads **`.env`** only when it exists.

## Prerequisites (Ubuntu)

- **Docker Engine** and **`docker compose`** (v2 plugin), *or* **Python 3.9+** and `pip` for a local run (the container image uses Python 3.11).

**Recommended:** install **Docker Engine** from **Docker’s apt repository** (supports **Ubuntu Noble/Jammy**, **amd64/arm64/armhf**, etc.). Follow the full guide: [Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/).

Summary of that method (matches **`./install.sh --install-docker`**):

1. Remove unofficial packages if you ever installed them (optional but avoids conflicts):

   `sudo apt remove docker.io docker-compose docker-compose-v2 docker-doc podman-docker`

2. Add Docker’s signing key and **`docker.sources`** (suite = your release, e.g. **`noble`**), then install **`docker-ce`**, **`docker-compose-plugin`**, and related packages:

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
printf '%s\n' \
  "Types: deb" \
  "URIs: https://download.docker.com/linux/ubuntu" \
  "Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")" \
  "Components: stable" \
  "Signed-By: /etc/apt/keyrings/docker.asc" \
  | sudo tee /etc/apt/sources.list.d/docker.sources
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

On **Debian**, use [Install Docker Engine on Debian](https://docs.docker.com/engine/install/debian/) (different **`gpg`** URL and **`URIs: https://download.docker.com/linux/debian`**).

**Fallback (not recommended vs official repo):** if you cannot use **`download.docker.com`**, Ubuntu’s **`docker.io`** plus **`universe`**’s **`docker-compose-plugin`** or the [Compose binary](https://github.com/docker/compose/releases) — **`install.sh`** only uses this if the official packages fail.

So **`docker info`** and **`docker compose version`** work **without** `sudo`, add your user to the `docker` group, then start a **new login session**:

```bash
sudo usermod -aG docker "$USER"
# log out and back in, or: newgrp docker
docker compose version
docker info
```

If those commands fail, **`./install.sh`** exits with a **non-zero status** when it tries to start the stack (default behavior).

On **Ubuntu/Debian**, **`./install.sh`** (or **`--install-docker`**) follows **[Docker’s Ubuntu apt instructions](https://docs.docker.com/engine/install/ubuntu/)** when Docker is missing and a start is requested, then falls back to Ubuntu **`docker.io`** only if that fails. It **exits with an error** if the daemon is unreachable (for example user not in **`docker`** group).

## Using `install.sh`

**If `docker` and `docker compose` work for your user** (`docker compose version`, `docker info`), **`./install.sh` is the only script you need**: it lays out files, writes **`.env`** when missing, **stops the previous stack**, **rebuilds images**, and **starts fresh containers**. It does **not** install or require host Python in that case.

**Permission denied?** Run **`chmod +x install.sh`** once, or **`bash install.sh`** (no execute bit needed). After you **commit**, the file should be mode **`100755`** in Git so others can run **`./install.sh`** after clone—see [Git: keeping `install.sh` executable](#git-keeping-installsh-executable).

**Default:** **`./install.sh`** updates files, ensures Docker when needed, then runs **`docker compose down --remove-orphans`** and **`docker compose up --build -d --force-recreate`**. Use **`./install.sh --no-start`** if you only want files (e.g. CI).

**Host Python:** On **`--no-start`** machines where Docker is **not** yet usable, **`./install.sh`** may install **Python 3.9+** via **apt** on Ubuntu/Debian so a local **`uvicorn`** run is possible. If you want to skip that step anyway:

```bash
./install.sh --skip-python
```

By default **`./install.sh`** **tears down** any existing project containers, **rebuilds**, and **starts** the stack in the background. To **only** refresh files without touching Docker, use **`./install.sh --no-start`**. On **Debian/Ubuntu-like** systems, if Docker is missing it will try the official **`docker-ce`** packages (see earlier); use **`--skip-docker-install`** to **refuse** automatic apt install and fail if Docker is not already usable.

**Windows (Git Bash):** `chmod +x` usually does **not** apply a real Unix executable bit on NTFS, and it does **not** change what Git stores. That is expected. To run the installer locally, use either:

```bash
bash install.sh
# or
sh install.sh
```

To **record** the executable bit in Git so Ubuntu clones get `./install.sh` working, use the Git commands in [Git: keeping `install.sh` executable](#git-keeping-installsh-executable) — do not rely on `chmod` on Windows.

Generate / refresh project files **and start containers** (default):

```bash
./install.sh
```

Files only, **no** **`docker compose`**:

```bash
./install.sh --no-start
```

Combine flags when needed:

```bash
./install.sh --skip-python
```

Force **`docker compose`** after a **`--no-start`** run (redundant if you omitted `--no-start`):

```bash
./install.sh --start
```

Install Docker via apt (Debian-like) if missing, then start the stack:

```bash
./install.sh --install-docker
```

Regenerate **only** `.env` (LAN detection / env vars), leaving other files as-is:

```bash
./install.sh --refresh-env
```

Then open the URL the script prints when **`PUBLIC_HOST`** is set in `.env`, or use `http://127.0.0.1:8000` by default.

## Run (Docker)

**`./install.sh`** already runs **`docker compose down --remove-orphans`** then **`docker compose up --build -d --force-recreate`** by default. To do the same manually from the project directory:

```bash
docker compose down --remove-orphans
docker compose up --build -d --force-recreate
```

Follow logs with **`docker compose logs -f`**. **`docker ps`** should list the **threebody** service. Stop with **`docker compose down`**.

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
- **`./install.sh` exits with code 1** when it tries to start the stack but Docker is missing, **`docker compose`** is not installed, the daemon is stopped, or **`docker info`** fails (often: user not in **`docker`** group — see Prerequisites). The script prints a short reason on **stderr**.
- **`E: Unable to locate package docker-compose-plugin`** when using **only** Ubuntu’s repos: use **[Docker’s apt repository](https://docs.docker.com/engine/install/ubuntu/)** so **`docker-compose-plugin`** comes from **`docker-ce`**, or run **`./install.sh --install-docker`**.
- **Mixing `docker.io` and `docker-ce`:** remove `docker.io` first (see Docker docs “Uninstall old versions”), then install `docker-ce` and `docker-compose-plugin` from `download.docker.com`.
- **`Unit file docker.service` missing**: no engine package installed successfully — complete the [official install steps](https://docs.docker.com/engine/install/ubuntu/) and run **`sudo systemctl enable --now docker`**.
- **`cp: '.../app/main.py' and 'app/main.py' are the same file` / exit code 1:** fixed in current `install.sh` (it skips self-copies when you run the script **from the repository directory**). Update `install.sh` or **`git pull`**, then re-run **`./install.sh`**.
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
