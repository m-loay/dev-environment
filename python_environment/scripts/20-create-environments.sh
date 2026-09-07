#!/usr/bin/env bash
# STEP_TOTAL, ASSUME_YES and DRY_RUN are read by lib/common.sh, not here.
# shellcheck disable=SC2034
#
# 20-create-environments.sh — create the managed conda environments and install
# the layered requirements into them.
#
# Design decision: conda provides ONLY the interpreter and pip. Every library
# comes from PyPI. Mixing conda-forge builds and pip wheels in one env is the
# most common source of "solves fine, segfaults on import", because the two
# resolvers do not share a view of ABI compatibility.
#
# Usage:
#   ./20-create-environments.sh                 # create/repair all managed envs
#   ./20-create-environments.sh ml-dev          # only one
#   ./20-create-environments.sh --recreate      # delete and rebuild from scratch
#   ./20-create-environments.sh --yes           # non-interactive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
CONFIG_DIR="$SCRIPT_DIR/../config"
REQ_DIR="$SCRIPT_DIR/../requirements"
# shellcheck source=../config/environments.conf
source "$CONFIG_DIR/environments.conf"

require_not_root

RECREATE=0
SELECTED=()
for arg in "$@"; do
  case "$arg" in
    --recreate) RECREATE=1 ;;
    --yes|-y)   ASSUME_YES=1 ;;
    --dry-run)  DRY_RUN=1 ;;
    -*)         die "unknown flag: $arg" ;;
    *)          SELECTED+=("$arg") ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve conda
# ---------------------------------------------------------------------------

if [[ -r "$HOME/.config/dev-environment/conda-root" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/dev-environment/conda-root"
fi
[[ -n "${CONDA_ROOT:-}" && -x "$CONDA_ROOT/bin/conda" ]] \
  || die "conda not found — run ./10-install-conda.sh first"
CONDA_BIN="$CONDA_ROOT/bin/conda"

# Build the work list from the manifest.
declare -a ENV_NAMES ENV_REQS
for pair in $MANAGED_ENVS; do
  name="${pair%%:*}"
  req="${pair##*:}"
  if [[ ${#SELECTED[@]} -gt 0 ]]; then
    printf '%s\n' "${SELECTED[@]}" | grep -qx "$name" || continue
  fi
  ENV_NAMES+=("$name")
  ENV_REQS+=("$req")
done
[[ ${#ENV_NAMES[@]} -gt 0 ]] || die "no matching environments in MANAGED_ENVS"

# 4 steps per env, plus 1 preamble step.
STEP_TOTAL=$((1 + 4 * ${#ENV_NAMES[@]}))

header "Creating ${#ENV_NAMES[@]} environment(s) on Python $PYTHON_VERSION"

step "Plan"
for i in "${!ENV_NAMES[@]}"; do
  target="$CONDA_ROOT/envs/${ENV_NAMES[$i]}"
  state="create"
  [[ -d "$target" ]] && state=$([[ "$RECREATE" == "1" ]] && echo "RECREATE (destructive)" || echo "update in place")
  summary_line "${ENV_NAMES[$i]}" "$state  <-  requirements/${ENV_REQS[$i]}"
done
printf '\n'
confirm "Proceed?" y || die "aborted by user"

# ---------------------------------------------------------------------------

write_activation_hooks() {
  # PYTHONNOUSERSITE stops ~/.local/lib/pythonX.Y/site-packages from shadowing
  # env packages. Without it, a stray `pip install --user` silently changes
  # what both the interpreter and basedpyright resolve.
  local prefix="$1"
  would "write activation hooks in $prefix" && return 0
  mkdir -p "$prefix/etc/conda/activate.d" "$prefix/etc/conda/deactivate.d"
  cat >"$prefix/etc/conda/activate.d/dev-environment.sh" <<'EOF'
export PYTHONNOUSERSITE=1
EOF
  cat >"$prefix/etc/conda/deactivate.d/dev-environment.sh" <<'EOF'
unset PYTHONNOUSERSITE
EOF
}

for i in "${!ENV_NAMES[@]}"; do
  name="${ENV_NAMES[$i]}"
  req="${ENV_REQS[$i]}"
  prefix="$CONDA_ROOT/envs/$name"
  py="$prefix/bin/python"

  step "[$name] Creating the environment"
  if [[ -d "$prefix" && "$RECREATE" == "1" ]]; then
    run "removing existing $name" "$CONDA_BIN" env remove -n "$name" --yes
  fi
  if [[ -d "$prefix" ]]; then
    ok "exists, reusing (pass --recreate to rebuild)"

    # An environment that predates this repo will not be on the managed Python
    # version, and pip will then silently resolve older numpy/scipy/pandas
    # because the newer releases declare requires-python >= 3.12. Say so
    # loudly: a quiet 3.11 environment is the source of "why is numpy 2.2".
    if [[ -x "$py" ]]; then
      existing_ver="$("$py" -c 'import sys;print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo '?')"
      if [[ "$existing_ver" != "$PYTHON_VERSION" ]]; then
        warn "$name is on Python $existing_ver, the manifest says $PYTHON_VERSION"
        warn "numpy >= 2.5 and scipy >= 1.18 require 3.12; pip will pin older"
        warn "releases instead of failing, so this is easy to miss"
        warn "fix: ./20-create-environments.sh --recreate $name"
        warn "or:  set PYTHON_VERSION=\"$existing_ver\" in config/environments.conf"
      fi

      # Reusing a large pre-existing environment mixes this repo's requirements
      # with whatever was already there. Worth a nudge, not an error.
      pkgs="$("$py" -m pip list --format=freeze 2>/dev/null | wc -l || echo 0)"
      if [[ "$pkgs" -gt 200 ]]; then
        warn "$name already has $pkgs packages from outside this repo"
        warn "a clean rebuild makes the environment match requirements/$req exactly"
      fi
    fi
  else
    run_stream "conda create -n $name python=$PYTHON_VERSION" \
      "$CONDA_BIN" create -n "$name" "python=$PYTHON_VERSION" pip setuptools wheel --yes
  fi
  [[ -x "$py" ]] || die "$py missing after creation"
  write_activation_hooks "$prefix"

  step "[$name] Upgrading the installer toolchain"
  run "pip/setuptools/wheel" "$py" -m pip install --upgrade pip setuptools wheel

  step "[$name] Installing requirements/$req"
  # --upgrade so re-running the script converges an existing env to the file
  # instead of silently keeping older pins.
  #
  # --constraint bounds transitive dependencies that no requirements file names
  # directly. Without it the s3fs/fsspec/datasets triangle resolves to a
  # 2023-era set that satisfies every declared requirement and then fails at
  # import time. See requirements/constraints.txt.
  run_stream "pip install -r $req (with constraints)" \
    "$py" -m pip install --upgrade \
      --constraint "$REQ_DIR/constraints.txt" \
      --requirement "$REQ_DIR/$req"

  step "[$name] Registering the Jupyter kernel"
  run "ipykernel: $name" "$py" -m ipykernel install --user \
    --name "$name" --display-name "Python ($name)"
  ok "environment $name ready at $prefix"
done

# ---------------------------------------------------------------------------

printf '\n'
header "Summary"
for name in "${ENV_NAMES[@]}"; do
  py="$CONDA_ROOT/envs/$name/bin/python"
  ver="$("$py" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))' 2>/dev/null || echo '?')"
  count="$("$py" -m pip list --format=freeze 2>/dev/null | wc -l || echo '?')"
  summary_line "$name" "python $ver, $count packages"
done

finish "Environments built. Next: ./30-verify.sh"
