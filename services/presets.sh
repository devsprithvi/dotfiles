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
                # Recompute the path: this function is called from run.sh AFTER
                # load_preset returns, so load_preset's `local` vars are gone.
                local code="$HOME/.local/bin/code"
                [[ -x "$code" ]] || { log_error "VS Code CLI not found — ENABLE_VSCODE_CLI=1 bash packages/vscode_cli.sh"; return 1; }
                # Persist creds to a file so headless auth survives boot/restart.
                export VSCODE_CLI_USE_FILE_KEYCHAIN="${VSCODE_CLI_USE_FILE_KEYCHAIN:-1}"

                # Already logged in (cached keychain from a prior run)? Nothing to do.
                "$code" tunnel user show >/dev/null 2>&1 && return 0

                if [[ -n "${GITHUB_VSCODE_PAT:-}" ]]; then
                    log_info "Authenticating VS Code tunnel with GitHub token..."
                    local out
                    if out="$("$code" tunnel user login --provider github --access-token "$GITHUB_VSCODE_PAT" 2>&1)"; then
                        return 0
                    fi
                    # Surface the real reason (expired/invalid PAT, missing scope, etc.).
                    log_error "GitHub token login failed. VS Code CLI said:"
                    while IFS= read -r _l; do log_error "  ${_l}"; done <<<"${out}"
                    log_error "Check that GITHUB_VSCODE_PAT is valid and has the required scope."
                    return 1
                fi

                # No PAT. Device login is interactive — only viable with a terminal.
                # Headless (systemd/boot) would hang forever, so fail loudly instead.
                if [[ -t 0 && -t 1 ]]; then
                    log_warn "No GITHUB_VSCODE_PAT available; falling back to interactive device login."
                    return 0
                fi
                log_error "no GITHUB_VSCODE_PAT and no terminal for device login (headless)."
                log_error "Set GITHUB_VSCODE_PAT (env) or store it in Infisical at /github, then retry."
                return 1
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

        devtunnel:host)
            local devtunnel="$HOME/.local/bin/devtunnel"
            has_command devtunnel && devtunnel="devtunnel"
            PRESET_DESC="Microsoft Dev Tunnel host"
            preset_authenticate() {
                local devtunnel="$HOME/.local/bin/devtunnel"
                has_command devtunnel && devtunnel="devtunnel"
                if [[ "$devtunnel" != "devtunnel" && ! -x "$devtunnel" ]]; then
                    log_error "devtunnel not found — ENABLE_DEVTUNNEL=1 bash packages/devtunnel.sh"; return 1
                fi
                # Already authenticated from a prior run? Reuse it.
                "$devtunnel" user show >/dev/null 2>&1 && return 0

                local token="${DEVTUNNEL_TOKEN:-${GITHUB_VSCODE_PAT:-}}"
                if [[ -z "$token" ]]; then
                    log_error "no DEVTUNNEL_TOKEN or GITHUB_VSCODE_PAT available to authenticate devtunnel."
                    log_error "Set one (env) or store it in Infisical at /tunnels or /github, then retry."
                    return 1
                fi
                log_info "Authenticating devtunnel with access token..."
                local out
                if out="$("$devtunnel" user login -d --access-token "$token" 2>&1)"; then
                    return 0
                fi
                log_error "devtunnel token login failed. It said:"
                while IFS= read -r _l; do log_error "  ${_l}"; done <<<"${out}"
                return 1
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
                has_command tailscale || { log_error "tailscale not found — ENABLE_TAILSCALE=1 bash packages/tailscale.sh"; return 1; }
                if tailscale status >/dev/null 2>&1; then
                    log_info "tailscale already connected."
                    exit 0
                fi
                if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
                    log_error "no TAILSCALE_AUTHKEY available (env or Infisical /tailscale)."
                    log_error "Set it, or run 'sudo tailscale up' manually to authenticate interactively."
                    return 1
                fi
                # 'tailscale up' needs root; we exec 'sudo -n' which fails cryptically
                # without passwordless sudo. Check now and explain clearly.
                if ! can_run_privileged; then
                    log_error "'tailscale up' needs root but no passwordless sudo is available."
                    log_error "Run it as root, or configure sudo, then retry."
                    return 1
                fi
            }
            # Prefix privilege escalation into the argv (exec can't call a function).
            local pre=()
            if ! is_root; then
                has_command sudo && pre=( sudo -n )
            fi
            PRESET_CMD=( "${pre[@]}" tailscale up --authkey "${TAILSCALE_AUTHKEY:-}" )
            ;;

        *)
            log_error "Unknown preset: ${spec}"
            return 1
            ;;
    esac
}
