#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Dotfile startup: run declared preset commands at every boot ─────────────
# ────────────────────────────────────────────────────────────────────────────
# The dotfile startup runs a declared set of commands automatically after every
# reboot. The commands are PRESETS (pre-designed commands + a small convenience
# layer) from commands/presets/. Which ones start at boot is the single source
# of truth: the DOTFILES_STARTUP list, declared when you apply your dotfiles:
#
#     DOTFILES_STARTUP="vscode:tunnel tailscale:up" chezmoi apply
#
# This script is called BY `chezmoi apply` (run_onchange). It is plumbing, not a
# manual tool — the commands/ folder is not even deployed to your home. It
# reconciles the list into OS autostart units:
#
#   * every preset in the list is registered + enabled to start at each boot;
#   * any unit we previously managed that is NO LONGER in the list is disabled.
#
# So editing DOTFILES_STARTUP and re-applying is the whole interface: add a name
# to autostart it forever, remove a name to stop it. Per-preset settings (tunnel
# name, ports, ...) come from that preset's own env vars, so the list stays a
# plain set of names.
#
# Each preset carries its own "common sense": it checks its state first and does
# not repeat work already done (e.g. it reuses an existing login instead of
# re-authenticating). The startup layer itself is dumb on purpose — it just runs
# what you declared, every boot.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
source "${SCRIPT_DIR}/autostart.sh"
source "${SCRIPT_DIR}/presets/index.sh"
log_set_component "startup"

RUNNER="${SCRIPT_DIR}/run.sh"

# Unit name for a "tool:sub" spec (systemd/launchd both use bare names).
_unit_name() { printf '%s\n' "${1/:/-}"; }

# Desired specs come from the arguments (the word-split DOTFILES_STARTUP list).
desired_specs=()
for spec in "$@"; do
    [[ -z "$spec" ]] && continue
    desired_specs+=("$spec")
done

# Need a driveable init system to register or remove anything.
if ! autostart_supported; then
    if [[ "${#desired_specs[@]}" -gt 0 ]]; then
        log_warn "Cannot set up startup here: $(autostart_unsupported_reason)."
        log_warn "Declared commands were not registered. On Linux this needs systemd."
    fi
    exit 0
fi

# ── 1. Enable everything listed. ─────────────────────────────────────────────
declare -A desired_names=()
for spec in "${desired_specs[@]}"; do
    if ! preset_exists "$spec"; then
        log_warn "skipping unknown preset in DOTFILES_STARTUP: '${spec}'"
        continue
    fi
    name="$(_unit_name "$spec")"
    desired_names["$name"]=1
    log_info "startup command: ${spec}"
    # The unit re-enters the generic runner so all secret/auth logic stays in one
    # place. env bash keeps the ExecStart first token absolute for systemd.
    autostart_register "$name" "dotfile startup: ${spec}" /usr/bin/env bash "$RUNNER" "$spec"
    autostart_enable "$name" || log_warn "could not enable '${spec}' (see message above)."
done

# ── 2. Disable anything we manage that is no longer listed. ──────────────────
# The declared list is authoritative: drop a name from it and it stops starting.
while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ -z "${desired_names[$name]:-}" ]]; then
        log_info "removing startup command '${name}' (no longer declared)."
        autostart_disable "$name"
    fi
done < <(autostart_managed_names)

log_success "dotfile startup reconciled — ${#desired_names[@]} command(s) will run at every boot."
