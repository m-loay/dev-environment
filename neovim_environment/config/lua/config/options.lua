vim.g.lazyvim_explorer = "snacks"
-- Python defaults used by LazyVim's official Python extra.
vim.g.lazyvim_python_lsp = "basedpyright"
vim.g.lazyvim_python_ruff = "ruff"

-- Keep LazyVim automatic formatting enabled.
vim.g.autoformat = true

-- VS Code-like absolute line numbers.
vim.opt.number = true
vim.opt.relativenumber = false

-- Editing preferences.
vim.opt.wrap = false
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.cursorline = true
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250
vim.opt.timeoutlen = 400

-- System clipboard when xclip/wl-clipboard is available.
vim.opt.clipboard = "unnamedplus"

-- Persist undo across sessions; cheap and repeatedly useful on a server.
vim.opt.undofile = true
vim.opt.undolevels = 10000
