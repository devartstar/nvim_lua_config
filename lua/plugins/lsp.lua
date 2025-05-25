return {
  -- Mason first, with explicit package installation
  {
    "williamboman/mason.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("mason").setup({
        install_root_dir = vim.fn.stdpath("data") .. "/mason",
        PATH = "append",
      })
      
      -- Ensure core packages are installed
      local registry = require("mason-registry")
      local function ensure_installed()
        for _, pkg_name in ipairs({ "lua-language-server", "clangd" }) do
          local pkg = registry.get_package(pkg_name)
          if not pkg:is_installed() then
            pkg:install()
          end
        end
      end
      registry.refresh(ensure_installed)
    end,
  },

  -- Mason-lspconfig bridge
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      automatic_installation = false,
    },
  },

  -- LSP configuration
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',
      { 'j-hui/fidget.nvim', opts = {} },
      'saghen/blink.cmp',
    },
    config = function()
      local lspconfig = require('lspconfig')
      
      -- Server configurations
      local servers = {
        clangd = {
          cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--header-insertion=iwyu",
            "--completion-style=detailed",
            "--function-arg-placeholders",
            "--fallback-style=llvm",
          },
        },
        lua_ls = {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
      }

      -- Setup each server
      for server_name, config in pairs(servers) do
        config.capabilities = vim.tbl_deep_extend(
          'force',
          {},
          require('blink.cmp').get_lsp_capabilities(),
          config.capabilities or {}
        )
        lspconfig[server_name].setup(config)
      end

      -- LSP attach handler setup
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc)
            vim.keymap.set('n', keys, func, { buffer = event.buf, desc = desc })
          end

          -- LSP keymaps
          map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
          map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
          map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
          map('K', vim.lsp.buf.hover, 'Hover Documentation')
          map('gK', vim.lsp.buf.signature_help, 'Signature Documentation')
          
          -- Workspace commands
          map('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
          map('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
          map('<leader>wl', function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
          end, '[W]orkspace [L]ist Folders')

          -- Code actions
          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')
          
          -- Symbol navigation
          map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
          map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')
          
          -- Setup inlay hints if supported
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          local supports_method = vim.fn.has('nvim-0.11') == 1 
            and client.supports_method("textDocument/inlayHint", { bufnr = event.buf })
            or client.supports_method("textDocument/inlayHint", { bufnr = event.buf })

          if client and supports_method then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end

          -- Document highlight setup
          if client and client.supports_method("textDocument/documentHighlight") then
            local highlight_group = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_group,
              callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_group,
              callback = vim.lsp.buf.clear_references,
            })
          end
        end,
      })

      -- Diagnostic configuration
      vim.diagnostic.config {
        severity_sort = true,
        float = { border = 'rounded', source = 'if_many' },
        underline = { severity = vim.diagnostic.severity.ERROR },
        signs = vim.g.have_nerd_font and {
          text = {
            [vim.diagnostic.severity.ERROR] = '󰅚 ',
            [vim.diagnostic.severity.WARN] = '󰀪 ',
            [vim.diagnostic.severity.INFO] = '󰋽 ',
            [vim.diagnostic.severity.HINT] = '󰌶 ',
          },
        } or {},
        virtual_text = {
          source = 'if_many',
          spacing = 2,
        },
      }
    end,
  },
  -- Add clangd_extensions configuration
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
