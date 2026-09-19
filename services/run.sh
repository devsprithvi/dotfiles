#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Generic Service Runner ──────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# ONE runner for every runtime action. It does three things, then hands the
# process to the tool in the FOREGROUND (so an init supervisor can own it):
#
#   1. HYDRATE secrets — pull named secrets from the secret manager (Infisical)
#      and export them as environment variables, but ONLY if they aren't already
#      set. Nothing is written to disk; values live in this process's env and
#      vanish when it exits. The tool then just reads them from the env.
#   2. AUTHENTICATE — run the preset's optional prepare/login step.
#   3. EXEC — replace this process with the target command.
#
# Two ways to call it:
#
#   run.sh <tool:sub> [args...]                       use a preset (services/presets.sh)
#   run.sh --secret VAR@PATH [--secret ...] -- CMD..  run a raw command, hydrating
#                                                      the secrets you name first
#
# Secret spec:  VAR@PATH        (environment defaults to "global")
#               VAR@ENV@PATH    (explicit Infisical environment)
#
# Secrets at boot: the tool's own persisted credentials usually suffice (VS Code
# file keychain, tailscaled). If a service must fetch secrets at boot, only the
# Infisical machine identity (INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET)
# needs to reach the unit. It is a STANDARD env var, not a services concept —
# provide it the standard way via ~/.config/environment.d/*.conf (the systemd
# user manager reads it automatically); everything else is fetched fresh here.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
source "${SCRIPT_DIR}/presets.sh"
log_set_component "run"

# Secret hydration (parsing, mapping, provider dispatch) lives in the secrets/
# subsystem. Here we just call secret_hydrate on each declared spec.
# Spec grammar: VAR[=LOCATOR], where LOCATOR is provider-specific (see
# secrets/core.sh and secrets/providers/<id>.sh for details).

_usage() {
    cat <<'EOF'
Usage:
  services/run.sh <tool:sub> [args...]                 run a preset
  services/run.sh --secret VAR[=LOCATOR] [...] -- CMD...   raw command

Presets:
EOF
    preset_list | sed 's/^/  /'
}

# ── Raw command mode ─────────────────────────────────────────────────────────
if [[ "${1:-}" == "--secret" || "${1:-}" == "--exec" || "${1:-}" == "--" ]]; then
    secrets=()
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --secret) secrets+=("$2"); shift 2 ;;
            --exec)   shift ;;
            --)       shift; break ;;
            *)        log_fatal "Unexpected argument in raw mode: $1" ;;
        esac
    done
    [[ "$#" -eq 0 ]] && { log_fatal "No command given after --."; }
    for s in "${secrets[@]}"; do secret_hydrate "$s"; done
    log_info "raw exec: $*"
    exec "$@"
fi

# ── Preset mode ──────────────────────────────────────────────────────────────
spec="${1:-}"
case "$spec" in
    ""|-h|--help|help) _usage; [[ "$spec" == "" ]] && exit 1 || exit 0 ;;
esac
shift || true

if ! preset_exists "$spec"; then
    log_error "Unknown preset: ${spec}"
    _usage >&2
    exit 1
fi

# 1. Hydrate declared secrets (static list — safe before load). Report clearly
#    when a declared secret could not be resolved, and why, so failures are
#    diagnosable instead of surfacing later as a confusing tool error. Mapping
#    (DOTFILES_SECRET_MAP) is applied inside secret_hydrate/secret_resolve_spec.
while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    secret_hydrate "$s"
    # Resolve the effective source (after any map override) for accurate reporting.
    secret_resolve_spec "$s" || continue
    if [[ -z "${!SECRET_VAR:-}" ]]; then
        if ! secret_provider_available; then
            log_warn "secret '${SECRET_VAR}' is unset and provider '${SECRET_PROVIDER}' is not configured — cannot fetch it."
        else
            log_warn "secret '${SECRET_VAR}' is unset and was not found ($(secret_describe "$SECRET_VAR" "$SECRET_LOCATOR"))."
        fi
    fi
done < <(preset_secret_specs "$spec" || true)

# 2. Build the command + auth hook now that the env is populated.
load_preset "$spec" "$@"

# 3. Prepare / authenticate (may exit 0 for a no-op, or fail to abort).
preset_authenticate || { log_fatal "Aborting '${spec}'."; }

# 4. Hand off to the tool in the foreground.
[[ "${#PRESET_CMD[@]}" -gt 0 ]] || { log_fatal "Preset '${spec}' produced no command."; }
log_info "${PRESET_DESC:-$spec} starting (Ctrl-C to stop): ${PRESET_CMD[*]}"
exec "${PRESET_CMD[@]}"
