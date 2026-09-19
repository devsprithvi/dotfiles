#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_SECRET_PROVIDER_ENV_LOADED:-}" ]] && return 0
_SECRET_PROVIDER_ENV_LOADED=1

# ════════════════════════════════════════════════════════════════════════════
# ── Secret provider: env — the null backend ─────────────────────────────────
# ════════════════════════════════════════════════════════════════════════════
# Fetches NOTHING. Select it with SECRET_PROVIDER=env for CI / air-gapped runs
# where no external store is reachable. Secrets must already be present in the
# environment (exported by you, a parent process, or ~/.config/environment.d).
# With this backend secret_hydrate becomes a no-op: every tool relies purely on
# pre-set variables.
#
# ── Provider contract (every provider file has this same shape) ─────────────
#   Locator dialect : none — this backend never reads a locator.
#   Config knobs    : none.
#   Functions       : the three _secret_provider_env_* definitions below, in the
#                     canonical order available → get → describe. The contract is
#                     documented once, authoritatively, in secrets/core.sh.
# ────────────────────────────────────────────────────────────────────────────

# ── Contract 1/3 · capability probe ─────────────────────────────────────────
# Return 0 only if this backend can fetch a value right now. The null backend
# never can, so resolution always falls through to "use whatever is already in
# the environment".
_secret_provider_env_available() { return 1; }

# ── Contract 2/3 · fetch ────────────────────────────────────────────────────
# Print the value for <var> located by <locator>, or return non-zero when it
# cannot be produced. The null backend owns no store, so it always reports
# "not found" and lets the caller keep any pre-set value. Both args are ignored.
_secret_provider_env_get() { return 1; }   # args: <var> <locator>

# ── Contract 3/3 · describe ─────────────────────────────────────────────────
# Print one human-readable line naming where the value would come from. Shown in
# diagnostics when a secret is missing. Both args are ignored here.
_secret_provider_env_describe() {
    printf 'env-only (no external store; pre-set the variable yourself)'
}

# ── Registration · make this backend selectable via SECRET_PROVIDER=env ─────
secret_provider_register env
