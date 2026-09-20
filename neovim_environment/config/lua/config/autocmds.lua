-- LazyVim already supplies the common IDE autocommands. Only additions here.

local group = vim.api.nvim_create_augroup("dev_environment", { clear = true })

-- Record the PATH Neovim started with, before any plugin mutates it.
vim.api.nvim_create_autocmd("VimEnter", {
  group = group,
  once = true,
  callback = function()
    vim.g.dev_environment_original_path = vim.env.PATH
  end,
})

-- Warn once if a Python buffer is opened while no interpreter is selected.
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "python",
  once = true,
  callback = function()
    vim.defer_fn(function()
      local ok, vs = pcall(require, "venv-selector")
      local py = ok and vs.python() or nil

      if not py or py == "" then
        vim.notify(
          "No Python environment selected.\nPress <leader>cv to choose one.",
          vim.log.levels.WARN,
          { title = "venv-selector" }
        )
      end
    end, 2000)
  end,
})
