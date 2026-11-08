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
        options = { options = { transparent = true } },
    },
    gruvbox = {
        name = "gruvbox",
        module = "gruvbox",
        background = "dark",
        options = { transparent_mode = false, contrast = "medium" },
    },
    gruvbox_light = {
        name = "gruvbox",
        background = "light",
        module = "gruvbox",
        options = { transparent_mode = false, contrast = "medium" },
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

function M.setup(theme_name)
    if type(theme_name) ~= "string" then
        theme_name = vim.env.NVIM_THEME
        if not theme_name or theme_name == "" then
            theme_name = "flexoki_light"
        end
    end

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

    local theme = assert(themes[theme_name], "Unknown theme preset: " .. theme_name)
    vim.opt.background = theme.background or "dark"
    if theme.module then
        require(theme.module).setup(theme.options)
    end
    vim.cmd.colorscheme(theme.name)
end

return M
