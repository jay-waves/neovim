local M = {}

local api = vim.api
local style = require("ui")
local ui2
local active_type
local depth = 0
local saved_window
local cmdline

local function cmd_window()
    local win = ui2.wins.cmd
    return win and api.nvim_win_is_valid(win) and win or nil
end

local function reset_cmdheight()
    vim._with({ noautocmd = true, o = { splitkeep = "screen" } }, function()
        vim.o.cmdheight = 0
    end)
end

-- Public blink menu callback: screen coordinates are zero-indexed.
function M.menu_position()
    local win = ui2 and cmd_window()
    if active_type and win then
        local pos = vim.fn.win_screenpos(win)
        -- win_screenpos is the content origin (1-indexed). Keep one column
        -- between the ':' prompt and the menu's existing label alignment.
        return { pos[1] - 1 + api.nvim_win_get_height(win), pos[2] + 2 }
    end
    return { vim.o.lines - math.max(vim.o.cmdheight, 1), 0 }
end

local function position()
    if not active_type then
        return
    end

    local win = cmd_window()
    if not win then
        return
    end
    if not saved_window then
        local cfg = api.nvim_win_get_config(win)
        saved_window = {
            config = {
                relative = cfg.relative,
                anchor = cfg.anchor,
                row = cfg.row,
                col = cfg.col,
                width = cfg.width,
                border = cfg.border,
            },
        }
    end

    local layout = style.float_config(api.nvim_win_get_height(win))
    local cfg = api.nvim_win_get_config(win)
    if cfg.relative ~= "editor" or cfg.row ~= layout.row or cfg.col ~= layout.col or cfg.width ~= layout.width then
        pcall(api.nvim_win_set_config, win, layout)
    end

    local menu = package.loaded["blink.cmp.completion.windows.menu"]
    if menu and menu.win:is_open() then menu.update_position() end
end

function M.setup()
    if ui2 then
        return
    end
    -- ui2 is an internal API; keep the standard command line on older builds.
    local ok, module = pcall(require, "vim._core.ui2")
    if not ok or type(module.enable) ~= "function" or not vim._with then
        vim.o.cmdheight = 1
        return
    end
    local ok_cmd, cmd = pcall(require, "vim._core.ui2.cmdline")
    if not ok_cmd or type(cmd.cmdline_show) ~= "function"
        or type(module.wins) ~= "table" or type(module.bufs) ~= "table" then
        vim.o.cmdheight = 1
        return
    end
    ui2, cmdline = module, cmd
    local group = api.nvim_create_augroup("PersonalCmdline", { clear = true })
    api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "cmd",
        callback = function()
            style.style_window(0)
        end,
    })

    reset_cmdheight()
    vim.opt.fillchars:append({ msgsep = "─" })
    ui2.enable({})

    -- ext_messages still emits write progress with shortmess=W.
    local messages = require("vim._core.ui2.messages")
    local original_message = messages.msg_show
    messages.msg_show = function(kind, content, replace_last, history, append, id, ...)
        if kind == "progress" and id == "bufwrite" then
            return
        end
        return original_message(kind, content, replace_last, history, append, id, ...)
    end

    local original_show = cmdline.cmdline_show
    cmdline.cmdline_show = function(...)
        original_show(...)
        if active_type then
            -- ui2 briefly raises cmdheight while drawing. Search keeps one row
            -- so Neovim can maintain its incremental-search preview.
            if active_type ~= "/" and active_type ~= "?" then
                reset_cmdheight()
            end
            position()
        end
    end
    api.nvim_create_autocmd("CmdlineEnter", {
        group = group,
        callback = function()
            depth = depth + 1
            active_type = vim.fn.getcmdtype()
            vim.schedule(position)
        end,
    })
    api.nvim_create_autocmd("CmdlineLeave", {
        group = group,
        callback = function()
            depth = math.max(0, depth - 1)
            -- CmdlineLeave also fires when returning to an outer command line.
            if depth > 0 then
                vim.schedule(function()
                    active_type = vim.fn.getcmdtype()
                    position()
                end)
                return
            end
            active_type = nil
            local win = cmd_window()
            if win and saved_window then
                pcall(api.nvim_win_set_config, win, saved_window.config)
            end
            saved_window = nil
            vim.schedule(function()
                if not active_type then
                    reset_cmdheight()
                end
            end)
        end,
    })
    api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
            vim.schedule(position)
        end,
    })
end

return M
