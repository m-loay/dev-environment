-- Test runner: neotest + neotest-python + pytest, debugged through nvim-dap.
--
-- Three fixes, each with a measured cause.
--
-- 1. INTERPRETER RESOLUTION
--
-- neotest-python resolves the Python it runs tests with in
-- base.get_python_command() (neotest-python/base.lua:30). It checks
-- VIRTUAL_ENV, then globs for pyvenv.cfg, then Pipfile, then poetry, and
-- finally falls back to `python3` from PATH. It never checks CONDA_PREFIX, so
-- a conda environment misses every branch. The result is memoised per project
-- root, so a wrong answer persists for the whole session even after
-- <leader>cv.
--
-- `python` accepts a function (neotest-python/init.lua:8), evaluated per root,
-- so the selected environment is picked up without restarting Neovim.
--
-- 2. LIBRARY CLASSIFICATION
--
-- `justMyCode = true` tells pydevd to step over library code. pydevd works out
-- what "library" means at runtime in _get_default_library_roots()
-- (pydevd_filtering.py:141): sysconfig paths, the directory holding os.py,
-- site.getsitepackages(), and any sys.path entry whose basename is
-- "site-packages".
--
-- pydevd reads LIBRARY_ROOTS from the environment first
-- (pydevd_filtering.py:112) and uses it INSTEAD of that discovery. Setting it
-- explicitly, from the interpreter that will actually run the tests, removes
-- the guesswork and stays correct when you switch environments.
--
-- 3. THE NEOTEST RUNNER SHIM
--
-- neotest-python does not hand pytest to debugpy directly. It launches its own
-- script (adapter.lua:99 -> base.create_dap_config), so the debuggee's program
-- is:
--
--     ~/.local/share/nvim/lazy/neotest-python/neotest.py
--
-- and the frame you return into after the last line of a test is:
--
--     ~/.local/share/nvim/lazy/neotest-python/neotest_python/pytest.py:111
--
-- That path is neither stdlib nor site-packages, so pydevd's discovery
-- classifies it as YOUR code, and justMyCode cannot exclude code it thinks is
-- yours. Stepping past `assert ...` therefore opens the plugin's shim instead
-- of stepping over it. Naming the plugin directory as a library root is what
-- stops that, and it is why fixes 1 and 2 alone were not enough.

-- Resolution order matches how the rest of this config thinks about
-- environments: venv-selector is authoritative, CONDA_PREFIX is the fallback,
-- PATH is the last resort.
local function project_python()
  local ok, vs = pcall(require, "venv-selector")
  if ok then
    local py = vs.python()
    if py and py ~= "" and vim.fn.executable(py) == 1 then
      return py
    end
  end

  if vim.env.CONDA_PREFIX and vim.env.CONDA_PREFIX ~= "" then
    local py = vim.env.CONDA_PREFIX .. "/bin/python"
    if vim.fn.executable(py) == 1 then
      return py
    end
  end

  if vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV ~= "" then
    local py = vim.env.VIRTUAL_ENV .. "/bin/python"
    if vim.fn.executable(py) == 1 then
      return py
    end
  end

  local py = vim.fn.exepath("python3")
  return py ~= "" and py or "python3"
end

-- Ask the interpreter itself where its stdlib and site-packages live rather
-- than assembling paths from a hardcoded version number, then append the
-- plugin directories whose code should never be stepped into.
--
-- Returns a colon-separated string, or nil if the interpreter cannot be
-- queried — in which case LIBRARY_ROOTS is left unset and pydevd falls back to
-- its own discovery, which is better than an empty or wrong value.
local function library_roots()
  local python = project_python()
  if vim.fn.executable(python) ~= 1 then
    return nil
  end

  local script = table.concat({
    "import site, sysconfig",
    "r = set()",
    "for n in ('stdlib', 'platstdlib', 'purelib', 'platlib'):",
    "    p = sysconfig.get_path(n)",
    "    if p: r.add(p)",
    "try:",
    "    r.update(site.getsitepackages())",
    "except Exception: pass",
    "try:",
    "    u = site.getusersitepackages()",
    "    r.add(u) if isinstance(u, str) else r.update(u)",
    "except Exception: pass",
    "print(':'.join(sorted(x for x in r if x)))",
  }, "\n")

  local out = vim.fn.system({ python, "-c", script })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  out = vim.trim(out)
  if out == "" then
    return nil
  end

  local roots = { out }

  -- The runner shim and anything else under the plugin tree that executes
  -- inside the debuggee. Confirmed landing point:
  --   .../lazy/neotest-python/neotest_python/pytest.py:111
  local lazy_dir = vim.fn.stdpath("data") .. "/lazy"
  for _, plugin in ipairs({ "neotest-python", "neotest" }) do
    local dir = lazy_dir .. "/" .. plugin
    if vim.fn.isdirectory(dir) == 1 then
      table.insert(roots, dir)
    end
  end

  return table.concat(roots, ":")
end

return {
  {
    "nvim-neotest/neotest",

    opts = function(_, opts)
      opts.adapters = opts.adapters or {}

      local dap_config = {
        -- Step over library code; step into project code.
        justMyCode = true,
      }

      local roots = library_roots()
      if roots then
        dap_config.env = { LIBRARY_ROOTS = roots }
      end

      -- neotest-python is already supplied by LazyVim's Python extra; this
      -- only configures it.
      opts.adapters["neotest-python"] = {
        runner = "pytest",
        python = project_python,
        -- Merged into the launch config by base.create_dap_config()
        -- (neotest-python/base.lua:176).
        dap = dap_config,
      }

      -- Show test state beside test functions.
      opts.status = {
        enabled = true,
        signs = true,
        virtual_text = true,
      }

      -- Show failed assertions as Neovim diagnostics.
      opts.diagnostic = {
        enabled = true,
        severity = vim.diagnostic.severity.ERROR,
      }

      -- Test Explorer / summary panel.
      opts.summary = {
        enabled = true,
        animated = true,
        follow = true,
        expand_errors = true,
        open = "botright vsplit | vertical resize 50",
      }

      -- Keep test output available without needing a terminal.
      opts.output = {
        enabled = true,
        open_on_run = false,
      }

      opts.output_panel = {
        enabled = true,
        open = "botright split | resize 15",
      }

      opts.quickfix = {
        enabled = true,
        open = false,
      }

      return opts
    end,
  },
}
