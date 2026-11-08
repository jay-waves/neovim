local M = {}

function M.setup()
    vim.pack.add({ "https://github.com/nvim-mini/mini.files" })

    --> PlugIn: Mini.Files, vim-like keymap, and = to save changes
    require("mini.files").setup({
        mappings = {
            go_in = "",
            go_in_plus = "l",
        },
        windows = {
            max_number = 3,
            preview = true,
            width_focus = 30,
            width_nofocus = 30,
            width_preview = 60,
        },
    })

    local files_group = vim.api.nvim_create_augroup("PersonalMiniFiles", { clear = true })
    local function style_files()
        for _, name in ipairs({ "MiniFilesNormal", "MiniFilesBorder", "MiniFilesTitle" }) do
            vim.api.nvim_set_hl(0, name, { link = "Normal" })
        end
        vim.api.nvim_set_hl(0, "MiniFilesTitleFocused", { link = "Title" })
    end
    style_files()
    vim.api.nvim_create_autocmd("ColorScheme", { group = files_group, callback = style_files })
    vim.api.nvim_create_autocmd("User", {
        group = files_group,
        pattern = "MiniFilesWindowUpdate",
        callback = function(args)
            local win = args.data.win_id
            local config = vim.api.nvim_win_get_config(win)
            config.height, config.border = math.min(config.height, 18), "rounded"
            vim.api.nvim_win_set_config(win, config)
            vim.wo[win].number = false
            vim.wo[win].relativenumber = false
            vim.wo[win].signcolumn = "no"
            vim.wo[win].statuscolumn = ""
            vim.wo[win].winblend = 0
        end,
    })

    vim.api.nvim_create_autocmd("User", {
        group = files_group,
        pattern = "MiniFilesBufferCreate",
        callback = function(args)
            vim.keymap.set("n", "L", function()
                local entry = require("mini.files").get_fs_entry()
                if not entry then
                    vim.notify("Cursor is not on a valid file or directory", vim.log.levels.WARN)
                    return
                end
                local _, err = vim.ui.open(entry.path)
                if err then
                    vim.notify(err, vim.log.levels.ERROR)
                    return
                end
                require("mini.files").close()
            end, { buffer = args.data.buf_id, desc = "Open with system default application and close explorer" })
        end,
    })

    vim.keymap.set("n", "<leader>e", function()
        require("mini.files").open(vim.api.nvim_buf_get_name(0))
    end, { desc = "Open Mini.Files", })

    vim.keymap.set("n", "<leader>E", function()
        vim.ui.open(vim.fn.getcwd())
    end, { desc = "Open file manager", })

end

return M
