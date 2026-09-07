#!/usr/bin/env bash
# STEP_TOTAL, ASSUME_YES and DRY_RUN are read by lib/common.sh, not here.
# shellcheck disable=SC2034
#
# 10-install-conda.sh — make sure a usable conda exists, install ~/.condarc,
# and wire up shell integration WITHOUT the base-auto-activation that breaks
# environment selection inside Neovim.
#
# Detection order: an explicit CONDA_ROOT from environments.conf, then any
# existing installation, then a fresh Miniforge install.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
CONFIG_DIR="$SCRIPT_DIR/../config"
# shellcheck source=../config/environments.conf
source "$CONFIG_DIR/environments.conf"

for arg in "$@"; do
  case "$arg" in
    --yes|-y)  ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *)         die "unknown flag: $arg" ;;
  esac
done

STEP_TOTAL=6
require_not_root
require_cmd curl

header "Conda installation and shell integration"

# ---------------------------------------------------------------------------

step "Locating a conda installation"

detect_conda_root() {
  local candidate
  if [[ -n "${CONDA_ROOT:-}" ]]; then
    printf '%s' "$CONDA_ROOT"; return 0
  fi
  for candidate in "$HOME/miniforge3" "$HOME/mambaforge" "$HOME/miniconda3" "$HOME/anaconda3" "/opt/conda"; do
    [[ -x "$candidate/bin/conda" ]] && { printf '%s' "$candidate"; return 0; }
  done
  # Fall back to whatever is on PATH (e.g. a system package).
  if have conda; then
    dirname "$(dirname "$(command -v conda)")"
    return 0
  fi
  return 1
}

if CONDA_ROOT="$(detect_conda_root)"; then
  ok "found conda at $CONDA_ROOT"
  INSTALL_CONDA=0
else
  info "no conda installation found"
  INSTALL_CONDA=1
fi

# ---------------------------------------------------------------------------

step "Installing Miniforge (if required)"

if [[ "$INSTALL_CONDA" == "1" ]]; then
  if [[ "${ALLOW_CONDA_INSTALL:-1}" != "1" ]]; then
    die "no conda found and ALLOW_CONDA_INSTALL=0 in config/environments.conf"
  fi

  printf '\n  Miniforge is used rather than Anaconda because it defaults to\n'
  printf '  conda-forge and carries no commercial-use licensing question.\n\n'

  ask_value CONDA_ROOT "Install Miniforge to" "$HOME/miniforge3"

  if [[ -e "$CONDA_ROOT" ]]; then
    confirm "$CONDA_ROOT exists. Back it up and reinstall?" n \
      && backup_path "$CONDA_ROOT" \
      || die "refusing to install over $CONDA_ROOT"
  fi

  case "$(arch_tag)" in
    x86_64) MF_ASSET="Miniforge3-Linux-x86_64.sh" ;;
    arm64)  MF_ASSET="Miniforge3-Linux-aarch64.sh" ;;
  esac
  MF_URL="https://github.com/conda-forge/miniforge/releases/latest/download/$MF_ASSET"
  MF_TMP="$(mktemp -d)"
  trap 'rm -rf "$MF_TMP"' EXIT

  run "downloading $MF_ASSET" curl -fsSL -o "$MF_TMP/$MF_ASSET" "$MF_URL"
  run "running the installer (batch mode)" bash "$MF_TMP/$MF_ASSET" -b -p "$CONDA_ROOT"
  ok "Miniforge installed to $CONDA_ROOT"
else
  info "skipping: using the existing installation"
fi

CONDA_BIN="$CONDA_ROOT/bin/conda"
[[ -x "$CONDA_BIN" ]] || die "conda binary not found at $CONDA_BIN"

# ---------------------------------------------------------------------------

step "Installing ~/.condarc"

if [[ -f "$HOME/.condarc" ]] && cmp -s "$CONFIG_DIR/condarc" "$HOME/.condarc"; then
  ok "condarc already matches the repo copy"
elif ! would "back up and replace $HOME/.condarc"; then
  backup_path "$HOME/.condarc"
  install -m 0644 "$CONFIG_DIR/condarc" "$HOME/.condarc"
  ok "condarc installed at $HOME/.condarc (previous version backed up if any)"
fi

# Belt and braces: write the setting through conda itself as well, so it lands
# in whichever config file conda considers authoritative on this version.
# `auto_activate` is conda >= 25.x; `auto_activate_base` is the older alias.
if would "conda config --set auto_activate false"; then
  :
elif "$CONDA_BIN" config --set auto_activate false >>"$LOG_FILE" 2>&1; then
  ok "conda config: auto_activate = false"
elif "$CONDA_BIN" config --set auto_activate_base false >>"$LOG_FILE" 2>&1; then
  ok "conda config: auto_activate_base = false"
else
  warn "could not set auto_activate via the CLI; relying on the condarc file"
fi

# ---------------------------------------------------------------------------

step "Wiring shell integration"

for shell_name in bash zsh; do
  rc="$HOME/.${shell_name}rc"
  if ! have "$shell_name"; then
    info "$shell_name not installed, skipping"
    continue
  fi
  if [[ -f "$rc" ]] && grep -q "conda initialize" "$rc"; then
    ok "$rc already has a conda initialize block"
  else
    run "conda init $shell_name" "$CONDA_BIN" init "$shell_name"
  fi
done

# Neovim launched from a desktop entry inherits no shell rc, so venv-selector
# would have no conda on PATH at all. A tiny profile.d-style export fixes that
# for graphical sessions without duplicating the init block.
PROFILE_SNIPPET="$HOME/.config/dev-environment/conda-path.sh"
if would "write $PROFILE_SNIPPET and source it from $HOME/.profile"; then
  SKIP_PROFILE=1
else
  SKIP_PROFILE=0
fi
mkdir -p "$(dirname "$PROFILE_SNIPPET")"
[[ "$SKIP_PROFILE" == "1" ]] || cat >"$PROFILE_SNIPPET" <<EOF
# Written by dev-environment/python_environment/scripts/10-install-conda.sh
# Minimal, activation-free conda exposure for non-login/graphical sessions.
export CONDA_ROOT="$CONDA_ROOT"
export CONDA_EXE="$CONDA_ROOT/bin/conda"
case ":\$PATH:" in
  *":$CONDA_ROOT/condabin:"*) ;;
  *) export PATH="$CONDA_ROOT/condabin:\$PATH" ;;
esac
EOF
[[ "$SKIP_PROFILE" == "1" ]] || ok "wrote $PROFILE_SNIPPET"

if [[ "$SKIP_PROFILE" != "1" ]] && ! grep -q "dev-environment/conda-path.sh" "$HOME/.profile" 2>/dev/null; then
  {
    printf '\n# dev-environment: expose conda to non-login sessions\n'
    printf '[ -r "%s" ] && . "%s"\n' "$PROFILE_SNIPPET" "$PROFILE_SNIPPET"
  } >>"$HOME/.profile"
  ok "sourced from ~/.profile"
elif [[ "$SKIP_PROFILE" != "1" ]]; then
  ok "already sourced from $HOME/.profile"
fi

# ---------------------------------------------------------------------------

step "Default environment for interactive shells"

# Disabling auto_activate fixes the Neovim terminal, but it also means a plain
# terminal now has NO environment active, so CONDA_DEFAULT_ENV is unset and
# prompt themes (oh-my-posh, starship, powerlevel10k) show nothing where they
# used to show (base).
#
# The conda hook's own activation is unconditional, which is exactly why it
# destroyed an inherited environment. This guarded version is not: it activates
# base only when nothing is active yet, so an environment handed down from
# Neovim survives untouched.

BASHRC="$HOME/.bashrc"
MARKER="# dev-environment: guarded default activation"

if [[ ! -f "$BASHRC" ]]; then
  info "no ~/.bashrc, skipping"
elif grep -qF "$MARKER" "$BASHRC"; then
  ok "guarded default activation already present"
elif would "append a guarded 'conda activate base' to $BASHRC"; then
  :
elif confirm "Activate 'base' in plain terminals so the prompt shows it again?" y; then
  cat >>"$BASHRC" <<EOF

$MARKER
# Activates base ONLY when no environment is already active, so an environment
# inherited from Neovim (CONDA_PREFIX set by venv-selector) is left alone.
# Must stay AFTER the conda initialize block: it needs the shell function.
if [ -z "\${CONDA_PREFIX:-}" ] && command -v conda >/dev/null 2>&1; then
    conda activate base
fi
EOF
  ok "appended to $BASHRC (takes effect in a new shell)"
else
  info "skipped — plain terminals will start with no environment active"
fi

# ---------------------------------------------------------------------------

step "Verifying"

CONDA_VERSION="$("$CONDA_BIN" --version 2>/dev/null || echo unknown)"
AUTO_ACTIVATE="$("$CONDA_BIN" config --show 2>/dev/null | grep -E '^auto_activate' || echo 'auto_activate: <unset>')"

printf '\n'
summary_line "conda root" "$CONDA_ROOT"
summary_line "version" "$CONDA_VERSION"
summary_line "auto-activate" "$(printf '%s' "$AUTO_ACTIVATE" | tr '\n' ' ')"
summary_line "condarc" "$HOME/.condarc"

if printf '%s' "$AUTO_ACTIVATE" | grep -qi 'true'; then
  warn "base auto-activation is still enabled — the Neovim terminal fix will not hold"
  warn "run: $CONDA_BIN config --set auto_activate false"
fi

# Persist the resolved root so later scripts and the Neovim config agree.
# This one is written even under --dry-run: it is pure metadata, and the later
# scripts need it to report anything useful.
mkdir -p "$HOME/.config/dev-environment"
printf 'CONDA_ROOT="%s"\n' "$CONDA_ROOT" >"$HOME/.config/dev-environment/conda-root"
ok "resolved root recorded in $HOME/.config/dev-environment/conda-root"

finish "Conda ready. Next: ./20-create-environments.sh"
