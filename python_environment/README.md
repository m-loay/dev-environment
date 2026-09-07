# Python environment

Reproducible conda environments for ML and LLM work, built so that Neovim,
the CLI, pre-commit and CI all resolve the same interpreter and the same types.

## Quick start

```bash
cd python_environment/scripts
./install.sh                # interactive
./install.sh --yes          # unattended (fresh server)
./install.sh --recreate     # destroy and rebuild the environments
```

Then open a **new** shell (the conda init block is only read at startup) and:

```bash
conda activate ml-dev
python -c "import tensorflow as tf; print(tf.__version__)"
```

## Architecture

Two environments, one shared base, one shared stub layer.

```
requirements/
├── constraints.txt   version bounds applied to every install (-c)
├── base.txt          config, serving, storage, MLOps, Jupyter, test tooling
├── stubs.txt         type stubs consumed by basedpyright
│
├── ml-dev.txt        -r base.txt  -r stubs.txt  + numeric/DL/CV stack
├── llm-dev.txt       -r base.txt  -r stubs.txt  + transformers/LangChain/RAG
│
├── gpu-optional.txt  bitsandbytes, xformers, flash-attn, vllm  (never auto-installed)
└── aws-extra.txt     sagemaker                                  (never auto-installed)
```

```
ml-dev                                  llm-dev
├─ numpy scipy pandas scikit-learn      ├─ torch transformers datasets peft trl
├─ xgboost lightgbm optuna              ├─ langchain langgraph langsmith
├─ tensorflow + types-tensorflow        ├─ openai anthropic cohere litellm
├─ opencv-python-headless Pillow        ├─ qdrant-client chromadb faiss-cpu
├─ h5py pyarrow fastparquet             ├─ pymupdf pypdf beautifulsoup4
└─ matplotlib seaborn netron            └─ SQLAlchemy alembic asyncpg psycopg2
             \                                    /
              \____________ base.txt ____________/
                 mlflow dvc boto3 fastapi typer
                 pytest ruff black isort mypy
                 jupyterlab ipykernel pynvim
```

### Why two environments and not one

`transformers` and `accelerate` pin torch; TensorFlow pins protobuf and numpy.
In one environment every upgrade becomes a resolver negotiation, and the usual
outcome is a silent numpy downgrade that breaks wheels compiled against the
newer ABI. Two environments cost one keystroke in Neovim (`<leader>cv`) and
remove the entire class of problem.

### Why conda provides only the interpreter

`conda create` installs Python, pip, setuptools, wheel — nothing else. Every
library comes from PyPI. Mixing conda-forge builds and pip wheels in one
environment is the most common cause of "it solved fine and then segfaulted on
import", because the two resolvers do not share a view of ABI compatibility.

### Why Python 3.12

It is the only version that satisfies both ends of the stack:

| Package | Constraint |
|---|---|
| TensorFlow 2.21 | wheels for cp310–cp313 |
| numpy 2.5 | `requires-python >= 3.12` |
| scipy 1.18 | `requires-python >= 3.12` |
| pandas 3.0 | `requires-python >= 3.11` |

Change it in `config/environments.conf` if a project forces your hand.

### Why Miniforge rather than Anaconda

conda-forge by default, no commercial-use licensing question, and a much
smaller base environment. If an Anaconda or Miniconda installation already
exists the scripts detect and reuse it — nothing is replaced.

## System packages

Installed by `scripts/00-system-packages.sh`. Every entry has a specific
runtime consumer; none is there for general convenience.

| Package | Why |
|---|---|
| `build-essential`, `pkg-config` | some sdists still compile (dvc plugins, arm64 wheels) |
| `curl`, `wget`, `git`, `tar`, `unzip`, `bzip2`, `xz-utils` | fetching and unpacking the Miniforge installer |
| `libgomp1` | scikit-learn, XGBoost and LightGBM `dlopen` `libgomp.so.1`. Missing it fails at `import lightgbm`, not at install time |
| `libglib2.0-0t64` | OpenCV's headless build still links libglib for threading |
| `libssl3`, `zlib1g` | TLS and compression for boto3, httpx, pyarrow |
| `libpq-dev` | only needed if a project pins `psycopg2` rather than `psycopg2-binary` |
| `libhdf5-dev` | only needed if h5py has to build from source (arm64) |
| `locales` | pandas and Jupyter misbehave under a POSIX-only locale |

## Scripts

| Script | Does | Idempotent |
|---|---|---|
| `00-system-packages.sh` | apt packages above | yes |
| `10-install-conda.sh` | detect or install Miniforge, install `~/.condarc`, `conda init`, disable base auto-activation | yes |
| `20-create-environments.sh` | create envs, install layered requirements, register Jupyter kernels | yes (`--recreate` to rebuild) |
| `30-verify.sh` | imports, `pip check`, stub inventory, `tf.keras` resolution, shell behaviour | read-only |
| `install.sh` | all of the above in order | yes |

Flags: `--yes`, `--dry-run`, `--recreate`, `--skip-system`.
Logs go to `~/.local/state/dev-environment/logs/`.

## Typing and autocomplete

The rule used to decide what goes in `requirements/stubs.txt`:

1. **Library ships `py.typed`** (numpy, matplotlib, pydantic, fastapi, mlflow,
   httpx) → install no stubs. Inline types are always in sync with the
   installed version.
2. **Library is untyped but readable** (scikit-learn, OpenCV, XGBoost, dvc) →
   install no stubs. basedpyright's `useLibraryCodeForTypes = true` infers from
   source, which beats any third-party stub that has to be kept up to date.
3. **Library is untyped and hostile to inference** → install stubs. Only two
   cases matter here.

### TensorFlow

`tf.keras` is lazy-loaded inside TensorFlow's `__init__.py`, so no amount of
source inference will resolve `tf.keras.layers.LSTM`. `types-tensorflow` fixes
it, and its `py.typed` contains the single word `partial`, which tells
basedpyright to fall back to real source for everything the stubs do not cover.
That combination is why it is safe to install.

### boto3

Client methods are generated at runtime from JSON service models. Without
`types-boto3` every `client.` completion is empty.

### Deliberately not installed

`scikit-learn-stubs` — a third-party repackage of Microsoft's stubs, last
released `0.0.3` in Aug 2025, and **not** marked partial. It shadows the real
scikit-learn completely, so anything added since then disappears from
completion. `30-verify.sh` detects it by provenance: it maps every installed `*-stubs`
directory back to the distribution that owns it and flags any distribution that
is not a typeshed `types-*` package, `pandas-stubs`, `scipy-stubs` or
`boto3-stubs`. Note that a *complete* stub package (empty `py.typed`) is
normal and correct — `partial` only means the checker may fall back to real
source, which matters for TensorFlow and not for pandas.

### Version coupling

`pandas-stubs` 3.0.x describes pandas 3.x. If a project pins pandas 2.x, pin
`pandas-stubs~=2.2` alongside it — otherwise completions confidently describe
an API that is not installed. The same applies to `types-tensorflow` against
the installed TensorFlow minor.

## Per-project setup

Copy `config/pyproject.template.toml` into a project root and edit `venv`:

```toml
[tool.basedpyright]
venvPath = "~/miniforge3/envs"
venv = "ml-dev"
```

This matters even though `<leader>cv` already works. venv-selector injects
`settings.python.pythonPath` into the running LSP client; that lives and dies
with the Neovim session and is invisible to the basedpyright CLI, pre-commit,
CI and Claude Code. The file is the durable source of truth.

The template also sets `[tool.isort] profile = "black"`, which stops isort and
black rewriting the same import block back and forth on every save.

## Troubleshooting

**`Ctrl+/` in Neovim opens a shell in `base`.**
`conda init` puts an eval of `conda shell.bash hook` in `~/.bashrc`. With
auto-activation on, that hook unconditionally appends `conda activate base`,
which strips the current prefix from `PATH` and prepends `base/bin`. Fix:

```bash
conda config --set auto_activate false        # conda >= 25.x
conda config --set auto_activate_base false   # older alias
```

`30-verify.sh` tests this end to end by launching `bash -i` with an
environment-only activation and checking which `python` survives.

**An existing environment is on the wrong Python version.**
`20-create-environments.sh` reuses an environment that already exists rather
than destroying it, and now warns when its interpreter does not match
`PYTHON_VERSION`. This matters more than it looks: numpy >= 2.5 and
scipy >= 1.18 declare `requires-python >= 3.12`, so on a 3.11 environment pip
resolves older releases silently instead of reporting a conflict. Either

```bash
./20-create-environments.sh --recreate ml-dev        # rebuild on 3.12
# or accept the older numeric stack:
#   set PYTHON_VERSION="3.11" in config/environments.conf
```

**A large pre-existing environment is being reused.**
Installing this repo's requirements into an environment that already has
several hundred unrelated packages produces an environment that matches no
file. The script warns above 200 packages. `--recreate` is the honest fix.

**`import datasets` fails with `pyarrow has no attribute PyExtensionType`.**
This is the failure mode `requirements/constraints.txt` exists to prevent, and
it is worth understanding because `pip check` calls the environment clean while
it is broken. `s3fs` pins `fsspec` to an exact minor; `datasets` caps `fsspec`
from above. At their latest releases the two ranges do not overlap, so pip
backtracks until it finds a consistent set — and lands on s3fs 2023.10.0 +
fsspec 2023.10.0 + datasets 2.15.0. Every declared requirement is satisfied, so
nothing complains. datasets 2.15 then calls an API pyarrow removed.

Repair an existing environment without rebuilding:

```bash
conda activate llm-dev
pip install -U -c ~/dev-environment/python_environment/requirements/constraints.txt \
  datasets fsspec s3fs
python -c "import datasets, pyarrow; print(datasets.__version__, pyarrow.__version__)"
```

**`pip check` reports conflicts.**
Usually an extra that is legitimately absent. If it names numpy or protobuf,
something pulled `sagemaker` or a GPU wheel into the environment — rebuild with
`./20-create-environments.sh --recreate`.

**A package imports in the terminal but not in Neovim.**
Different interpreter. Run `<leader>cV` in Neovim; it prints
`python()`, `CONDA_PREFIX`, `PATH[1]` and the `pythonPath` basedpyright is
actually using.

**`pip install --user` broke an environment.**
`PYTHONNOUSERSITE=1` is exported by the activation hook written into each
environment (`etc/conda/activate.d/dev-environment.sh`) precisely to stop
`~/.local/lib/python3.12/site-packages` shadowing environment packages. If you
see this, the environment was created before that hook existed — rebuild it.
