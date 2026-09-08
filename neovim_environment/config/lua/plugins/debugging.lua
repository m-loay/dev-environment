-- Debug only my code, not library internals.
--
-- WHAT WAS ALREADY RIGHT
--
-- `justMyCode` is the correct lever, and `test.lua` sets it correctly for
-- neotest's dap strategy. `require("dap-python").setup("debugpy-adapter")`
-- matches what LazyVim's Python extra does, so nothing regressed there, and
-- dap-python resolves the debuggee interpreter from CONDA_PREFIX
-- (dap-python.lua:105), which `python.lua`'s activation callback sets.
--
-- WHY THE LOOP OVER dap.configurations.python IS NOT ENOUGH
--
-- 1. `justMyCode` already defaults to true in debugpy. Setting it on the
--    default configurations changes nothing — which is why the symptom
--    survived the change.
--
-- 2. It only touches configurations that exist at that moment. Three sources
--    appear later and are missed entirely:
--
--      .vscode/launch.json     loaded by LazyVim's dap.core through
--                              require("dap.ext.vscode").load_launchjs()
--      <leader>dPt / <leader>dPc
--                              dap-python's trigger_test() builds a fresh
--                              config table and calls dap.run() directly;
--                              it never reads dap.configurations.python
--      ad-hoc dap.run(...)     anything a plugin launches programmatically
--
-- THE APPROACH HERE
--
-- Wrap `dap.run`, which every one of those paths funnels through. A single
-- choke point covers configurations that do not exist yet and configurations
-- this file has never seen.
--
-- The spec stays on nvim-dap-python, exactly where it was. Overriding
-- nvim-dap's own `config` instead would drop LazyVim's mason-nvim-dap wiring,
-- the DapStoppedLine highlight and the sign definitions, which all live in
-- that function (lazyvim/plugins/extras/dap/core.lua:55).
--
-- LazyVim's nvim-dap-python config is a single setup() call, so replacing it
-- costs nothing as long as that call is reproduced — it is, below.

return {
  {
    "mfussenegger/nvim-dap-python",

    config = function()
      -- Identical to LazyVim's own config for this plugin.
      require("dap-python").setup("debugpy-adapter")

      local dap = require("dap")

      -- Applied to every Python session, whatever built the configuration.
      local function apply_python_defaults(config)
        if config.type ~= "python" and config.type ~= "debugpy" then
          return config
        end

        config = vim.deepcopy(config)

        -- true  -> step into project code, step OVER stdlib and site-packages
        -- false -> the debugger may enter anything
        if config.justMyCode == nil then
          config.justMyCode = true
        end

        -- debugpy decides what counts as "my code" relative to the debuggee's
        -- interpreter. Without an explicit cwd it uses the process working
        -- directory, which for a Neovim-launched session is wherever Neovim
        -- happened to start — so files under the project can be classified as
        -- library code and skipped, or the reverse.
        config.cwd = config.cwd or LazyVim.root()

        -- Keep frozen stdlib frames (importlib._bootstrap on Python 3.11+)
        -- out of the step path.
        if config.subProcess == nil then
          config.subProcess = false
        end

        return config
      end

      -- Wrap once. Guard against a second wrap if this file is re-sourced.
      if not dap.__python_defaults_wrapped then
        local original_run = dap.run
        dap.run = function(config, opts)
          return original_run(apply_python_defaults(config), opts)
        end
        dap.__python_defaults_wrapped = true
      end
    end,
  },
}
