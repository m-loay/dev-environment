return {
  {
    "folke/sidekick.nvim",
    opts = {
      nes = {
        enabled = false,
      },
    },
    keys = {
      {
        "<leader>ac",
        "<cmd>Sidekick cli show name=claude focus=true<cr>",
        desc = "Claude Code",
      },
      {
        "<leader>ao",
        "<cmd>Sidekick cli show name=codex focus=true<cr>",
        desc = "OpenAI Codex",
      },
    },
  },
}
