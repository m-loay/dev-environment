#!/usr/bin/env bash
# STEP_TOTAL, ASSUME_YES and DRY_RUN are read by lib/common.sh, not here.
# shellcheck disable=SC2034
#
# 00-system-packages.sh — OS-level packages required before any conda work.
#
# Nothing here is a Python package. Everything here exists because some wheel,
# installer or runtime loads it from the system: libgomp for the OpenMP kernels
# in scikit-learn/XGBoost/LightGBM, libglib for OpenCV's headless build, bzip2
# for the Miniforge self-extracting installer.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

STEP_TOTAL=3
require_not_root

APT_PACKAGES=(
  # Toolchain — some sdists still compile (dvc plugins, older wheels on arm64).
  build-essential
  pkg-config

  # Fetching and unpacking installers
  curl
  wget
  git
  ca-certificates
  tar
  unzip
  bzip2
  xz-utils

  # OpenMP runtime: scikit-learn, XGBoost and LightGBM dlopen libgomp.so.1.
  # Missing it produces an ImportError at `import lightgbm`, not at install.
  libgomp1

  # OpenCV headless still links libglib-2.0 for its threading primitives.
  libglib2.0-0t64

  # TLS/compression used by boto3, httpx, pyarrow at runtime
  libssl3
  zlib1g

  # Postgres client headers, in case a project pins psycopg2 (not -binary)
  libpq-dev

  # HDF5 headers, in case h5py has to build from source on arm64
  libhdf5-dev

  # Locale support — pandas/Jupyter misbehave under POSIX-only locales
  locales
)

header "System packages for the Python environment"

step "Detecting the platform"
if ! is_debian_like; then
  warn "This script targets Debian/Ubuntu (detected: $(os_id))."
  warn "Install the equivalents manually, then re-run 10-install-conda.sh."
  printf '\n  Required, by role:\n'
  printf '    toolchain     build-essential pkg-config\n'
  printf '    fetch/unpack  curl wget git tar unzip bzip2 xz\n'
  printf '    OpenMP        libgomp\n'
  printf '    OpenCV        glib2\n'
  printf '    optional      libpq-dev libhdf5-dev\n\n'
  exit 1
fi
ok "$(os_id) $( . /etc/os-release && echo "${VERSION_ID:-}" )$(is_wsl && echo ' (WSL)' || true)"

step "Refreshing the package index"
run "apt-get update" sudo apt-get update

step "Installing ${#APT_PACKAGES[@]} packages"
# libglib2.0-0t64 exists on Ubuntu 24.04+; older releases use libglib2.0-0.
# Resolve the name rather than failing the whole transaction.
if ! apt-cache show libglib2.0-0t64 >/dev/null 2>&1; then
  for i in "${!APT_PACKAGES[@]}"; do
    [[ "${APT_PACKAGES[$i]}" == "libglib2.0-0t64" ]] && APT_PACKAGES[$i]="libglib2.0-0"
    [[ "${APT_PACKAGES[$i]}" == "libssl3" ]] && APT_PACKAGES[$i]="libssl-dev"
  done
  info "older release detected: using libglib2.0-0 / libssl-dev"
fi

run_stream "apt-get install" sudo apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"

finish "System packages ready. Next: ./10-install-conda.sh"
