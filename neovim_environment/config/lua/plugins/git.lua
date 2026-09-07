return {
  {
    "sindrets/diffview.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewFileHistory",
    },
    keys = {
      {
        "<leader>gD",
        "<cmd>DiffviewOpen<cr>",
        desc = "Diffview",
      },
      {
        "<leader>gH",
        "<cmd>DiffviewFileHistory %<cr>",
        desc = "File History",
      },
    },
  },
}
