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

local function set_highlights()
    local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end
    local mode = hl("StatusLine")
    mode.bold = true
    vim.api.nvim_set_hl(0, "StatusLineMode", mode)
    vim.api.nvim_set_hl(0, "GitSignsVirtLnum", { link = "LineNr" })
    vim.api.nvim_set_hl(0, "GitSignsChangeLn", { link = "GitSignsAddLn" })

    for _, name in ipairs({ "MiniFilesNormal", "MiniFilesBorder", "MiniFilesTitle" }) do
        vim.api.nvim_set_hl(0, name, { link = "Normal" })
    end
    vim.api.nvim_set_hl(0, "MiniFilesTitleFocused", { link = "Title" })

    local normal = hl("Normal")
    local accent = hl("Title").fg or hl("DiagnosticInfo").fg or normal.fg
    local muted = hl("Comment").fg or normal.fg
    local function set_hl(name, options)
        options.bg = normal.bg
        vim.api.nvim_set_hl(0, name, options)
    end
    set_hl("BlinkCmpMenu", { fg = normal.fg })
    set_hl("BlinkCmpMenuBorder", { fg = accent })
    set_hl("BlinkCmpLabel", { fg = normal.fg })
    set_hl("BlinkCmpLabelMatch", { fg = accent, bold = true })
    set_hl("BlinkCmpLabelDetail", { fg = muted })
    set_hl("BlinkCmpLabelDescription", { fg = muted })
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
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("PersonalTheme", { clear = true }),
        callback = set_highlights,
    })
    vim.cmd.colorscheme(theme.name)
end

return M
