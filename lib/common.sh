# shellcheck shell=bash
#
# Shared shell library for the dev-environment installers.
#
# Provides:
#   - Consistent, colourised logging and step counters.
#   - run()        : quiet command execution with a live spinner + logfile.
#   - run_stream() : streaming command execution (pip/conda, where output matters).
#   - confirm()    : y/N prompt honouring ASSUME_YES / --yes.
#   - Small helpers: die, have, require_cmd, os_id, arch_tag, backup_path.
#
# Every script that sources this file gets `set -euo pipefail` and a trap that
# prints the failing line, so a partially applied install is always visible.

set -euo pipefail

# ---------------------------------------------------------------------------
# Terminal capabilities
# ---------------------------------------------------------------------------

if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  C_RESET="$(tput sgr0)"
  C_BOLD="$(tput bold)"
  C_DIM="$(tput dim)"
  C_RED="$(tput setaf 1)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"
  C_CYAN="$(tput setaf 6)"
  IS_TTY=1
else
  C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
  IS_TTY=0
fi

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

STEP_CURRENT=0
STEP_TOTAL="${STEP_TOTAL:-0}"
SCRIPT_NAME="$(basename "${BASH_SOURCE[1]:-$0}")"

LOG_DIR="${LOG_DIR:-$HOME/.local/state/dev-environment/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_FILE:-$LOG_DIR/$(date +%Y%m%d-%H%M%S)-${SCRIPT_NAME%.sh}.log}"
: >"$LOG_FILE"

ASSUME_YES="${ASSUME_YES:-0}"
DRY_RUN="${DRY_RUN:-0}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_ts() { date +%H:%M:%S; }

log_raw() { printf '%s\n' "$*"; printf '[%s] %s\n' "$(_ts)" "$*" >>"$LOG_FILE"; }

header() {
  printf '\n%s%s==> %s%s\n' "$C_BOLD" "$C_BLUE" "$*" "$C_RESET"
  printf '\n===== %s =====\n' "$*" >>"$LOG_FILE"
}

step() {
  STEP_CURRENT=$((STEP_CURRENT + 1))
  local label="[$STEP_CURRENT/${STEP_TOTAL:-?}]"
  printf '\n%s%s %s%s\n' "$C_BOLD$C_CYAN" "$label" "$*" "$C_RESET"
  printf '\n--- %s %s ---\n' "$label" "$*" >>"$LOG_FILE"
}

info() { printf '  %s·%s %s\n' "$C_DIM" "$C_RESET" "$*"; printf '[%s] INFO %s\n' "$(_ts)" "$*" >>"$LOG_FILE"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; printf '[%s] OK   %s\n' "$(_ts)" "$*" >>"$LOG_FILE"; }
warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; printf '[%s] WARN %s\n' "$(_ts)" "$*" >>"$LOG_FILE"; }
fail() { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*"; printf '[%s] FAIL %s\n' "$(_ts)" "$*" >>"$LOG_FILE"; }

die() {
  fail "$*"
  printf '\n%sLog:%s %s\n' "$C_DIM" "$C_RESET" "$LOG_FILE"
  exit 1
}

on_error() {
  local rc=$? line=${1:-?}
  printf '\n%s%s✗ %s failed (exit %s) at line %s%s\n' "$C_BOLD" "$C_RED" "$SCRIPT_NAME" "$rc" "$line" "$C_RESET"
  printf '%sLast 30 log lines:%s\n' "$C_DIM" "$C_RESET"
  tail -n 30 "$LOG_FILE" || true
  printf '\n%sFull log:%s %s\n' "$C_DIM" "$C_RESET" "$LOG_FILE"
  exit "$rc"
}
trap 'on_error $LINENO' ERR

# ---------------------------------------------------------------------------
# Command execution
# ---------------------------------------------------------------------------

_spinner_pid=""

_spin() {
  local msg="$1" frames='|/-\' i=0 start
  start=$(date +%s)
  while :; do
    i=$(((i + 1) % 4))
    printf '\r  %s%s%s %s %s(%ss)%s ' \
      "$C_CYAN" "${frames:$i:1}" "$C_RESET" "$msg" "$C_DIM" "$(( $(date +%s) - start ))" "$C_RESET"
    sleep 0.15
  done
}

_spin_start() {
  [[ "$IS_TTY" == "1" ]] || return 0
  _spin "$1" &
  _spinner_pid=$!
  disown "$_spinner_pid" 2>/dev/null || true
}

_spin_stop() {
  [[ -n "$_spinner_pid" ]] || return 0
  kill "$_spinner_pid" >/dev/null 2>&1 || true
  wait "$_spinner_pid" 2>/dev/null || true
  _spinner_pid=""
  printf '\r\033[K'
}

# run "description" cmd args...
# Quiet: all output goes to the logfile. Shows a spinner while running.
run() {
  local desc="$1"; shift
  if [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN: $desc  ->  $*"
    return 0
  fi
  printf '[%s] RUN  %s :: %s\n' "$(_ts)" "$desc" "$*" >>"$LOG_FILE"
  _spin_start "$desc"
  local rc=0
  "$@" >>"$LOG_FILE" 2>&1 || rc=$?
  _spin_stop
  if [[ $rc -eq 0 ]]; then
    ok "$desc"
  else
    fail "$desc (exit $rc)"
    printf '%s--- last 30 log lines ---%s\n' "$C_DIM" "$C_RESET"
    tail -n 30 "$LOG_FILE" || true
    return $rc
  fi
}

# run_stream "description" cmd args...
# Streams output to the terminal AND the logfile. Use for pip/conda where the
# user genuinely wants to watch resolution and download progress.
run_stream() {
  local desc="$1"; shift
  if [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN: $desc  ->  $*"
    return 0
  fi
  info "$desc"
  printf '[%s] RUN  %s :: %s\n' "$(_ts)" "$desc" "$*" >>"$LOG_FILE"
  local rc=0
  set -o pipefail
  "$@" 2>&1 | tee -a "$LOG_FILE" | sed 's/^/    /' || rc=$?
  if [[ $rc -eq 0 ]]; then
    ok "$desc"
  else
    fail "$desc (exit $rc)"
    return $rc
  fi
}

# would "description"
#
# Returns 0 (true) when DRY_RUN is set, so the caller must SKIP the action:
#
#     would "install ~/.condarc" || install -m 0644 "$src" "$dst"
#
# run()/run_stream() already honour DRY_RUN, but plain builtins (install, mv,
# ln, mkdir, redirections) do not — every one of those must go through this.
would() {
  if [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN: $*"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

confirm() {
  local prompt="$1" default="${2:-n}" reply
  if [[ "$ASSUME_YES" == "1" ]]; then
    info "$prompt -> yes (--yes)"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    info "$prompt -> $default (non-interactive)"
    [[ "$default" == "y" ]]
    return
  fi
  local hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"
  read -r -p "  ${C_YELLOW}?${C_RESET} $prompt $hint " reply || reply=""
  reply="${reply:-$default}"
  [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

ask_value() {
  # ask_value VARNAME "prompt" "default"
  local __var="$1" prompt="$2" default="$3" reply
  if [[ "$ASSUME_YES" == "1" || ! -t 0 ]]; then
    printf -v "$__var" '%s' "$default"
    return 0
  fi
  read -r -p "  ${C_YELLOW}?${C_RESET} $prompt [$default] " reply || reply=""
  printf -v "$__var" '%s' "${reply:-$default}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
  local c
  for c in "$@"; do
    have "$c" || die "required command not found: $c"
  done
}

require_not_root() {
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "do not run this as root; it installs into \$HOME and uses sudo only where needed"
}

os_id() {
  # shellcheck disable=SC1091
  [[ -r /etc/os-release ]] && . /etc/os-release && printf '%s' "${ID:-unknown}" || printf 'unknown'
}

os_like() {
  # shellcheck disable=SC1091
  [[ -r /etc/os-release ]] && . /etc/os-release && printf '%s' "${ID_LIKE:-}" || printf ''
}

is_debian_like() {
  local id like
  id="$(os_id)"; like="$(os_like)"
  [[ "$id" == "ubuntu" || "$id" == "debian" || "$like" == *debian* ]]
}

is_wsl() { grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; }

arch_tag() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

backup_path() {
  # Move a path aside with a timestamp suffix. No-op if it does not exist.
  local p="$1"
  [[ -e "$p" || -L "$p" ]] || return 0
  local dest
  dest="${p}.bak.$(date +%Y%m%d-%H%M%S)"
  mv "$p" "$dest"
  warn "backed up $p -> $dest"
}

summary_line() {
  printf '  %-34s %s\n' "$1" "$2"
}

finish() {
  printf '\n%s%s✓ %s%s\n' "$C_BOLD" "$C_GREEN" "$*" "$C_RESET"
  printf '%sLog:%s %s\n' "$C_DIM" "$C_RESET" "$LOG_FILE"
}
