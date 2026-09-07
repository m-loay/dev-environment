return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            hidden = true, -- dotfiles: .git, .gitignore, .env
            ignored = true, -- gitignored: node_modules, __pycache__, *.pyc
          },
        },
      },
    },
  },
}
