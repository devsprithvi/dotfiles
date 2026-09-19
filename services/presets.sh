#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_PRESETS_LIB_LOADED:-}" ]] && return 0
_PRESETS_LIB_LOADED=1

# ────────────────────────────────────────────────────────────────────────────
# ── Service Presets — the "convenience layer" as data, not scripts ──────────
# ────────────────────────────────────────────────────────────────────────────
# There is ONE generic runner (services/run.sh) that hydrates secrets, performs
# any auth step, then execs a command. It can run a raw command directly — but
# raw commands don't know WHICH secret to fetch, HOW to log in, or the little
# per-tool quirks. That knowledge lives here as a small declarative map keyed by
# "tool:sub", instead of one hand-written script per tool.
#
# Each preset is described by two hooks the runner calls in order:
#
#   preset_secret_specs <spec>          → prints the secrets to hydrate, one per
#                                          line as "VAR@PATH" or "VAR@ENV@PATH".
#                                          Purely static (no values needed yet).
#
#   load_preset <spec> [args...]        → runs AFTER secrets are in the env and
#                                          populates, for the runner:
#                                            PRESET_DESC   human description
#                                            PRESET_CMD[]  the foreground argv
#                                          and (re)defines preset_authenticate,
#                                          a prepare/login step run before exec
#                                          (return non-zero to abort; it may also
#                                          `exit 0` for a no-op like "already up").
#
# Adding a tool = adding a case here. No new file, no new dispatcher wiring.
# ────────────────────────────────────────────────────────────────────────────

# Available preset specs (also used by `services/index.sh list`).
preset_list() {
    cat <<'EOF'
vscode:tunnel   [name]                  VS Code remote tunnel (vscode.dev/tunnel/<name>)
vscode:web      [host] [port] [token]   VS Code web server (serve-web)
devtunnel:host  [port ...]              Microsoft Dev Tunnel host
tailscale:up                            connect this machine to the tailnet
EOF
}

preset_exists() { preset_secret_specs "$1" >/dev/null 2>&1 && [[ "$(_preset_known "$1")" == yes ]]; }

_preset_known() {
    case "$1" in
        vscode:tunnel|vscode:web|devtunnel:host|tailscale:up) printf 'yes\n' ;;
        *) printf 'no\n' ;;
    esac
}

# ── Static secret declarations (safe to call before hydration) ──────────────
preset_secret_specs() {
    case "$1" in
        vscode:tunnel)  printf '%s\n' "GITHUB_VSCODE_PAT@/github" ;;
        vscode:web)     : ;;  # token is optional; no mandatory secret
        devtunnel:host) printf '%s\n' "DEVTUNNEL_TOKEN@/tunnels" "GITHUB_VSCODE_PAT@/github" ;;
        tailscale:up)   printf '%s\n' "TAILSCALE_AUTHKEY@/tailscale" ;;
        *)              return 1 ;;
    esac
}

# ── Preset loader: build PRESET_CMD + auth using the (now hydrated) env ─────
load_preset() {
    local spec="$1"; shift || true

    PRESET_DESC=""
    PRESET_CMD=()
    # Default prepare/auth step is a no-op; presets override as needed.
    preset_authenticate() { :; }

    case "$spec" in
        vscode:tunnel)
            local code="$HOME/.local/bin/code"
            local name="${1:-${VSCODE_TUNNEL_NAME:-$(hostname 2>/dev/null || echo dev)}}"
            PRESET_DESC="VS Code tunnel"
            preset_authenticate() {
                [[ -x "$code" ]] || { echo "[run] VS Code CLI not found — ENABLE_VSCODE_CLI=1 bash packages/vscode_cli.sh" >&2; return 1; }
                # Persist creds to a file so headless auth survives boot/restart.
                export VSCODE_CLI_USE_FILE_KEYCHAIN="${VSCODE_CLI_USE_FILE_KEYCHAIN:-1}"
                if ! "$code" tunnel user show >/dev/null 2>&1; then
                    if [[ -n "${GITHUB_VSCODE_PAT:-}" ]]; then
                        echo "[run] Authenticating VS Code tunnel with GitHub token..."
                        "$code" tunnel user login --provider github --access-token "$GITHUB_VSCODE_PAT" >/dev/null 2>&1 || \
                            echo "[run] WARNING: token login did not complete; may prompt for device login." >&2
                    else
                        echo "[run] No PAT available; you may be prompted for device login."
                    fi
                fi
            }
            PRESET_CMD=( "$code" tunnel --accept-server-license-terms --name "$name" )
            ;;

        vscode:web)
            local code="$HOME/.local/bin/code"
            local host="${1:-${VSCODE_WEB_HOST:-0.0.0.0}}"
            local port="${2:-${VSCODE_WEB_PORT:-8000}}"
            local token="${3:-${VSCODE_WEB_TOKEN:-}}"
            PRESET_DESC="VS Code web server"
            preset_authenticate() {
                [[ -x "$code" ]] || { echo "[run] VS Code CLI not found — ENABLE_VSCODE_CLI=1 bash packages/vscode_cli.sh" >&2; return 1; }
            }
            PRESET_CMD=( "$code" serve-web --accept-server-license-terms --host "$host" --port "$port" )
            if [[ -n "$token" ]]; then
                PRESET_CMD+=( --connection-token "$token" )
            else
                PRESET_CMD+=( --without-connection-token )
                echo "[run] VS Code web has NO auth token — bind to localhost or a tunnel/VPN on shared networks." >&2
            fi
            ;;

        devtunnel:host)
            local devtunnel="$HOME/.local/bin/devtunnel"
            has_command devtunnel && devtunnel="devtunnel"
            PRESET_DESC="Microsoft Dev Tunnel host"
            preset_authenticate() {
                if [[ "$devtunnel" != "devtunnel" && ! -x "$devtunnel" ]]; then
                    echo "[run] devtunnel not found — ENABLE_DEVTUNNEL=1 bash packages/devtunnel.sh" >&2; return 1
                fi
                local token="${DEVTUNNEL_TOKEN:-${GITHUB_VSCODE_PAT:-}}"
                if [[ -n "$token" ]]; then
                    echo "[run] Authenticating devtunnel with access token..."
                    "$devtunnel" user login -d --access-token "$token" >/dev/null 2>&1 || \
                        echo "[run] WARNING: token login did not complete; run 'devtunnel user login' if needed." >&2
                else
                    echo "[run] No token available; run 'devtunnel user login' if hosting fails."
                fi
            }
            PRESET_CMD=( "$devtunnel" host )
            if [[ "$#" -eq 0 ]]; then
                PRESET_CMD+=( -p 8000 )
            else
                local port
                for port in "$@"; do PRESET_CMD+=( -p "$port" ); done
            fi
            ;;

        tailscale:up)
            PRESET_DESC="Tailscale up"
            preset_authenticate() {
                has_command tailscale || { echo "[run] tailscale not found — ENABLE_TAILSCALE=1 bash packages/tailscale.sh" >&2; return 1; }
                if tailscale status >/dev/null 2>&1; then
                    echo "[run] tailscale already connected."
                    exit 0
                fi
                [[ -n "${TAILSCALE_AUTHKEY:-}" ]] || { echo "[run] No auth key; run 'sudo tailscale up' manually." >&2; return 1; }
            }
            # Prefix privilege escalation into the argv (exec can't call a function).
            local pre=()
            if ! is_root; then
                has_command sudo && pre=( sudo -n )
            fi
            PRESET_CMD=( "${pre[@]}" tailscale up --authkey "${TAILSCALE_AUTHKEY:-}" )
            ;;

        *)
            echo "[run] Unknown preset: ${spec}" >&2
            return 1
            ;;
    esac
}
