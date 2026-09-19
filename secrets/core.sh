#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_SECRETS_CORE_LOADED:-}" ]] && return 0
_SECRETS_CORE_LOADED=1

# ────────────────────────────────────────────────────────────────────────────
# ── Secrets Core — provider-agnostic resolution & hydration ─────────────────
# ────────────────────────────────────────────────────────────────────────────
# A secret is nothing more than an ENVIRONMENT VARIABLE that a tool reads. This
# core knows only three provider-neutral facts:
#
#   1. the VARIABLE a tool consumes            (e.g. GITHUB_PAT) — a stable
#      contract, owned by the caller/preset;
#   2. an opaque LOCATOR string                (e.g. "ADMIN_PAT@/github") — how
#      to find the value, whose SYNTAX AND MEANING belong entirely to the
#      provider, never to this core;
#   3. which PROVIDER to ask                    (SECRET_PROVIDER).
#
# The core NEVER parses a locator, logs into anything, or knows what a "path" or
# "key" is. It only: reads the mapping, picks the provider, hands (VAR, LOCATOR)
# to the provider, and exports whatever comes back. All store-specific knowledge
# lives in secrets/providers/<id>.sh. Add a store = add one file. Nothing here
# changes.
#
# ── Spec grammar (provider-neutral) ─────────────────────────────────────────
#   VAR                 → ask the provider for VAR using its own defaults
#   VAR=LOCATOR         → ask the provider for VAR using this opaque locator
#
#   Everything after the first '=' is the locator and is passed verbatim to the
#   provider. What it means (key, path, namespace, URL, file, …) is the
#   provider's business. Examples for the infisical provider:
#       GITHUB_PAT=ADMIN_PAT@/github
#       GITHUB_PAT=ADMIN_PAT@prod:/github
#   For a hypothetical "pass" provider the same VAR might read:
#       GITHUB_PAT=github/admin-pat
#
# ── Mapping (the only knob most people need) ────────────────────────────────
#   Presets ship DEFAULT specs. Repoint any VAR without editing code via
#   DOTFILES_SECRET_MAP (whitespace-separated specs, keyed by VAR):
#       DOTFILES_SECRET_MAP="GITHUB_PAT=ADMIN_PAT@/github"
#   Provide it headlessly via ~/.config/environment.d/*.conf so the systemd user
#   manager exports it at boot.
#
# ── Provider contract (authoritative — how to author a backend) ─────────────
#   Every file in secrets/providers/ follows the SAME standard layout so that
#   adding a backend is always the same exercise in the same shape:
#
#     1. Config          — env-overridable knobs (endpoints, ids, credentials).
#     2. Secret map      — ONE associative array, the single place that maps an
#                          ENV VAR NAME to a locator in THIS provider's dialect:
#                              declare -gA _<ID>_SECRET_MAP=( [VAR]="locator" )
#                          A fetching backend that has secrets to address MUST
#                          declare this here (and nowhere else). Services stay
#                          unaware; they only ever pass a bare variable name.
#                          The null "env" backend has no store, so it omits it.
#     3. Private helpers — locator parsing, auth, transports (internal only).
#     4. Three contract functions, named by convention, in this canonical order,
#        then a register call:
#          a. _secret_provider_<id>_available                 → 0 if it can fetch
#          b. _secret_provider_<id>_get       <var> <locator> → print value/non-0
#          c. _secret_provider_<id>_describe  <var> <locator> → human source line
#          secret_provider_register <id>
#
#   How get/describe use the map: when <locator> is empty (the normal case —
#   services send bare var names), the provider fills it from its own secret map,
#   falling back to its own naming convention when the var has no row. The
#   <locator> is OPAQUE to this core: its syntax and meaning belong entirely to
#   the provider (only the provider knows its own language). Adding a backend is
#   one new file — nothing in this core changes. See providers/env.sh (minimal
#   template) and providers/infisical.sh (full example with a secret map).
#
# ── Public API ───────────────────────────────────────────────────────────────
#   secret_parse_spec <spec>          → sets SECRET_VAR, SECRET_LOCATOR
#   secret_resolve_spec <default>     → parse, then apply DOTFILES_SECRET_MAP
#   secret_get <var> <locator>        → value from the active provider
#   secret_hydrate <default-spec>     → export VAR if unset and resolvable
#   secret_provider_available         → 0 if the active provider can fetch
#   secret_describe <var> <locator>   → human-readable source description
# ────────────────────────────────────────────────────────────────────────────

# The active backend. Override with SECRET_PROVIDER=<id> (e.g. env) to switch
# stores without touching any caller.
SECRET_PROVIDER="${SECRET_PROVIDER:-infisical}"

# Registry of provider ids. Each provider file appends its id by calling
# secret_provider_register at load time (see the provider contract above).
_SECRET_PROVIDERS=()

# Record a provider id once (idempotent). Called by each provider file.
secret_provider_register() {
    local id
    for id in "${_SECRET_PROVIDERS[@]}"; do [[ "$id" == "$1" ]] && return 0; done
    _SECRET_PROVIDERS+=("$1")
}

# List every registered provider id, one per line (handy for diagnostics).
secret_providers() { printf '%s\n' "${_SECRET_PROVIDERS[@]}"; }

# ── Spec grammar: VAR[=LOCATOR] (locator is opaque to the core) ─────────────
# Split a spec on the FIRST '=' into the exported globals SECRET_VAR (left) and
# SECRET_LOCATOR (everything after, verbatim). The core never looks inside the
# locator. Returns non-zero for an empty spec or a missing variable name.
secret_parse_spec() {
    local spec="$1"
    SECRET_VAR="" SECRET_LOCATOR=""
    [[ -z "$spec" ]] && return 1
    SECRET_VAR="${spec%%=*}"
    if [[ "$spec" == *=* ]]; then SECRET_LOCATOR="${spec#*=}"; fi
    [[ -z "$SECRET_VAR" ]] && return 1
    return 0
}

# Find an override for VAR in DOTFILES_SECRET_MAP (matched by variable name).
_secret_map_lookup() {
    local want="$1" entry evar
    for entry in ${DOTFILES_SECRET_MAP:-}; do
        [[ -z "$entry" ]] && continue
        evar="${entry%%=*}"
        [[ "$evar" == "$want" ]] && { printf '%s\n' "$entry"; return 0; }
    done
    return 1
}

# Parse a default spec, then let a DOTFILES_SECRET_MAP entry override its locator.
secret_resolve_spec() {
    local default_spec="$1" override
    secret_parse_spec "$default_spec" || return 1
    if override="$(_secret_map_lookup "$SECRET_VAR")"; then
        secret_parse_spec "$override" || return 1
    fi
    return 0
}

# ── Provider dispatch (core stays neutral) ──────────────────────────────────
# Every call below routes to the active provider by building the conventional
# function name for the current SECRET_PROVIDER, then invoking it if it exists.
# The core never contains provider-specific logic — it only dispatches.

# Build a contract function name for the active provider, e.g. get →
# _secret_provider_infisical_get.
_secret_provider_fn() { printf '_secret_provider_%s_%s\n' "$SECRET_PROVIDER" "$1"; }

# Fetch <var> using <locator> from the active provider. The locator is passed
# through verbatim — only the provider parses it. Non-zero if unfetchable.
secret_get() {
    local var="$1" locator="$2" fn
    fn="$(_secret_provider_fn get)"
    if declare -F "$fn" >/dev/null 2>&1; then
        "$fn" "$var" "$locator"
    else
        log_warn "unknown SECRET_PROVIDER '${SECRET_PROVIDER}' — cannot fetch '${var}'."
        return 1
    fi
}

# Ask the active provider whether it can fetch right now (contract: available).
# Unknown/unset provider → treated as "cannot fetch".
secret_provider_available() {
    local fn; fn="$(_secret_provider_fn available)"
    if declare -F "$fn" >/dev/null 2>&1; then "$fn"; else return 1; fi
}

# Human-readable source line for <var>/<locator>, for diagnostics. Falls back to
# a generic description when the provider defines no describe function.
secret_describe() {
    local var="$1" locator="$2" fn
    fn="$(_secret_provider_fn describe)"
    if declare -F "$fn" >/dev/null 2>&1; then
        "$fn" "$var" "$locator"
    else
        printf "provider '%s', %s" "$SECRET_PROVIDER" "${locator:+locator '$locator'}"
    fi
}

# ── High-level hydration ─────────────────────────────────────────────────────
# Resolve the spec (default + any map override), respect an already-set var,
# otherwise fetch via the active provider and export into THIS process only.
# Never writes to disk; the value vanishes when the process exits.
secret_hydrate() {
    secret_resolve_spec "$1" || return 0
    local var="$SECRET_VAR"
    [[ -z "$var" ]] && return 0
    [[ -n "${!var:-}" ]] && return 0   # caller-provided value always wins

    local val
    val="$(secret_get "$var" "$SECRET_LOCATOR" 2>/dev/null || true)"
    [[ -n "$val" ]] && export "${var}=${val}"
    return 0
}
