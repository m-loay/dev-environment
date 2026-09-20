return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}

      -- Python formatting pipeline:
      -- 1. Fix Ruff lint issues
      -- 2. Organize/sort imports
      -- 3. Format Python code
      opts.formatters_by_ft.python = {
        "ruff_fix",
        "ruff_organize_imports",
        "ruff_format",
      }
    end,
  },
}
