#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Services Universal Index, Dispatcher & Supervisor ───────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Single entry point for RUNTIME actions, mirroring packages/index.sh for
# installation. There is ONE generic runner (run.sh) and a declarative preset
# map (presets.sh) — no per-tool service scripts. A service runs two ways:
#
#   1. run     — foreground, by hand (you hold the terminal).
#   2. enable  — hand the action to the OS init system (systemd user unit on
#                Linux, launchd LaunchAgent on macOS, Task Scheduler on Windows)
#                so it STARTS ON ITS OWN at boot/login and is supervised. This
#                is the "how does it actually run?" answer: chezmoi installs, the
#                OS init runs — not chezmoi, because a `run_` script must finish
#                and a tunnel never does.
#
# WHICH services autostart is config-driven (DOTFILES_SERVICES), symmetric with
# the ENABLE_* install flags — see run_onchange_register-services.sh.tmpl.
#
# Usage:
#   services/index.sh run     <tool:sub> [args...]   run in the foreground
#   services/index.sh enable  <tool:sub> [args...]   autostart via the OS init
#   services/index.sh disable <tool:sub>             remove the autostart unit
#   services/index.sh status  [tool:sub]             show status
#   services/index.sh list                           list presets & managed units
#
# Examples:
#   services/index.sh run    vscode:tunnel my-box
#   services/index.sh enable vscode:tunnel my-box
#   services/index.sh enable tailscale:up
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
source "${SCRIPT_DIR}/presets.sh"
log_set_component "services"

RUNNER="${SCRIPT_DIR}/run.sh"

# Unit name for a "tool:sub" spec (systemd/launchd/schtasks all use bare names).
_unit_name() { printf '%s\n' "${1/:/-}"; }

_require_preset() {
    if ! preset_exists "$1"; then
        log_error "Unknown preset: ${1:-<none>}"
        _usage >&2
        exit 1
    fi
}

_usage() {
    cat <<'EOF'
Usage: services/index.sh <command> [args...]

Commands:
  run     <tool:sub> [args...]   run a service in the foreground
  enable  <tool:sub> [args...]   autostart via the OS init system (boot/login)
  disable <tool:sub>             remove the autostart unit
  status  [tool:sub]             show status of managed services
  list                           list presets and managed units

Presets:
EOF
    preset_list | sed 's/^/  /'
    cat <<'EOF'

Examples:
  services/index.sh run    vscode:tunnel my-box
  services/index.sh enable vscode:tunnel my-box
  services/index.sh enable tailscale:up
EOF
}

# ── Command: run (foreground) ────────────────────────────────────────────────
_cmd_run() {
    [[ -z "${1:-}" ]] && { _usage >&2; exit 1; }
    exec bash "$RUNNER" "$@"
}

# ── Command: enable (register + start via OS init) ──────────────────────────
_cmd_enable() {
    [[ -z "${1:-}" ]] && { log_error "enable needs <tool:sub>."; exit 1; }
    local spec="$1"; shift
    _require_preset "$spec"

    if ! service_supported; then
        log_error "Cannot autostart here: $(service_unsupported_reason)."
        log_error "Run it in the foreground instead: services/index.sh run ${spec} $*"
        exit 1
    fi

    local name desc
    name="$(_unit_name "$spec")"
    desc="dotfiles service: ${spec}"

    # The unit re-enters the generic runner so all secret/auth logic stays in one
    # place. env bash keeps the ExecStart first token absolute for systemd.
    log_info "enabling autostart for '${spec}'..."
    service_register "$name" "$desc" /usr/bin/env bash "$RUNNER" "$spec" "$@"
    service_enable "$name"
    log_success "'${spec}' enabled — it will start automatically at boot/login."
}

# ── Command: disable ─────────────────────────────────────────────────────────
_cmd_disable() {
    [[ -z "${1:-}" ]] && { log_error "disable needs <tool:sub>."; exit 1; }
    local name; name="$(_unit_name "$1")"
    service_disable "$name"
    log_success "'${1}' disabled and removed."
}

# ── Command: status ──────────────────────────────────────────────────────────
_cmd_status() {
    if [[ -n "${1:-}" ]]; then
        service_status "$(_unit_name "$1")"
    else
        log_info "Managed units:"
        service_list
    fi
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
cmd="${1:-}"
shift || true
case "$cmd" in
    run)             _cmd_run "$@" ;;
    enable)          _cmd_enable "$@" ;;
    disable)         _cmd_disable "$@" ;;
    status)          _cmd_status "$@" ;;
    list|""|-h|--help|help) _usage ;;
    *)
        log_error "Unknown command: ${cmd}"
        _usage >&2
        exit 1
        ;;
esac
