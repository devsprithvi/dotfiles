#!/usr/bin/env bash
set -eo pipefail

# ── Post-Setup: Default Shell → zsh ────────────────────────────────────────
# Changes the user's login shell to zsh.
# Safe to run repeatedly — skips if zsh is already the default.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if ! has_command zsh; then
    echo "[shell] zsh is not installed. Skipping shell change."
    exit 0
fi

if os_is_windows; then
    echo "[shell] Skipping shell change on Windows."
    exit 0
fi

ZSH_PATH="$(command -v zsh)"

# ── Already the default? ───────────────────────────────────────────────────
CURRENT_SHELL="${SHELL:-}"
if [[ "${CURRENT_SHELL}" == "${ZSH_PATH}" ]]; then
    echo "[shell] zsh is already the default shell."
    exit 0
fi

# ── Containers / non-interactive environments ──────────────────────────────
# In containers, chsh is often unavailable or pointless.
if ${OS_IS_CONTAINER}; then
    echo "[shell] Container detected. Skipping chsh."
    echo "[shell] To use zsh in this container, run: exec zsh"
    exit 0
fi

# ── Ensure zsh is in /etc/shells ───────────────────────────────────────────
# chsh will refuse to set a shell not listed in /etc/shells.
if [[ -f /etc/shells ]] && ! grep -qxF "${ZSH_PATH}" /etc/shells; then
    echo "[shell] Adding ${ZSH_PATH} to /etc/shells..."
    if can_run_privileged; then
        echo "${ZSH_PATH}" | run_privileged tee -a /etc/shells > /dev/null
    else
        echo "[shell] WARNING: Cannot add zsh to /etc/shells without sudo."
        echo "[shell] You may need to run manually: echo '${ZSH_PATH}' | sudo tee -a /etc/shells"
    fi
fi

# ── Change the default shell ──────────────────────────────────────────────
echo "[shell] Changing default shell to zsh (${ZSH_PATH})..."

if os_is_macos; then
    # macOS: chsh works without sudo for the current user
    chsh -s "${ZSH_PATH}" && echo "[shell] Default shell changed to zsh." || {
        echo "[shell] WARNING: chsh failed. You can change it manually:"
        echo "[shell]   chsh -s ${ZSH_PATH}"
    }
elif os_is_linux; then
    if can_run_privileged; then
        run_privileged chsh -s "${ZSH_PATH}" "$(whoami)" && \
            echo "[shell] Default shell changed to zsh." || {
            echo "[shell] WARNING: chsh failed. You can change it manually:"
            echo "[shell]   chsh -s ${ZSH_PATH}"
        }
    else
        echo "[shell] Cannot change shell without sudo."
        echo "[shell] Run manually: chsh -s ${ZSH_PATH}"
    fi
fi
