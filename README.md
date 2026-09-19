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
├── services/             # RUN — one generic runner + a preset map; run by hand OR autostart via the OS init
├── utilities/            # Shared libraries (OS detection, privilege handling, secrets, service manager)
│   └── installers/       # Generic package manager abstractions (apt, brew, dnf, etc.)
├── components/           # Standalone projects under development, parked here (NOT deployed)
└── dot_*                 # Managed user configurations mapped directly to $HOME
```

### Architectural Responsibilities

The layering enforces one hard boundary: **install** and **run** are separate.

* **`packages/`**: Installation only. Each script installs exactly one tool (download the binary, or defer to a package manager) and exits. It performs **no** authentication, tunnel/service registration, or `tailscale up` — those are runtime concerns. This is what `chezmoi` runs once during bootstrap.
* **`services/`**: Runtime actions only. There is **one generic runner** (`run.sh`) plus a **declarative preset map** (`presets.sh`) keyed by `tool:sub` — not one script per tool. The runner hydrates secrets from the secret manager into environment variables, performs the preset's auth step, then execs the tool in the foreground. It never installs; if a tool is missing the preset points you at the matching package. `run.sh` also runs a **raw command** directly (`--secret VAR@PATH -- CMD...`). Services run two ways: **by hand** (`run`) or **supervised by the OS** so they autostart at boot/login (`enable` — see [Autostart](#autostart--how-services-actually-run)).
* **`utilities/installers/`**: Low-level package manager wrappers. Uniform, idempotent helpers around system package managers (`apt`, `brew`, `dnf`, `pacman`, etc.) so packages don't duplicate distro-specific install logic.
* **`utilities/`**: Core shared libraries for OS/architecture discovery (`os.sh`), privilege escalation and credential lookups (`helpers.sh`), and the init-system abstraction that registers autostart units (`service_manager.sh`). Sourced by both packages and services.
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
replacement for the ad-hoc `utilities/installers/` shell wrappers, orchestrated
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

Installation and running are deliberately separate. `services/` is **one generic runner** (`run.sh`) driven by a **preset map** (`presets.sh`) keyed by `tool:sub`. The runner hydrates the preset's secrets into the environment, performs its auth step, then runs the tool in the foreground.

```bash
services/index.sh run <tool:sub> [args...]   # run a preset in the foreground
services/index.sh list                       # show presets and managed units

# presets:
services/index.sh run vscode:tunnel [name]              # VS Code tunnel (vscode.dev/tunnel/<name>)
services/index.sh run vscode:web [host] [port] [token]  # VS Code web server (serve-web)
services/index.sh run devtunnel:host [port ...]         # host ports via a Microsoft Dev Tunnel
services/index.sh run tailscale:up                      # connect this machine to the tailnet

# run ANY command through the same convenience layer (raw mode):
services/run.sh --secret GITHUB_VSCODE_PAT@/github -- my-tool --flag
```

Adding a tool is a new `case` in `presets.sh` (a command + its secret paths + an optional login step) — no new script file, no dispatcher wiring.

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
> own), so autostart needs no secret at boot. If a service *does* need secrets at
> boot (e.g. Infisical machine identity), the generated systemd unit optionally
> sources `~/.config/dotfiles/service.env` — create it yourself (chmod 600); we
> never write secrets to disk for you.
>
> **No init system?** Containers and WSL without systemd have no `systemctl --user`
> manager; `enable` detects this, tells you, and you fall back to `run`.

**Configuration Variables (read by the services at run time):**
* `VSCODE_TUNNEL_NAME`: Tunnel name (defaults to `$(hostname)`).
* `VSCODE_WEB_HOST` / `VSCODE_WEB_PORT` / `VSCODE_WEB_TOKEN`: web server bind host (`0.0.0.0`), port (`8000`), and optional connection token.
* `GITHUB_VSCODE_PAT`: GitHub PAT for non-interactive VS Code tunnel / dev tunnel login (otherwise fetched from Infisical at `/github`).
* `DEVTUNNEL_TOKEN`: Dev Tunnels access token (otherwise fetched from Infisical at `/tunnels`).
* `TAILSCALE_AUTHKEY`: Auth key for non-interactive connect (otherwise fetched from Infisical at `/tailscale`).
* `DOTFILES_SERVICES`: space-separated `tool:sub` list to autostart at bootstrap/apply.

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

## ⚙️ Secrets Management (Infisical)

Secrets are never committed or stored persistently in plaintext on disk:
1. **Dynamic REST API Resolution**: Chezmoi templates and scripts authenticate on-the-fly via Infisical Universal Auth (`INFISICAL_CLIENT_ID` / `INFISICAL_CLIENT_SECRET`) directly using `curl` and `python3`.
2. **Centralized Helper**: `fetch_infisical_secret` in `utilities/helpers.sh` provides a single function for scripts to retrieve vault secrets without hardcoding paths or relying on local credentials.
3. **Graceful Degradation**: When credentials are not provided, secrets evaluate to empty strings and opt-in services fall back cleanly without breaking the bootstrap run.

### How a service gets its secrets

The model is **environment variables, hydrated on demand** — the tool always just reads its secret from the env; where that value comes from differs by context:

* **You already exported it** (e.g. a secret manager populated your shell env): `run.sh` sees the variable is set and uses it as-is. Nothing is fetched.
* **It's unset**: `run.sh` pulls it from Infisical at start (via the machine identity) and exports it into *this process only*. The tool reads it from the env; the value is never written to disk and disappears when the process exits. Each preset declares its secrets statically as `VAR@PATH` (e.g. `GITHUB_VSCODE_PAT@/github`); raw mode takes the same specs via `--secret`.

**At boot (autostart)** there is no shell to pre-export anything, so the service hydrates its own secrets at start. The only thing that must reach the unit is the Infisical machine identity — put `INFISICAL_CLIENT_ID` / `INFISICAL_CLIENT_SECRET` in `~/.config/dotfiles/service.env` (chmod 600), which the generated systemd unit sources via `EnvironmentFile=-`. Everything else is fetched fresh. In practice most tools also cache their own credentials after the first authenticated run (VS Code file keychain, `tailscaled`), so even that is often unnecessary.

> Recommended: **don't** dump every secret into a persisted env file. Persist only
> the machine identity (or nothing) and let each service pull exactly what it needs
> at start. That keeps the "no plaintext secrets on disk" guarantee intact.

---

## 🔄 Execution Flow

```
# Install (bootstrap, re-applied when packages/ changes):
bootstrap.sh
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
