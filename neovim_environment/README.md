# Neovim environment

A LazyVim-based Python IDE, pinned by `lazy-lock.json`, with the conda
environment handling actually working.

## Quick start

Two scripts, both standalone. Neither runs `apt update` or `apt upgrade`.

```bash
cd neovim_environment

./purge-neovim.sh        # remove every existing Neovim, binaries and state
./install-neovim.sh      # install Neovim, tools and this config
./install-ai-clis.sh     # Claude Code + OpenAI Codex (interactive login after)
```

`install-neovim.sh` checks its system prerequisites and, if any are missing,
prints the exact `apt install` line and stops. Install them yourself, re-run.

Flags: `-y` (no prompts), `--dry-run` (purge only), `--keep-config` (purge only),
`--no-bootstrap` (skip plugin download), `--config PATH`.

Then, in a **new** shell:

```
nvim file.py
<leader>cv     select ml-dev or llm-dev
Ctrl+/         terminal — `which python` must show the selected env
<leader>cV     environment diagnostics if it does not
```

### basedpyright runs on its strict default

`config/lua/plugins/` contains no `lsp.lua`, so basedpyright uses its own
default `typeCheckingMode = "recommended"` — effectively `"all"`. That is the
strictest setting and it reports every untyped third-party call.

To quiet it, either enable the optional file globally:

```bash
cp config/optional/lsp-quiet.lua ~/.config/nvim/lua/plugins/lsp.lua
```

or set it per project in `pyproject.toml`, which overrides the editor entirely.
See `config/optional/README.md`.

### AI: Claude Code and Codex

`config/lua/plugins/ai.lua` configures sidekick with `<leader>ac` for Claude and
`<leader>ao` for Codex, and disables Copilot NES. The binaries come from
`./install-ai-clis.sh`; sign-in is a browser flow you run once.

### `~/.config/nvim` is a real directory

`install-neovim.sh` copies. It never creates a symlink. Edit `~/.config/nvim`
however you like; this repo is unaffected. To send an edit back:

```bash
cp -a ~/.config/nvim/lua/. <repo>/neovim_environment/config/lua/
```

### What gets installed where

| Path                        | What                                          |
| --------------------------- | --------------------------------------------- |
| `~/.local/opt/nvim-0.12.5/` | the Neovim tree; rollback is a symlink change |
| `~/.local/bin/nvim`         | symlink into it                               |
| `~/.local/bin/tree-sitter`  | parser compiler, pinned ≥ 0.26.1              |
| `~/.local/bin/lazygit`      | git TUI, bound to `<leader>gg`                |
| `~/.config/nvim/`           | this config, copied                           |
| `~/.local/share/nvim/`      | plugins, mason packages, parsers (downloaded) |

---

## System packages

Installed by `scripts/00-system-packages.sh`.

| Package                                       | Needed by                                                                                                                                                    |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `build-essential`                             | nvim-treesitter (`main` branch) compiles every parser from C                                                                                                 |
| `curl`, `wget`, `tar`, `unzip`, `gzip`, `git` | release downloads; treesitter shells out to curl+tar for parser sources                                                                                      |
| `ripgrep`                                     | Snacks.picker and grug-far grep backend                                                                                                                      |
| `fd-find`                                     | venv-selector's searches are `fd` invocations (`$FD` in the spec). Debian installs it as `fdfind`; the plugin probes `fd`, `fdfind`, `fd_find` in that order |
| `fzf`                                         | fzf-lua's backend binary                                                                                                                                     |
| `xclip`, `wl-clipboard`                       | `clipboard=unnamedplus` needs a provider (X11/XWayland and Wayland respectively)                                                                             |
| `nodejs` (≥ 18), `npm`                        | mason installs yaml-language-server, dockerfile-language-server, json-lsp, markdownlint-cli2, prettier as npm packages                                       |
| `python3`, `python3-pip`, `python3-venv`      | mason installs ruff/black/isort/debugpy via pip                                                                                                              |
| `fontconfig`                                  | Nerd Font resolution on a desktop; irrelevant headless                                                                                                       |

Two binaries are **not** from apt because the distribution versions are too old:

| Binary        | Version  | Source                                                                                              | Why not apt                                                                                   |
| ------------- | -------- | --------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `nvim`        | v0.12.5  | GitHub release tarball → `~/.local/share/nvim-releases/<version>`, symlinked to `~/.local/bin/nvim` | nvim-treesitter `main` requires Neovim ≥ 0.12.0; Ubuntu ships far behind                      |
| `tree-sitter` | ≥ 0.26.1 | GitHub release binary → `~/.local/bin/tree-sitter`                                                  | nvim-treesitter's README requires ≥ 0.26.1 and explicitly says **not** to install it from npm |

Versioning the Neovim install under `nvim-releases/<version>` makes a rollback
a symlink change rather than a reinstall.

## Configuration layout

```
config/
├── init.lua                    require("config.lazy")
├── lazy-lock.json              plugin commit pins — this is the reproducibility
├── lazyvim.json                enabled LazyVim extras
├── .stylua.toml                formatting for the config itself
└── lua/
    ├── config/
    │   ├── lazy.lua            bootstrap + lazy.nvim setup
    │   ├── options.lua         basedpyright as the Python LSP, editor options
    │   ├── keymaps.lua         env-aware terminal override, run-file, diagnostics
    │   └── autocmds.lua        pristine-PATH capture, "no env selected" warning
    └── plugins/
        ├── python.lua          venv-selector: conda state + terminal invalidation
        ├── lsp.lua             basedpyright analysis settings
        ├── formatting.lua      conform: ruff_fix → isort(--profile black) → black
        ├── tools.lua           mason-tool-installer package list
        ├── xml.lua             lemminx + xml parser
        ├── git.lua             diffview
        ├── ai.lua              sidekick: Claude Code / Codex
        ├── neogen.lua          docstring generation
        └── noice.lua           change pop-up cmdline to bottomline toolbar
```

### Enabled LazyVim extras

`ai.sidekick`, `dap.core`, `formatting.black`, `formatting.prettier`,
`lang.docker`, `lang.git`, `lang.json`, `lang.markdown`, `lang.python`,
`lang.toml`, `lang.yaml`, `test.core`, `util.dot`.

### Tooling installed by mason

| Group           | Tools                                                                                   |
| --------------- | --------------------------------------------------------------------------------------- |
| Python          | `basedpyright`, `ruff`, `black`, `isort`, `debugpy`                                     |
| Markup / config | `marksman`, `markdownlint-cli2`, `yaml-language-server`, `json-lsp`, `taplo`, `lemminx` |
| Docker / CI     | `dockerfile-language-server`, `docker-compose-language-service`, `actionlint`           |
| Lua / shell     | `lua-language-server`, `stylua`, `shellcheck`, `shfmt`, `prettier`                      |

## Keymaps

Only what this config adds or overrides; LazyVim's defaults are unchanged.

| Key                         | Action                                                                                        |
| --------------------------- | --------------------------------------------------------------------------------------------- |
| `<leader>cv`                | select a Python environment (LazyVim default, ft=python)                                      |
| `<leader>cV`                | **environment diagnostics** — interpreter, conda vars, `PATH[1]`, basedpyright's `pythonPath` |
| `Ctrl+/`, `Ctrl+_`          | terminal at project root, **with the active environment** (override)                          |
| `<leader>ft` / `<leader>fT` | terminal at root / cwd, with the active environment                                           |
| `<leader>rp`                | write and run the current Python file with the selected interpreter                           |
| `Ctrl+p`                    | find files                                                                                    |
| `Ctrl+b`                    | toggle explorer                                                                               |
| `F5` / `F9` / `F6` / `F7`   | continue / breakpoint / step over / step into                                                 |
| `<leader>cg`                | generate a docstring (neogen)                                                                 |
| `<leader>gD` / `<leader>gH` | diffview / file history                                                                       |
| `<leader>ac` / `<leader>ao` | Claude Code / OpenAI Codex                                                                    |

## Scripts

| Script               | Does                                                                                                                                                                                                                         |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `purge-neovim.sh`    | inventory, then remove: every `nvim` on `PATH`, installation trees under `~/.local/opt` `~/opt` `/opt`, apt/snap/flatpak packages, `~/.config/nvim*`, plugins, mason, parsers, shada. Five scopes, each confirmed separately |
| `install-ai-clis.sh` | Claude Code (native installer) and OpenAI Codex (npm), plus the npm-prefix fix so global installs do not need sudo. Sign-in stays manual: both need a browser                                                                |
| `install-neovim.sh`  | prerequisite gate (reports, never installs), PATH check and shadow removal, Neovim tarball, tree-sitter CLI, LazyGit, config copy, `Lazy! restore`, `MasonToolsInstallSync`, parser build, verification                      |

`install-neovim.sh` runs `Lazy! restore`, not `Lazy! sync`. Restore installs
exactly the commits in `lazy-lock.json`; sync would rewrite the lockfile and
throw away the pinning. To update deliberately: open Neovim, `:Lazy sync`, then
copy the changed `lazy-lock.json` back to this repo.

## Verification

`30-verify.sh` does more than check that files exist. Two checks are the point:

**The terminal test.** It launches `bash -i` with only environment variables
set — exactly what Neovim does — and asserts that `command -v python` still
resolves inside the environment afterwards. If `~/.bashrc` re-activates base,
this fails.

**The basedpyright test.** It writes a probe file that touches
`tf.keras.layers.LSTM`, `pd.DataFrame`, `np.zeros` and
`RandomForestClassifier`, runs the mason-installed `basedpyright` against the
`ml-dev` interpreter with `--outputjson`, and asserts zero errors. A
`reportAttributeAccessIssue` on `tf.keras` means `types-tensorflow` is missing.

python_environment/config/pyproject.template.toml`.
