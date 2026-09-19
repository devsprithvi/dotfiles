#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_LOGGER_LIB_LOADED:-}" ]] && return 0
_LOGGER_LIB_LOADED=1

# ════════════════════════════════════════════════════════════════════════════
# ── Dotfiles Logger — the single, dedicated logging facility ────────────────
# ════════════════════════════════════════════════════════════════════════════
# One logger for the whole dotfiles lifecycle (bootstrap → package install →
# service registration → runtime). It has no third-party dependencies: pure
# bash + coreutils, so it works the moment a shell exists.
#
# WHAT IT GIVES YOU
#   • Structured, timestamped lines: every entry carries an ISO-8601 UTC
#     timestamp, a severity level, and the component that emitted it. So you
#     can answer "what installed, what failed, and WHEN" by reading one file.
#   • Dual output: a clean, optionally-colored view on the console (stderr) and
#     a complete, uncolored, machine-greppable record in a log file.
#   • ONE file per run, shared across processes. Each package runs in its own
#     `bash` process; they all inherit DOTFILES_LOG_FILE and append to the SAME
#     file, so a full `chezmoi apply` is a single, coherent log.
#   • A stable pointer: <log-dir>/latest.log always points at the newest run.
#   • Self-pruning: only the newest DOTFILES_LOG_KEEP runs are retained.
#
# WHERE LOGS LIVE
#   ${DOTFILES_LOG_DIR:-${XDG_STATE_HOME:-~/.local/state}/dotfiles/logs}
#     ├── run-YYYYMMDD-HHMMSS-<pid>.log   (one per top-level run)
#     └── latest.log                      (symlink → newest run file)
#
# PUBLIC API
#   log_init [run-label]        (re)initialize; safe & idempotent, auto-runs
#   log_set_component <name>    label subsequent lines from this script
#   log_trace   <msg...>        very fine-grained detail (file only by default)
#   log_debug   <msg...>        diagnostic detail
#   log_info    <msg...>        normal progress
#   log_success <msg...>        a step completed successfully
#   log_warn    <msg...>        something notable but non-fatal
#   log_error   <msg...>        a failure (does NOT exit — caller decides)
#   log_fatal   <msg...>        log an error and exit with status 1
#   log_section <title>         a visual banner (file + console)
#   log_run     <cmd...>        run a command, capturing ALL its output to the
#                               log with timestamps; streams live to console
#   log_file_path               print the active log file path
#
# CONFIGURATION (environment variables)
#   DOTFILES_LOG_DIR         override the log directory
#   DOTFILES_LOG_FILE        the active run file (exported; inherited by children)
#   DOTFILES_LOG_LEVEL       console threshold: TRACE|DEBUG|INFO|WARN|ERROR
#                            (default: INFO)
#   DOTFILES_LOG_FILE_LEVEL  file threshold (default: DEBUG — capture almost all)
#   DOTFILES_LOG_KEEP        number of run files to retain (default: 20)
#   DOTFILES_LOG_NO_COLOR    set to disable ANSI color on the console
#   NO_COLOR                 honored (any value disables color)
# ════════════════════════════════════════════════════════════════════════════

# ── Level model ──────────────────────────────────────────────────────────────
# Numeric ranks let us compare a message's level against the active threshold.
# SUCCESS shares INFO's rank so it shows at the default verbosity.
_log_level_rank() {
    case "$1" in
        TRACE)   printf '0\n' ;;
        DEBUG)   printf '1\n' ;;
        INFO)    printf '2\n' ;;
        SUCCESS) printf '2\n' ;;
        WARN)    printf '3\n' ;;
        ERROR)   printf '4\n' ;;
        *)       printf '2\n' ;;
    esac
}

# ── Timestamps ───────────────────────────────────────────────────────────────
# UTC ISO-8601 for the file (unambiguous across machines/timezones); a shorter
# local wall-clock for the console (easier to read at a glance).
_log_ts_file()    { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
_log_ts_console() { date '+%H:%M:%S'; }

# ── Color ────────────────────────────────────────────────────────────────────
# Colors apply ONLY to the console, and only when stderr is a TTY and color is
# not disabled. The file is always plain text.
_log_use_color() {
    [[ -n "${DOTFILES_LOG_NO_COLOR:-}" || -n "${NO_COLOR:-}" ]] && return 1
    [[ -t 2 ]]
}

# Emit the ANSI SGR code for a level (empty when color is off).
_log_color_for() {
    _log_use_color || { printf '' ; return 0; }
    case "$1" in
        TRACE)   printf '\033[2;37m'  ;;  # dim grey
        DEBUG)   printf '\033[36m'    ;;  # cyan
        INFO)    printf '\033[34m'    ;;  # blue
        SUCCESS) printf '\033[32m'    ;;  # green
        WARN)    printf '\033[33m'    ;;  # yellow
        ERROR)   printf '\033[31m'    ;;  # red
        *)       printf ''            ;;
    esac
}
_log_color_reset() { _log_use_color && printf '\033[0m' || printf ''; }
_log_color_dim()   { _log_use_color && printf '\033[2m'  || printf ''; }

# ── Component label ──────────────────────────────────────────────────────────
# Defaults to the running script's basename (e.g. "git.sh" → "git"); orchestrators
# set an explicit, friendlier name via log_set_component.
_LOG_COMPONENT="${_LOG_COMPONENT:-}"

log_set_component() { _LOG_COMPONENT="$1"; }

_log_component() {
    if [[ -n "${_LOG_COMPONENT:-}" ]]; then
        printf '%s\n' "${_LOG_COMPONENT}"
        return 0
    fi
    local base="${0##*/}"
    base="${base%.sh}"
    [[ -z "$base" || "$base" == "bash" || "$base" == "-bash" ]] && base="dotfiles"
    printf '%s\n' "$base"
}

# ── Log file lifecycle ───────────────────────────────────────────────────────
_log_dir() {
    printf '%s\n' "${DOTFILES_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/logs}"
}

# Prune all but the newest DOTFILES_LOG_KEEP run files. Best-effort and silent.
_log_prune() {
    local dir keep
    dir="$(_log_dir)"
    keep="${DOTFILES_LOG_KEEP:-20}"
    [[ "$keep" =~ ^[0-9]+$ ]] || keep=20
    [[ -d "$dir" ]] || return 0

    # Newest first; delete everything past the keep count.
    local -a files=()
    local f
    while IFS= read -r f; do
        [[ -n "$f" ]] && files+=("$f")
    done < <(ls -1t "$dir"/run-*.log 2>/dev/null || true)

    local i=0
    for f in "${files[@]}"; do
        i=$((i + 1))
        if (( i > keep )); then
            rm -f "$f" 2>/dev/null || true
        fi
    done
}

# Point <dir>/latest.log at the current run file (symlink, copy-fallback).
_log_update_latest() {
    local dir file latest
    dir="$(_log_dir)"
    file="${DOTFILES_LOG_FILE}"
    latest="${dir}/latest.log"
    [[ -n "$file" ]] || return 0
    ln -sf "$file" "$latest" 2>/dev/null || true
}

# Create the log directory and file if needed. On any failure we degrade to
# console-only logging (never abort the caller for a logging problem).
_LOG_FILE_READY=""
_log_ensure_file() {
    [[ -n "${_LOG_FILE_READY:-}" ]] && return 0

    # A parent process already established the run file — reuse it verbatim.
    if [[ -n "${DOTFILES_LOG_FILE:-}" ]]; then
        local parent_dir="${DOTFILES_LOG_FILE%/*}"
        if mkdir -p "$parent_dir" 2>/dev/null && { [[ -e "$DOTFILES_LOG_FILE" ]] || : >"$DOTFILES_LOG_FILE" 2>/dev/null; }; then
            _LOG_FILE_READY=1
            return 0
        fi
        # Parent path is unusable here (different user/host); fall through and
        # mint a fresh file for this process.
        unset DOTFILES_LOG_FILE
    fi

    local dir stamp
    dir="$(_log_dir)"
    if ! mkdir -p "$dir" 2>/dev/null; then
        _LOG_FILE_READY=0   # 0 = tried and failed → console-only
        return 1
    fi

    stamp="$(date -u '+%Y%m%d-%H%M%S')"
    DOTFILES_LOG_FILE="${dir}/run-${stamp}-$$.log"
    if ! : >"$DOTFILES_LOG_FILE" 2>/dev/null; then
        unset DOTFILES_LOG_FILE
        _LOG_FILE_READY=0
        return 1
    fi
    export DOTFILES_LOG_FILE

    _log_update_latest
    _log_prune
    _LOG_FILE_READY=1
    return 0
}

# ── Session header ───────────────────────────────────────────────────────────
# Written once, by whichever process first creates the run file, so a log opens
# with the full context needed to reproduce/diagnose the run.
_log_write_header() {
    local label="${1:-}"
    {
        printf '════════════════════════════════════════════════════════════════════════════\n'
        printf ' Dotfiles run log%s\n' "${label:+ — ${label}}"
        printf '════════════════════════════════════════════════════════════════════════════\n'
        printf ' Run ID     : %s\n' "${DOTFILES_RUN_ID:-unknown}"
        printf ' Started    : %s (local: %s)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf ' Host       : %s\n' "$(hostname 2>/dev/null || echo unknown)"
        printf ' User       : %s (uid %s)\n' "$(id -un 2>/dev/null || echo unknown)" "$(id -u 2>/dev/null || echo '?')"
        printf ' OS         : %s\n' "${OS_PRETTY_NAME:-${OSTYPE:-unknown}}"
        printf ' Arch       : %s\n' "${OS_ARCH:-$(uname -m 2>/dev/null || echo unknown)}"
        printf ' Log file   : %s\n' "${DOTFILES_LOG_FILE}"
        printf ' Levels     : console=%s file=%s\n' "${DOTFILES_LOG_LEVEL:-INFO}" "${DOTFILES_LOG_FILE_LEVEL:-DEBUG}"
        printf '────────────────────────────────────────────────────────────────────────────\n'
    } >>"${DOTFILES_LOG_FILE}" 2>/dev/null || true
}

# ── Initialization ───────────────────────────────────────────────────────────
# Idempotent. Establishes a shared run id, ensures the file exists, and writes
# the header exactly once. Auto-invoked on the first log call, but orchestrators
# may call it explicitly to control the run label and header placement.
_LOG_INITIALIZED=""
log_init() {
    local label="${1:-}"

    # Shared run id: created once, then inherited by every child process.
    if [[ -z "${DOTFILES_RUN_ID:-}" ]]; then
        DOTFILES_RUN_ID="$(date -u '+%Y%m%d-%H%M%S')-$$"
        export DOTFILES_RUN_ID
    fi

    [[ -n "${_LOG_INITIALIZED:-}" ]] && return 0
    _LOG_INITIALIZED=1

    # Was the file already established (by us or a parent)? If not, we are the
    # process that creates it and therefore owns the header.
    local existed=""
    [[ -n "${DOTFILES_LOG_FILE:-}" ]] && existed=1

    _log_ensure_file || return 0   # console-only fallback

    if [[ -z "$existed" ]]; then
        _log_write_header "$label"
    fi
    return 0
}

# ── Core emit ────────────────────────────────────────────────────────────────
# Formats one entry and writes it to the file (if it meets the file threshold)
# and to the console/stderr (if it meets the console threshold). Console and
# file are independent, so the file can keep full detail while the console stays
# quiet.
_log_emit() {
    local level="$1"; shift
    local msg="$*"

    # Lazy init on first use so a bare `log_info` "just works".
    [[ -n "${_LOG_INITIALIZED:-}" ]] || log_init

    local rank console_thr file_thr comp
    rank="$(_log_level_rank "$level")"
    console_thr="$(_log_level_rank "${DOTFILES_LOG_LEVEL:-INFO}")"
    file_thr="$(_log_level_rank "${DOTFILES_LOG_FILE_LEVEL:-DEBUG}")"
    comp="$(_log_component)"

    # ── File record (plain, complete) ──
    if [[ "${_LOG_FILE_READY:-}" == "1" && "$rank" -ge "$file_thr" ]]; then
        printf '%s  %-7s [%s] %s\n' "$(_log_ts_file)" "$level" "$comp" "$msg" \
            >>"${DOTFILES_LOG_FILE}" 2>/dev/null || true
    fi

    # ── Console view (colored, concise) ──
    if [[ "$rank" -ge "$console_thr" ]]; then
        local color reset dim
        color="$(_log_color_for "$level")"
        reset="$(_log_color_reset)"
        dim="$(_log_color_dim)"
        printf '%s%s%s %s%-7s%s %s[%s]%s %s\n' \
            "$dim" "$(_log_ts_console)" "$reset" \
            "$color" "$level" "$reset" \
            "$dim" "$comp" "$reset" \
            "$msg" >&2
    fi
    return 0
}

# ── Level convenience wrappers ───────────────────────────────────────────────
log_trace()   { _log_emit TRACE   "$@"; }
log_debug()   { _log_emit DEBUG   "$@"; }
log_info()    { _log_emit INFO    "$@"; }
log_success() { _log_emit SUCCESS "$@"; }
log_warn()    { _log_emit WARN    "$@"; }
log_error()   { _log_emit ERROR   "$@"; }

# Log an error and abort the process. Use for genuinely unrecoverable failures.
log_fatal() {
    _log_emit ERROR "$@"
    exit 1
}

# ── Section banner ───────────────────────────────────────────────────────────
# A visual divider in both outputs. Handy to mark phase boundaries (e.g. the
# start of package installation) while keeping everything in the same log.
log_section() {
    local title="$*"
    [[ -n "${_LOG_INITIALIZED:-}" ]] || log_init

    if [[ "${_LOG_FILE_READY:-}" == "1" ]]; then
        {
            printf '\n%s  ─────────────────────────────────────────────────────────────\n' "$(_log_ts_file)"
            printf '%s  ── %s\n' "$(_log_ts_file)" "$title"
            printf '%s  ─────────────────────────────────────────────────────────────\n' "$(_log_ts_file)"
        } >>"${DOTFILES_LOG_FILE}" 2>/dev/null || true
    fi

    if _log_use_color; then
        printf '\n\033[1;35m── %s\033[0m\n' "$title" >&2
    else
        printf '\n── %s\n' "$title" >&2
    fi
    return 0
}

# ── Command capture ──────────────────────────────────────────────────────────
# Run a command, stream its combined output live to the console, AND capture
# every line into the log file with timestamps. Returns the command's real exit
# status (not tee's), and logs a clear success/failure result line.
#
# Usage:  log_run <command> [args...]
#
# Note: takes a plain command + args (no shell operators). For a pipeline, wrap
# it: log_run bash -c 'a | b'.
log_run() {
    [[ "$#" -gt 0 ]] || { log_error "log_run called with no command"; return 2; }
    [[ -n "${_LOG_INITIALIZED:-}" ]] || log_init

    log_debug "exec: $*"

    local ts_prefix status
    ts_prefix="$(_log_ts_file)"

    if [[ "${_LOG_FILE_READY:-}" == "1" ]]; then
        # Tee to console while a read-loop stamps each line into the file. The
        # command's real status comes from PIPESTATUS[0], shielded from `set -e`
        # by running inside an `if`.
        if "$@" 2>&1 | while IFS= read -r line; do
                printf '%s  OUTPUT  [%s] %s\n' "$(_log_ts_file)" "$(_log_component)" "$line" >>"${DOTFILES_LOG_FILE}" 2>/dev/null || true
                printf '%s\n' "$line" >&2
            done; then
            status="${PIPESTATUS[0]}"
        else
            status="${PIPESTATUS[0]}"
        fi
    else
        # Console-only fallback.
        "$@" >&2 2>&1
        status=$?
    fi

    if [[ "$status" -eq 0 ]]; then
        log_debug "exit 0: $1"
    else
        log_error "command failed (exit ${status}): $*"
    fi
    return "$status"
}

# ── Introspection ────────────────────────────────────────────────────────────
log_file_path() { printf '%s\n' "${DOTFILES_LOG_FILE:-}"; }
