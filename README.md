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
├── commands/             # RUN — preset commands + runner (run.sh) + boot registrar (startup.sh) + autostart.sh
│   └── presets/          # One file per tool (vscode, tailscale, devtunnel) + the loader index
├── utilities/            # Shared libraries (OS detection, logging, privilege handling, secrets bridge)
│   └── logger.sh         # Dedicated logging facility (timestamped, leveled, console + file)
├── tests/                # Offline unit tests (e.g. secrets_test.sh); not deployed
├── components/           # Standalone projects under development, parked here (NOT deployed)
└── dot_*                 # Managed user configurations mapped directly to $HOME
```

### Architectural Responsibilities

The layering enforces one hard boundary: **install** and **run** are separate.

* **`packages/`**: Installation only. Each script installs exactly one tool (download the binary, or defer to a package manager) and exits. It performs **no** authentication, tunnel/service registration, or `tailscale up` — those are runtime concerns. This is what `chezmoi` runs once during bootstrap.
* **`commands/`**: Runtime actions only. A **command** is a preset — a pre-designed command plus a small convenience layer — defined **one file per tool** under `commands/presets/` (keyed by `tool:sub`); `commands/presets/index.sh` is the tiny loader. `commands/run.sh` is the generic engine: it hydrates secrets into the environment, runs the preset's non-interactive auth check (which reuses any existing login instead of repeating it), then execs the tool in the foreground. `commands/startup.sh` is the **dotfile startup**: it turns the declared list into OS autostart units so those commands run at every boot. This folder is ignored by chezmoi (never copied to `$HOME`) — you don't run it by hand; you declare what should autostart (see [Autostart](#autostart--how-commands-actually-run)). `run.sh` can also run a **raw command** directly (`--secret VAR@PATH -- CMD...`).
* **`packages/installers/`**: Low-level package manager wrappers. Uniform, idempotent helpers around system package managers (`apt`, `brew`, `dnf`, `pacman`, etc.) so packages don't duplicate distro-specific install logic. They live inside `packages/` because the package scripts are their only consumers.
* **`utilities/`**: Core shared libraries for OS/architecture discovery (`os.sh`), the dedicated logger (`logger.sh`), and privilege escalation and credential lookups (`helpers.sh`). Sourced across the whole repo. The OS init-system abstraction that registers autostart units is **not** here — it lives in `commands/autostart.sh`, next to its only consumer `commands/startup.sh`.
* **`utilities/logger.sh`**: A single, dependency-free logging facility used across the whole lifecycle (bootstrap → install → startup). Every line is timestamped and leveled; output goes to both the console and a persistent per-run log file so failures are diagnosable after the fact. See [Logging & Diagnostics](#-logging--diagnostics).
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
* **Developer Tools**: Git, GitHub CLI (`gh`), Antigravity CLI, and OpenCode (terminal AI coding agent).
* **Secret Management**: Infisical CLI.

### Controlled / Optional Tools
Certain heavy tools or remote-access daemons are opt-in, controlled via environment variables:

These flags only control **installation** (what `chezmoi`/bootstrap installs). Running the tools is a separate step — see [Commands & Startup](#commands--startup-commands) below.

| Feature / Tool | Trigger Flag | Installs |
|---|---|---|
| **VS Code CLI** | `ENABLE_VSCODE_CLI=1` | The lightweight standalone `code` binary for headless/remote machines. |
| **Dev Tunnel** | `ENABLE_DEVTUNNEL=1` | Microsoft's standalone Dev Tunnels CLI. |
| **Tailscale** | `ENABLE_TAILSCALE=1` | The Tailscale mesh VPN client. |

**Example:**
```bash
ENABLE_VSCODE_CLI=1 ENABLE_TAILSCALE=1 ./bootstrap.sh
```

### Commands & Startup (`commands/`)

Installation and running are deliberately separate. A **command** is a *preset*: a pre-designed command plus a small convenience layer, defined **one file per tool** in `commands/presets/`, keyed by `tool:sub`. `commands/run.sh` is the engine — it hydrates the preset's secrets into the environment, runs its non-interactive auth check, then execs the tool in the foreground. The **dotfile startup** (`commands/startup.sh`) runs whichever commands you declare automatically at every boot.

#### Available preset commands

| Command (`tool:sub`) | Runtime settings (env) | What it does |
|---|---|---|
| `vscode:tunnel` | `VSCODE_TUNNEL_NAME` | VS Code remote tunnel (`vscode.dev/tunnel/<name>`) |
| `vscode:web` | `VSCODE_WEB_HOST` / `_PORT` / `_TOKEN` | VS Code web server (`serve-web`) |
| `devtunnel:host` | — | host ports via a Microsoft Dev Tunnel |
| `tailscale:up` | `TAILSCALE_AUTHKEY` | connect this machine to the tailnet |

**You normally never run these by hand** — `commands/` is ignored by chezmoi and isn't in your `$HOME`. You declare which ones autostart (next section). The engine is available for one-off debugging from the source dir if needed:

```bash
# one-off, from the chezmoi source dir (~/.local/share/chezmoi):
commands/run.sh <tool:sub>                                   # run a preset once, foreground
commands/run.sh --secret GITHUB_PAT=ADMIN_PAT@/github -- CMD  # raw command, no preset
```

> **`vscode:tunnel` — log in ONCE (manually), then it autostarts forever.**
> Authentication and running are separate jobs. The tunnel service rejects GitHub
> PATs ([microsoft/vscode#310726](https://github.com/microsoft/vscode/issues/310726)),
> so the credential can only come from an interactive OAuth login — done with the
> VS Code CLI's own command, which authenticates *without* starting a tunnel:
> `code tunnel user login --provider github`. Run it once on the machine, open the
> printed `github.com/login/device` link and enter the code. The VS Code CLI
> stores that login itself and reuses it on every later boot. The `vscode:tunnel`
> command only *runs* the tunnel; until you've logged in it just prints that
> command and stops cleanly (no restart loop) rather than trying to log in for you.

Adding a tool is a new file under `commands/presets/` — one file per tool, defining its `list` line, the secrets it needs, and how it runs (`_preset_<tool>_load`, with an optional non-interactive `preset_authenticate`). No dispatcher wiring, no single shared preset file to edit. Keep this table and the [secret table](#what-the-secret-manager-fetches) in sync when you do.

### Autostart — how commands actually run

`chezmoi` can't keep a command running for you: a `run_` script must **finish** during `chezmoi apply`, and a tunnel / web server / VPN session never finishes. So instead of running them, we hand the ones you declare to the OS's own init system, which starts and supervises them:

| OS | Mechanism | Where |
|---|---|---|
| **Linux** | systemd **user** unit (`Restart=on-failure`, linger enabled so it survives logout/boot) | `~/.config/systemd/user/dotfiles-<name>.service` |
| **macOS** | launchd **LaunchAgent** (`RunAtLoad`, `KeepAlive`) | `~/Library/LaunchAgents/dotfiles-<name>.plist` |
| **Windows** | Task Scheduler **logon task** (best-effort) | `dotfiles\<name>` |

**The whole interface is one declaration.** Set the `DOTFILES_STARTUP` env var (a space-separated list of `tool:sub` presets) when you apply — symmetric with the `ENABLE_*` install flags. During `chezmoi apply`, `run_onchange_register-startup` reconciles that list into autostart units: everything listed is enabled to start at every boot, and **anything previously managed but no longer listed is removed**. The list is the single source of truth; empty (the default) removes everything. Per-preset settings come from that preset's own env vars, so the list stays a plain set of names.

```bash
# install VS Code CLI + Tailscale, then autostart a tunnel and the tailnet:
ENABLE_VSCODE_CLI=1 ENABLE_TAILSCALE=1 \
DOTFILES_STARTUP="vscode:tunnel tailscale:up" ./bootstrap.sh

# later: change the set by re-applying with a different list
DOTFILES_STARTUP="tailscale:up" chezmoi apply    # drops the tunnel, keeps tailscale
DOTFILES_STARTUP="" chezmoi apply                # removes everything we manage
```

There is no manual enable/disable/status command — editing `DOTFILES_STARTUP` and re-applying is how you turn things on and off. Inspect a running unit with the OS's own tools:

```bash
# Linux:
systemctl --user status dotfiles-vscode-tunnel
journalctl --user -u dotfiles-vscode-tunnel -f
```

> **Boot-time secrets:** most tools persist their own credentials after the first
> authenticated run (VS Code stores its login; `tailscaled` reconnects on its
> own), so autostart needs no secret at boot. There is **no startup-specific env
> file** — the unit inherits the standard systemd user environment. If a command
> *does* need the Infisical machine identity at boot, set it like any other env
> var via `~/.config/environment.d/*.conf` (the user manager reads it
> automatically); it is not special to startup.
>
> **Headless boot (SSH / cloud-init):** on a server with no interactive login there
> is no active `systemd --user` session yet, and `XDG_RUNTIME_DIR` is unset — so a
> naive `systemctl --user` can't reach the user bus. The reconciler handles this: it
> sets `XDG_RUNTIME_DIR`, enables **linger** (which starts `user@UID.service` now and
> at every boot), waits for the user bus, then enables the unit. No interactive login
> required.
>
> **No init system?** Containers and WSL *without* systemd have no `systemctl --user`
> manager at all; the reconciler detects that (systemd isn't PID 1), warns, and
> registers nothing.

**Configuration Variables (read by the commands at run time):**
* `VSCODE_TUNNEL_NAME`: Tunnel name (defaults to `$(hostname)`).
* `VSCODE_WEB_HOST` / `VSCODE_WEB_PORT` / `VSCODE_WEB_TOKEN`: web server bind host (`0.0.0.0`), port (`8000`), and optional connection token.
* `GITHUB_PAT`: GitHub personal access token for non-interactive **dev tunnel** login (default source: key `ADMIN_PAT` at `/github`). Note: the **VS Code tunnel does not accept PATs** — it needs a manual `code tunnel user login`.
* `DEVTUNNEL_TOKEN`: Dev Tunnels access token (otherwise fetched at `/tunnels`).
* `TAILSCALE_AUTHKEY`: Auth key for non-interactive connect (otherwise fetched at `/tailscale`).
* `DOTFILES_STARTUP`: space-separated `tool:sub` list of preset commands to autostart at every boot (declared at bootstrap/apply; the single source of truth).
* `DOTFILES_SECRET_MAP`: per-var source overrides, e.g. `GITHUB_PAT=ADMIN_PAT@/github` — change *where* a secret comes from without editing any preset.
* `SECRET_PROVIDER`: secret backend id (default `infisical`; `env` = use only pre-set vars).
* `INFISICAL_ENV`: default environment slug for `infisical` lookups (default `global`).

> `vscode web` runs without a connection token unless one is supplied — bind it to
> localhost or place it behind a tunnel/VPN/reverse proxy on shared networks.

> **Design — one generic runner, one preset file per tool, one startup list.**
> `commands/run.sh` is the single engine (hydrate secrets → non-interactive auth
> check → exec). The tool-specific knowledge a raw command lacks — the command to
> run, the secret names it needs, its auth check — lives in its own file under
> `commands/presets/` (`vscode.sh`, `devtunnel.sh`, `tailscale.sh`); `presets/index.sh`
> only loads and dispatches to them. `commands/startup.sh` reconciles the
> `DOTFILES_STARTUP` list into boot units. Authentication that requires a human
> (e.g. the VS Code tunnel OAuth login) stays a manual step you run with the tool's
> own CLI — the preset never automates it. Each preset is idempotent: it checks its
> own state and never repeats work already done.

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
2. **Three separated concerns**: the **env var** a tool reads (the stable contract — services declare only this), the **mapping** from that var to a location (owned entirely by the active provider), and **which backend** to ask (`SECRET_PROVIDER`). Changing one never forces a change to the others.
3. **Graceful degradation**: with no credentials (or `SECRET_PROVIDER=env`), lookups return empty and opt-in commands fall back cleanly without breaking bootstrap.

### Where the mapping lives

A preset declares only the **env var names** it needs — never a key or a path:

```bash
# commands/presets/devtunnel.sh
_preset_devtunnel_secret_specs() { case "$1" in host) printf '%s\n' "GITHUB_PAT" ;; esac; }
```

The active provider owns the map from a var to its location, in that provider's
own dialect. For `infisical` (`secrets/providers/infisical.sh`):

```bash
declare -gA _INFISICAL_SECRET_MAP=(
    [GITHUB_PAT]="ADMIN_PAT@/github"   # key ADMIN_PAT, path /github
)
```

The locator syntax is the provider's own: `[KEY][@[ENV:]PATH]`. Anything omitted
falls back to the named constants at the top of the provider file — key to the
var name, env to `$INFISICAL_ENV` (default `global`), path to
`$INFISICAL_DEFAULT_PATH` (default `/`). So `DEVTUNNEL_TOKEN` mapped to
`@/tunnels` means "key `DEVTUNNEL_TOKEN`, path `/tunnels`".

To repoint a var at runtime **without editing the provider**, set
**`DOTFILES_SECRET_MAP`** (keyed by var). It wins over the provider map:

```bash
DOTFILES_SECRET_MAP="GITHUB_PAT=ADMIN_PAT@/github"
```

Precedence: `DOTFILES_SECRET_MAP` → provider map → convention. Provide the
override headlessly via `~/.config/environment.d/*.conf` so it is set at boot.

### How a service gets its secrets

The model is **plain environment variables, hydrated on demand**. A tool always just reads its secret from the environment; where that value comes from differs by context:

* **You already exported it** (e.g. a secret manager populated your env): `run.sh` sees the variable is set and uses it as-is. Nothing is fetched. The same `GITHUB_PAT` serves `gh`, VS Code, and dev tunnels — one env var, many consumers.
* **It's unset**: `secret_hydrate` resolves the var (a `DOTFILES_SECRET_MAP` override, else the active provider's map), fetches from the backend, and exports it into *this process only*. The value is never written to disk and disappears when the process exits. Raw mode can also pass an explicit locator via `--secret VAR[=LOCATOR]`.

**At boot (autostart)** there is no shell to pre-export anything, so the command hydrates its own secrets at start using the Infisical machine identity. That identity is **not** a startup concept — it's a standard environment credential. Provide it headlessly the standard way, via `~/.config/environment.d/*.conf`, which the systemd user manager reads automatically:

```ini
# ~/.config/environment.d/10-infisical.conf   (chmod 600)
INFISICAL_CLIENT_ID=...
INFISICAL_CLIENT_SECRET=...
```

Everything else is fetched fresh at start. In practice most tools also cache their own credentials after the first authenticated run (VS Code stores its login, `tailscaled`), so even the machine identity is often unnecessary at boot.

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
                    ├── 2. User-Level Tools     (starship, sheldon, gh, infisical, antigravity, opencode)
                    └── 3. Controlled Tools     (vscode_cli, devtunnel, tailscale)

# Autostart at every boot (the whole interface — declared via DOTFILES_STARTUP):
DOTFILES_STARTUP="vscode:tunnel tailscale:up" chezmoi apply
  └─→ .chezmoiscripts/run_onchange_register-startup.sh.tmpl   (re-runs when commands/ or the list changes)
        └─→ commands/startup.sh   (reconcile: enable listed, remove unlisted)
              └─→ registers a systemd/launchd unit per command
                    └─→ OS init starts + supervises it at boot/login
                          └─→ commands/run.sh <tool:sub>   (hydrate secret → auth check → foreground)

# One-off by hand (rarely needed; from the chezmoi source dir):
commands/run.sh <tool:sub> [args...]
  └─→ hydrate secrets (env / Infisical) → auth check → exec in the foreground
```
