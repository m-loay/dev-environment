#!/usr/bin/env bash
#
# purge-neovim.sh — remove every Neovim installation and all Neovim state.
#
# Standalone: no other file from this repo is needed. Does not run apt update
# or apt upgrade. The only apt call is a purge, and only if an apt-installed
# neovim package is actually present.
#
#   ./purge-neovim.sh              ask before each scope
#   ./purge-neovim.sh -y           remove everything, no prompts
#   ./purge-neovim.sh --keep-config    leave ~/.config/nvim alone
#   ./purge-neovim.sh --dry-run    show what would be removed

set -uo pipefail

YES=0
KEEP_CONFIG=0
DRY=0

for a in "$@"; do
  case "$a" in
    -y|--yes)      YES=1 ;;
    --keep-config) KEEP_CONFIG=1 ;;
    --dry-run)     DRY=1 ;;
    -h|--help)     sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown flag: $a" >&2; exit 1 ;;
  esac
done

if [ -t 1 ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else
  R=""; G=""; Y=""; B=""; D=""; N=""
fi

say()  { printf '%s\n' "$*"; }
head_() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
info() { printf '  %s·%s %s\n' "$D" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }

ask() {
  [ "$YES" = 1 ] && { info "$1 -> yes"; return 0; }
  [ -t 0 ] || { info "$1 -> yes (non-interactive)"; return 0; }
  printf '  %s?%s %s [Y/n] ' "$Y" "$N" "$1"
  read -r r || r=""
  case "${r:-y}" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Remove a path, using sudo only when the parent directory is not writable.
nuke() {
  p="$1"
  [ -e "$p" ] || [ -L "$p" ] || return 0
  if [ "$DRY" = 1 ]; then info "would remove $p"; return 0; fi
  if [ -w "$(dirname "$p")" ]; then rm -rf "$p"; else sudo rm -rf "$p"; fi
  ok "removed $p"
}

# ---------------------------------------------------------------------------
head_ "1. What is installed"

FOUND=0

# Every nvim reachable through PATH, in resolution order. A second install
# earlier on PATH is the reason a new one can appear to do nothing.
BINS=$(which -a nvim 2>/dev/null)
if [ -n "$BINS" ]; then
  FOUND=1
  say "  binaries on PATH:"
  printf '%s\n' "$BINS" | while read -r b; do
    printf '    %s  ->  %s\n' "$b" "$(readlink -f "$b" 2>/dev/null || echo "$b")"
  done
  say "  active version: $(nvim --version 2>/dev/null | head -n1)"
fi

# Installation trees, wherever they were unpacked.
TREES=$(find "$HOME/.local/opt" "$HOME/opt" "$HOME" /opt /usr/local/share \
             -maxdepth 1 -type d \( -name 'nvim*' -o -name 'neovim*' \) 2>/dev/null)
[ -d "$HOME/.local/share/nvim-releases" ] && TREES="$TREES
$HOME/.local/share/nvim-releases"

if [ -n "${TREES// /}" ]; then
  FOUND=1
  say "  installation trees:"
  printf '%s\n' "$TREES" | grep -v '^$' | while read -r t; do
    printf '    %s  (%s)\n' "$t" "$(du -sh "$t" 2>/dev/null | cut -f1)"
  done
fi

# Config directories, including NVIM_APPNAME siblings.
CONFIGS=$(find "$HOME/.config" -maxdepth 1 -type d -o -maxdepth 1 -type l 2>/dev/null | grep -E '/nvim' || true)
if [ -n "$CONFIGS" ]; then
  FOUND=1
  say "  configuration:"
  printf '%s\n' "$CONFIGS" | while read -r c; do
    if [ -L "$c" ]; then
      printf '    %s  ->  %s  (symlink)\n' "$c" "$(readlink -f "$c")"
    else
      printf '    %s  (%s files)\n' "$c" "$(find "$c" -type f 2>/dev/null | wc -l)"
    fi
  done
fi

say "  state:"
for d in "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"; do
  if [ -e "$d" ]; then
    FOUND=1
    printf '    %s  (%s)\n' "$d" "$(du -sh "$d" 2>/dev/null | cut -f1)"
  fi
done

say "  packages:"
command -v dpkg >/dev/null 2>&1 && dpkg -l neovim 2>/dev/null | grep -q '^ii' && { printf '    apt: neovim\n'; FOUND=1; }
command -v snap >/dev/null 2>&1 && snap list nvim >/dev/null 2>&1 && { printf '    snap: nvim\n'; FOUND=1; }
command -v flatpak >/dev/null 2>&1 && flatpak list --app 2>/dev/null | grep -qi neovim && { printf '    flatpak: io.neovim.nvim\n'; FOUND=1; }

[ "$FOUND" = 1 ] || { ok "nothing found — already clean"; exit 0; }

# ---------------------------------------------------------------------------
head_ "2. Binaries and installation trees"

if ask "Remove every nvim binary and installation tree?"; then
  # Sweep PATH first: this is what makes the removal actually take effect.
  IFS=: read -r -a PATH_DIRS <<< "$PATH"
  for d in "${PATH_DIRS[@]}"; do
    [ -n "$d" ] && [ -e "$d/nvim" ] && nuke "$d/nvim"
  done

  for p in /usr/local/bin/nvim /usr/local/bin/nvim.appimage \
           "$HOME/.local/bin/nvim" "$HOME/.local/bin/nvim.appimage" "$HOME/bin/nvim"; do
    nuke "$p"
  done

  printf '%s\n' "$TREES" | grep -v '^$' | while read -r t; do nuke "$t"; done
  nuke /usr/local/share/nvim

  hash -r 2>/dev/null || true
else
  info "skipped"
fi

# ---------------------------------------------------------------------------
head_ "3. Package-manager installations"

if command -v dpkg >/dev/null 2>&1 && dpkg -l neovim 2>/dev/null | grep -q '^ii'; then
  if ask "Purge the apt neovim package?"; then
    if [ "$DRY" = 1 ]; then
      info "would run: sudo apt-get purge -y neovim neovim-runtime"
    else
      sudo apt-get purge -y neovim neovim-runtime && ok "apt package purged"
    fi
  fi
else
  info "no apt package"
fi

if command -v snap >/dev/null 2>&1 && snap list nvim >/dev/null 2>&1; then
  ask "Remove the nvim snap?" && { [ "$DRY" = 1 ] && info "would run: sudo snap remove nvim" || sudo snap remove nvim; }
else
  info "no snap package"
fi

if command -v flatpak >/dev/null 2>&1 && flatpak list --app 2>/dev/null | grep -qi neovim; then
  ask "Remove the Neovim flatpak?" && { [ "$DRY" = 1 ] && info "would run: flatpak uninstall -y io.neovim.nvim" || flatpak uninstall -y io.neovim.nvim; }
else
  info "no flatpak app"
fi

# ---------------------------------------------------------------------------
head_ "4. Configuration"

if [ "$KEEP_CONFIG" = 1 ]; then
  info "keeping configuration (--keep-config)"
elif [ -n "$CONFIGS" ]; then
  printf '%s\n' "$CONFIGS" | while read -r c; do
    if ask "Remove $c?"; then nuke "$c"; fi
  done
else
  info "no configuration directories"
fi

# ---------------------------------------------------------------------------
head_ "5. Plugins, mason, parsers, shada, undo"

say "  ~/.local/share/nvim   lazy plugins, mason packages, treesitter parsers"
say "  ~/.local/state/nvim   shada, swap, undo, logs"
say "  ~/.cache/nvim         luac and treesitter build cache"
say "  All of it is regenerated on the next start."
say ""

if ask "Remove all Neovim state?"; then
  nuke "$HOME/.local/share/nvim"
  nuke "$HOME/.local/state/nvim"
  nuke "$HOME/.cache/nvim"
else
  warn "keeping state — plugins compiled against a different Neovim API are a"
  warn "common source of errors after a version change"
fi

# ---------------------------------------------------------------------------
head_ "Result"

hash -r 2>/dev/null || true
if command -v nvim >/dev/null 2>&1; then
  bad "nvim is still reachable: $(command -v nvim)"
  which -a nvim | sed 's/^/    /'
  warn "if this is unexpected, it is outside every path this script checks"
else
  ok "no nvim on PATH"
fi

for p in "$HOME/.config/nvim" "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"; do
  [ -e "$p" ] && warn "still present: $p" || ok "gone: $p"
done

printf '\nNext: ./install-neovim.sh\n\n'
