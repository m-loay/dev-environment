return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters = opts.formatters or {}

      -- <leader>cf runs LazyVim's normal format command. For Python the tools
      -- run sequentially: ruff auto-fix -> isort -> black.
      opts.formatters_by_ft.python = {
        "ruff_fix",
        "isort",
        "black",
      }

      -- Without profile=black, isort's default grid wrapping and black's magic
      -- trailing comma disagree on multi-line imports, so every save rewrites
      -- the same lines back and forth. Setting it here means the chain is
      -- correct even in a project with no [tool.isort] section.
      opts.formatters.isort = {
        prepend_args = { "--profile", "black" },
      }
    end,
  },
}
