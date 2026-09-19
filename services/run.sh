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

# Fetch one "VAR@PATH" / "VAR@ENV@PATH" secret into the env if not already set.
hydrate_secret() {
    local spec="$1" var env path a b c
    IFS='@' read -r a b c <<<"$spec"
    if [[ -n "$c" ]]; then var="$a"; env="$b"; path="$c"; else var="$a"; env="global"; path="$b"; fi
    [[ -z "$var" ]] && return 0

    # Respect a value the caller already exported (e.g. secret-manager-populated).
    [[ -n "${!var:-}" ]] && return 0

    local val
    val="$(fetch_infisical_secret "$var" "$env" "$path" 2>/dev/null || true)"
    [[ -n "$val" ]] && export "${var}=${val}"
    return 0
}

_usage() {
    cat <<'EOF'
Usage:
  services/run.sh <tool:sub> [args...]                 run a preset
  services/run.sh --secret VAR@PATH [...] -- CMD...     run a raw command

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
            *)        echo "[run] Unexpected argument in raw mode: $1" >&2; exit 1 ;;
        esac
    done
    [[ "$#" -eq 0 ]] && { echo "[run] No command given after --." >&2; exit 1; }
    for s in "${secrets[@]}"; do hydrate_secret "$s"; done
    exec "$@"
fi

# ── Preset mode ──────────────────────────────────────────────────────────────
spec="${1:-}"
case "$spec" in
    ""|-h|--help|help) _usage; [[ "$spec" == "" ]] && exit 1 || exit 0 ;;
esac
shift || true

if ! preset_exists "$spec"; then
    echo "[run] Unknown preset: ${spec}" >&2
    echo "" >&2
    _usage >&2
    exit 1
fi

# 1. Hydrate declared secrets (static list — safe before load). Report clearly
#    when a declared secret could not be resolved, and why, so failures are
#    diagnosable instead of surfacing later as a confusing tool error.
while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    hydrate_secret "$s"
    var="${s%%@*}"
    if [[ -z "${!var:-}" ]]; then
        if [[ -z "${INFISICAL_CLIENT_ID:-}" || -z "${INFISICAL_CLIENT_SECRET:-}" ]]; then
            echo "[run] NOTE: secret '${var}' is unset and Infisical is not configured (no INFISICAL_CLIENT_ID/SECRET) — cannot fetch it." >&2
        else
            echo "[run] NOTE: secret '${var}' is unset and was not found in Infisical (path '${s#*@}')." >&2
        fi
    fi
done < <(preset_secret_specs "$spec" || true)

# 2. Build the command + auth hook now that the env is populated.
load_preset "$spec" "$@"

# 3. Prepare / authenticate (may exit 0 for a no-op, or fail to abort).
preset_authenticate || { echo "[run] Aborting '${spec}'." >&2; exit 1; }

# 4. Hand off to the tool in the foreground.
[[ "${#PRESET_CMD[@]}" -gt 0 ]] || { echo "[run] Preset '${spec}' produced no command." >&2; exit 1; }
echo "[run] ${PRESET_DESC:-$spec} (Ctrl-C to stop)..."
exec "${PRESET_CMD[@]}"
