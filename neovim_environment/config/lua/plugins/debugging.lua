return {
  {
    "mfussenegger/nvim-dap-python",

    config = function()
      -- Keep LazyVim's normal debugpy setup.
      require("dap-python").setup("debugpy-adapter")

      local dap = require("dap")

      -- Apply this to EVERY normal Python debug configuration.
      --
      -- true:
      --   step into your project code
      --   skip Python stdlib
      --   skip site-packages
      --   skip numpy / pandas / torch / pytest internals, etc.
      --
      -- false:
      --   debugger can enter everything
      for _, config in ipairs(dap.configurations.python or {}) do
        config.justMyCode = true
      end
    end,
  },
}
