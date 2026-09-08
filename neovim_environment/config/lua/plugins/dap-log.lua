-- TEMPORARY DIAGNOSTIC. Delete once the debug problem is settled.
--
-- Every path that starts a debug session — neotest's dap strategy,
-- <leader>dPt, .vscode/launch.json, plain <leader>dc — ends up calling
-- dap.run(). This wraps that one function and writes the configuration it was
-- handed to a file, before debugpy sees it.
--
-- That removes the guessing: the file shows the interpreter, the cwd, and
-- whether justMyCode actually arrived, for the exact session that misbehaved.
-- No need to catch a live session with :lua, which is why the earlier attempt
-- printed "no session" — by the time you type the command the session is gone.
--
--   cat /tmp/dap-config.log

return {
  {
    "mfussenegger/nvim-dap",

    init = function()
      -- init runs at startup, before the plugin loads. Defer the wrap until
      -- the dap module actually exists, whichever plugin pulls it in.
      vim.api.nvim_create_autocmd("User", {
        pattern = "LazyLoad",
        callback = function(ev)
          if ev.data ~= "nvim-dap" then
            return
          end

          local dap = require("dap")
          if dap.__config_logger then
            return
          end
          dap.__config_logger = true

          local logfile = "/tmp/dap-config.log"
          local original_run = dap.run

          dap.run = function(config, opts)
            local lines = {
              "",
              "================================================================",
              os.date("%Y-%m-%d %H:%M:%S"),
              "================================================================",
              "config passed to dap.run():",
              vim.inspect(config),
              "",
              "environment at launch:",
              "  CONDA_PREFIX      = " .. tostring(vim.env.CONDA_PREFIX),
              "  CONDA_DEFAULT_ENV = " .. tostring(vim.env.CONDA_DEFAULT_ENV),
              "  VIRTUAL_ENV       = " .. tostring(vim.env.VIRTUAL_ENV),
              "  cwd (Neovim)      = " .. vim.fn.getcwd(),
              "  PATH[1]           = " .. tostring(vim.split(vim.env.PATH or "", ":")[1]),
            }

            local ok, vs = pcall(require, "venv-selector")
            table.insert(lines, "  venv-selector     = " .. (ok and tostring(vs.python()) or "<not loaded>"))

            local fh = io.open(logfile, "a")
            if fh then
              fh:write(table.concat(lines, "\n") .. "\n")
              fh:close()
            end

            vim.notify("dap config written to " .. logfile, vim.log.levels.INFO)

            return original_run(config, opts)
          end
        end,
      })
    end,
  },
}
