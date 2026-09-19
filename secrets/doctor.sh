#!/usr/bin/env bash

# ════════════════════════════════════════════════════════════════════════════
# ── Secrets Doctor — end-to-end diagnostic for the Infisical flow ───────────
# ════════════════════════════════════════════════════════════════════════════
# One command that answers the only question that matters: "is secret fetching
# actually working, and if not, WHERE does it break?" It walks the exact chain
# the real subsystem uses and prints a PASS/FAIL for every link, so you never
# again have to guess from a cryptic CLI error like
#     "run infisical init ... or pass in project id with --projectId".
#
# It NEVER prints a secret value. Every fetched value is reported only as
# OK (<n> chars) so this is safe to run and safe to paste.
#
# USAGE
#   bash secrets/doctor.sh            # full diagnostic
#   bash secrets/doctor.sh GITHUB_PAT # also probe one specific mapped variable
#
# It sources the real subsystem (utilities + secrets), so it exercises the same
# code path your services and shells use — not a re-implementation.
# ════════════════════════════════════════════════════════════════════════════

set -o pipefail

# ── Locate the repo and load the real subsystem ─────────────────────────────
_DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_DIR="$(cd "${_DOCTOR_DIR}/.." && pwd)"

# Loading the utilities index pulls in os/logger/helpers AND the secrets index
# (which loads core.sh + every provider). This is the same entry point the rest
# of the dotfiles use.
# shellcheck source=/dev/null
source "${_REPO_DIR}/utilities/index.sh"

# ── Tiny local check harness (independent of the logger's level filtering) ──
_PASS=0
_FAIL=0
_c_green() { [[ -t 1 ]] && printf '\033[32m%s\033[0m' "$1" || printf '%s' "$1"; }
_c_red()   { [[ -t 1 ]] && printf '\033[31m%s\033[0m' "$1" || printf '%s' "$1"; }
_c_yellow(){ [[ -t 1 ]] && printf '\033[33m%s\033[0m' "$1" || printf '%s' "$1"; }
_c_dim()   { [[ -t 1 ]] && printf '\033[2m%s\033[0m'  "$1" || printf '%s' "$1"; }

pass() { _PASS=$((_PASS + 1)); printf '  %s %s\n' "$(_c_green "PASS")" "$1"; }
fail() { _FAIL=$((_FAIL + 1)); printf '  %s %s\n' "$(_c_red   "FAIL")" "$1"; }
note() { printf '  %s %s\n' "$(_c_dim "····")" "$1"; }
hdr()  { printf '\n%s\n' "$(_c_yellow "── $1")"; }

# ── 1. Tooling ──────────────────────────────────────────────────────────────
hdr "1. Tooling"
if has_command curl;    then pass "curl present";    else fail "curl MISSING — REST transport cannot run"; fi
if has_command python3; then pass "python3 present"; else fail "python3 MISSING — token/JSON parsing cannot run"; fi
if has_command infisical; then
    pass "infisical CLI present ($(command -v infisical))"
else
    note "infisical CLI not installed — that's fine, REST transport is the primary engine"
fi

# ── 2. Configuration ────────────────────────────────────────────────────────
hdr "2. Configuration"
printf '  %s SECRET_PROVIDER=%s\n' "$(_c_dim "····")" "${SECRET_PROVIDER:-<unset>}"
printf '  %s INFISICAL_ENV=%s  path=%s\n' "$(_c_dim "····")" "${INFISICAL_ENV:-<unset>}" "${INFISICAL_DEFAULT_PATH:-<unset>}"
if [[ -n "${INFISICAL_PROJECT_ID:-}" ]]; then
    pass "INFISICAL_PROJECT_ID resolved (${INFISICAL_PROJECT_ID})"
else
    fail "INFISICAL_PROJECT_ID empty — CLI would demand 'infisical init'"
fi

_conf="${HOME}/.config/environment.d/infisical.conf"
if [[ -f "$_conf" ]]; then
    pass "credential file present: $_conf"
else
    note "no $_conf (fine if creds come from the container/systemd environment)"
fi

# ── 3. Credentials ──────────────────────────────────────────────────────────
hdr "3. Credentials"
if [[ -n "${INFISICAL_TOKEN:-}" ]]; then
    pass "INFISICAL_TOKEN already set (${#INFISICAL_TOKEN} chars) — will be used directly"
elif [[ -n "${INFISICAL_CLIENT_ID:-}" && -n "${INFISICAL_CLIENT_SECRET:-}" ]]; then
    pass "machine identity present (CLIENT_ID + CLIENT_SECRET) — token will be minted"
else
    fail "no INFISICAL_TOKEN and no CLIENT_ID/CLIENT_SECRET — nothing can authenticate"
    note "load them with: export \$(grep -v '^#' \"$_conf\" | xargs)"
fi

# ── 4. Provider availability (the subsystem's own check) ────────────────────
hdr "4. Provider availability"
if secret_provider_available; then
    pass "active provider '${SECRET_PROVIDER}' reports it CAN fetch"
else
    fail "active provider '${SECRET_PROVIDER}' reports it CANNOT fetch (missing creds)"
fi

# ── 5. Live token exchange ──────────────────────────────────────────────────
hdr "5. Token exchange (universal-auth login)"
_tok=""
if [[ -n "${INFISICAL_TOKEN:-}" ]]; then
    _tok="$INFISICAL_TOKEN"
    pass "using pre-set INFISICAL_TOKEN"
elif [[ -n "${INFISICAL_CLIENT_ID:-}" && -n "${INFISICAL_CLIENT_SECRET:-}" ]] && has_command curl && has_command python3; then
    _tok="$(_infisical_login_token 2>/dev/null || true)"
    if [[ -n "$_tok" ]]; then
        pass "login succeeded — access token minted (${#_tok} chars)"
    else
        fail "login FAILED — check CLIENT_ID/CLIENT_SECRET and network to app.infisical.com"
    fi
else
    fail "cannot attempt login — missing credentials or curl/python3"
fi

# ── 6. Live secret fetch (REST + CLI), per mapped variable ──────────────────
hdr "6. Live secret fetch"
# Build the list: every var in the provider's secret map, plus any CLI argument.
_vars=()
for _k in "${!_INFISICAL_SECRET_MAP[@]}"; do _vars+=("$_k"); done
for _arg in "$@"; do _vars+=("$_arg"); done

if [[ ${#_vars[@]} -eq 0 ]]; then
    note "no variables in the secret map to probe"
elif [[ -z "$_tok" ]]; then
    fail "skipping fetches — no token available"
else
    for _var in "${_vars[@]}"; do
        printf '  %s %s → %s\n' "$(_c_dim "····")" "$_var" "$(secret_describe "$_var" "" 2>/dev/null)"

        # Resolve coordinates once, then probe each transport directly so we can
        # attribute success/failure to REST vs CLI independently.
        _IF_KEY=""; _IF_ENV=""; _IF_PATH=""
        _infisical_resolve "$_var" ""

        _rest="$(_infisical_get_api "$_IF_KEY" "$_IF_ENV" "$_IF_PATH" 2>/dev/null || true)"
        if [[ -n "$_rest" ]]; then
            pass "    REST fetch OK (${#_rest} chars)"
        else
            fail "    REST fetch returned empty — key missing at that env/path, or auth/network issue"
        fi

        if has_command infisical; then
            _cli="$(_infisical_get_cli "$_IF_KEY" "$_IF_ENV" "$_IF_PATH" 2>/dev/null || true)"
            if [[ -n "$_cli" ]]; then
                pass "    CLI fetch OK (${#_cli} chars)"
            else
                note "    CLI fetch empty (non-fatal — REST is the fallback the subsystem relies on)"
            fi
        fi
    done
fi

# ── Summary ─────────────────────────────────────────────────────────────────
hdr "Summary"
printf '  %s passed, %s failed\n' "$(_c_green "${_PASS}")" "$( [[ $_FAIL -gt 0 ]] && _c_red "$_FAIL" || printf '%s' 0 )"
if [[ $_FAIL -eq 0 ]]; then
    printf '  %s Secret fetching is working end to end.\n' "$(_c_green "✔")"
    exit 0
else
    printf '  %s Fix the first FAIL above — later steps depend on it.\n' "$(_c_red "✘")"
    exit 1
fi
