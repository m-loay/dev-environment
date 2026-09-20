return {
  {
    "folke/tokyonight.nvim",

    opts = {
      style = "night",
      transparent = false,

      styles = {
        comments = {},
        keywords = {},
        functions = {},
        variables = {},

        sidebars = "normal",
        floats = "normal",
      },

      on_colors = function(c)
        -- Dracula Official palette
        c.bg = "#282A35"
        c.bg_dark = "#282A35"
        c.bg_float = "#21222C"
        c.bg_highlight = "#44475A"
        c.bg_popup = "#21222C"
        c.bg_search = "#44475A"
        c.bg_sidebar = "#282A35"
        c.bg_statusline = "#21222C"

        c.fg = "#F8F8F2"
        c.fg_dark = "#F8F8F2"
        c.fg_float = "#F8F8F2"
        c.fg_gutter = "#6272A4"
        c.fg_sidebar = "#F8F8F2"

        c.comment = "#6272A4"

        c.blue = "#8BE9FD"
        c.blue0 = "#8BE9FD"
        c.blue1 = "#8BE9FD"
        c.blue2 = "#8BE9FD"
        c.blue5 = "#8BE9FD"
        c.blue6 = "#8BE9FD"
        c.blue7 = "#8BE9FD"

        c.cyan = "#8BE9FD"

        c.green = "#50FA7B"
        c.green1 = "#50FA7B"
        c.green2 = "#50FA7B"

        c.orange = "#FFB86C"
        c.yellow = "#F1FA8C"

        c.magenta = "#FF79C6"
        c.magenta2 = "#BD93F9"
        c.purple = "#BD93F9"

        c.red = "#FF5555"
        c.red1 = "#FF5555"

        c.error = "#FF5555"
        c.warning = "#FFB86C"
        c.info = "#8BE9FD"
        c.hint = "#BD93F9"

        c.border = "#44475A"
        c.border_highlight = "#BD93F9"
      end,

      on_highlights = function(hl, c)
        local bg = "#282A35"
        local fg = "#F8F8F2"
        local comment = "#6272A4"
        local cyan = "#8BE9FD"
        local green = "#50FA7B"
        local orange = "#FFB86C"
        local pink = "#FF79C6"
        local purple = "#BD93F9"
        local red = "#FF5555"
        local yellow = "#F1FA8C"
        local selection = "#44475A"
        local menu = "#21222C"

        -- Editor
        hl.Normal = { fg = fg, bg = bg }
        hl.NormalNC = { fg = fg, bg = bg }
        hl.SignColumn = { bg = bg }
        hl.FoldColumn = { bg = bg }
        hl.EndOfBuffer = { fg = bg, bg = bg }

        hl.LineNr = { fg = comment, bg = bg }
        hl.CursorLineNr = { fg = fg, bg = bg, bold = true }

        hl.CursorLine = { bg = selection }
        hl.ColorColumn = { bg = selection }
        hl.Visual = { bg = selection }

        -- Floating UI
        hl.NormalFloat = { fg = fg, bg = menu }
        hl.FloatBorder = { fg = comment, bg = menu }

        hl.Pmenu = { fg = fg, bg = menu }
        hl.PmenuSel = { fg = fg, bg = selection }

        -- Traditional syntax
        hl.Comment = { fg = comment }

        hl.String = { fg = yellow }
        hl.Character = { fg = yellow }

        hl.Number = { fg = purple }
        hl.Float = { fg = purple }
        hl.Boolean = { fg = purple }
        hl.Constant = { fg = purple }

        hl.Function = { fg = green }

        hl.Keyword = { fg = pink }
        hl.Statement = { fg = pink }
        hl.Conditional = { fg = pink }
        hl.Repeat = { fg = pink }
        hl.Operator = { fg = pink }
        hl.Exception = { fg = pink }

        hl.Type = { fg = cyan }
        hl.StorageClass = { fg = pink }

        -- Treesitter
        hl["@comment"] = { fg = comment }

        hl["@string"] = { fg = yellow }
        hl["@string.escape"] = { fg = cyan }

        hl["@number"] = { fg = purple }
        hl["@number.float"] = { fg = purple }
        hl["@boolean"] = { fg = purple }

        hl["@constant"] = { fg = purple }
        hl["@constant.builtin"] = { fg = purple }

        hl["@variable"] = { fg = fg }

        hl["@variable.builtin"] = {
          fg = purple,
          italic = true,
        }

        hl["@variable.parameter"] = {
          fg = orange,
          italic = true,
        }

        hl["@variable.member"] = { fg = fg }
        hl["@property"] = { fg = fg }

        hl["@function"] = { fg = green }
        hl["@function.call"] = { fg = green }
        hl["@function.method"] = { fg = green }
        hl["@function.method.call"] = { fg = green }
        hl["@function.macro"] = { fg = green }

        hl["@function.builtin"] = { fg = cyan }

        hl["@keyword"] = { fg = pink }
        hl["@keyword.function"] = { fg = pink }
        hl["@keyword.return"] = { fg = pink }
        hl["@keyword.conditional"] = { fg = pink }
        hl["@keyword.repeat"] = { fg = pink }
        hl["@keyword.exception"] = { fg = pink }
        hl["@keyword.import"] = { fg = pink }
        hl["@keyword.operator"] = { fg = pink }

        hl["@operator"] = { fg = pink }

        hl["@type"] = { fg = cyan }

        hl["@type.builtin"] = {
          fg = cyan,
          italic = true,
        }

        hl["@type.definition"] = { fg = cyan }

        hl["@module"] = { fg = fg }
        hl["@constructor"] = { fg = cyan }
        hl["@attribute"] = { fg = green }

        -- LSP semantic tokens
        hl["@lsp.type.class"] = { fg = cyan }
        hl["@lsp.type.struct"] = { fg = cyan }
        hl["@lsp.type.interface"] = { fg = cyan }
        hl["@lsp.type.enum"] = { fg = cyan }
        hl["@lsp.type.enumMember"] = { fg = purple }

        hl["@lsp.type.type"] = { fg = cyan }
        hl["@lsp.type.typeParameter"] = { fg = cyan }

        hl["@lsp.type.function"] = { fg = green }
        hl["@lsp.type.method"] = { fg = green }

        hl["@lsp.type.parameter"] = {
          fg = orange,
          italic = true,
        }

        hl["@lsp.type.variable"] = { fg = fg }
        hl["@lsp.type.property"] = { fg = fg }
        hl["@lsp.type.namespace"] = { fg = fg }

        -- Diagnostics
        hl.DiagnosticError = { fg = red }
        hl.DiagnosticWarn = { fg = orange }
        hl.DiagnosticInfo = { fg = cyan }
        hl.DiagnosticHint = { fg = purple }

        -- Important for Snacks
        hl.SnacksDashboardNormal = {
          fg = fg,
          bg = bg,
        }
      end,
    },
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "tokyonight",
    },
  },
}
