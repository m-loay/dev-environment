-- Keep LazyVim's built-in mappings for:
--   <leader>cv  -> VenvSelect
--   <leader>cf  -> format
--   <leader>d*  -> debugger
--   <leader>t*  -> tests
--
-- Only additions and one deliberate override live here.

local map = vim.keymap.set

-- ---------------------------------------------------------------------------
-- Terminal: environment-aware override of LazyVim's Ctrl+/
--
-- LazyVim maps <C-/> to Snacks.terminal.focus(nil, { cwd = LazyVim.root() }).
-- Snacks derives the terminal cache key from cmd/cwd/env/count only
-- (snacks/terminal.lua:M.tid). With no `env` in the options table the key is
-- constant, so after switching Python environments Ctrl+/ re-attaches to the
-- shell process created under the OLD environment — a process whose
-- environment block was copied at fork() and cannot be updated.
--
-- Passing the conda variables explicitly does two things: the child shell gets
-- the right environment, and the cache key changes with the environment, so a
-- new terminal is spawned per environment instead of a stale one being reused.
-- ---------------------------------------------------------------------------

local function terminal_env()
  return {
    PATH = vim.env.PATH,
    CONDA_PREFIX = vim.env.CONDA_PREFIX or "",
    CONDA_DEFAULT_ENV = vim.env.CONDA_DEFAULT_ENV or "",
    CONDA_SHLVL = vim.env.CONDA_SHLVL or "0",
    CONDA_PROMPT_MODIFIER = vim.env.CONDA_PROMPT_MODIFIER or "",
    VIRTUAL_ENV = vim.env.VIRTUAL_ENV or "",
    -- Defensive: stop the .bashrc conda hook from activating base on top of
    -- the environment we just handed it.
    CONDA_AUTO_ACTIVATE = "false",
    CONDA_AUTO_ACTIVATE_BASE = "false",
    PYTHONNOUSERSITE = "1",
  }
end

-- <C-/> and <C-_> are the same chord; terminals differ in what they send.
for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
  map({ "n", "t" }, lhs, function()
    Snacks.terminal.focus(nil, { cwd = LazyVim.root(), env = terminal_env() })
  end, { desc = "Terminal (Root Dir)" })
end

map("n", "<leader>fT", function()
  Snacks.terminal(nil, { env = terminal_env() })
end, { desc = "Terminal (cwd)" })

map("n", "<leader>ft", function()
  Snacks.terminal(nil, { cwd = LazyVim.root(), env = terminal_env() })
end, { desc = "Terminal (Root Dir)" })

-- Show what the next terminal will inherit. First thing to run when the
-- environment looks wrong.
map("n", "<leader>cV", function()
  local lines = {
    "python()        : " .. tostring(require("venv-selector").python()),
    "CONDA_PREFIX    : " .. tostring(vim.env.CONDA_PREFIX),
    "CONDA_DEFAULT_ENV: " .. tostring(vim.env.CONDA_DEFAULT_ENV),
    "CONDA_SHLVL     : " .. tostring(vim.env.CONDA_SHLVL),
    "VIRTUAL_ENV     : " .. tostring(vim.env.VIRTUAL_ENV),
    "PATH[1]         : " .. tostring(vim.split(vim.env.PATH or "", ":")[1]),
  }
  local client = vim.lsp.get_clients({ name = "basedpyright" })[1]
  if client then
    local py = vim.tbl_get(client.settings or {}, "python", "pythonPath")
    table.insert(lines, "basedpyright    : " .. tostring(py))
  else
    table.insert(lines, "basedpyright    : <not attached>")
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Env diagnostics" })
end, { desc = "Env Diagnostics" })

-- ---------------------------------------------------------------------------
-- VS Code-like navigation
-- ---------------------------------------------------------------------------

map("n", "<C-p>", function()
  Snacks.picker.files()
end, { desc = "Find Files" })

map("n", "<C-b>", function()
  Snacks.explorer()
end, { desc = "Explorer" })

-- ---------------------------------------------------------------------------
-- VS Code-like debugger function keys
-- ---------------------------------------------------------------------------

map("n", "<F5>", function()
  require("dap").continue()
end, { desc = "Debug: Start / Continue" })

map("n", "<F9>", function()
  require("dap").toggle_breakpoint()
end, { desc = "Debug: Toggle Breakpoint" })

map("n", "<F6>", function()
  require("dap").step_over()
end, { desc = "Debug: Step Over" })

map("n", "<F7>", function()
  require("dap").step_into()
end, { desc = "Debug: Step Into" })

-- ---------------------------------------------------------------------------
-- Run the current Python file in the selected environment
-- ---------------------------------------------------------------------------

local function selected_python()
  -- Prefer venv-selector's own answer; it is authoritative and survives cases
  -- where the environment variables were cleared.
  local ok, vs = pcall(require, "venv-selector")
  if ok then
    local py = vs.python()
    if py and py ~= "" and vim.fn.executable(py) == 1 then
      return py
    end
  end

  if vim.env.CONDA_PREFIX and vim.env.CONDA_PREFIX ~= "" then
    return vim.env.CONDA_PREFIX .. "/bin/python"
  end

  if vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV ~= "" then
    return vim.env.VIRTUAL_ENV .. "/bin/python"
  end

  local python = vim.fn.exepath("python3")
  return python ~= "" and python or "python"
end

map("n", "<leader>rp", function()
  if vim.bo.filetype ~= "python" then
    vim.notify("Current file is not Python", vim.log.levels.WARN)
    return
  end

  vim.cmd("write")
  local file = vim.fn.expand("%:p")
  Snacks.terminal({ selected_python(), file }, {
    cwd = LazyVim.root(),
    env = terminal_env(),
  })
end, { desc = "Run Python File" })

-- ---------------------------------------------------------------------------
-- Tests / pytest
-- ---------------------------------------------------------------------------

map("n", "<leader>tt", function()
  require("neotest").run.run()
end, { desc = "Run Nearest Test" })

map("n", "<leader>tf", function()
  require("neotest").run.run(vim.fn.expand("%"))
end, { desc = "Run Test File" })

map("n", "<leader>ta", function()
  require("neotest").run.run(vim.fn.getcwd())
end, { desc = "Run All Tests" })

map("n", "<leader>ts", function()
  require("neotest").summary.toggle()
end, { desc = "Toggle Test Explorer" })

map("n", "<leader>to", function()
  require("neotest").output.open({ enter = true })
end, { desc = "Show Test Output" })

map("n", "<leader>tO", function()
  require("neotest").output_panel.toggle()
end, { desc = "Toggle Test Output Panel" })

map("n", "<leader>td", function()
  require("neotest").run.run({
    suite = false,
    strategy = "dap",
  })
end, { desc = "Debug Nearest Test" })

map("n", "]t", function()
  require("neotest").jump.next({ status = "failed" })
end, { desc = "Next Failed Test" })

map("n", "[t", function()
  require("neotest").jump.prev({ status = "failed" })
end, { desc = "Previous Failed Test" })

-- ---------------------------------------------------------------------------
-- Format + fix + save
-- ---------------------------------------------------------------------------

local function format_and_save()
  LazyVim.format({ force = true })
  vim.cmd("write")
end

map("n", "<C-s>", format_and_save, {
  desc = "Format, Fix, and Save",
})

map("i", "<C-s>", function()
  vim.cmd("stopinsert")
  format_and_save()
  vim.cmd("startinsert")
end, {
  desc = "Format, Fix, and Save",
})

-- ---------------------------------------------------------------------------
-- VS Code-style navigation
--
-- <C-p> and <C-b> already live in the "VS Code-like navigation" block above.
-- F5/F6/F7/F9 are the debugger. Everything below is free of those.
-- ---------------------------------------------------------------------------

-- F12 family: definition / references / implementation.
map("n", "<F12>", vim.lsp.buf.definition, { desc = "Go to Definition" })
map("n", "<F2>", vim.lsp.buf.rename, { desc = "Rename Symbol" })

-- Ctrl+G: go to line. Opens the command line primed with a colon; type the
-- number and press Enter. This shadows the built-in "show file info" —
-- <C-g> is rarely used for that, and :f still does it.
map({ "n", "v" }, "<C-g>", ":", { desc = "Go to Line (type a number)" })

-- Alt+Arrow: walk the jumplist. This is the actual VS Code back/forward —
-- it steps through every gd / gI / gr jump, across files.
map("n", "<M-Left>", "<C-o>", { desc = "Jump Back" })
map("n", "<M-Right>", "<C-i>", { desc = "Jump Forward" })

-- Close and switch "tabs". VS Code tabs are Neovim BUFFERS, not tabpages,
-- so these operate on the bufferline you can see at the top.
map("n", "<C-w>", function()
  Snacks.bufdelete()
end, { desc = "Close Buffer" })

map("n", "<M-Up>", "<cmd>bprevious<cr>", { desc = "Previous Buffer" })
map("n", "<M-Down>", "<cmd>bnext<cr>", { desc = "Next Buffer" })

-- Ctrl+Tab: cycle buffers. Likely inert in a terminal — see the note below.
map("n", "<C-Tab>", "<cmd>bnext<cr>", { desc = "Next Buffer" })
map("n", "<C-S-Tab>", "<cmd>bprevious<cr>", { desc = "Previous Buffer" })
