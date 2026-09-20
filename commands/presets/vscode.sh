#!/usr/bin/env bash

# ────────────────────────────────────────────────────────────────────────────
# ── Preset: VS Code CLI ─────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# One self-contained file for the `vscode:*` commands. It defines only how to
# RUN them; it does NOT log anybody in.
#
# Authentication is deliberately NOT here. The VS Code tunnel credential can
# only be created by an interactive OAuth login, and the VS Code CLI already has
# its own command for that (`code tunnel user login`) which authenticates
# WITHOUT starting a tunnel and persists the credential itself across reboots.
# So logging in is a one-time MANUAL step you run yourself; this preset just
# starts the tunnel and, if you haven't logged in yet, prints the exact command
# to run and stops. (GitHub PATs don't work for the tunnel: they appear to
# succeed but the tunnel API returns 401 — microsoft/vscode#310726.)
# ────────────────────────────────────────────────────────────────────────────

_PRESET_TOOLS+=(vscode)

# One line per sub-command for the catalog listing.
_preset_vscode_list() {
    cat <<'EOF'
vscode:tunnel   [name]                  VS Code remote tunnel (vscode.dev/tunnel/<name>)
vscode:web      [host] [port] [token]   VS Code web server (serve-web)
EOF
}

# Secrets to hydrate before running (none: the tunnel logs in manually, the web
# token is optional). Unknown subcommands return non-zero so existence checks fail.
_preset_vscode_secret_specs() {
    case "$1" in
        tunnel) : ;;
        web)    : ;;
        *)      return 1 ;;
    esac
}

# Build PRESET_CMD (+ an optional non-interactive preset_authenticate) for a sub.
_preset_vscode_load() {
    local sub="$1"; shift || true
    local code="$HOME/.local/bin/code"

    case "$sub" in
        tunnel)
            local name="${1:-${VSCODE_TUNNEL_NAME:-$(hostname 2>/dev/null || echo dev)}}"
            PRESET_DESC="VS Code tunnel"
            # Runs on every start (foreground or autostart) and MUST be
            # non-interactive: it only checks whether you are already logged in.
            preset_authenticate() {
                local code="$HOME/.local/bin/code"
                [[ -x "$code" ]] || { log_error "VS Code CLI not found — ENABLE_VSCODE_CLI=1 bash packages/vscode_cli.sh"; return 1; }

                # Already logged in? The CLI stored the credential; just run.
                "$code" tunnel user show >/dev/null 2>&1 && return 0

                # Not logged in. Authentication is manual and separate — we do not
                # automate it. Print the exact command and stop cleanly (exit 0 so
                # a systemd unit does not restart-loop).
                log_warn "Not logged in to the VS Code tunnel — authenticate manually first, then start it again:"
                log_warn "    ${code} tunnel user login --provider github"
                log_warn "The VS Code CLI stores that login itself and reuses it on every boot."
                exit 0
            }
            PRESET_CMD=( "$code" tunnel --accept-server-license-terms --name "$name" )
            ;;

        web)
            local host="${1:-${VSCODE_WEB_HOST:-0.0.0.0}}"
            local port="${2:-${VSCODE_WEB_PORT:-8000}}"
            local token="${3:-${VSCODE_WEB_TOKEN:-}}"
            PRESET_DESC="VS Code web server"
            preset_authenticate() {
                local code="$HOME/.local/bin/code"
                [[ -x "$code" ]] || { log_error "VS Code CLI not found — ENABLE_VSCODE_CLI=1 bash packages/vscode_cli.sh"; return 1; }
            }
            PRESET_CMD=( "$code" serve-web --accept-server-license-terms --host "$host" --port "$port" )
            if [[ -n "$token" ]]; then
                PRESET_CMD+=( --connection-token "$token" )
            else
                PRESET_CMD+=( --without-connection-token )
                log_warn "VS Code web has NO auth token — bind to localhost or a tunnel/VPN on shared networks."
            fi
            ;;

        *)
            log_error "Unknown preset: vscode:${sub}"
            return 1
            ;;
    esac
}
