#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_SECRET_PROVIDER_INFISICAL_LOADED:-}" ]] && return 0
_SECRET_PROVIDER_INFISICAL_LOADED=1

# ════════════════════════════════════════════════════════════════════════════
# ── Secret provider: infisical ──────────────────────────────────────────────
# ════════════════════════════════════════════════════════════════════════════
# A "provider" answers exactly one question for the core: given a variable name,
# produce its secret VALUE. Everything infisical-specific (where a secret lives,
# how to authenticate, how to fetch) is contained in THIS file. The core and the
# services never learn any of it.
#
# This file follows the standard provider layout (identical in every provider,
# see secrets/core.sh for the authoritative contract):
#     1. Config           — env-overridable knobs
#     2. Secret map       — the ONE place that says where each secret lives
#     3. Private helpers  — locator parsing, auth, transports (never called out)
#     4. Provider contract — available / get / describe  (+ register)
# ════════════════════════════════════════════════════════════════════════════

# ── 1. Config — every default is a named, overridable constant ──────────────
# No magic literals are buried in the logic below: the locator parser reads ONLY
# these variables, so this block is the single source of truth for defaults.
# Each is `${OVERRIDE:-fallback}`, so exporting the env var before load wins.
#
#   INFISICAL_ENV           environment slug used when a locator omits one
#   INFISICAL_DEFAULT_PATH  secret path used when a locator omits one
#   INFISICAL_PROJECT_ID    workspace id
#   INFISICAL_TOKEN         pre-issued access token (skips machine-identity login)
#   INFISICAL_CLIENT_ID   \ machine identity used to mint a short-lived token
#   INFISICAL_CLIENT_SECRET/  when INFISICAL_TOKEN is not supplied
INFISICAL_ENV="${INFISICAL_ENV:-global}"
INFISICAL_DEFAULT_PATH="${INFISICAL_DEFAULT_PATH:-/}"
INFISICAL_PROJECT_ID="${INFISICAL_PROJECT_ID:-e3e7a48d-605a-4ae2-b202-2dbf45918227}"

# A locator that omits the KEY reuses the variable's own name. This is a
# structural rule (not a tunable value), so it is applied in code as "${key:-$var}".

# ── 2. Secret map — WHERE each env var lives in Infisical ────────────────────
# This is the scalable heart of the provider: the single table that maps a
# tool-facing ENV VAR NAME to its location in the store. Services ask for the
# var name only; this table (and this table alone) knows the address.
#
# Value syntax is this provider's locator dialect:  [KEY][@[ENV:]PATH]
#   KEY   the secret's name in Infisical   — omit to reuse the ENV VAR NAME
#   ENV   environment slug                 — omit to use $INFISICAL_ENV
#   PATH  folder path in Infisical         — omit to use $INFISICAL_DEFAULT_PATH
# (Both defaults are the named constants declared in section 1 above.)
#
# To ADD a secret: add one row. To move it: edit its row. Nothing else changes.
#
#   ENV VAR              locator                 ⇒ resolves to
#   ───────────────────  ──────────────────────  ──────────────────────────────
declare -gA _INFISICAL_SECRET_MAP=(
    [GITHUB_PAT]="ADMIN_PAT@/github"          # key ADMIN_PAT,        env global, path /github
    [DEVTUNNEL_TOKEN]="@/tunnels"             # key DEVTUNNEL_TOKEN,  env global, path /tunnels   (key = var name)
    [TAILSCALE_AUTHKEY]="@/tailscale"         # key TAILSCALE_AUTHKEY, env global, path /tailscale (key = var name)
)

# Look up the locator for a variable. An explicit map row wins; otherwise return
# "" so the parser applies its defaults (key = var name, env = $INFISICAL_ENV,
# path = $INFISICAL_DEFAULT_PATH).
_infisical_locator_for() { printf '%s' "${_INFISICAL_SECRET_MAP[$1]:-}"; }

# ── 3. Private helpers (implementation detail; not part of the contract) ─────

# Parse a locator string into the globals _IF_KEY / _IF_ENV / _IF_PATH.
#   $1 = variable name (used as the KEY fallback)
#   $2 = locator in [KEY][@[ENV:]PATH] form (may be empty → all defaults)
_infisical_parse_locator() {
    local var="$1" locator="$2" keypart rest env_candidate

    # Split KEY (before the first '@') from the rest (env + path).
    keypart="${locator%%@*}"
    if [[ "$locator" == *@* ]]; then rest="${locator#*@}"; else rest=""; fi

    # KEY defaults to the variable name when not given.
    _IF_KEY="${keypart:-$var}"

    # rest is "[ENV:]PATH". An "ENV:" prefix is present only when there is a ':'
    # before any '/', so a bare "/github" is treated as a path, not an env.
    env_candidate="${rest%%:*}"
    if [[ "$rest" == *:* && -n "$env_candidate" && "$env_candidate" != /* ]]; then
        _IF_ENV="$env_candidate"
        _IF_PATH="${rest#*:}"
    else
        _IF_ENV="$INFISICAL_ENV"
        _IF_PATH="$rest"
    fi

    # PATH defaults to the configured root.
    [[ -z "$_IF_PATH" ]] && _IF_PATH="$INFISICAL_DEFAULT_PATH"
}

# Resolve a (var, locator) pair into _IF_KEY / _IF_ENV / _IF_PATH. When the
# caller passes no locator (the normal case — services send bare var names), the
# locator is taken from the secret map above. This is the single junction where
# "env var name" becomes "concrete store coordinates".
_infisical_resolve() {
    local var="$1" locator="$2"
    [[ -z "$locator" ]] && locator="$(_infisical_locator_for "$var")"
    _infisical_parse_locator "$var" "$locator"
}

# Obtain an access token: an explicit INFISICAL_TOKEN wins; otherwise exchange
# the universal-auth machine identity for a short-lived token via REST.
_infisical_login_token() {
    [[ -n "${INFISICAL_TOKEN:-}" ]] && { printf '%s\n' "$INFISICAL_TOKEN"; return 0; }
    [[ -n "${INFISICAL_CLIENT_ID:-}" && -n "${INFISICAL_CLIENT_SECRET:-}" ]] || return 1
    has_command curl    || return 1
    has_command python3 || return 1
    curl -s --max-time 10 -X POST \
        "https://app.infisical.com/api/v1/auth/universal-auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"clientId\": \"${INFISICAL_CLIENT_ID}\", \"clientSecret\": \"${INFISICAL_CLIENT_SECRET}\"}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken',''))" 2>/dev/null
}

# Transport 1: official CLI. Best-effort — any failure falls through to REST.
_infisical_get_cli() {
    has_command infisical || return 1
    local key="$1" env="$2" path="$3" token
    token="$(_infisical_login_token)" || return 1
    [[ -n "$token" ]] || return 1
    local val
    val="$(INFISICAL_TOKEN="$token" infisical secrets get "$key" \
            --env="$env" --path="$path" \
            ${INFISICAL_PROJECT_ID:+--projectId="$INFISICAL_PROJECT_ID"} \
            --plain --silent 2>/dev/null)" || return 1
    [[ -n "$val" ]] || return 1
    printf '%s\n' "$val"
}

# Transport 2: REST API (curl + python3). The reliable engine.
_infisical_get_api() {
    local key="$1" env="$2" path="$3" token encoded_path
    has_command curl    || return 1
    has_command python3 || return 1
    token="$(_infisical_login_token)" || return 1
    [[ -z "$token" ]] && return 1

    encoded_path=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$path" 2>/dev/null)

    curl -s --max-time 10 -X GET \
        "https://app.infisical.com/api/v3/secrets/raw?environment=${env}&secretPath=${encoded_path}&workspaceId=${INFISICAL_PROJECT_ID}" \
        -H "Authorization: Bearer ${token}" \
        | SECRET_KEY_LOOKUP="$key" python3 -c "
import os, sys, json
key = os.environ['SECRET_KEY_LOOKUP']
secrets = json.load(sys.stdin).get('secrets', [])
print(next((s['secretValue'] for s in secrets if s['secretKey'] == key), ''))
" 2>/dev/null
}

# ── 4. Provider contract (available → get → describe, then register) ─────────

# available: can this backend fetch right now? True only if we hold credentials
# (a pre-issued token, or a full machine identity of client id + secret).
_secret_provider_infisical_available() {
    [[ -n "${INFISICAL_TOKEN:-}" ]] && return 0
    [[ -n "${INFISICAL_CLIENT_ID:-}" && -n "${INFISICAL_CLIENT_SECRET:-}" ]]
}

# get: resolve the var to store coordinates (via the secret map), then fetch —
# CLI first, REST as fallback. Prints the value, or returns non-zero on failure.
_secret_provider_infisical_get() {
    local _IF_KEY _IF_ENV _IF_PATH
    _infisical_resolve "$1" "$2"
    _infisical_get_cli "$_IF_KEY" "$_IF_ENV" "$_IF_PATH" && return 0
    _infisical_get_api "$_IF_KEY" "$_IF_ENV" "$_IF_PATH"
}

# describe: one human-readable line of the resolved coordinates, for diagnostics
# (e.g. shown when a secret is missing). Fetches nothing.
_secret_provider_infisical_describe() {
    local _IF_KEY _IF_ENV _IF_PATH
    _infisical_resolve "$1" "$2"
    printf "infisical key '%s', env '%s', path '%s'" "$_IF_KEY" "$_IF_ENV" "$_IF_PATH"
}

# Make this backend selectable via SECRET_PROVIDER=infisical.
secret_provider_register infisical

# ── Backward-compatible shim (not part of the contract) ──────────────────────
# Older callers used: fetch_infisical_secret KEY [env] [path]
fetch_infisical_secret() {
    local key="$1" env="${2:-$INFISICAL_ENV}" path="${3:-$INFISICAL_DEFAULT_PATH}"
    _infisical_get_cli "$key" "$env" "$path" && return 0
    _infisical_get_api "$key" "$env" "$path"
}
