-- Small shared style for our floats; no UI lifecycle or ui2 internals here.
local M = {}

function M.float_config(height)
    local width = math.max(1, math.min(vim.o.columns - 2, 80, math.max(40, math.floor(vim.o.columns * 0.6))))
    -- Keep the prompt at the same height as ':'; results grow downwards.
    local row = math.max(0, math.floor((vim.o.lines - 3) * 0.25))
    height = math.max(1, math.min(height, vim.o.lines - row - 3))
    return {
        relative = "editor", border = "rounded", width = width, height = height,
        row = row, col = math.max(0, math.floor((vim.o.columns - width - 2) * 0.5)),
    }
end

function M.style_window(win)
    vim.wo[win].winhighlight = "Normal:Normal,NormalNC:Normal,FloatBorder:Normal,FloatTitle:Normal,Search:,CurSearch:,IncSearch:"
    vim.wo[win].winblend = 0
end

function M.open_float(buf, enter, config)
    config.style = "minimal"
    local win = vim.api.nvim_open_win(buf, enter, config)
    M.style_window(win)
    return win
end

function M.palette()
    local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end
    local normal = hl("Normal")
    return {
        fg = normal.fg,
        bg = normal.bg,
        accent = hl("Title").fg or hl("DiagnosticInfo").fg or normal.fg,
        muted = hl("Comment").fg or normal.fg,
    }
end

return M
