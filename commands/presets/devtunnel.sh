#!/usr/bin/env bash

# ────────────────────────────────────────────────────────────────────────────
# ── Preset: Microsoft Dev Tunnels (devtunnel) ───────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Self-contained `devtunnel:*` service. Unlike the VS Code tunnel, devtunnel
# CAN authenticate non-interactively with an access token (DEVTUNNEL_TOKEN, or a
# GitHub PAT), so its auth step is safe to automate here.
# ────────────────────────────────────────────────────────────────────────────

_PRESET_TOOLS+=(devtunnel)

_preset_devtunnel_list() {
    cat <<'EOF'
devtunnel:host  [port ...]              Microsoft Dev Tunnel host
EOF
}

_preset_devtunnel_secret_specs() {
    case "$1" in
        host) printf '%s\n' "DEVTUNNEL_TOKEN" "GITHUB_PAT" ;;
        *)    return 1 ;;
    esac
}

_preset_devtunnel_load() {
    local sub="$1"; shift || true

    case "$sub" in
        host)
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

        *)
            log_error "Unknown preset: devtunnel:${sub}"
            return 1
            ;;
    esac
}
