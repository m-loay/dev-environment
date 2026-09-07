#!/usr/bin/env bash
# STEP_TOTAL, ASSUME_YES and DRY_RUN are read by lib/common.sh, not here.
# shellcheck disable=SC2034
#
# install.sh — run the whole Python environment setup end to end.
#
#   ./install.sh                  interactive
#   ./install.sh --yes            non-interactive (CI / fresh server)
#   ./install.sh --recreate       destroy and rebuild the conda environments
#   ./install.sh --skip-system    skip apt (already provisioned)
#   ./install.sh --dry-run        print what would run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

SKIP_SYSTEM=0
PASS_THROUGH=()
for arg in "$@"; do
  case "$arg" in
    --skip-system) SKIP_SYSTEM=1 ;;
    --yes|-y)      ASSUME_YES=1; export ASSUME_YES; PASS_THROUGH+=("--yes") ;;
    --dry-run)     DRY_RUN=1; export DRY_RUN; PASS_THROUGH+=("--dry-run") ;;
    --recreate)    PASS_THROUGH+=("--recreate") ;;
    -h|--help)     sed -n '2,12p' "$0"; exit 0 ;;
    *)             die "unknown flag: $arg" ;;
  esac
done

export LOG_FILE   # every sub-script appends to one log for this run

header "Python environment — full install"
printf '  Log: %s\n' "$LOG_FILE"

if [[ "$SKIP_SYSTEM" == "0" ]]; then
  bash "$SCRIPT_DIR/00-system-packages.sh"
else
  info "skipping system packages (--skip-system)"
fi

bash "$SCRIPT_DIR/10-install-conda.sh"
bash "$SCRIPT_DIR/20-create-environments.sh" "${PASS_THROUGH[@]}"

# Verification is meaningless after a dry run: nothing was installed, so it
# would report the absence of packages the dry run deliberately skipped.
VERIFY_STATUS=0
if [[ "$DRY_RUN" == "1" ]]; then
  info "skipping verification (--dry-run installed nothing to verify)"
else
  bash "$SCRIPT_DIR/30-verify.sh" || VERIFY_STATUS=$?
fi

printf '\n'
if [[ "$VERIFY_STATUS" -ne 0 ]]; then
  warn "verification reported problems — see above; the install itself completed"
fi

header "Next steps"
printf '  1. Open a NEW shell (the conda init block is only read at startup).\n'
printf '  2. conda activate ml-dev   # or llm-dev\n'
printf '  3. Copy config/pyproject.template.toml into a project and set `venv`.\n'
printf '  4. Install the Neovim side: ../../neovim_environment/scripts/install.sh\n\n'

exit "$VERIFY_STATUS"
