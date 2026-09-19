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
├── .chezmoiscripts/      # Chezmoi lifecycle triggers (runs package orchestration once)
├── packages/             # Software definitions — each script installs & configures a tool
├── utilities/            # Shared libraries (OS detection, privilege handling, secrets)
│   └── installers/       # Generic package manager abstractions (apt, brew, dnf, etc.)
├── components/           # Standalone projects under development, parked here (NOT deployed)
└── dot_*                 # Managed user configurations mapped directly to $HOME
```

### Architectural Responsibilities

* **`packages/`**: High-level tool recipes. Each script manages the end-to-end lifecycle of a specific tool or application (system prerequisites, developer CLI tools, optional networking daemons).
* **`utilities/installers/`**: Low-level package manager wrappers. These provide uniform, idempotent helper functions around system package managers (`apt`, `brew`, `dnf`, `pacman`, etc.) so tool scripts don't duplicate distro-specific installation logic.
* **`utilities/`**: Core runtime libraries for OS/architecture discovery (`os.sh`), privilege escalation and credential lookups (`helpers.sh`).
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

| Feature / Tool | Trigger Flag | Intent & Notes |
|---|---|---|
| **VS Code CLI** | `ENABLE_VSCODE_CLI=1` | Installs the lightweight standalone `code` binary for headless/remote machines. |
| **VS Code Tunnel** | `ENABLE_VSCODE_TUNNEL=1` | Configures the `code tunnel` subcommand and registers a background systemd user service. (Auto-installs the CLI). |
| **Tailscale** | `ENABLE_TAILSCALE=1` | Installs Tailscale mesh VPN; connects non-interactively if an auth key is supplied. |

**Example:**
```bash
ENABLE_VSCODE_TUNNEL=1 ENABLE_TAILSCALE=1 ./bootstrap.sh
```

**Optional Configuration Variables:**
* `VSCODE_TUNNEL_NAME`: Custom tunnel name (defaults to current `$(hostname)`).
* `TAILSCALE_AUTHKEY`: Direct auth key override (otherwise fetched dynamically from Infisical vault at `/tailscale`).

---

## ⚙️ Secrets Management (Infisical)

Secrets are never committed or stored persistently in plaintext on disk:
1. **Dynamic REST API Resolution**: Chezmoi templates and scripts authenticate on-the-fly via Infisical Universal Auth (`INFISICAL_CLIENT_ID` / `INFISICAL_CLIENT_SECRET`) directly using `curl` and `python3`.
2. **Centralized Helper**: `fetch_infisical_secret` in `utilities/helpers.sh` provides a single function for scripts to retrieve vault secrets without hardcoding paths or relying on local credentials.
3. **Graceful Degradation**: When credentials are not provided, secrets evaluate to empty strings and opt-in services fall back cleanly without breaking the bootstrap run.

---

## 🔄 Execution Flow

```
bootstrap.sh
  └─→ chezmoi init --apply
        ├─→ Deploy dotfiles into $HOME (~/.bashrc, ~/.config, etc.)
        └─→ .chezmoiscripts/run_once_install-packages.sh.tmpl
              └─→ packages/index.sh
                    ├── 1. System Prerequisites (git, curl, zsh)
                    ├── 2. User-Level Tools     (starship, sheldon, gh, infisical, antigravity)
                    └── 3. Controlled Tools     (vscode_cli [with optional tunnel], tailscale)
```
