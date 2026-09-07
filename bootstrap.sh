#!/usr/bin/env bash
# STEP_TOTAL, ASSUME_YES and DRY_RUN are read by lib/common.sh, not here.
# shellcheck disable=SC2034
#
# bootstrap.sh — set up both halves of the development environment.
#
# Order matters: the Neovim verification step type-checks a probe file against
# the ml-dev interpreter, so the Python environments must exist first.
#
#   ./bootstrap.sh                   interactive
#   ./bootstrap.sh --yes             unattended
#   ./bootstrap.sh --yes --purge     unattended, wiping any existing Neovim
#   ./bootstrap.sh --python-only
#   ./bootstrap.sh --neovim-only
#   ./bootstrap.sh --dry-run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DO_PYTHON=1
DO_NEOVIM=1
DO_PURGE=0
PY_ARGS=()
NV_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --python-only) DO_NEOVIM=0 ;;
    --neovim-only) DO_PYTHON=0 ;;
    --purge)       DO_PURGE=1 ;;
    --recreate)    PY_ARGS+=("--recreate") ;;
    --skip-system) PY_ARGS+=("--skip-system") ;;
    --yes|-y)      ASSUME_YES=1; export ASSUME_YES; PY_ARGS+=("--yes"); NV_ARGS+=("-y") ;;
    --dry-run)     DRY_RUN=1; export DRY_RUN; PY_ARGS+=("--dry-run") ;;
    -h|--help)     sed -n '2,14p' "$0"; exit 0 ;;
    *)             die "unknown flag: $arg" ;;
  esac
done

require_not_root
export LOG_FILE

header "dev-environment bootstrap"
printf '  Host    : %s (%s)%s\n' "$(hostname)" "$(os_id)" "$(is_wsl && echo ' WSL' || true)"
printf '  Arch    : %s\n' "$(arch_tag)"
printf '  Log     : %s\n' "$LOG_FILE"
printf '  Plan    : %s%s\n' \
  "$([[ "$DO_PYTHON" == "1" ]] && echo 'python ' || echo '')" \
  "$([[ "$DO_NEOVIM" == "1" ]] && echo 'neovim' || echo '')"
printf '\n'

confirm "Proceed?" y || die "aborted by user"

# A failed verification in one half must not stop the other half from
# installing: the checks are diagnostics, not preconditions. Failures are
# collected and reported at the end, and the exit status still reflects them.
PY_STATUS=0
NV_STATUS=0

if [[ "$DO_PYTHON" == "1" ]]; then
  bash "$SCRIPT_DIR/python_environment/scripts/install.sh" "${PY_ARGS[@]}" || PY_STATUS=$?
fi

if [[ "$DO_NEOVIM" == "1" && "$DO_PURGE" == "1" ]]; then
  bash "$SCRIPT_DIR/neovim_environment/purge-neovim.sh" "${NV_ARGS[@]}"
fi

if [[ "$DO_NEOVIM" == "1" ]]; then
  bash "$SCRIPT_DIR/neovim_environment/install-neovim.sh" "${NV_ARGS[@]}" || NV_STATUS=$?
fi

printf '\n'
header "Done"
# Distinguish the two: install.sh exits 1 when only verification failed, and
# aborts earlier (via the ERR trap) when a step itself failed. Both surface as
# a non-zero status here, so say "failed", not "verification failed".
[[ "$DO_PYTHON" == "1" ]] && summary_line "python environment" "$([[ "$PY_STATUS" -eq 0 ]] && echo 'ok' || echo "failed (exit $PY_STATUS) — see the log")"
[[ "$DO_NEOVIM" == "1" ]] && summary_line "neovim environment" "$([[ "$NV_STATUS" -eq 0 ]] && echo 'ok' || echo "failed (exit $NV_STATUS) — see the log")"
printf '\n' 
printf '  Start a new login shell so PATH and the conda init block are picked up:\n\n'
printf '    exec "$SHELL" -l\n\n'
printf '  Then:\n'
printf '    conda activate ml-dev\n'
printf '    nvim something.py     ->  <leader>cv  ->  Ctrl+/  ->  which python\n\n'

exit $(( PY_STATUS != 0 || NV_STATUS != 0 ))
