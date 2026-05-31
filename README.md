# 🌌 Prudhvi's Dotfiles

A fully automated, zero-dependency, cross-platform configuration setup built on top of [Chezmoi](https://www.chezmoi.io/), featuring modern shell utilities, highly curated styling, and secure, non-blocking credential lookups.

## 🚀 Quick Start / Bootstrap

To seamlessly install Chezmoi and apply these dotfiles on any new Debian/Ubuntu, macOS, or Windows environment, run the following two commands:

### 1. Install Chezmoi (User Level)
```bash
sh -c "$(curl -fsSL https://get.chezmoi.io)" -- -b "$HOME/.local/bin"
```

### 2. Add to PATH and Apply
```bash
export PATH="$HOME/.local/bin:$PATH"
chezmoi init --apply https://github.com/devsprithvi/dotfiles.git
```

> [!TIP]
> Alternatively, you can run the bootstrap script directly to manage everything including automatic secret resolution and dependency setup:
> ```bash
> sh -c "$(curl -fsSL https://raw.githubusercontent.com/devsprithvi/dotfiles/main/bootstrap.sh)"
> ```

---

## 🛠️ What's Installed & Configured

Once initialized, the automated bootstrapping process will silently and non-interactively install the following core tools:

*   **Shell & Prompts**: Zsh & Starship prompt.
*   **Plugins**: Sheldon plugin manager.
*   **Version Control**: Git & GitHub CLI (`gh`).
*   **Secret Management**: Infisical CLI (via official Cloudsmith repositories).
*   **AI Pair Programming**: Antigravity CLI.

---

## ⚙️ Secrets Integration (Machine Identity & Token Automation)

This setup securely retrieves credentials (e.g., GitHub tokens) via **Infisical**, completely bypassing limited container environment tokens to avoid `403 Forbidden` push errors.

### 1. On-The-Fly Template Resolution (Native Chezmoi)
The chezmoi template `private_hosts.yml.tmpl` automatically detects `INFISICAL_CLIENT_ID` and `INFISICAL_CLIENT_SECRET` in the active shell environment. If present during execution, it runs a dynamic `curl` pipeline to perform a Universal Auth login to the Infisical API, fetches your secrets, and retrieves the GitHub administrative token (`ADMIN_PAT`) natively on-the-fly. This keeps the bootstrap script (`bootstrap.sh`) 100% minimal and simple.

### 2. Dynamic Shell Integration
Your `.bashrc` and `.zshrc` shell configurations are enhanced with an automated startup sequence:
*   When a new shell session initializes, it dynamically authenticates with Infisical.
*   It exposes `INFISICAL_TOKEN` and `INFISICAL_PROJECT_ID` variables to your environment.
*   Any future interactive shell operations can utilize these credentials directly.

### 3. Safe Fallback Mode
If no Infisical credentials are found in the environment, the templates gracefully fall back to empty strings `""` without throwing execution errors, keeping the bootstrap 100% automated and non-interactive.
