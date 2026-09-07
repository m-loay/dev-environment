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
