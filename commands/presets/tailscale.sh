#!/usr/bin/env bash

# ────────────────────────────────────────────────────────────────────────────
# ── Preset: Tailscale ───────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Self-contained `tailscale:*` service. Connects this machine to the tailnet
# with a pre-shared auth key (non-interactive). `tailscale up` needs root, so
# we prefix privilege escalation into the command.
# ────────────────────────────────────────────────────────────────────────────

_PRESET_TOOLS+=(tailscale)

_preset_tailscale_list() {
    cat <<'EOF'
tailscale:up                            connect this machine to the tailnet
EOF
}

_preset_tailscale_secret_specs() {
    case "$1" in
        up) printf '%s\n' "TAILSCALE_AUTHKEY" ;;
        *)  return 1 ;;
    esac
}

_preset_tailscale_load() {
    local sub="$1"; shift || true

    case "$sub" in
        up)
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
            log_error "Unknown preset: tailscale:${sub}"
            return 1
            ;;
    esac
}
