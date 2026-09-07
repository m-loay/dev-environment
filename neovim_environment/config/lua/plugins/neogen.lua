return {
  {
    "danymat/neogen",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {
      snippet_engine = "nvim",
    },
    keys = {
      {
        "<leader>cg",
        function()
          require("neogen").generate()
        end,
        desc = "Generate Docstring",
      },
    },
  },
}
