#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_PRESETS_LIB_LOADED:-}" ]] && return 0
_PRESETS_LIB_LOADED=1

# ────────────────────────────────────────────────────────────────────────────
# ── Preset loader / dispatcher (index of commands/presets/) ─────────────────
# ────────────────────────────────────────────────────────────────────────────
# There is ONE generic runner (commands/run.sh). The per-tool knowledge — which
# command to run, which secrets it needs, how (or whether) it authenticates —
# lives in ONE FILE PER TOOL in this directory. Adding a tool = dropping a new
# <tool>.sh file here. Nothing in this index needs editing.
#
# Each commands/presets/<tool>.sh appends its tool name to _PRESET_TOOLS and
# defines three functions, keyed by the part before the ":" in a "tool:sub" spec:
#
#   _preset_<tool>_list                      prints its `list` line(s)
#   _preset_<tool>_secret_specs <sub>        prints "VAR" secrets to hydrate,
#                                            or returns non-zero for a bad sub
#   _preset_<tool>_load <sub> [args...]      sets PRESET_DESC + PRESET_CMD[] and
#                                            (re)defines preset_authenticate
#
# This index only wires those together; it holds no tool-specific logic.
# ────────────────────────────────────────────────────────────────────────────

_PRESETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Registry populated by each sourced tool file.
_PRESET_TOOLS=()
for _f in "$_PRESETS_DIR"/*.sh; do
    [[ -e "$_f" ]] || continue
    [[ "$(basename "$_f")" == "index.sh" ]] && continue   # skip this loader itself
    # shellcheck source=/dev/null
    source "$_f"
done
unset _f

_preset_tool() { printf '%s\n' "${1%%:*}"; }
_preset_sub()  { printf '%s\n' "${1#*:}"; }

_preset_tool_known() {
    local t
    for t in "${_PRESET_TOOLS[@]}"; do [[ "$t" == "$1" ]] && return 0; done
    return 1
}

# ── Public API (used by commands/run.sh and commands/startup.sh) ────────────

# List every preset from every tool file.
preset_list() {
    local t
    for t in "${_PRESET_TOOLS[@]}"; do "_preset_${t}_list"; done
}

# True if "tool:sub" is a real preset (tool file exists AND knows the sub).
preset_exists() {
    local tool; tool="$(_preset_tool "$1")"
    _preset_tool_known "$tool" || return 1
    "_preset_${tool}_secret_specs" "$(_preset_sub "$1")" >/dev/null 2>&1
}

# Static list of secrets to hydrate for a spec (safe before hydration).
preset_secret_specs() {
    local tool; tool="$(_preset_tool "$1")"
    _preset_tool_known "$tool" || return 1
    "_preset_${tool}_secret_specs" "$(_preset_sub "$1")"
}

# Build PRESET_CMD + auth hook for a spec, now that the env is populated.
load_preset() {
    local spec="$1"; shift || true
    local tool sub
    tool="$(_preset_tool "$spec")"
    sub="$(_preset_sub "$spec")"

    PRESET_DESC=""
    PRESET_CMD=()
    # Default prepare/auth step is a no-op; tool files override as needed. It runs
    # on every run/autostart and MUST stay non-interactive.
    preset_authenticate() { :; }

    if ! _preset_tool_known "$tool"; then
        log_error "Unknown preset: ${spec}"
        return 1
    fi
    "_preset_${tool}_load" "$sub" "$@"
}
