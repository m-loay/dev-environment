return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = {
      "mason-org/mason.nvim",
    },
    opts = {
      ensure_installed = {
        -- Python
        "basedpyright",
        "ruff",
        "black",
        "isort",
        "debugpy",

        -- Markdown / YAML / JSON / TOML / Docker
        "marksman",
        "markdownlint-cli2",
        "yaml-language-server",
        "json-lsp",
        "taplo",
        "dockerfile-language-server",
        "docker-compose-language-service",

        -- GitHub Actions / XML
        "actionlint",
        "lemminx",

        -- Lua / shell
        "lua-language-server",
        "stylua",
        "shellcheck",
        "shfmt",
        "prettier",
      },
      run_on_start = true,
      start_delay = 0,
      debounce_hours = 24,
    },
  },
}
