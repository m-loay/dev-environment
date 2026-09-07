#!/usr/bin/env bash
#
# install-neovim.sh — install Neovim, its external tools, and this config.
#
# Standalone: no other file from this repo is needed except ./config.
# Runs NO apt commands. If a system package is missing it prints the exact
# apt line and stops, so you install it yourself.
#
#   ./install-neovim.sh                 install everything, ask before replacing
#   ./install-neovim.sh -y              no prompts
#   ./install-neovim.sh --no-bootstrap  skip plugin/LSP download
#   ./install-neovim.sh --config PATH   use a different config directory
#
# Installs to:
#   ~/.local/opt/nvim-<version>/    the Neovim tree
#   ~/.local/bin/nvim               symlink to it
#   ~/.local/bin/tree-sitter        parser compiler CLI
#   ~/.local/bin/lazygit            git TUI, bound to <leader>gg
#   ~/.config/nvim/                 a REAL DIRECTORY, copied — never a symlink

set -uo pipefail

NVIM_VERSION="${NVIM_VERSION:-0.12.5}"
LAZYGIT_VERSION="${LAZYGIT_VERSION:-0.64.0}"
TREESITTER_MIN="0.26.1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/config"
CONFIG_DST="${NVIM_CONFIG_DIR:-$HOME/.config/nvim}"
BIN_DIR="$HOME/.local/bin"
OPT_DIR="$HOME/.local/opt"

YES=0
BOOTSTRAP=1

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)       YES=1 ;;
    --no-bootstrap) BOOTSTRAP=0 ;;
    --config)       CONFIG_SRC="$2"; shift ;;
    -h|--help)      sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ -t 1 ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else
  R=""; G=""; Y=""; B=""; D=""; N=""
fi

STEP=0
step() { STEP=$((STEP+1)); printf '\n%s[%d/8] %s%s\n' "$B" "$STEP" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
info() { printf '  %s·%s %s\n' "$D" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; exit 1; }

ask() {
  [ "$YES" = 1 ] && { info "$1 -> yes"; return 0; }
  [ -t 0 ] || return 0
  printf '  %s?%s %s [Y/n] ' "$Y" "$N" "$1"
  read -r r || r=""
  case "${r:-y}" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

have() { command -v "$1" >/dev/null 2>&1; }

case "$(uname -m)" in
  x86_64|amd64)  NVIM_ARCH="x86_64"; LG_ARCH="x86_64"; TS_ARCH="x64" ;;
  aarch64|arm64) NVIM_ARCH="arm64";  LG_ARCH="arm64";  TS_ARCH="arm64" ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

# ---------------------------------------------------------------------------
step "System prerequisites"

# Deliberately does not install anything. Missing packages are reported with
# the command to run, and the script stops.
MISSING=""
need() { have "$1" || MISSING="$MISSING $2"; }

need curl curl
need tar tar
need gzip gzip
need git git
need cc build-essential          # treesitter compiles every parser from C
need rg ripgrep                  # Snacks.picker / grug-far grep backend
need fzf fzf                     # fzf-lua backend
need node nodejs                 # mason installs npm-based language servers
need npm npm
need python3 python3             # mason installs ruff/black/isort/debugpy

if ! have fd && ! have fdfind; then
  MISSING="$MISSING fd-find"     # venv-selector's searches are fd invocations
fi

if [ -n "$MISSING" ]; then
  printf '  %s✗%s missing system packages:%s\n' "$R" "$N" "$MISSING"
  printf '\n  Install them, then re-run this script:\n\n'
  printf '    sudo apt install -y%s\n\n' "$MISSING"
  exit 1
fi
ok "all system prerequisites present"

if have node; then
  NODE_MAJOR="$(node --version | sed 's/^v//' | cut -d. -f1)"
  if [ "$NODE_MAJOR" -ge 18 ]; then
    ok "node $(node --version)"
  else
    warn "node $(node --version) is below 18; several mason packages will fail"
  fi
fi

# Debian installs fd as fdfind. venv-selector probes fd, fdfind, fd_find in
# that order, so either works, but a plain `fd` is convenient.
mkdir -p "$BIN_DIR" "$OPT_DIR"
if ! have fd && have fdfind; then
  ln -sf "$(command -v fdfind)" "$BIN_DIR/fd"
  ok "linked fdfind -> $BIN_DIR/fd"
fi

# ---------------------------------------------------------------------------
step "PATH"

case ":$PATH:" in
  *":$BIN_DIR:"*) ok "$BIN_DIR is on PATH" ;;
  *)
    warn "$BIN_DIR is not on PATH"
    if ask "Add it to ~/.bashrc?"; then
      printf '\n# Neovim and friends\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
      ok "added to ~/.bashrc (new shells only)"
    fi
    export PATH="$BIN_DIR:$PATH"
    ;;
esac

# A second installation earlier on PATH means everything below installs
# correctly and none of it is what runs. Deal with it now, not at the end.
if have nvim && [ "$(command -v nvim)" != "$BIN_DIR/nvim" ]; then
  OTHER="$(command -v nvim)"
  warn "another nvim is earlier on PATH: $OTHER"
  warn "it would keep winning after this install"
  if ask "Remove it?"; then
    TARGET="$(readlink -f "$OTHER" 2>/dev/null || echo "$OTHER")"
    if [ -w "$(dirname "$OTHER")" ]; then rm -f "$OTHER"; else sudo rm -f "$OTHER"; fi
    ok "removed $OTHER"
    TREE="$(dirname "$(dirname "$TARGET")")"
    case "$TREE" in
      *nvim*|*neovim*)
        if [ -d "$TREE" ] && ask "Also remove its tree $TREE?"; then
          if [ -w "$(dirname "$TREE")" ]; then rm -rf "$TREE"; else sudo rm -rf "$TREE"; fi
          ok "removed $TREE"
        fi
        ;;
    esac
    hash -r 2>/dev/null || true
  else
    warn "continuing — the pinned version will be installed but not used"
  fi
fi

# ---------------------------------------------------------------------------
step "Neovim $NVIM_VERSION"

NVIM_TREE="$OPT_DIR/nvim-$NVIM_VERSION"

if [ -x "$NVIM_TREE/bin/nvim" ] && ! ask "Neovim $NVIM_VERSION is already unpacked. Reinstall?"; then
  info "reusing $NVIM_TREE"
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  URL="https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz"
  info "downloading $URL"
  curl -fL --retry 3 --progress-bar -o "$TMP/nvim.tar.gz" "$URL" \
    || die "download failed — check that v$NVIM_VERSION exists"

  # A proxy can serve an HTML error page with a 200 status; check the gzip
  # magic bytes rather than trusting the exit code.
  MAGIC="$(head -c2 "$TMP/nvim.tar.gz" | od -An -tx1 | tr -d ' \n')"
  [ "$MAGIC" = "1f8b" ] || die "downloaded file is not a gzip archive (magic=$MAGIC)"

  tar -xzf "$TMP/nvim.tar.gz" -C "$TMP" || die "extraction failed"
  SRC="$(find "$TMP" -maxdepth 1 -type d -name 'nvim-linux*' | head -n1)"
  [ -n "$SRC" ] || die "unexpected archive layout"

  rm -rf "$NVIM_TREE"
  mv "$SRC" "$NVIM_TREE"
  ok "unpacked to $NVIM_TREE"
fi

ln -sfn "$NVIM_TREE/bin/nvim" "$BIN_DIR/nvim"
hash -r 2>/dev/null || true
ok "$BIN_DIR/nvim -> $NVIM_TREE/bin/nvim"
ok "$(nvim --version | head -n1)"

# ---------------------------------------------------------------------------
step "tree-sitter CLI"

# nvim-treesitter's main branch requires >= 0.26.1 and its README says to
# install it from a release binary, not npm: the npm package ships a different
# layout and the parser build shells out expecting the native one.
ts_version_ok() {
  have tree-sitter || return 1
  v="$(tree-sitter --version 2>/dev/null | awk '{print $2}')" || return 1
  [ "$(printf '%s\n%s\n' "$TREESITTER_MIN" "$v" | sort -V | head -n1)" = "$TREESITTER_MIN" ]
}

if ts_version_ok; then
  ok "tree-sitter $(tree-sitter --version | awk '{print $2}') (>= $TREESITTER_MIN)"
else
  TMP2="$(mktemp -d)"
  URL="https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-${TS_ARCH}.gz"
  info "downloading $URL"
  curl -fL --retry 3 --progress-bar -o "$TMP2/ts.gz" "$URL" || die "tree-sitter download failed"
  gunzip -f "$TMP2/ts.gz" || die "gunzip failed"
  install -m 0755 "$TMP2/ts" "$BIN_DIR/tree-sitter"
  rm -rf "$TMP2"
  hash -r 2>/dev/null || true
  ok "tree-sitter $(tree-sitter --version | awk '{print $2}')"
fi

# ---------------------------------------------------------------------------
step "LazyGit $LAZYGIT_VERSION"

# LazyVim binds <leader>gg to LazyGit but does not install the binary.
if have lazygit; then
  ok "lazygit already installed: $(command -v lazygit)"
else
  TMP3="$(mktemp -d)"
  URL="https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_${LG_ARCH}.tar.gz"
  info "downloading $URL"
  if curl -fL --retry 3 --progress-bar -o "$TMP3/lg.tar.gz" "$URL" \
     && tar -xzf "$TMP3/lg.tar.gz" -C "$TMP3" lazygit; then
    install -m 0755 "$TMP3/lazygit" "$BIN_DIR/lazygit"
    ok "installed $BIN_DIR/lazygit"
  else
    warn "lazygit install failed — <leader>gg will not work, everything else is fine"
  fi
  rm -rf "$TMP3"
fi

# ---------------------------------------------------------------------------
step "Configuration"

[ -d "$CONFIG_SRC" ] || die "config directory not found: $CONFIG_SRC"
[ -f "$CONFIG_SRC/init.lua" ] || die "$CONFIG_SRC does not look like a Neovim config (no init.lua)"

if [ -L "$CONFIG_DST" ]; then
  warn "$CONFIG_DST is a SYMLINK -> $(readlink -f "$CONFIG_DST")"
  warn "that target is what Neovim has been loading until now"
  ask "Replace it with a real directory?" || die "aborted"
  mv "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d-%H%M%S)"
  ok "symlink moved aside"
elif [ -d "$CONFIG_DST" ]; then
  info "$CONFIG_DST exists ($(find "$CONFIG_DST" -type f | wc -l) files)"
  ask "Back it up and replace it?" || die "aborted"
  mv "$CONFIG_DST" "$CONFIG_DST.bak.$(date +%Y%m%d-%H%M%S)"
  ok "backed up"
fi

mkdir -p "$CONFIG_DST"
# `optional/` holds files that are deliberately not loaded; excluding it keeps
# ~/.config/nvim to exactly what Neovim reads.
( cd "$CONFIG_SRC" && tar --exclude=./optional -cf - . ) | ( cd "$CONFIG_DST" && tar -xf - )
ok "copied $(find "$CONFIG_SRC" -type f -not -path '*/optional/*' | wc -l) files to $CONFIG_DST"
info "a real directory: edit it freely, this repo is not affected"

if [ -f "$CONFIG_DST/lazy-lock.json" ]; then
  ok "lazy-lock.json present — plugin versions pinned"
else
  warn "no lazy-lock.json; plugin versions will float"
fi

# ---------------------------------------------------------------------------
step "Plugins, language servers, parsers"

if [ "$BOOTSTRAP" = 0 ]; then
  info "skipped (--no-bootstrap); they install on first start instead"
else
  # restore, not sync: restore installs exactly the commits in lazy-lock.json,
  # sync would rewrite the lockfile and throw the pinning away.
  # Every headless invocation gets </dev/null and a timeout.
  #
  # Without </dev/null, a headless nvim that hits any error prints it and then
  # BLOCKS on the "Press ENTER or type command to continue" prompt, waiting on
  # a terminal that is not going to answer. That is a hang with no output, not
  # a failure. TSUpdateSync in particular does not exist on nvim-treesitter's
  # main branch — it is a master-branch command — so it raises E492 every time
  # and hangs there.
  #
  # `silent!` suppresses the message so the prompt is never raised at all;
  # </dev/null guarantees it cannot block even if something else prints.
  headless() {
    timeout "${2:-900}" nvim --headless "+silent! $1" +qa </dev/null 2>&1
  }

  info "lazy.nvim: restoring pinned plugin versions (first run clones ~50 repos)"
  headless "Lazy! restore" 1800 | sed 's/^/    /'

  info "mason: installing language servers and formatters"
  headless "MasonToolsInstallSync" 900 | sed 's/^/    /' \
    || warn "mason reported errors; check :Mason inside Neovim"

  info "treesitter: building parsers (slowest step)"
  # main branch has no TSUpdateSync; call the install API and fall back.
  headless "lua pcall(function() require('nvim-treesitter').install(require('nvim-treesitter.config').get_installed()):wait(600000) end)" 900 >/dev/null \
    || warn "parsers did not build headlessly; they build on first file open"
fi

# ---------------------------------------------------------------------------
step "Verify"

FAIL=0
check() {
  # </dev/null for the same reason: an eval'd grep that ends up without a
  # filename reads standard input and waits forever.
  if eval "$2" </dev/null >/dev/null 2>&1; then
    ok "$1"
  else
    printf '  %s✗%s %s\n' "$R" "$N" "$1"
    FAIL=$((FAIL+1))
  fi
}

hash -r 2>/dev/null || true

if [ "$(command -v nvim)" = "$BIN_DIR/nvim" ]; then
  ok "nvim resolves to the managed install"
else
  printf '  %s✗%s nvim resolves to %s, not %s\n' "$R" "$N" "$(command -v nvim)" "$BIN_DIR/nvim"
  which -a nvim | sed 's/^/      /'
  FAIL=$((FAIL+1))
fi

ok "version: $(nvim --version | head -n1)"
check "tree-sitter >= $TREESITTER_MIN"        "ts_version_ok"
check "config: init.lua"                       "[ -f '$CONFIG_DST/init.lua' ]"
check "config: lua/plugins/python.lua"         "[ -f '$CONFIG_DST/lua/plugins/python.lua' ]"
check "config: lua/plugins/ai.lua"             "[ -f '$CONFIG_DST/lua/plugins/ai.lua' ]"
check "config is a real directory, not a link" "[ ! -L '$CONFIG_DST' ]"
check "optional/ not copied"                   "[ ! -d '$CONFIG_DST/optional' ]"

if [ "$BOOTSTRAP" = 1 ]; then
  check "plugins installed"   "[ -d \"$HOME/.local/share/nvim/lazy\" ]"
  check "mason: basedpyright" "[ -x \"$HOME/.local/share/nvim/mason/bin/basedpyright\" ]"
  check "mason: ruff"         "[ -x \"$HOME/.local/share/nvim/mason/bin/ruff\" ]"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '%s✓ Neovim is ready%s\n\n' "$G" "$N"
  printf '  Open a NEW shell, then:\n'
  printf '    nvim file.py\n'
  printf '    <leader>cv    select a conda environment\n'
  printf '    Ctrl+/        terminal — `which python` shows the selected env\n'
  printf '    <leader>cV    environment diagnostics if it does not\n\n'
  exit 0
fi
printf '%s✗ %d check(s) failed%s\n\n' "$R" "$FAIL" "$N"
exit 1
