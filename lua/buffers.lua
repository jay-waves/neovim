local M = {}
local api = vim.api
local style = require("ui")
local ns = api.nvim_create_namespace("PersonalBuffers")
local active

local function close(s)
    if s.closed then return end
    s.closed = true
    if active == s then active = nil end
    local win = api.nvim_get_current_win()
    local restore = win == s.prompt_win or win == s.win
    if restore then vim.cmd.stopinsert() end
    if s.group then api.nvim_del_augroup_by_id(s.group) end
    for _, id in ipairs({ s.prompt_win, s.win }) do
        if api.nvim_win_is_valid(id) then api.nvim_win_close(id, true) end
    end
    if restore and api.nvim_win_is_valid(s.origin) then
        api.nvim_set_current_win(s.origin)
    end
end

local function accept(s, index)
    local item = s.matches[index or s.selected]
    if not item then return end
    close(s)
    if api.nvim_win_is_valid(s.origin) and api.nvim_buf_is_valid(item.bufnr)
        and vim.bo[item.bufnr].buflisted then
        api.nvim_set_current_win(s.origin)
        local ok, err = pcall(api.nvim_win_set_buf, s.origin, item.bufnr)
        if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
    end
end

local function layout(s)
    local cfg = style.float_config(math.min(13, math.max(2, #s.matches + 1)))
    api.nvim_win_set_config(s.win, cfg)
    api.nvim_win_set_config(s.prompt_win, {
        relative = "editor", row = cfg.row + 1, col = cfg.col + 1,
        width = cfg.width, height = 1,
    })
end

local function draw(s)
    if s.closed then return end
    local lines = { "" }
    -- Scroll the results without moving the search field.
    local capacity = math.max(1, api.nvim_win_get_height(s.win) - 1)
    s.top = math.max(1, math.min(s.top, s.selected))
    if s.selected >= s.top + capacity then s.top = s.selected - capacity + 1 end
    for i = s.top, math.min(#s.matches, s.top + capacity - 1) do
        local item = s.matches[i]
        lines[#lines + 1] = (item.bufnr == s.current and "> " or "  ")
            .. string.format("%-" .. s.id_width .. "s  ", tostring(item.bufnr))
            .. item.label .. (vim.bo[item.bufnr].modified and " [+]" or "")
    end
    if #s.matches == 0 then lines[2] = "  No matches" end
    vim.bo[s.buf].modifiable = true
    api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
    vim.bo[s.buf].modifiable = false
    api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
    if #s.matches > 0 then
        api.nvim_buf_set_extmark(s.buf, ns, s.selected - s.top + 1, 0, {
            line_hl_group = "PmenuSel", hl_eol = true,
        })
    end
end

local function refresh(s)
    if s.closed then return end
    local query = table.concat(api.nvim_buf_get_lines(s.prompt, 0, -1, false), " ")
    -- Pasted multiline text must not turn the one-line search into an editor.
    if api.nvim_buf_line_count(s.prompt) > 1 then
        api.nvim_buf_set_lines(s.prompt, 0, -1, false, { query })
        api.nvim_win_set_cursor(s.prompt_win, { 1, #query })
    end
    s.items = vim.tbl_filter(function(item)
        return api.nvim_buf_is_valid(item.bufnr) and vim.bo[item.bufnr].buflisted
    end, s.items)
    local id = query:match("^(%d+)$")
    if query == "" then
        s.matches = s.items
    elseif id then
        s.matches = vim.tbl_filter(function(item)
            return item.bufnr == tonumber(id)
        end, s.items)
    else
        s.matches = vim.fn.matchfuzzy(s.items, query, { key = "label" })
    end
    s.selected, s.top = 1, 1
    layout(s)
    draw(s)
end

function M.open()
    if active then close(active) end
    local s = {
        origin = api.nvim_get_current_win(), current = api.nvim_get_current_buf(),
        items = {}, matches = {}, selected = 1, top = 1, id_width = 2,
    }
    local infos = vim.fn.getbufinfo({ buflisted = 1 })
    table.sort(infos, function(a, b)
        if a.bufnr == s.current then return b.bufnr ~= s.current end
        if b.bufnr == s.current then return false end
        if a.lastused ~= b.lastused then return a.lastused > b.lastused end
        return a.bufnr < b.bufnr
    end)
    for _, info in ipairs(infos) do
        s.id_width = math.max(s.id_width, #tostring(info.bufnr))
        local label = info.name == "" and "[No Name]"
            or vim.fn.fnamemodify(info.name, ":~:.")
        s.items[#s.items + 1] = {
            bufnr = info.bufnr, label = label:gsub("[%z\1-\31\127]", " "),
        }
    end
    s.matches = s.items
    s.buf = api.nvim_create_buf(false, true)
    s.prompt = api.nvim_create_buf(false, true)
    for _, buf in ipairs({ s.buf, s.prompt }) do
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].swapfile = false
        vim.b[buf].completion = false
        vim.bo[buf].filetype = "bufferpicker"
    end
    local cfg = style.float_config(math.min(13, math.max(2, #s.items + 1)))
    cfg.style, cfg.title, cfg.title_pos = "minimal", " Buffers ", "left"
    s.win = api.nvim_open_win(s.buf, false, cfg)
    s.prompt_win = api.nvim_open_win(s.prompt, true, {
        relative = "editor", row = cfg.row + 1, col = cfg.col + 1,
        width = cfg.width, height = 1, style = "minimal", zindex = 51,
    })
    active = s
    for _, win in ipairs({ s.win, s.prompt_win }) do
        style.style_window(win)
        vim.wo[win].wrap = false
        vim.wo[win].scrolloff = 0
        vim.wo[win].sidescrolloff = 0
    end
    local function move(delta)
        if #s.matches == 0 then return end
        s.selected = (s.selected - 1 + delta) % #s.matches + 1
        draw(s)
    end
    local function search(digit)
        api.nvim_set_current_win(s.prompt_win)
        if digit then
            api.nvim_buf_set_lines(s.prompt, 0, -1, false, { digit })
            refresh(s)
        end
        local query = api.nvim_buf_get_lines(s.prompt, 0, 1, false)[1] or ""
        api.nvim_win_set_cursor(s.prompt_win, { 1, #query })
        vim.cmd.startinsert({ bang = true })
    end
    for _, buf in ipairs({ s.buf, s.prompt }) do
        local function map(key, fn, mode)
            vim.keymap.set(mode or { "n", "i" }, key, fn, { buffer = buf, silent = true })
        end
        map("<Esc>", function() close(s) end, "n")
        map("q", function() close(s) end, "n")
        -- Use the native mode transition so a following Esc reaches the normal map.
        map("<Esc>", "<Esc>", "i")
        map("j", function() move(1) end, "n")
        map("k", function() move(-1) end, "n")
        for _, key in ipairs({ "/", "i" }) do
            map(key, function() search() end, "n")
        end
        for digit = 0, 9 do
            local value = tostring(digit)
            map(value, function() search(value) end, "n")
        end
        map("<C-c>", function() close(s) end)
        map("<CR>", function() accept(s) end)
        for _, key in ipairs({ "<Down>", "<C-n>" }) do map(key, function() move(1) end) end
        for _, key in ipairs({ "<Up>", "<C-p>" }) do map(key, function() move(-1) end) end
        map("<ScrollWheelDown>", function() move(1) end)
        map("<ScrollWheelUp>", function() move(-1) end)
        map("<LeftMouse>", function()
            local mouse = vim.fn.getmousepos()
            if mouse.winid == s.win and mouse.line >= 2 then
                local index = s.top + mouse.line - 2
                if index <= #s.matches then accept(s, index) end
            elseif mouse.winid == s.prompt_win then
                api.nvim_win_set_cursor(s.prompt_win, { 1, math.min(
                    math.max(0, mouse.column - 1), #api.nvim_get_current_line()) })
            end
        end)
    end
    s.group = api.nvim_create_augroup("PersonalBuffers", { clear = true })
    api.nvim_create_autocmd({ "TextChangedI", "TextChanged", "TextChangedP" }, {
        group = s.group, buffer = s.prompt, callback = function() refresh(s) end,
    })
    api.nvim_create_autocmd("VimResized", { group = s.group, callback = function()
        layout(s)
        draw(s)
    end })
    api.nvim_create_autocmd({ "WinLeave", "WinClosed", "BufWipeout" }, {
        group = s.group, callback = function()
            vim.schedule(function()
                if s.closed then return end
                local win = api.nvim_get_current_win()
                if not api.nvim_win_is_valid(s.win) or not api.nvim_win_is_valid(s.prompt_win)
                    or (win ~= s.win and win ~= s.prompt_win) then close(s) end
            end)
        end,
    })
    draw(s)
    vim.cmd.stopinsert()
end

return M
