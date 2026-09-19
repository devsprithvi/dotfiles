#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Configuration ───────────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

GITHUB_USER="devsprithvi"
DOTFILES_REPO="dotfiles"
BIN_DIR="$HOME/.local/bin"

# ────────────────────────────────────────────────────────────────────────────
# ── Bootstrap Logger (self-contained) ───────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# bootstrap.sh runs BEFORE the repo exists (often piped from curl), so it can't
# source utilities/logger.sh. This is a minimal, format-compatible logger: it
# writes the SAME timestamped file format and EXPORTS the run file + id, so the
# `chezmoi apply` phase that follows (which loads the full logger) appends to
# this very same file. Result: bootstrap + install + services = one log.

DOTFILES_LOG_DIR="${DOTFILES_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/logs}"

# Establish the shared run file + id (idempotent; respects an inherited file).
_boot_log_init() {
    export DOTFILES_RUN_ID="${DOTFILES_RUN_ID:-$(date -u '+%Y%m%d-%H%M%S')-$$}"

    if [[ -n "${DOTFILES_LOG_FILE:-}" ]]; then
        mkdir -p "${DOTFILES_LOG_FILE%/*}" 2>/dev/null || true
        : >>"${DOTFILES_LOG_FILE}" 2>/dev/null || true
        return 0
    fi

    if mkdir -p "${DOTFILES_LOG_DIR}" 2>/dev/null; then
        export DOTFILES_LOG_FILE="${DOTFILES_LOG_DIR}/run-$(date -u '+%Y%m%d-%H%M%S')-$$.log"
        if : >"${DOTFILES_LOG_FILE}" 2>/dev/null; then
            ln -sf "${DOTFILES_LOG_FILE}" "${DOTFILES_LOG_DIR}/latest.log" 2>/dev/null || true
            {
                printf '════════════════════════════════════════════════════════════════════════════\n'
                printf ' Dotfiles run log — bootstrap\n'
                printf '════════════════════════════════════════════════════════════════════════════\n'
                printf ' Run ID     : %s\n' "${DOTFILES_RUN_ID}"
                printf ' Started    : %s (local: %s)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
                printf ' Host       : %s\n' "$(hostname 2>/dev/null || echo unknown)"
                printf ' User       : %s (uid %s)\n' "$(id -un 2>/dev/null || echo unknown)" "$(id -u 2>/dev/null || echo '?')"
                printf ' OS         : %s\n' "$(uname -srm 2>/dev/null || echo unknown)"
                printf ' Log file   : %s\n' "${DOTFILES_LOG_FILE}"
                printf '────────────────────────────────────────────────────────────────────────────\n'
            } >>"${DOTFILES_LOG_FILE}" 2>/dev/null || true
        else
            unset DOTFILES_LOG_FILE
        fi
    fi
}

# Colored console (stderr) when interactive; always a plain timestamped file line.
_boot_log() {
    local level="$1"; shift
    local msg="$*" comp="bootstrap" color="" reset=""

    if [[ -n "${DOTFILES_LOG_FILE:-}" ]]; then
        printf '%s  %-7s [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$comp" "$msg" \
            >>"${DOTFILES_LOG_FILE}" 2>/dev/null || true
    fi

    if [[ -t 2 && -z "${NO_COLOR:-}" && -z "${DOTFILES_LOG_NO_COLOR:-}" ]]; then
        case "$level" in
            INFO)    color=$'\033[34m' ;;
            SUCCESS) color=$'\033[32m' ;;
            WARN)    color=$'\033[33m' ;;
            ERROR)   color=$'\033[31m' ;;
        esac
        reset=$'\033[0m'
    fi
    printf '%s %s%-7s%s [%s] %s\n' "$(date '+%H:%M:%S')" "$color" "$level" "$reset" "$comp" "$msg" >&2
}

log_info()    { _boot_log INFO    "$@"; }
log_success() { _boot_log SUCCESS "$@"; }
log_warn()    { _boot_log WARN    "$@"; }
log_error()   { _boot_log ERROR   "$@"; }
log_fatal()   { _boot_log ERROR   "$@"; exit 1; }

_boot_log_init

# ────────────────────────────────────────────────────────────────────────────
# ── Helper Functions ────────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

# Check if a specific command is available in the current environment
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# Run a command with privilege (root or sudo) if available
run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        log_error "Root privileges are required but sudo is not installed."
        return 127
    fi
}

# Ensure user's local binary directory exists and is at the front of PATH
setup_path() {
    mkdir -p "$BIN_DIR"
    export PATH="$BIN_DIR:$PATH"
}

# ────────────────────────────────────────────────────────────────────────────
# ── Package Installations ───────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

# Install curl using the system package manager (fallback if curl is missing)
install_curl() {
    log_info "curl not found. Attempting auto-installation..."
    
    if has_command apt-get; then
        run_privileged apt-get update -qq && run_privileged apt-get install -y -qq curl
    elif has_command dnf; then
        run_privileged dnf install -y curl
    elif has_command pacman; then
        run_privileged pacman -Sy --noconfirm --needed curl
    elif has_command apk; then
        run_privileged apk add --no-cache curl
    elif has_command zypper; then
        run_privileged zypper --non-interactive install curl
    else
        log_error "curl is not installed and no supported package manager was found."
        log_fatal "Please install curl manually and run this script again."
    fi
    
    if ! has_command curl; then
        log_fatal "Failed to install curl. Cannot continue."
    fi
    log_success "curl installed."
}

# Detect or install chezmoi on the system
install_chezmoi() {
    # If chezmoi is already available on PATH, we are good to go
    if has_command chezmoi; then
        log_info "chezmoi is already installed."
        return 0
    fi

    # Fallback check in case chezmoi exists in local bin but PATH isn't updated yet
    if [[ -x "$BIN_DIR/chezmoi" ]]; then
        log_info "chezmoi is already installed at $BIN_DIR/chezmoi."
        return 0
    fi

    log_info "chezmoi not found. Installing to $BIN_DIR..."
    
    # We require curl to download chezmoi from the installer URL
    if ! has_command curl; then
        install_curl
    fi

    if ! curl -fsSL https://get.chezmoi.io | sh -s -- -b "$BIN_DIR"; then
        log_fatal "Failed to download and install chezmoi."
    fi
    
    if [[ ! -x "$BIN_DIR/chezmoi" ]] && ! has_command chezmoi; then
        log_fatal "chezmoi was not installed successfully."
    fi
    log_success "chezmoi installed to $BIN_DIR."
}

# ────────────────────────────────────────────────────────────────────────────
# ── Chezmoi Initialization ──────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

# Initialize and apply the chezmoi dotfiles repository
init_dotfiles() {
    log_info "Initializing dotfiles with chezmoi..."
    
    local repo_url="https://github.com/${GITHUB_USER}/${DOTFILES_REPO}.git"
    local chezmoi_bin="chezmoi"

    if [[ -x "$BIN_DIR/chezmoi" ]]; then
        chezmoi_bin="$BIN_DIR/chezmoi"
    fi

    # Apply the dotfiles repository directly using chezmoi. The child scripts it
    # runs inherit DOTFILES_LOG_FILE, so their logs land in this same file.
    if ! "$chezmoi_bin" init --apply "$repo_url"; then
        log_fatal "chezmoi init --apply failed. See the log for details: ${DOTFILES_LOG_FILE:-<console only>}"
    fi
    log_success "chezmoi applied dotfiles."
}

# ────────────────────────────────────────────────────────────────────────────
# ── Main Execution Flow ─────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

main() {
    log_info "════════════ Dotfiles Bootstrap ════════════"
    log_info "Logging to: ${DOTFILES_LOG_FILE:-<console only>}"

    setup_path
    install_chezmoi
    init_dotfiles

    log_success "════════════ Bootstrap complete! Open a new shell to continue. ════════════"
}

main "$@"
