local M = {}

local themes = {
    flexoki = {
        name = "flexoki-dark",
        background = "dark",
    },
    flexoki_light = {
        name = "flexoki-light",
        background = "light",
    },
    nordbones = {
        name = "nordbones",
        background = "dark",
    },
    zenwritten_light = {
        name = "zenwritten",
        background = "light",
    },
    patana_light = {
        name = "patana",
        background = "light",
    },
    github_light = {
        name = "github_light",
        background = "light",
        module = "github-theme",
        options = { options = { transparent = false } },
    },
    github = {
        name = "github_dark_tritanopia",
        module = "github-theme",
        options = { options = { transparent = false } },
    },
    gruvbox = {
        name = "gruvbox",
        module = "gruvbox",
        background = "dark",
        options = { transparent_mode = false, contrast = "" },
    },
    gruvbox_light = {
        name = "gruvbox",
        background = "light",
        module = "gruvbox",
        options = { transparent_mode = false, contrast = "" },
    },
    alabaster = {
        name = "alabaster",
        background = "light",
    },
    zenbones = {
        name = "zenbones",
        background = "dark",
    },
}

local function system_background()
    if vim.fn.has("win32") ~= 1 then
        return "dark"
    end

    local ffi = require("ffi")
    ffi.cdef[[
        long __stdcall RegGetValueA(void *key, const char *subkey,
            const char *value, unsigned long flags, unsigned long *type,
            void *data, unsigned long *size);
    ]]
    local registry = ffi.load("advapi32")
    local value = ffi.new("unsigned long[1]")
    local size = ffi.new("unsigned long[1]", ffi.sizeof(value))
    -- Sign-extended HKEY_CURRENT_USER; read only the DWORD application preference.
    local current_user = ffi.cast("void *", ffi.cast("intptr_t", -2147483647))
    local status = registry.RegGetValueA(current_user,
        [[Software\Microsoft\Windows\CurrentVersion\Themes\Personalize]],
        "AppsUseLightTheme", 0x10, nil, value, size)
    return status == 0 and value[0] == 1 and "light" or "dark"
end

local function setup_statusline()
    local api = vim.api
    local function set_highlights()
        local mode = api.nvim_get_hl(0, { name = "StatusLine", link = false })
        mode.bold = true
        api.nvim_set_hl(0, "StatusLineMode", mode)
    end

    vim.o.laststatus = 3
    vim.o.showmode = false
    vim.o.statusline = " %#StatusLineMode#%{mode()}%*  %<%f%( %m%r%)%{get(b:, 'minigit_summary_string', '')} (%{len(filter(getbufinfo(), 'v:val.listed'))})%= %y  %l:%v  %p%% "
    local group = api.nvim_create_augroup("PersonalStatusline", { clear = true })
    set_highlights()
    api.nvim_create_autocmd("ColorScheme", {
        group = group, callback = set_highlights,
    })
    local function redraw()
        vim.schedule(function() vim.cmd.redrawstatus() end)
    end
    api.nvim_create_autocmd({ "ModeChanged", "BufAdd", "BufDelete" }, {
        group = group, callback = redraw,
    })
    api.nvim_create_autocmd("OptionSet", {
        group = group, pattern = "buflisted", callback = redraw,
    })
end

local function setup_title()
    -- 保存原始标题配置
    local original = {
        title = vim.o.title,
        titlestring = vim.o.titlestring,
    }

    local group = vim.api.nvim_create_augroup("BufTitle", {
        clear = true,
    })

    local function restore()
        vim.o.titlestring = original.titlestring
        vim.o.title = original.title
    end

    -- 进入 Buffer 或窗口时更新标题
    vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
        group = group,
        callback = function()
            if vim.bo.buftype ~= "" then
                restore()
                return
            end

            vim.o.title = true
            -- 标题表达式会随 modified 状态更新：未保存时显示 *，保存后消失。
            vim.o.titlestring = "%t%{&modified ? ' *' : ''}"
        end,
    })

    -- 离开窗口时恢复原始标题
    vim.api.nvim_create_autocmd("WinLeave", {
        group = group,
        callback = restore,
    })
end

function M.setup(config)
    local name = config[system_background()]
    local theme = assert(themes[name], "Unknown theme preset: " .. tostring(name))

    vim.g.zenbones_darkness = "warm"

    vim.pack.add({
        "https://github.com/rktjmp/lush.nvim",
        "https://github.com/zenbones-theme/zenbones.nvim",
        "https://github.com/projekt0n/github-nvim-theme",
        "https://github.com/ellisonleao/gruvbox.nvim",
        "https://github.com/cvigilv/patana.nvim",
        "https://github.com/dchinmay2/alabaster.nvim",
        "https://github.com/kepano/flexoki-neovim",
    })

    vim.opt.background = theme.background or "dark"
    if theme.module then
        require(theme.module).setup(theme.options)
    end
    vim.cmd.colorscheme(theme.name)
    setup_statusline()
    setup_title()
end

return M
