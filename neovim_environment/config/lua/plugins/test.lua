return {
  {
    "nvim-neotest/neotest",

    opts = function(_, opts)
      opts.adapters = opts.adapters or {}

      -- neotest-python is already supplied by LazyVim's Python extra.
      -- Configure pytest explicitly.
      opts.adapters["neotest-python"] = {
        runner = "pytest",

        dap = {
          justMyCode = true,
        },
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
