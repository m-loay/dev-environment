#!/usr/bin/env bash
#
# install-ai-clis.sh — install Claude Code and OpenAI Codex, the two CLIs that
# sidekick.nvim drives from inside Neovim.
#
# Kept separate from install-neovim.sh because both tools need an interactive
# browser login, which does not belong in an unattended installer. This script
# installs the binaries and then tells you what to run; it never tries to
# automate the sign-in.
#
#   ./install-ai-clis.sh            both
#   ./install-ai-clis.sh --claude   Claude Code only
#   ./install-ai-clis.sh --codex    Codex only
#
# Keymaps provided by config/lua/plugins/ai.lua:
#   <leader>ac   Claude Code
#   <leader>ao   OpenAI Codex
#   <leader>aa   toggle the current sidekick CLI   (LazyVim sidekick extra)
#   <leader>as   choose which CLI
#   <C-.>        focus the sidekick window

set -uo pipefail

DO_CLAUDE=1
DO_CODEX=1

for a in "$@"; do
  case "$a" in
    --claude) DO_CODEX=0 ;;
    --codex)  DO_CLAUDE=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown flag: $a" >&2; exit 1 ;;
  esac
done

if [ -t 1 ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else
  R=""; G=""; Y=""; B=""; D=""; N=""
fi

step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
info() { printf '  %s·%s %s\n' "$D" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

# ---------------------------------------------------------------------------
step "npm global prefix"

# Codex installs through npm. On a default Debian setup, `npm install -g` writes
# to /usr/local/lib/node_modules and fails with EACCES. Repeatedly working
# around that with `sudo npm install -g` leaves root-owned packages in a
# user-facing tree, so point the prefix at $HOME instead. One-time change.
if have npm; then
  PREFIX="$(npm config get prefix 2>/dev/null)"
  if [ "$PREFIX" = "$HOME/.local" ]; then
    ok "npm prefix already $HOME/.local"
  elif [ -w "$PREFIX/lib/node_modules" ] 2>/dev/null; then
    ok "npm prefix $PREFIX is writable, leaving it alone"
  else
    warn "npm prefix is $PREFIX (not writable without sudo)"
    npm config set prefix "$HOME/.local" && ok "npm prefix set to $HOME/.local"
  fi
else
  warn "npm not found — Codex cannot be installed"
  DO_CODEX=0
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ok "$BIN_DIR is on PATH" ;;
  *) warn "$BIN_DIR is not on PATH; add it to ~/.bashrc"
     export PATH="$BIN_DIR:$PATH" ;;
esac

# ---------------------------------------------------------------------------
if [ "$DO_CLAUDE" = 1 ]; then
  step "Claude Code"

  if have claude; then
    ok "already installed: $(command -v claude)  $(claude --version 2>/dev/null)"
  else
    have curl || { bad "curl not found"; exit 1; }
    info "running Anthropic's native installer"
    # The native installer is what Anthropic recommends on Linux; the npm
    # package is not the supported path there.
    curl -fsSL https://claude.ai/install.sh | bash
    hash -r 2>/dev/null || true
    if have claude; then
      ok "installed: $(command -v claude)"
    else
      bad "claude not on PATH after install — check the installer output above"
    fi
  fi
fi

# ---------------------------------------------------------------------------
if [ "$DO_CODEX" = 1 ]; then
  step "OpenAI Codex"

  if have codex; then
    ok "already installed: $(command -v codex)  $(codex --version 2>/dev/null)"
  else
    info "npm i -g @openai/codex"
    if npm i -g @openai/codex; then
      hash -r 2>/dev/null || true
      have codex && ok "installed: $(command -v codex)" \
                 || bad "codex not on PATH after install"
    else
      bad "npm install failed"
      warn "if this was EACCES under /usr/local, re-run: the prefix step above"
      warn "should have moved global installs to $HOME/.local"
    fi
  fi
fi

# ---------------------------------------------------------------------------
step "Next: sign in"

printf '\n  Both tools need an interactive login once. Run each and follow the\n'
printf '  browser prompt:\n\n'
have claude && printf '    claude          # then: claude doctor\n'
have codex  && printf '    codex\n'
printf '\n  Then, inside Neovim:\n\n'
printf '    :checkhealth sidekick     both should show as installed\n'
printf '    <leader>ac                Claude Code\n'
printf '    <leader>ao                OpenAI Codex\n'
printf '    <leader>as                pick a CLI\n'
printf '    <C-.>                     focus the AI window\n\n'
