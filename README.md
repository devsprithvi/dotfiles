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

## ⚙️ Secrets Integration & Architecture Philosophy

This repository implements a highly secure, modern, and completely automated approach to secret management using **Infisical**. It is designed to work seamlessly in both local environments and restricted container systems (like GitHub Codespaces) without throwing validation errors.

### 1. On-The-Fly REST API Secret Resolution
To preserve a stateless and highly secure environment, **secrets are never hardcoded or persistently stored in config files**. Instead, any chezmoi template requiring authentication utilizes a standard API pipeline:
*   During template compilation, the template detects `INFISICAL_CLIENT_ID` and `INFISICAL_CLIENT_SECRET` in the active environment.
*   It performs a dynamic, non-interactive Universal Auth login request to the Infisical REST API on-the-fly.
*   The raw secrets are retrieved directly from your project vault (`e3e7a48d-605a-4ae2-b202-2dbf45918227`) and parsed in-memory.
*   This approach completely eliminates dependencies on local session files or the `infisical` CLI binary during the bootstrap phase, executing natively via standard utilities (`curl` and `python3`).

### 2. Dynamic Shell Sessions
Your `.bashrc` and `.zshrc` shell configurations are enhanced with an automated startup sequence that dynamically authenticates your shell with Infisical when a new session initializes. This exposes the necessary tokens directly in your environment, allowing any subsequent interactive terminal commands or manual chezmoi updates to inherit the credentials seamlessly.

### 3. Safe Fallback Design
If no Infisical credentials are found in the environment, the templates gracefully fall back to empty strings `""` without throwing execution errors, keeping the bootstrap 100% automated and non-interactive.
