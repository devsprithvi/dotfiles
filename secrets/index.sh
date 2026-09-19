#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_SECRETS_INDEX_LOADED:-}" ]] && return 0
_SECRETS_INDEX_LOADED=1

# ────────────────────────────────────────────────────────────────────────────
# ── Secrets Universal Index ──────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Single entry point for the secrets subsystem. Sourcing this loads the
# provider-agnostic core, then auto-discovers every backend under providers/.
# Adding a new store is a single new file in providers/ — no wiring here.
#
# Depends on the utilities logger/helpers (log_*, has_command, run_privileged).
# Those carry their own source guards, so re-sourcing them is a cheap no-op and
# keeps this subsystem usable on its own without a load-order footgun.
# ────────────────────────────────────────────────────────────────────────────

SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_UTIL_DIR="$(cd "${SECRETS_DIR}/../utilities" && pwd)"

# Ensure logging + helpers are present (idempotent via their own guards).
source "${_UTIL_DIR}/os.sh"
source "${_UTIL_DIR}/logger.sh"
source "${_UTIL_DIR}/helpers.sh"

# Core engine (generic; no provider specifics).
source "${SECRETS_DIR}/core.sh"

# Auto-load every provider. Drop a file in providers/ to add a backend.
for _secret_provider_file in "${SECRETS_DIR}/providers/"*.sh; do
    [[ -e "$_secret_provider_file" ]] && source "$_secret_provider_file"
done
unset _secret_provider_file
