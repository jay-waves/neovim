local M = {}

local servers = {
    "lua_ls",
    "gopls",
    "ty",
    "tinymist",
--     "rumdl",
}

function M.setup()
    -- Completion is initialized by init.lua before LSP setup.
    vim.pack.add({
        "https://github.com/nvim-treesitter/nvim-treesitter",
        "https://github.com/neovim/nvim-lspconfig",
        "https://github.com/stevearc/conform.nvim",
    })

    --> PlugIn: TreeSitter, use TSInstall & TSUpdate
    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("PersonalTreesitter", { clear = true }),
        callback = function()
            local filetype = vim.bo.filetype
            -- Skip temporary and plugin UI buffers, which are not source files.
            if vim.bo.buftype ~= "" or filetype == "qf" or filetype == "minifiles" or filetype == "fzf" then
                return
            end

            local lang = vim.treesitter.language.get_lang(filetype)
            if not lang then
                return
            end

            pcall(vim.treesitter.start, 0, lang)
        end,
    })

    ---------------------------------------------------------------------------
    -- Diagnostics
    ---------------------------------------------------------------------------

    vim.diagnostic.config({
        severity_sort = true,
        underline = true,
        signs = true,
        update_in_insert = false,
        virtual_text = false,

        float = {
            border = "rounded",
            source = "if_many",
        },
    })

    ---------------------------------------------------------------------------
    -- LSP defaults
    ---------------------------------------------------------------------------

    -- Applied to every LSP server.
    vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(),
    })

    ---------------------------------------------------------------------------
    -- Lua
    ---------------------------------------------------------------------------

    vim.lsp.config("lua_ls", {
        settings = {
            Lua = {
                diagnostics = {
                    globals = { "vim" },
                },
            },
        },
    })

    ---------------------------------------------------------------------------
    -- Typst
    --
    -- cmd/filetypes/root_markers come from nvim-lspconfig.
    ---------------------------------------------------------------------------

    vim.lsp.config("tinymist", {
        settings = {
            syntaxOnly = "disable",
            projectResolution = "singleFile",
            systemFonts = false,
            fontPaths = {},
            exportPdf = "never",
            formatterMode = "typstyle",

            preview = {
                background = {
                    enabled = false,
                },
            },
        },
    })

    ---------------------------------------------------------------------------
    -- Markdown
    ---------------------------------------------------------------------------

    -- vim.lsp.config("rumdl", {
    --     root_markers = {
    --         ".rumdl.toml",
    --         "rumdl.toml",
    --         ".git",
    --     },
    --
    --     init_options = {
    --         disableRules = {
    --             "MD033",
    --             "MD041",
    --             "MD045",
    --             "MD004",
    --             "MD007",
    --             "MD009",
    --         },
    --
    --         settings = {
    --             lineLength = 100,
    --         },
    --     },
    -- })

    ---------------------------------------------------------------------------
    -- Enable LSP servers
    --
    -- gopls and ty need no local configuration; nvim-lspconfig provides
    -- cmd, filetypes, root detection, etc.
    ---------------------------------------------------------------------------

    -- Server executables are installed separately on each host.
    for _, server in ipairs(servers) do
        local config = vim.lsp.config[server]
        local cmd = config and config.cmd
        if type(cmd) == "function" or (type(cmd) == "table" and vim.fn.executable(cmd[1]) == 1) then
            vim.lsp.enable(server)
        end
    end

    ---------------------------------------------------------------------------
    -- Formatting
    ---------------------------------------------------------------------------

    local conform = require("conform")

    conform.setup({
        formatters_by_ft = {
            lua = {
                "stylua",
            },

            -- Prefer goimports; fall back to gofmt if it isn't installed.
            go = {
                "goimports",
                "gofmt",
                stop_after_first = true,
            },

            python = {
                "ruff_format",
            },

            -- Prettier also formats supported code fences embedded in Markdown.
            html = { "prettier" },
            css = { "prettier" },
            scss = { "prettier" },
            less = { "prettier" },
            javascript = { "prettier" },
            javascriptreact = { "prettier" },
            typescript = { "prettier" },
            typescriptreact = { "prettier" },
            json = { "prettier" },
            jsonc = { "prettier" },
            yaml = { "prettier" },
            graphql = { "prettier" },
            vue = { "prettier" },
            svelte = { "prettier" },
            astro = { "prettier" },
            handlebars = { "prettier" },
            markdown = { "prettier" },

            -- Typst deliberately has no external formatter here.
            -- Conform falls back to Tinymist, whose formatterMode is typstyle.
        },

        default_format_opts = {
            timeout_ms = 3000,
            lsp_format = "fallback",
        },

        notify_on_error = true,
        notify_no_formatters = false,
    })

    -- Use the native gq operator (gqq, gq{motion}, and visual-mode gq).
    vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

end

return M
