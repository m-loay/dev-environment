-- Python environment selection.
--
-- Two bugs are fixed here. Both produced the same visible symptom — "I pick an
-- env with <leader>cv, then Ctrl+/ opens a shell in base".
--
-- BUG 1: incomplete conda state.
--   venv-selector (venv.lua:update_paths) prepends <env>/bin to vim.env.PATH
--   and sets CONDA_PREFIX. It does not set CONDA_SHLVL, CONDA_DEFAULT_ENV or
--   CONDA_PROMPT_MODIFIER, so the child shell does not look activated: the
--   prompt has no (env), `conda install` targets base, and `conda deactivate`
--   is a no-op.
--
-- BUG 2: ~/.bashrc re-activates base.
--   `conda init` evals `conda shell.bash hook`. When auto-activation is on,
--   that hook appends `conda activate base` unconditionally (conda/activate.py:
--   `builder.append(f"conda activate '{context.default_activation_env}'")`).
--   `conda activate base` removes the current prefix's bin from PATH and
--   prepends base/bin — the selection is gone before the prompt renders.
--   The permanent fix lives in ~/.condarc (auto_activate: false); the
--   CONDA_AUTO_ACTIVATE* exports below are a per-terminal fallback so the
--   config is still correct on a machine where that has not been applied.
--
-- BUG 3 (adjacent): Snacks caches terminals on cmd/cwd/env/count only
--   (snacks/terminal.lua:M.tid). With no `env` passed, the key never changes,
--   so Ctrl+/ re-attaches to a shell process whose environment was fixed at
--   fork() time. Handled by closing terminals here and by the env-aware
--   Ctrl+/ override in lua/config/keymaps.lua.

local function conda_env_roots()
  local roots = {}
  for _, dir in ipairs({
    "~/miniforge3/envs",
    "~/mambaforge/envs",
    "~/miniconda3/envs",
    "~/anaconda3/envs",
    "/opt/conda/envs",
  }) do
    local expanded = vim.fn.expand(dir)
    if vim.fn.isdirectory(expanded) == 1 then
      table.insert(roots, expanded)
    end
  end
  return roots
end

return {
  {
    "linux-cultist/venv-selector.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.notify_user_on_venv_activation = true
      opts.options.override_notify = false

      -- Defaults, stated explicitly because the whole fix depends on them:
      -- prepend <env>/bin to $PATH, and export CONDA_PREFIX / VIRTUAL_ENV.
      opts.options.activate_venv_in_terminal = true
      opts.options.set_environment_variables = true

      -- LazyVim/venv-selector already searches ~/miniconda3 and project-local
      -- .venv directories. Add every conda root that exists on this machine;
      -- the built-in Linux searches do not cover ~/anaconda3/envs or miniforge.
      opts.search = opts.search or {}
      for i, root in ipairs(conda_env_roots()) do
        -- NO --full-path here. With it, fd matches the pattern against the
        -- whole pathname instead of the filename, so the anchored regex
        -- ^python$ can never match .../envs/<name>/bin/python and the picker
        -- comes up empty. Depth 3 covers <env>/bin/python from the envs root.
        opts.search["conda_root_" .. i] = {
          command = "$FD '^python$' "
            .. vim.fn.shellescape(root)
            .. " --type f --type l --color never --max-depth 3",
          type = "anaconda",
        }
      end

      opts.options.on_venv_activate_callback = function()
        local python = require("venv-selector").python()
        if not python or python == "" then
          return
        end

        -- python() returns .../envs/<name>/bin/python, so two dirnames give
        -- the prefix. Do not use venv-selector's venv(): it returns the bin
        -- directory, not the environment root.
        local bin = vim.fs.dirname(python)
        local prefix = vim.fs.dirname(bin)

        -- conda-meta only exists inside a conda prefix. Plain venvs and uv
        -- environments are already handled correctly by the plugin.
        if vim.fn.isdirectory(prefix .. "/conda-meta") ~= 1 then
          return
        end

        local name = vim.fs.basename(prefix)

        vim.env.VIRTUAL_ENV = nil
        vim.env.CONDA_PREFIX = prefix
        vim.env.CONDA_DEFAULT_ENV = name
        vim.env.CONDA_SHLVL = "1"
        vim.env.CONDA_PROMPT_MODIFIER = "(" .. name .. ") "

        -- Suppress `conda activate base` from the .bashrc hook even when
        -- ~/.condarc has not been fixed. conda reads config parameters from
        -- CONDA_<NAME>; auto_activate is the >=25.x name, auto_activate_base
        -- the older alias.
        vim.env.CONDA_AUTO_ACTIVATE = "false"
        vim.env.CONDA_AUTO_ACTIVATE_BASE = "false"

        -- Stop ~/.local/lib/python*/site-packages from shadowing the env.
        vim.env.PYTHONNOUSERSITE = "1"

        -- Drop terminals spawned under the previous environment. Their
        -- environment was copied at fork() and cannot be changed. This kills
        -- anything still running in them; remove the loop if you park
        -- long-lived jobs in the Snacks terminal.
        local ok, term = pcall(function()
          return Snacks.terminal
        end)
        if ok and term then
          for _, t in ipairs(term.list()) do
            pcall(function()
              t:close()
            end)
          end
        end

        vim.notify(
          ("conda env: %s\n%s"):format(name, python),
          vim.log.levels.INFO,
          { title = "venv-selector" }
        )
      end
    end,
  },
}
