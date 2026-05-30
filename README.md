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

---

## 🛠️ What's Installed & Configured

Once initialized, the automated bootstrapping process will silently and non-interactively install the following core tools:

*   **Shell & Prompts**: Zsh & Starship prompt.
*   **Plugins**: Sheldon plugin manager.
*   **Version Control**: Git & GitHub CLI (`gh`).
*   **Secret Management**: Infisical CLI (via official Cloudsmith repositories).
*   **AI Pair Programming**: Antigravity CLI.

---

## ⚙️ Secrets Integration (Machine Identity)

This setup securely retrieves credentials (e.g. GitHub tokens) via **Infisical**.

*   **Zero-Config Seamless Mode**: If you configure your Infisical Machine Identity credentials in your environment variables (`INFISICAL_CLIENT_ID` and `INFISICAL_CLIENT_SECRET`), the setup retrieves your secrets fully automatically and seamlessly.
*   **Safe Fallback Mode**: If these environment variables are not found, the templates gracefully fall back to empty strings `""` without throwing any execution errors, keeping the bootstrap 100% automated and non-interactive.
