#!/usr/bin/env bash
#
# ── Secrets subsystem tests (mock, no network) ──────────────────────────────
# Verifies the provider-agnostic resolution rules and the infisical secret map
# WITHOUT contacting any store: the network transports are stubbed so a "fetch"
# just echoes the resolved coordinates. Run it directly:
#
#     bash secrets/secrets_test.sh
#
# Exits 0 when every assertion passes, non-zero otherwise.
# ────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load the whole utility+secrets stack. Silence the logger's session header.
source "${SCRIPT_DIR}/../utilities/index.sh" >/dev/null 2>&1

_PASS=0
_FAIL=0

# assert_eq <label> <expected> <actual>
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  PASS  %s\n' "$label"
        _PASS=$((_PASS + 1))
    else
        printf '  FAIL  %s\n        expected: %q\n        actual:   %q\n' "$label" "$expected" "$actual"
        _FAIL=$((_FAIL + 1))
    fi
}

# ── Stub the infisical transports so nothing hits the network ───────────────
# get_cli always "misses" so resolution flows to get_api, which echoes the
# resolved key/env/path it was handed. That lets us assert the map math.
_infisical_get_cli() { return 1; }
_infisical_get_api() { printf 'VAL[key=%s env=%s path=%s]\n' "$1" "$2" "$3"; }

echo "── 1. Secret map resolution (infisical) ──"
SECRET_PROVIDER=infisical
assert_eq "GITHUB_PAT uses explicit map key + path" \
    "infisical key 'ADMIN_PAT', env 'global', path '/github'" \
    "$(secret_describe GITHUB_PAT '')"
assert_eq "DEVTUNNEL_TOKEN key defaults to var name, path from map" \
    "infisical key 'DEVTUNNEL_TOKEN', env 'global', path '/tunnels'" \
    "$(secret_describe DEVTUNNEL_TOKEN '')"
assert_eq "unmapped var falls back to convention (key=var, path=/)" \
    "infisical key 'RANDOM_VAR', env 'global', path '/'" \
    "$(secret_describe RANDOM_VAR '')"

echo "── 2. DOTFILES_SECRET_MAP override wins over the provider map ──"
(
    export DOTFILES_SECRET_MAP="GITHUB_PAT=OTHER_KEY@prod:/elsewhere"
    secret_resolve_spec "GITHUB_PAT"
    assert_eq "override repoints key/env/path" \
        "infisical key 'OTHER_KEY', env 'prod', path '/elsewhere'" \
        "$(secret_describe "$SECRET_VAR" "$SECRET_LOCATOR")"
)

echo "── 3. Hydration exports the fetched value (bare var name) ──"
(
    export INFISICAL_TOKEN="dummy"      # make the provider "available"
    unset GITHUB_PAT
    secret_hydrate "GITHUB_PAT"
    assert_eq "GITHUB_PAT hydrated from map coordinates" \
        "VAL[key=ADMIN_PAT env=global path=/github]" \
        "${GITHUB_PAT:-<unset>}"
)

echo "── 4. A caller-provided value always wins (no fetch) ──"
(
    export INFISICAL_TOKEN="dummy"
    export GITHUB_PAT="already-set"
    secret_hydrate "GITHUB_PAT"
    assert_eq "pre-set var is left untouched" "already-set" "${GITHUB_PAT}"
)

echo "── 5. The null 'env' provider fetches nothing ──"
(
    export SECRET_PROVIDER=env
    unset TAILSCALE_AUTHKEY
    secret_hydrate "TAILSCALE_AUTHKEY"
    assert_eq "env backend leaves the var unset" "<unset>" "${TAILSCALE_AUTHKEY:-<unset>}"
    assert_eq "env backend reports unavailable" "no" "$(secret_provider_available && echo yes || echo no)"
)

echo "── 6. Presets declare bare names only (no provider dialect) ──"
source "${SCRIPT_DIR}/../services/presets.sh" >/dev/null 2>&1
assert_eq "vscode:tunnel spec is a bare var name" \
    "GITHUB_PAT" \
    "$(preset_secret_specs vscode:tunnel | tr '\n' ' ' | sed 's/ *$//')"
assert_eq "devtunnel:host lists bare var names" \
    "DEVTUNNEL_TOKEN GITHUB_PAT" \
    "$(preset_secret_specs devtunnel:host | tr '\n' ' ' | sed 's/ *$//')"

echo
printf 'Result: %d passed, %d failed\n' "$_PASS" "$_FAIL"
[[ "$_FAIL" -eq 0 ]]
