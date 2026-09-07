return {
  {
    "folke/noice.nvim",
    opts = function(_, opts)
      opts.cmdline = opts.cmdline or {}
      opts.cmdline.view = "cmdline"

      opts.presets = opts.presets or {}
      opts.presets.command_palette = false
      opts.presets.bottom_search = true
      opts.presets.long_message_to_split = true

      return opts
    end,
  },
}
