#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Packages Universal Index & Orchestrator ─────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# This file serves as the single entry point to install all defined packages
# in the correct dependency order.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

log_set_component "packages"
log_init "package installation"
log_section "Installing Packages"
log_info "OS: ${OS_PRETTY_NAME:-unknown} (${OS_ARCH:-?}) — logging to ${DOTFILES_LOG_FILE:-<console only>}"

# Track outcomes so the run ends with a clear, greppable summary.
_PKG_OK=()
_PKG_FAILED=()

run_package() {
    local name="$1"
    local script="${SCRIPT_DIR}/${name}.sh"

    if [[ ! -f "${script}" ]]; then
        log_error "${name}.sh not found. Skipping."
        _PKG_FAILED+=("$name")
        return 1
    fi

    log_info "── ${name} ──"
    # Child inherits DOTFILES_LOG_FILE/component-agnostic env and logs to the
    # same file under its own component name.
    if bash "${script}"; then
        _PKG_OK+=("$name")
    else
        local rc=$?
        log_error "package '${name}' failed (exit ${rc})."
        _PKG_FAILED+=("$name")
        return "$rc"
    fi
}

# ── 1. System prerequisites (may need sudo) ─────────────────────────────────
run_package "git"
run_package "curl"
run_package "zsh"

# ── 2. User-level tools (no sudo) ───────────────────────────────────────────
run_package "starship"
run_package "sheldon"
run_package "gh"
run_package "infisical"
run_package "antigravity_cli"
run_package "opencode"

# ── 3. Optional / controlled tools (env-var gated) ──────────────────────────
# These packages only install when their corresponding ENABLE_* env var is set.
# See each script's header for control variables and dependencies.
run_package "vscode_cli"
run_package "devtunnel"
run_package "tailscale"

log_section "Package installation summary"
log_success "Installed/verified: ${_PKG_OK[*]:-none}"
if [[ "${#_PKG_FAILED[@]}" -gt 0 ]]; then
    log_error "Failed: ${_PKG_FAILED[*]}"
    log_error "Review the full log: ${DOTFILES_LOG_FILE:-<console only>}"
else
    log_success "All packages installed! Full log: ${DOTFILES_LOG_FILE:-<console only>}"
fi
