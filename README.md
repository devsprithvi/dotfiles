# 🌌 Prudhvi's Dotfiles

A fully automated, zero-dependency, cross-platform configuration setup built on top of [Chezmoi](https://www.chezmoi.io/), featuring modern shell utilities, highly curated styling, and secure, non-blocking credential lookups.

## 🚀 Quick Start / Bootstrap

To seamlessly install Chezmoi and apply these dotfiles on any new Debian/Ubuntu, macOS, or Windows environment:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/devsprithvi/dotfiles/main/bootstrap.sh)"
```

Or manually via Chezmoi:
```bash
sh -c "$(curl -fsSL https://get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi init --apply https://github.com/devsprithvi/dotfiles.git
```

---

## 📁 Repository Architecture & Intent

The repository is modularly layered with a clear separation of concerns:

```
dotfiles/
├── bootstrap.sh          # One-liner system entrypoint (installs chezmoi & initializes)
├── .chezmoiscripts/      # Chezmoi lifecycle triggers (runs package installation once)
├── packages/             # INSTALL only — index.sh installs every tool, one script each
│   └── installers/       # Generic package manager abstractions (apt, brew, dnf, etc.)
├── services/             # RUN — one generic runner + a preset map; run by hand OR autostart via the OS init
├── utilities/            # Shared libraries (OS detection, logging, privilege handling, secrets, service manager)
│   └── logger.sh         # Dedicated logging facility (timestamped, leveled, console + file)
├── components/           # Standalone projects under development, parked here (NOT deployed)
└── dot_*                 # Managed user configurations mapped directly to $HOME
```

### Architectural Responsibilities

The layering enforces one hard boundary: **install** and **run** are separate.

* **`packages/`**: Installation only. Each script installs exactly one tool (download the binary, or defer to a package manager) and exits. It performs **no** authentication, tunnel/service registration, or `tailscale up` — those are runtime concerns. This is what `chezmoi` runs once during bootstrap.
* **`services/`**: Runtime actions only. There is **one generic runner** (`run.sh`) plus a **declarative preset map** (`presets.sh`) keyed by `tool:sub` — not one script per tool. The runner hydrates secrets from the secret manager into environment variables, performs the preset's auth step, then execs the tool in the foreground. It never installs; if a tool is missing the preset points you at the matching package. `run.sh` also runs a **raw command** directly (`--secret VAR@PATH -- CMD...`). Services run two ways: **by hand** (`run`) or **supervised by the OS** so they autostart at boot/login (`enable` — see [Autostart](#autostart--how-services-actually-run)).
* **`packages/installers/`**: Low-level package manager wrappers. Uniform, idempotent helpers around system package managers (`apt`, `brew`, `dnf`, `pacman`, etc.) so packages don't duplicate distro-specific install logic. They live inside `packages/` because the package scripts are their only consumers.
* **`utilities/`**: Core shared libraries for OS/architecture discovery (`os.sh`), the dedicated logger (`logger.sh`), privilege escalation and credential lookups (`helpers.sh`), and the init-system abstraction that registers autostart units (`service_manager.sh`). Sourced by both packages and services.
* **`utilities/logger.sh`**: A single, dependency-free logging facility used across the whole lifecycle (bootstrap → install → services). Every line is timestamped and leveled; output goes to both the console and a persistent per-run log file so failures are diagnosable after the fact. See [Logging & Diagnostics](#-logging--diagnostics).
* **`components/`**: Standalone side-projects being developed alongside these dotfiles and parked here for now. They are **not** part of the bootstrap flow and are excluded from `chezmoi apply` (see [Components](#-components-under-development)).

---

## 🧩 Components (Under Development)

> Status: **under active development — parked, not released.** No stable or beta
> builds exist yet. Nothing here runs during bootstrap; the directory is
> `.chezmoiignore`d so it is never deployed to `$HOME`. These are checked in so
> the work-in-progress lives with the repo, nothing more.

| Component | What it is | State |
|---|---|---|
| **`components/pulipil`** | A configuration-driven package **installer manager** with its own **CUE** config language. You declare the packages you want (installed via pluggable providers: dnf, apt, pacman, brew, ...) *and* the commands to run, and its interpreter engine executes only what you declare, in order, honouring dependencies and platform guards. Written in Go. | In development |
| **`components/pulipil-vscode`** | The VS Code editor support for `pulipil.cue` files — a thin language-server client for `pulipil`, giving real-time, provider-aware package-name completion. Written in TypeScript. | In development |

The long-term intent is that `pulipil` becomes a cleaner, declarative
replacement for the ad-hoc `packages/installers/` shell wrappers, orchestrated
by chezmoi: its `run_once_` / `run_onchange_` scripts would decide *when* to
invoke pulipil, while pulipil decides *what* to install and run. That migration
has **not** started; chezmoi and the shell installers remain the source of
truth today. Each component carries its own `README.md` with local build
details.

---

## 🛠️ Package Management & Tooling

### Core Tools (Default)
Applied automatically during bootstrap without manual intervention:
* **Shell & Prompt**: Zsh, Starship cross-shell prompt, and Sheldon plugin manager.
* **Developer Tools**: Git, GitHub CLI (`gh`), and Antigravity CLI.
* **Secret Management**: Infisical CLI.

### Controlled / Optional Tools
Certain heavy tools or remote-access daemons are opt-in, controlled via environment variables:

These flags only control **installation** (what `chezmoi`/bootstrap installs). Running the tools is a separate step — see [On-Demand Actions](#on-demand-actions-services) below.

| Feature / Tool | Trigger Flag | Installs |
|---|---|---|
| **VS Code CLI** | `ENABLE_VSCODE_CLI=1` | The lightweight standalone `code` binary for headless/remote machines. |
| **Dev Tunnel** | `ENABLE_DEVTUNNEL=1` | Microsoft's standalone Dev Tunnels CLI. |
| **Tailscale** | `ENABLE_TAILSCALE=1` | The Tailscale mesh VPN client. |

**Example:**
```bash
ENABLE_VSCODE_CLI=1 ENABLE_TAILSCALE=1 ./bootstrap.sh
```

### On-Demand Actions (`services/`)

Installation and running are deliberately separate. `services/` is **one generic runner** (`run.sh`) driven by a **preset map** (`presets.sh`) keyed by `tool:sub`. The runner hydrates the preset's secrets into the environment, performs its auth step, then runs the tool in the foreground. Anything can be run this way — a preset just carries the tool-specific knowledge (secret path, login step) that a raw command lacks.

#### Available presets

The presets evolve with the repo, so this is the canonical list (`services/index.sh list` prints the same on any box):

| Preset (`tool:sub`) | Args | What it does |
|---|---|---|
| `vscode:tunnel` | `[name]` | VS Code remote tunnel (`vscode.dev/tunnel/<name>`) |
| `vscode:web` | `[host] [port] [token]` | VS Code web server (`serve-web`) |
| `devtunnel:host` | `[port ...]` | host ports via a Microsoft Dev Tunnel |
| `tailscale:up` | — | connect this machine to the tailnet |

```bash
services/index.sh run <tool:sub> [args...]   # run a preset in the foreground
services/index.sh list                       # print presets and managed units

services/index.sh run vscode:tunnel my-box   # e.g. a named tunnel

# run ANY command through the same runner (raw mode) — no preset needed:
services/run.sh --secret GITHUB_PAT=ADMIN_PAT@/github -- my-tool --flag
```

Adding a tool is a new `case` in `presets.sh` (a command + its secret paths + an optional login step) — no new script file, no dispatcher wiring. Keep this table and the [secret table](#what-the-secret-manager-fetches) in sync when you do.

### Autostart — how services actually run

`chezmoi` can't run a service for you: a `run_` script must **finish** during `chezmoi apply`, and a tunnel / web server / VPN session never finishes. So instead of running them, we hand the ones you declare to the OS's own init system, which starts and supervises them:

| OS | Mechanism | Where |
|---|---|---|
| **Linux** | systemd **user** unit (`Restart=on-failure`, linger enabled so it survives logout/boot) | `~/.config/systemd/user/dotfiles-<name>.service` |
| **macOS** | launchd **LaunchAgent** (`RunAtLoad`, `KeepAlive`) | `~/Library/LaunchAgents/dotfiles-<name>.plist` |
| **Windows** | Task Scheduler **logon task** (best-effort) | `dotfiles\<name>` |

**Declare what autostarts** via the `DOTFILES_SERVICES` env var (a space-separated list of `tool:sub` specs) — symmetric with the `ENABLE_*` install flags. Chezmoi's `run_onchange_register-services` script reads it during `apply` and registers exactly those. Empty (the default) touches nothing.

```bash
# install VS Code CLI + Tailscale, then autostart a tunnel and the tailnet:
ENABLE_VSCODE_CLI=1 ENABLE_TAILSCALE=1 \
DOTFILES_SERVICES="vscode:tunnel tailscale:up" ./bootstrap.sh
```

Manage units directly at any time:

```bash
services/index.sh enable  vscode:tunnel my-box   # register + start now, and at boot/login
services/index.sh status  vscode:tunnel          # show status
services/index.sh disable vscode:tunnel          # stop + remove the unit
services/index.sh status                         # list all managed units
```

> **Boot-time secrets:** most tools persist their own credentials after the first
> authenticated run (VS Code uses a file keychain; `tailscaled` reconnects on its
> own), so autostart needs no secret at boot. There is **no services-specific env
> file** — the unit inherits the standard systemd user environment. If a service
> *does* need the Infisical machine identity at boot, set it like any other env
> var via `~/.config/environment.d/*.conf` (the user manager reads it
> automatically); it is not special to services.
>
> **Headless boot (SSH / cloud-init):** on a server with no interactive login there
> is no active `systemd --user` session yet, and `XDG_RUNTIME_DIR` is unset — so a
> naive `systemctl --user` can't reach the user bus. `enable` handles this: it sets
> `XDG_RUNTIME_DIR`, enables **linger** (which starts `user@UID.service` now and at
> every boot), waits for the user bus, then enables the unit. No interactive login
> required.
>
> **No init system?** Containers and WSL *without* systemd have no `systemctl --user`
> manager at all; `enable` detects that (systemd isn't PID 1), tells you, and you
> fall back to `run`.

**Configuration Variables (read by the services at run time):**
* `VSCODE_TUNNEL_NAME`: Tunnel name (defaults to `$(hostname)`).
* `VSCODE_WEB_HOST` / `VSCODE_WEB_PORT` / `VSCODE_WEB_TOKEN`: web server bind host (`0.0.0.0`), port (`8000`), and optional connection token.
* `GITHUB_PAT`: GitHub personal access token for non-interactive VS Code tunnel / dev tunnel login (default source: key `ADMIN_PAT` at `/github`).
* `DEVTUNNEL_TOKEN`: Dev Tunnels access token (otherwise fetched at `/tunnels`).
* `TAILSCALE_AUTHKEY`: Auth key for non-interactive connect (otherwise fetched at `/tailscale`).
* `DOTFILES_SERVICES`: space-separated `tool:sub` list to autostart at bootstrap/apply.
* `DOTFILES_SECRET_MAP`: per-var source overrides, e.g. `GITHUB_PAT=ADMIN_PAT@/github` — change *where* a secret comes from without editing any preset.
* `SECRET_PROVIDER`: secret backend id (default `infisical`; `env` = use only pre-set vars).
* `INFISICAL_ENV`: default environment slug for `infisical` lookups (default `global`).

> `vscode web` runs without a connection token unless one is supplied — bind it to
> localhost or place it behind a tunnel/VPN/reverse proxy on shared networks.

> **Design — one generic service, presets as data.** There are no per-tool
> service scripts. `run.sh` is the single runner (hydrate secrets → authenticate
> → exec), and `presets.sh` is a declarative map that supplies the tool-specific
> knowledge a raw command lacks: which secret to fetch, how to log in, small
> quirks. This keeps the convenience layer while collapsing the tool files into
> data, and lines up with the `pulipil` direction (declare commands + services,
> an engine runs them). Prefer a preset for known tools; use `run.sh --secret ...
> -- CMD` for anything ad-hoc.

---

## ⚙️ Secrets Management

Secret resolution is its own subsystem under **`secrets/`**, built to be **provider-agnostic** — Infisical today, something else tomorrow — with a mandatory **mapping** layer so the unpredictable part (where a secret lives) is never welded to the stable part (the env var a tool reads).

```
secrets/
  index.sh              # entry point: loads the core, auto-discovers providers
  core.sh               # generic engine — knows only VAR, an opaque LOCATOR, and a provider
  providers/
    infisical.sh        # Infisical dialect: login + CLI/REST fetch + locator syntax
    env.sh              # null backend: use only pre-set env vars
```

Secrets are never committed or stored persistently in plaintext on disk:
1. **Provider abstraction**: `SECRET_PROVIDER` selects a backend (default `infisical`). The core never logs in or parses a location — it hands `(VAR, LOCATOR)` to `_secret_provider_<id>_get`. Adding Vault/AWS/pass/etc. is a single new file in `secrets/providers/`; nothing else changes. The `infisical` backend prefers the CLI and falls back to the REST API (`curl` + `python3`, Universal Auth).
2. **Three separated concerns**: the **env var** a tool reads (stable contract, owned by the preset), the **locator** telling the provider where the value lives (syntax owned entirely by the provider), and **which backend** to ask. Changing one never forces a change to the others.
3. **Graceful degradation**: with no credentials (or `SECRET_PROVIDER=env`), lookups return empty and opt-in services fall back cleanly without breaking bootstrap.

### The spec grammar and mapping

The core grammar is deliberately tiny and provider-neutral: `VAR[=LOCATOR]`.

| Piece | Meaning |
|---|---|
| `VAR` | env var to export (the tool contract) |
| `=LOCATOR` | opaque string passed verbatim to the provider; omit to use the provider's default for `VAR` |

The **locator** syntax belongs to the provider. For `infisical` it is `[KEY][@[ENV:]PATH]` (key defaults to `VAR`, env to `INFISICAL_ENV`→`global`, path to `/`). A different backend would define its own — the core neither knows nor cares.

Presets ship **default** specs. To repoint a var without editing a preset, add an override to **`DOTFILES_SECRET_MAP`** (keyed by var):

```bash
# The GitHub PAT is stored under the key ADMIN_PAT at /github, but tools read
# GITHUB_PAT. The map bridges the two — no preset edits:
DOTFILES_SECRET_MAP="GITHUB_PAT=ADMIN_PAT@/github"
```

Provide it headlessly (like the machine identity) via `~/.config/environment.d/*.conf` so the systemd user manager exports it at boot.

### How a service gets its secrets

The model is **plain environment variables, hydrated on demand**. A tool always just reads its secret from the environment; where that value comes from differs by context:

* **You already exported it** (e.g. a secret manager populated your env): `run.sh` sees the variable is set and uses it as-is. Nothing is fetched. The same `GITHUB_PAT` serves `gh`, VS Code, and dev tunnels — one env var, many consumers.
* **It's unset**: `secret_hydrate` resolves the spec (applying any `DOTFILES_SECRET_MAP` override), fetches from the active backend, and exports it into *this process only*. The value is never written to disk and disappears when the process exits. Raw mode takes the same specs via `--secret VAR[=LOCATOR]`.

**At boot (autostart)** there is no shell to pre-export anything, so the service hydrates its own secrets at start using the Infisical machine identity. That identity is **not** a services concept — it's a standard environment credential. Provide it headlessly the standard way, via `~/.config/environment.d/*.conf`, which the systemd user manager reads automatically:

```ini
# ~/.config/environment.d/10-infisical.conf   (chmod 600)
INFISICAL_CLIENT_ID=...
INFISICAL_CLIENT_SECRET=...
```

Everything else is fetched fresh at start. In practice most tools also cache their own credentials after the first authenticated run (VS Code file keychain, `tailscaled`), so even the machine identity is often unnecessary at boot.

#### What the secret manager fetches

The values the runner pulls, and their **default** source (key + path). If the env var is already set, it wins and nothing is fetched; any entry can be repointed via `DOTFILES_SECRET_MAP`.

| Env var | Default key | Path | Used by |
|---|---|---|---|
| `GITHUB_PAT` | `ADMIN_PAT` | `/github` | `vscode:tunnel`, `devtunnel:host` (fallback) |
| `DEVTUNNEL_TOKEN` | `DEVTUNNEL_TOKEN` | `/tunnels` | `devtunnel:host` |
| `TAILSCALE_AUTHKEY` | `TAILSCALE_AUTHKEY` | `/tailscale` | `tailscale:up` |
| `INFISICAL_CLIENT_ID` / `INFISICAL_CLIENT_SECRET` | (the machine identity itself) | — | authenticates every fetch above |

> Recommended: **don't** dump every secret into a persisted file. Persist only the
> machine identity (or nothing) and let each service pull exactly what it needs at
> start. That keeps the "no plaintext secrets on disk" guarantee intact.

---

## 🪵 Logging & Diagnostics

Every phase — bootstrap, package install, service registration, and runtime — logs
through **one dedicated logger** (`utilities/logger.sh`). It is pure bash +
coreutils (no third-party dependency), so it works the moment a shell exists. The
goal is simple: after any run you can answer **what installed, what failed, and
when** by reading a single file.

### Where the logs live

```
${XDG_STATE_HOME:-~/.local/state}/dotfiles/logs/
├── run-YYYYMMDD-HHMMSS-<pid>.log   # one file per run
└── latest.log                      # symlink → the newest run
```

Pull the most recent run's log from anywhere:

```bash
cat ~/.local/state/dotfiles/logs/latest.log        # full record of the last run
grep -E '\b(ERROR|WARN)\b' ~/.local/state/dotfiles/logs/latest.log   # just the problems
```

### What you get

* **Timestamped, structured lines.** Each file entry carries an ISO-8601 UTC
  timestamp, a severity level, and the component that emitted it:
  ```
  2026-01-01T12:34:56Z  INFO    [git]     git is already installed.
  2026-01-01T12:34:57Z  ERROR   [zsh]     Failed to install zsh. Cannot continue.
  ```
* **Dual output.** A clean, colored, concise view on the console (stderr, colored
  only on a TTY) and a complete, plain, greppable record in the file.
* **One file per run, shared across processes.** Each package installs in its own
  `bash` process, but they all inherit `DOTFILES_LOG_FILE` and append to the *same*
  file — so a full `bootstrap` + `chezmoi apply` is a single coherent log. Services
  that start at boot (no inherited env) mint their own run file, which is what you
  want for diagnosing runtime failures separately.
* **Full command capture.** Install commands run through `log_run`, which streams a
  tool's output live to the console *and* records every line into the log with
  timestamps, plus the command's real exit code.
* **Self-managing.** Writes a session header (run id, host, user, OS, arch) once
  per file, and prunes to the newest `DOTFILES_LOG_KEEP` runs (default 20).

### Tuning (environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `DOTFILES_LOG_DIR` | `${XDG_STATE_HOME:-~/.local/state}/dotfiles/logs` | Where log files are written |
| `DOTFILES_LOG_LEVEL` | `INFO` | Console verbosity: `TRACE`\|`DEBUG`\|`INFO`\|`WARN`\|`ERROR` |
| `DOTFILES_LOG_FILE_LEVEL` | `DEBUG` | File verbosity (kept more detailed than the console) |
| `DOTFILES_LOG_KEEP` | `20` | Number of run files to retain |
| `DOTFILES_LOG_NO_COLOR` / `NO_COLOR` | — | Set to disable ANSI color on the console |

```bash
# quieter console, but keep everything (incl. TRACE) in the file:
DOTFILES_LOG_LEVEL=WARN DOTFILES_LOG_FILE_LEVEL=TRACE ./bootstrap.sh
```

### Using it in a script

Any script that sources `utilities/index.sh` gets the logger automatically:

```bash
source "${SCRIPT_DIR}/../utilities/index.sh"
log_set_component "mytool"      # label lines from this script

log_info    "starting"
log_success "done"
log_warn    "optional step skipped"
log_error   "something failed"   # logs, does NOT exit
log_fatal   "unrecoverable"      # logs an error and exits 1
log_run curl -fsSL https://example.com/install.sh   # capture full output + exit code
```

---

## 🔄 Execution Flow

```
# Every phase below logs to one shared run file:
#   ${XDG_STATE_HOME:-~/.local/state}/dotfiles/logs/latest.log

# Install (bootstrap, re-applied when packages/ changes):
bootstrap.sh                                   # opens the run log; exports DOTFILES_LOG_FILE
  └─→ chezmoi init --apply
        ├─→ Deploy dotfiles into $HOME (~/.bashrc, ~/.config, etc.)
        └─→ .chezmoiscripts/run_onchange_install-packages.sh.tmpl   (re-runs when any packages/*.sh changes)
              └─→ packages/index.sh                    (install only)
                    ├── 1. System Prerequisites (git, curl, zsh)
                    ├── 2. User-Level Tools     (starship, sheldon, gh, infisical, antigravity)
                    └── 3. Controlled Tools     (vscode_cli, devtunnel, tailscale)

# Run (by hand):
services/index.sh run <tool:sub> [args...]
  └─→ run.sh: hydrate secrets (env / Infisical) → authenticate → exec in the foreground

# Autostart (declared via DOTFILES_SERVICES; registered by chezmoi, run by the OS):
chezmoi apply
  └─→ .chezmoiscripts/run_onchange_register-services.sh.tmpl   (re-runs when services/ or the list changes)
        └─→ services/index.sh enable <tool:sub>   (register a systemd/launchd/schtasks unit)
              └─→ OS init starts + supervises it at boot/login
                    └─→ services/run.sh <tool:sub>   (hydrate secret → authenticate → foreground)
```
