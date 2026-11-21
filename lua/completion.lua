local M = {}

function M.setup()
    vim.pack.add({
        { src = "https://github.com/saghen/blink.cmp", version = "v1" },  
        { src = "https://github.com/erooke/blink-cmp-latex" },
    })

    --> PlugIn: Blink.CMP
    local cmp = require("blink.cmp")
    cmp.setup({
        keymap = {
            preset = "super-tab",
            ["<C-Space>"] = false,
            ["<F2>"] = { "show", "fallback" },
        },

        sources = {
            providers = {
                snippets = {
                    -- Keep snippets out of ordinary word completion and super-tab.
                    enabled = function()
                        local line = vim.api.nvim_get_current_line()
                        local col = vim.api.nvim_win_get_cursor(0)[2]
                        return line:sub(1, col):match("![%w_]*$") ~= nil
                    end,
                },
                latex = {
                    name = "Latex",
                    module = "blink-cmp-latex",
                    opts = {
                            insert_command = true,
                    },
                },
            },
            per_filetype = {
                -- Prose files retain structured completion without buffer words.
                typst = { "lsp", "path", "snippets" },
                text = { "lsp", "path", "snippets" },
                markdown = { inherit_defaults = true, "latex", },
            },
        },


        cmdline = {
            keymap = {
                preset = "cmdline",
                ["<C-Space>"] = false,
                ["<F2>"] = { "show", "fallback" },
                ["<Tab>"] = { "accept", "fallback" },
            },
            completion = {
                menu = { auto_show = true },
                ghost_text = { enabled = false },
            },
        },

        completion = {
            menu = {
                auto_show = false,
                border = "rounded",
                scrollbar = false,
                cmdline_position = require("ui").menu_position,
            },

            ghost_text = {
                enabled = true,
            },
        },
    })
end

return M
