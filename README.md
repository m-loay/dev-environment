# dev-environment

Reproducible Python and Neovim development environment for ML / LLM work on
Debian/Ubuntu (including WSL2). Clone, run one script, get the same machine.

## Layout

```
dev-environment/
├── bootstrap.sh              both halves, in the right order
├── lib/common.sh             shared logging, progress, prompts
│
├── python_environment/
│   ├── README.md             system packages, architecture, typing rules
│   ├── requirements/         layered: base + stubs + ml-dev / llm-dev
│   ├── config/               environments.conf, condarc, pyproject template
│   └── scripts/              00 system · 10 conda · 20 envs · 30 verify
│
└── neovim_environment/
    ├── README.md             system packages, plugins, keymaps, the bug analysis
    ├── config/               the whole ~/.config/nvim tree, lazy-lock pinned
    └── scripts/              00 system · 05 purge · 10 nvim · 20 config · 30 verify
```

## New machine

```bash
git clone <this-repo> ~/dev-environment
cd ~/dev-environment
./bootstrap.sh --yes
exec "$SHELL" -l          # pick up the new PATH and conda init
```

`bootstrap.sh` runs the Python half first on purpose: the Neovim verification
step type-checks a probe file against the `ml-dev` interpreter, which has to
exist by then.

## Piecemeal

```bash
./python_environment/scripts/install.sh --yes
./neovim_environment/scripts/install.sh --yes --purge
```

Or step by step — every script is standalone, idempotent and safe to re-run.

## Flags

| Flag | Effect |
|---|---|
| `--yes` / `-y` | answer every prompt with the default; required for unattended runs |
| `--dry-run` | print what would happen, change nothing |
| `--skip-system` | skip apt (already provisioned, or not root-capable) |
| `--recreate` | Python only: destroy and rebuild the conda environments |
| `--purge` | Neovim only: remove every existing Neovim first |
| `--link` | Neovim only: symlink `~/.config/nvim` into this repo instead of copying |

`--link` is right on a workstation where you iterate on the config and commit
the result. `--copy` (the default) is right on a server, where you do not want
an accidental edit inside the editor to modify a git working tree.

## What gets written outside the repo

| Path | Written by | Contents |
|---|---|---|
| `~/miniforge3` | `10-install-conda.sh` | conda, only if none exists |
| `~/.condarc` | `10-install-conda.sh` | conda-forge, strict priority, **base auto-activation off** |
| `~/miniforge3/envs/{ml-dev,llm-dev}` | `20-create-environments.sh` | the environments |
| `~/.local/share/nvim-releases/<ver>` | `10-install-neovim.sh` | versioned Neovim, symlinked to `~/.local/bin/nvim` |
| `~/.local/bin/{nvim,tree-sitter,fd}` | `10-install-neovim.sh`, `00-system-packages.sh` | binaries and the fd alias |
| `~/.config/nvim` | `20-install-config.sh` | the editor config (copy or symlink) |
| `~/.config/dev-environment/` | several | resolved conda root, PATH snippets sourced from `~/.profile` and the shell rc files |
| `~/.local/state/dev-environment/logs/` | all | one timestamped log per run |

Anything pre-existing at those paths is moved aside with a `.bak.<timestamp>`
suffix rather than deleted. The one exception is `05-purge-neovim.sh`, whose
entire job is deletion — it confirms each of its three scopes separately, and
`--keep-config` opts out of touching `~/.config/nvim*`.

## Updating

Plugin versions are pinned in `neovim_environment/config/lazy-lock.json`, which
is why a rebuild six months from now produces the same editor. To move forward
deliberately:

```bash
nvim                       # :Lazy sync
cp ~/.config/nvim/lazy-lock.json neovim_environment/config/lazy-lock.json
git commit -am "chore: update plugin pins"
```

Python versions are intentionally unpinned in `requirements/`, so a rebuild
picks up current wheels. If you need byte-identical environments across
machines, freeze after a verified build:

```bash
conda activate ml-dev
pip freeze > python_environment/requirements/ml-dev.lock.txt
```

and install from the lock file instead.

## Reading order

If something is wrong, the mechanism is documented rather than just the fix:

- `python_environment/README.md` — typing rules, why `scikit-learn-stubs` is
  excluded, why TensorFlow needs stubs and scikit-learn does not.
- `neovim_environment/README.md` — the four defects behind "Ctrl+/ opens in
  base" and "autocomplete is broken", with the upstream source that causes each.

## Requirements

Debian or Ubuntu (24.04+ tested; older releases handled where the package names
differ), `sudo` for the apt steps only, and roughly 15 GB of disk for both
environments plus the editor toolchain.
