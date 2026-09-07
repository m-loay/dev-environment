#!/usr/bin/env bash
# STEP_TOTAL, ASSUME_YES and DRY_RUN are read by lib/common.sh, not here.
# shellcheck disable=SC2034
#
# 30-verify.sh — prove the environments actually work, rather than assuming the
# installer's exit code meant something.
#
# Checks, in order of how often each one is the real problem:
#   1. conda base auto-activation is OFF   (the Neovim terminal bug)
#   2. every env imports its headline packages
#   3. `pip check` finds no broken dependency graph
#   4. tf.keras resolves statically           (the stub bug)
#   5. stub packages are visible to a type checker

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
CONFIG_DIR="$SCRIPT_DIR/../config"
# shellcheck source=../config/environments.conf
source "$CONFIG_DIR/environments.conf"

# Verification must report every failure, not stop at the first one.
trap - ERR
set +e

if [[ -r "$HOME/.config/dev-environment/conda-root" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/dev-environment/conda-root"
fi
[[ -n "${CONDA_ROOT:-}" ]] || CONDA_ROOT="$HOME/miniforge3"
CONDA_BIN="$CONDA_ROOT/bin/conda"

FAILURES=0
check() {
  local desc="$1"; shift
  if "$@" >>"$LOG_FILE" 2>&1; then
    ok "$desc"
  else
    fail "$desc"
    FAILURES=$((FAILURES + 1))
  fi
}

STEP_TOTAL=6
header "Verifying the Python environments"

# ---------------------------------------------------------------------------

step "conda shell behaviour"

if [[ ! -x "$CONDA_BIN" ]]; then
  fail "conda not found at $CONDA_BIN"
  FAILURES=$((FAILURES + 1))
else
  AUTO="$("$CONDA_BIN" config --show 2>/dev/null | grep -E '^auto_activate' | tr '\n' ' ')"
  if printf '%s' "$AUTO" | grep -qi 'true'; then
    fail "base auto-activation is ON ($AUTO)"
    warn "every interactive shell will run 'conda activate base' and destroy"
    warn "the PATH that Neovim's venv-selector passes to the terminal"
    FAILURES=$((FAILURES + 1))
  else
    ok "base auto-activation is off (${AUTO:-defaulted via ~/.condarc})"
  fi

  # The decisive end-to-end test: does a fresh interactive login shell keep an
  # environment that was activated only through the inherited environment?
  for pair in $MANAGED_ENVS; do
    name="${pair%%:*}"
    prefix="$CONDA_ROOT/envs/$name"
    [[ -d "$prefix" ]] || continue
    resolved="$(
      env CONDA_PREFIX="$prefix" \
          CONDA_DEFAULT_ENV="$name" \
          CONDA_SHLVL=1 \
          PATH="$prefix/bin:$PATH" \
          bash -i -c 'command -v python' 2>/dev/null | tail -n1
    )"
    if [[ "$resolved" == "$prefix/bin/python" ]]; then
      ok "interactive shell keeps $name  ($resolved)"
    else
      fail "interactive shell lost $name: got '${resolved:-<none>}'"
      warn "something in ~/.bashrc is re-activating conda; check for a second"
      warn "'conda activate' line outside the managed initialize block"
      FAILURES=$((FAILURES + 1))
    fi
  done
fi

# ---------------------------------------------------------------------------

step "Imports"

verify_imports() {
  local py="$1"; shift
  "$py" - "$@" <<'PY'
import importlib, sys
bad = []
for mod in sys.argv[1:]:
    try:
        importlib.import_module(mod)
    except Exception as exc:            # noqa: BLE001 - report, do not raise
        bad.append(f"{mod}: {type(exc).__name__}: {exc}")
for line in bad:
    print(line, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
}

ML_MODULES=(numpy scipy pandas sklearn xgboost lightgbm matplotlib seaborn cv2 h5py pyarrow mlflow dvc boto3 tensorflow)
LLM_MODULES=(numpy pandas torch transformers datasets langchain langgraph openai anthropic qdrant_client chromadb faiss fastapi sqlalchemy mlflow)

for pair in $MANAGED_ENVS; do
  name="${pair%%:*}"
  py="$CONDA_ROOT/envs/$name/bin/python"
  if [[ ! -x "$py" ]]; then
    fail "$name: interpreter missing"
    FAILURES=$((FAILURES + 1))
    continue
  fi
  case "$name" in
    ml-dev)  mods=("${ML_MODULES[@]}") ;;
    llm-dev) mods=("${LLM_MODULES[@]}") ;;
    *)       mods=(numpy pandas) ;;
  esac
  info "$name: importing ${#mods[@]} modules"
  if out="$(verify_imports "$py" "${mods[@]}" 2>&1)"; then
    ok "$name: all imports clean"
  else
    fail "$name: import failures"
    printf '%s\n' "$out" | sed 's/^/      /'
    FAILURES=$((FAILURES + 1))
  fi
done

# ---------------------------------------------------------------------------

step "Dependency graph"

for pair in $MANAGED_ENVS; do
  name="${pair%%:*}"
  py="$CONDA_ROOT/envs/$name/bin/python"
  [[ -x "$py" ]] || continue
  if out="$("$py" -m pip check 2>&1)"; then
    ok "$name: pip check clean"
  else
    warn "$name: pip check reported conflicts"
    printf '%s\n' "$out" | sed 's/^/      /'
    # Not fatal: pip check is noisy about extras that are legitimately absent.
  fi
done

# ---------------------------------------------------------------------------

step "Static resolution of tf.keras"

ML_PY="$CONDA_ROOT/envs/ml-dev/bin/python"
if [[ -x "$ML_PY" ]]; then
  STUB_DIR="$("$ML_PY" -c 'import site,os;p=[d for d in site.getsitepackages() if d.endswith("site-packages")];print(p[0] if p else "")' 2>/dev/null)"
  if [[ -f "$STUB_DIR/tensorflow-stubs/py.typed" ]]; then
    marker="$(cat "$STUB_DIR/tensorflow-stubs/py.typed")"
    if [[ "$marker" == "partial" ]]; then
      ok "types-tensorflow installed and marked 'partial' (falls back to source)"
    else
      warn "tensorflow-stubs is NOT partial — unstubbed submodules will break"
    fi
    if [[ -f "$STUB_DIR/tensorflow-stubs/keras/__init__.pyi" ]]; then
      ok "tensorflow-stubs/keras present — tf.keras.* will resolve"
    else
      fail "keras stubs missing; tf.keras will stay Unknown"
      FAILURES=$((FAILURES + 1))
    fi
  else
    fail "types-tensorflow not installed in ml-dev"
    warn "tf.keras is lazy-loaded in TensorFlow's __init__ and cannot be"
    warn "resolved from source — the stubs are the only fix"
    FAILURES=$((FAILURES + 1))
  fi

  # Runtime sanity: the same symbol must exist at run time, not just in stubs.
  check "ml-dev: tf.keras.layers.LSTM importable at runtime" \
    "$ML_PY" -c 'import tensorflow as tf; tf.keras.layers.LSTM'
else
  warn "ml-dev not built, skipping"
fi

# ---------------------------------------------------------------------------

step "Stub packages and shadowing"

# The previous version of this check flagged every stub package whose py.typed
# did not contain the word "partial". That was wrong: a COMPLETE stub package
# (empty py.typed) is the normal, correct shape for pandas-stubs and for every
# typeshed `types-*` distribution. "partial" only means a type checker may fall
# back to real source for unstubbed submodules — decisive for TensorFlow,
# irrelevant for pandas.
#
# What actually matters is provenance: which DISTRIBUTION installed the stub
# directory, and did we ask for it. An unrequested `*-stubs` directory shadows
# the installed library with somebody else's snapshot of it.

if [[ -x "$ML_PY" ]]; then
  STUB_REPORT="$(mktemp)"
  "$ML_PY" - >"$STUB_REPORT" 2>&1 <<'STUBCHECK'
import importlib.metadata as md
import importlib.util
import pathlib
import site

APPROVED_PREFIXES = ("types-",)          # typeshed, versioned against upstream
APPROVED_EXACT = {
    "pandas-stubs",      # maintained by pandas-dev
    "scipy-stubs",       # tracks SciPy release-for-release
    "boto3-stubs",       # accepted alternative to types-boto3
    "botocore-stubs",
}
KNOWN_BAD = {
    "scikit-learn-stubs": (
        "unmaintained third-party repackage (0.0.3, Aug 2025). It shadows the "
        "installed scikit-learn, so anything added upstream since then vanishes "
        "from completion. Source inference is strictly better."
    ),
}

sp = next((p for p in site.getsitepackages() if p.endswith("site-packages")), None)
root = pathlib.Path(sp) if sp else None

# Map every installed *-stubs directory back to the distribution that owns it.
owner = {}
for dist in md.distributions():
    try:
        name = dist.metadata["Name"] or "<unknown>"
        for f in (dist.files or []):
            top = str(f).split("/")[0]
            if top.endswith("-stubs"):
                owner.setdefault(top, name)
    except Exception:                     # noqa: BLE001 - a broken dist is not fatal
        continue

wanted = ["pandas-stubs", "scipy-stubs", "tensorflow-stubs", "boto3-stubs"]
present = sorted({d.name for d in root.iterdir() if d.name.endswith("-stubs")}) if root else []

print("expected stub packages:")
for name in wanted:
    print(f"  {'ok     ' if name in present else 'MISSING'} {name}")

print("installed stub directories:")
problems = 0
for d in present:
    dist = owner.get(d, "<unknown distribution>")
    pt = root / d / "py.typed"
    kind = "partial" if (pt.exists() and pt.read_text().strip() == "partial") else "complete"
    if dist in KNOWN_BAD:
        print(f"  BAD     {d:24s} <- {dist} [{kind}]")
        print(f"          {KNOWN_BAD[dist]}")
        print(f"          fix: pip uninstall -y {dist}")
        problems += 1
    elif dist.startswith(APPROVED_PREFIXES) or dist in APPROVED_EXACT:
        print(f"  ok      {d:24s} <- {dist} [{kind}]")
    elif dist.lower().replace("_", "-") == d[: -len("-stubs")].lower().replace("_", "-"):
        # The library ships its own stub directory (ujson, wrapt). That is the
        # package's own type information, not a third party shadowing it — and
        # "uninstall it" would remove the library.
        print(f"  ok      {d:24s} <- {dist} (self-shipped) [{kind}]")
    elif dist == "<unknown distribution>":
        # No RECORD to attribute it to (conda-installed, or hand-copied).
        # Worth showing, not worth failing on: we cannot name a fix.
        print(f"  ?       {d:24s} <- provenance unknown [{kind}]")
    else:
        print(f"  UNKNOWN {d:24s} <- {dist} [{kind}]")
        print("          not requested by requirements/stubs.txt, and it shadows")
        print("          the real package. Remove it unless it was deliberate:")
        print(f"          pip uninstall -y {dist}")
        problems += 1

print("inline-typed libraries (these must NOT have a stub package):")
for mod in ("numpy", "matplotlib", "pydantic", "mlflow", "fastapi", "httpx"):
    spec = importlib.util.find_spec(mod)
    if spec and spec.origin:
        has = (pathlib.Path(spec.origin).parent / "py.typed").exists()
        print(f"  {'ok     ' if has else '--     '} {mod}: inline py.typed={has}")

print(f"PROBLEMS={problems}")
STUBCHECK

  grep -v '^PROBLEMS=' "$STUB_REPORT" | sed 's/^/    /'
  cat "$STUB_REPORT" >>"$LOG_FILE"
  STUB_PROBLEMS="$(sed -n 's/^PROBLEMS=//p' "$STUB_REPORT" | tail -n1)"
  rm -f "$STUB_REPORT"

  if [[ "${STUB_PROBLEMS:-0}" -eq 0 ]]; then
    ok "stub inventory clean"
  else
    fail "$STUB_PROBLEMS unexpected stub package(s) shadowing real libraries"
    FAILURES=$((FAILURES + 1))
  fi
else
  warn "ml-dev not built, skipping"
fi

# ---------------------------------------------------------------------------

step "Interpreter versions"

for pair in $MANAGED_ENVS; do
  name="${pair%%:*}"
  py="$CONDA_ROOT/envs/$name/bin/python"
  [[ -x "$py" ]] || continue
  ver="$("$py" -c 'import sys;print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo '?')"
  if [[ "$ver" == "$PYTHON_VERSION" ]]; then
    ok "$name: Python $ver (matches the manifest)"
  else
    warn "$name: Python $ver, manifest says $PYTHON_VERSION"
    warn "numpy >= 2.5 and scipy >= 1.18 declare requires-python >= 3.12, so pip"
    warn "quietly resolves older releases here instead of reporting a conflict"
    warn "fix: ./20-create-environments.sh --recreate $name"
  fi
done

# ---------------------------------------------------------------------------

printf '\n'
header "Result"
if [[ "$FAILURES" -eq 0 ]]; then
  finish "All checks passed"
  exit 0
fi
fail "$FAILURES check(s) failed"
printf '%sLog:%s %s\n' "$C_DIM" "$C_RESET" "$LOG_FILE"
exit 1
