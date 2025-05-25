return {
  {
    "p00f/clangd_extensions.nvim",
    lazy = true,
    ft = { "c", "cpp" },
    config = function()
      require("clangd_extensions").setup({
        inlay_hints = {
          inline = false,
        },
        ast = {
          -- Adding all AST icons from original config
          role_icons = {
            type = "🄣",
            declaration = "📢",
            expression = "📣",
            statement = ";",
            specifier = "🔍",
            ["template argument"] = "🆃",
          },
          kind_icons = {
            Compound = "🄲",
            Recovery = "💉",
            TranslationUnit = "🅄",
            PackExpansion = "📦",
            TemplateTypeParm = "🆃",
            TemplateTemplateParm = "🆃",
            TemplateParamObject = "🅟",
          },
        },
      })
    end,
  },
}
