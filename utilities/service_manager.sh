#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_SERVICE_MANAGER_LIB_LOADED:-}" ]] && return 0
_SERVICE_MANAGER_LIB_LOADED=1

# ────────────────────────────────────────────────────────────────────────────
# ── Service Manager — OS init-system abstraction ────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# The missing piece between "install" (packages/) and "run" (services/): making
# a runtime action start ON ITS OWN — at boot / login — supervised by the OS's
# native init system instead of a human holding a terminal open.
#
#   Linux    → systemd *user* units      (~/.config/systemd/user/<name>.service)
#   macOS    → launchd LaunchAgents       (~/Library/LaunchAgents/<name>.plist)
#   Windows  → Task Scheduler logon task  (schtasks, best-effort)
#
# chezmoi deliberately does NOT run long-lived services during `apply` (a `run_`
# script must finish; a tunnel never does). So instead of running them, we hand
# them to the OS supervisor: chezmoi registers the units, the OS starts them.
#
# Every unit is prefixed "dotfiles-" so managed units are always identifiable
# and removable. The command to run is passed as separate arguments (no shell
# string splitting), so args with paths stay intact across all three backends.
#
# Public API:
#   service_supported                       → 0 if this OS has a driveable init
#   service_register <name> <desc> <cmd...> → create/refresh the unit definition
#   service_enable   <name>                 → enable + start now (+ boot persist)
#   service_disable  <name>                 → stop + disable + remove the unit
#   service_status   <name>                 → print current status
#   service_list                            → list dotfiles-managed units
#
# <name> is the bare service name (e.g. "vscode-tunnel"); the "dotfiles-" prefix
# and the backend-specific extension are added internally.
# ────────────────────────────────────────────────────────────────────────────

SERVICE_PREFIX="dotfiles-"

# Log directory for backends that need explicit stdout/stderr redirection.
_service_log_dir() { printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/services"; }

# ── Linux / systemd (user scope) ────────────────────────────────────────────
_systemd_user_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; }

# Per-user runtime dir that holds the user bus socket (systemctl --user needs it).
_systemd_runtime_dir() { printf '%s\n' "/run/user/$(id -u)"; }

# A headless / non-login shell (SSH, cloud-init, chezmoi apply) often has no
# XDG_RUNTIME_DIR, so `systemctl --user` can't find the bus even when the user
# manager is running. Point it at the standard location when it exists.
_systemd_export_runtime_dir() {
    [[ -n "${XDG_RUNTIME_DIR:-}" ]] && return 0
    local rt; rt="$(_systemd_runtime_dir)"
    [[ -d "$rt" ]] && export XDG_RUNTIME_DIR="$rt"
    return 0
}

# systemd is the SYSTEM init here (PID 1). True even when no *user* manager is
# running yet — that case we can bootstrap via linger. False in containers / a
# WSL distro without systemd, where there is nothing to drive.
_systemd_is_init() {
    has_command systemctl && [[ -d /run/systemd/system ]]
}

# The per-user systemd manager is reachable RIGHT NOW.
_has_systemd_user() {
    has_command systemctl || return 1
    _systemd_export_runtime_dir
    systemctl --user show-environment >/dev/null 2>&1
}

# Let this user's services run at boot without an active login. Enabling linger
# also starts user@UID.service immediately, creating /run/user/UID and its bus —
# which is exactly what a headless server (no interactive session) needs.
# A user can usually enable their own linger; fall back to privilege if not.
_systemd_enable_linger() {
    has_command loginctl || return 1
    loginctl enable-linger "$(id -un)" >/dev/null 2>&1 && return 0
    run_privileged loginctl enable-linger "$(id -un)" >/dev/null 2>&1
}

# Ensure `systemctl --user` works, bootstrapping the user manager via linger if
# it isn't up yet. Returns 0 once the user bus is reachable, 1 if it can't be.
_systemd_ensure_user_manager() {
    _has_systemd_user && return 0
    _systemd_is_init  || return 1

    log_info "no active systemd user session — enabling linger to start it headlessly..."
    _systemd_enable_linger || {
        log_error "could not enable linger for $(id -un) (loginctl missing or no privilege)."
        return 1
    }

    # user@UID.service starts asynchronously; wait briefly for its bus to appear.
    local i
    for i in {1..20}; do
        _has_systemd_user && return 0
        sleep 0.5
    done
    return 1
}

_systemd_register() {
    local name="$1" desc="$2"; shift 2
    local unit_dir unit_file exec_start
    _systemd_export_runtime_dir
    unit_dir="$(_systemd_user_dir)"
    unit_file="${unit_dir}/${SERVICE_PREFIX}${name}.service"
    mkdir -p "$unit_dir"

    # systemd ExecStart wants a single command line; our args are paths/simple
    # tokens (no embedded spaces), so a plain join is safe and readable.
    exec_start="$*"

    cat >"$unit_file" <<EOF
[Unit]
Description=${desc}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# No services-specific env file: the unit inherits the STANDARD systemd user
# environment. To make the Infisical machine identity available headlessly at
# boot, put it in ~/.config/environment.d/*.conf like any other env var — the
# user manager reads that automatically. Absent is fine; most tools persist
# their own credentials after the first authenticated run.
ExecStart=${exec_start}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload >/dev/null 2>&1 || true
    log_success "registered systemd user unit: ${SERVICE_PREFIX}${name}.service"
}

_systemd_enable()  {
    _systemd_ensure_user_manager || {
        log_error "systemd user manager is unreachable and could not be started headlessly."
        return 1
    }
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable --now "${SERVICE_PREFIX}$1.service"
}
_systemd_disable() {
    _systemd_export_runtime_dir
    systemctl --user disable --now "${SERVICE_PREFIX}$1.service" >/dev/null 2>&1 || true
    rm -f "$(_systemd_user_dir)/${SERVICE_PREFIX}$1.service"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
}
_systemd_status()  { _systemd_export_runtime_dir; systemctl --user --no-pager status "${SERVICE_PREFIX}$1.service"; }
_systemd_list()    { _systemd_export_runtime_dir; systemctl --user list-unit-files "${SERVICE_PREFIX}*.service" --no-pager 2>/dev/null || true; }

# ── macOS / launchd (LaunchAgent) ───────────────────────────────────────────
_launchd_dir() { printf '%s\n' "$HOME/Library/LaunchAgents"; }

_launchd_register() {
    local name="$1" desc="$2"; shift 2
    local label plist log_dir plist_dir
    label="${SERVICE_PREFIX}${name}"
    plist_dir="$(_launchd_dir)"
    plist="${plist_dir}/${label}.plist"
    log_dir="$(_service_log_dir)"
    mkdir -p "$plist_dir" "$log_dir"

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0">'
        echo '<dict>'
        echo "  <key>Label</key><string>${label}</string>"
        echo "  <!-- ${desc} -->"
        echo '  <key>ProgramArguments</key>'
        echo '  <array>'
        local arg
        for arg in "$@"; do
            printf '    <string>%s</string>\n' "$arg"
        done
        echo '  </array>'
        echo '  <key>RunAtLoad</key><true/>'
        echo '  <key>KeepAlive</key><true/>'
        echo "  <key>StandardOutPath</key><string>${log_dir}/${name}.log</string>"
        echo "  <key>StandardErrorPath</key><string>${log_dir}/${name}.log</string>"
        echo '</dict>'
        echo '</plist>'
    } >"$plist"

    log_success "registered launchd agent: ${label}.plist"
}

_launchd_enable() {
    local plist; plist="$(_launchd_dir)/${SERVICE_PREFIX}$1.plist"
    launchctl unload -w "$plist" >/dev/null 2>&1 || true
    launchctl load -w "$plist"
}
_launchd_disable() {
    local plist; plist="$(_launchd_dir)/${SERVICE_PREFIX}$1.plist"
    launchctl unload -w "$plist" >/dev/null 2>&1 || true
    rm -f "$plist"
}
_launchd_status() {
    launchctl list | grep "${SERVICE_PREFIX}$1" || log_info "${SERVICE_PREFIX}$1 is not loaded."
}
_launchd_list() { ls -1 "$(_launchd_dir)" 2>/dev/null | grep "^${SERVICE_PREFIX}" || true; }

# ── Windows / Task Scheduler (best-effort logon task) ───────────────────────
_schtasks_name() { printf '%s\n' "dotfiles\\$1"; }

_win_register() {
    local name="$1" desc="$2"; shift 2
    has_command schtasks || { log_error "schtasks unavailable; cannot register '${name}' on Windows."; return 1; }
    # Run the command through bash at logon. Paths coming from a POSIX shell may
    # need translation for cmd; this is a best-effort convenience on Windows.
    local cmd="$*"
    schtasks /Create /TN "$(_schtasks_name "$name")" \
        /TR "bash -lc \"${cmd}\"" /SC ONLOGON /RL LIMITED /F >/dev/null
    log_success "registered scheduled task: $(_schtasks_name "$name") (${desc})"
}
_win_enable()  { schtasks /Run  /TN "$(_schtasks_name "$1")" >/dev/null 2>&1 || true; }
_win_disable() { schtasks /Delete /TN "$(_schtasks_name "$1")" /F  >/dev/null 2>&1 || true; }
_win_status()  { schtasks /Query /TN "$(_schtasks_name "$1")" 2>/dev/null || log_info "task not found."; }
_win_list()    { schtasks /Query /FO LIST 2>/dev/null | grep -i 'dotfiles\\\\' || true; }

# ── Public dispatch ──────────────────────────────────────────────────────────
service_supported() {
    # Linux: drivable if the user bus is already up OR systemd is the init and we
    # can bootstrap a user manager via linger. A cold headless boot has no active
    # user session yet, so gating on the live bus alone would wrongly refuse.
    if os_is_linux;   then _has_systemd_user || _systemd_is_init; return $?; fi
    if os_is_macos;   then has_command launchctl; return $?; fi
    if os_is_windows; then has_command schtasks;  return $?; fi
    return 1
}

# Print a human-friendly reason when the init system can't be driven here.
service_unsupported_reason() {
    if os_is_linux; then
        if ! has_command systemctl; then
            echo "systemctl not found (no systemd)"
        else
            echo "systemd is not the init system here (containers / WSL without systemd don't have one)"
        fi
    elif os_is_macos; then
        echo "launchctl not found"
    elif os_is_windows; then
        echo "schtasks not found"
    else
        echo "unsupported OS family '${OS_FAMILY}'"
    fi
}

service_register() {
    local name="$1" desc="$2"; shift 2
    if os_is_linux;   then _systemd_register "$name" "$desc" "$@"; return $?; fi
    if os_is_macos;   then _launchd_register "$name" "$desc" "$@"; return $?; fi
    if os_is_windows; then _win_register     "$name" "$desc" "$@"; return $?; fi
    log_error "unsupported OS family '${OS_FAMILY}'."; return 1
}

service_enable() {
    if os_is_linux;   then _systemd_enable "$1"; return $?; fi
    if os_is_macos;   then _launchd_enable "$1"; return $?; fi
    if os_is_windows; then _win_enable     "$1"; return $?; fi
    return 1
}

service_disable() {
    if os_is_linux;   then _systemd_disable "$1"; return $?; fi
    if os_is_macos;   then _launchd_disable "$1"; return $?; fi
    if os_is_windows; then _win_disable     "$1"; return $?; fi
    return 1
}

service_status() {
    if os_is_linux;   then _systemd_status "$1"; return $?; fi
    if os_is_macos;   then _launchd_status "$1"; return $?; fi
    if os_is_windows; then _win_status     "$1"; return $?; fi
    return 1
}

service_list() {
    if os_is_linux;   then _systemd_list; return $?; fi
    if os_is_macos;   then _launchd_list; return $?; fi
    if os_is_windows; then _win_list;     return $?; fi
    return 1
}
