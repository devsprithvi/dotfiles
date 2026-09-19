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
# Each service lists only the ENV VAR NAMES it needs — no keys, no paths, no
# provider dialect. Services are provider-unaware. WHERE each var comes from
# lives in the active provider's secret map (e.g. secrets/providers/infisical.sh),
# and can still be repointed at runtime via DOTFILES_SECRET_MAP.
preset_secret_specs() {
    case "$1" in
        vscode:tunnel)  printf '%s\n' "GITHUB_PAT" ;;
        vscode:web)     : ;;  # token is optional; no mandatory secret
        devtunnel:host) printf '%s\n' "DEVTUNNEL_TOKEN" "GITHUB_PAT" ;;
        tailscale:up)   printf '%s\n' "TAILSCALE_AUTHKEY" ;;
        *)              return 1 ;;
    esac
}

# ── Helper: verify a GitHub PAT before we ever touch the tunnel service ─────
# Proves the token is actually accepted by GitHub (and reports WHO it belongs to
# and WHICH scopes it carries) BEFORE we attempt any tunnel login. This turns a
# late, cryptic "401 from the tunnel API" into an early, precise message.
#
# Contract:
#   in : $1 = the token value (NEVER logged or echoed)
#   out: on success prints the authenticated GitHub login to stdout, returns 0
#        on failure logs the specific reason to the log (stderr+file), returns 1
# The token is passed as an argument and used only in an Authorization header;
# it is never written to stdout, the log, or the process table beyond this call.
_vscode_tunnel_verify_github_pat() {
    local token="$1"

    # No curl → we cannot pre-verify. Don't block the flow: warn and soft-pass so
    # the subsequent real login still gets its chance (and logs its own errors).
    if ! has_command curl; then
        log_warn "curl not found — skipping GitHub PAT pre-flight check."
        printf 'unknown'
        return 0
    fi

    local tmp_body tmp_hdr http
    tmp_body="$(mktemp 2>/dev/null)" || tmp_body=""
    tmp_hdr="$(mktemp 2>/dev/null)"  || tmp_hdr=""

    # -s/-S: quiet but still report hard errors; -o body, -D headers, -w status.
    http="$(curl -sS --max-time 15 \
        -o "${tmp_body:-/dev/null}" -D "${tmp_hdr:-/dev/null}" -w '%{http_code}' \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/user" 2>/dev/null)" || http="000"

    case "$http" in
        200)
            local login="" scopes=""
            if [[ -n "$tmp_body" && -f "$tmp_body" ]]; then
                login="$(sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp_body" | head -n1)"
            fi
            if [[ -n "$tmp_hdr" && -f "$tmp_hdr" ]]; then
                # Classic PATs report their grants here; fine-grained PATs won't.
                scopes="$(sed -n 's/^[Xx]-[Oo][Aa]uth-[Ss]copes:[[:space:]]*//p' "$tmp_hdr" | tr -d '\r' | head -n1)"
            fi
            [[ -n "$scopes" ]] && log_debug "GitHub PAT scopes: ${scopes}"
            rm -f "$tmp_body" "$tmp_hdr" 2>/dev/null || true
            printf '%s' "${login:-unknown}"
            return 0
            ;;
        401)
            log_error "GitHub rejected the PAT (HTTP 401) — the token is invalid, revoked, or malformed."
            ;;
        403)
            log_error "GitHub returned HTTP 403 for the PAT — forbidden or rate-limited (check SSO authorization)."
            ;;
        000)
            log_error "Could not reach api.github.com to verify the PAT (network, DNS, or timeout)."
            ;;
        *)
            log_error "Unexpected HTTP ${http} from api.github.com while verifying the PAT."
            ;;
    esac
    rm -f "$tmp_body" "$tmp_hdr" 2>/dev/null || true
    return 1
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

                # ── Path A: a GitHub PAT is available → verify it, then log in. ──
                # We deliberately do NOT trust an existing cached credential here.
                # A cached-but-expired token makes `tunnel user show` succeed while
                # the tunnel API still answers 401 — the exact crash loop we hit.
                # So when we have a PAT, we prove it, drop any stale cred, and mint
                # a fresh session.
                if [[ -n "${GITHUB_PAT:-}" ]]; then
                    # 1) Pre-flight: prove the PAT works against GitHub itself
                    #    BEFORE touching the tunnel service. The token is never logged.
                    log_info "Verifying GitHub PAT before connecting to the tunnel service..."
                    local login
                    if login="$(_vscode_tunnel_verify_github_pat "${GITHUB_PAT}")"; then
                        log_success "GitHub PAT verified (authenticated as '${login}')."
                    else
                        log_error "GitHub PAT pre-flight check failed — aborting before tunnel login."
                        log_error "Confirm ADMIN_PAT (/github in Infisical) is valid and reachable."
                        return 1
                    fi

                    # 2) Drop any stale/expired cached tunnel credential so it can't
                    #    shadow the fresh login below.
                    if "$code" tunnel user show >/dev/null 2>&1; then
                        log_info "Existing tunnel credential found — refreshing it with the verified PAT."
                        "$code" tunnel user logout >/dev/null 2>&1 || true
                    fi

                    # 3) Fresh login with the verified PAT.
                    log_info "Logging in to the VS Code tunnel (provider: github)..."
                    local out
                    if ! out="$("$code" tunnel user login --provider github --access-token "${GITHUB_PAT}" 2>&1)"; then
                        log_error "VS Code tunnel login failed. VS Code CLI said:"
                        while IFS= read -r _l; do [[ -n "$_l" ]] && log_error "  ${_l}"; done <<<"${out}"
                        return 1
                    fi

                    # 4) Confirm the session is genuinely valid now.
                    if "$code" tunnel user show >/dev/null 2>&1; then
                        log_success "VS Code tunnel credential confirmed — starting tunnel."
                        return 0
                    fi
                    log_error "Tunnel login reported success but 'tunnel user show' still fails."
                    return 1
                fi

                # ── Path B: no PAT, but a cached credential exists → reuse it. ──
                if "$code" tunnel user show >/dev/null 2>&1; then
                    log_info "No GITHUB_PAT set — using the existing cached tunnel credential."
                    return 0
                fi

                # ── Path C: no PAT and no cached credential. ──
                # Device login is interactive — only viable with a terminal.
                # Headless (systemd/boot) would hang forever, so fail loudly instead.
                if [[ -t 0 && -t 1 ]]; then
                    log_warn "No GITHUB_PAT and no cached credential — falling back to interactive device login."
                    return 0
                fi
                log_error "No GITHUB_PAT, no cached credential, and no terminal for device login (headless)."
                log_error "Set GITHUB_PAT (env) or map it via DOTFILES_SECRET_MAP, then retry."
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

                local token="${DEVTUNNEL_TOKEN:-${GITHUB_PAT:-}}"
                if [[ -z "$token" ]]; then
                    log_error "no DEVTUNNEL_TOKEN or GITHUB_PAT available to authenticate devtunnel."
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
