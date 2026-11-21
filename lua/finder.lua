local M = {}
local api = vim.api
local ui = require("ui")

-- File and buffer picker --------------------------------------------------
local active

local function selected(s)
    return api.nvim_win_get_cursor(s.win)[1]
end

local function close(s)
    if s.closed then return end
    s.closed = true
    if active == s then active = nil end
    local win = api.nvim_get_current_win()
    local restore = win == s.prompt_win or win == s.win
    if restore then vim.cmd.stopinsert() end
    if s.job then s.job:kill(15); s.job = nil end
    if s.group then api.nvim_del_augroup_by_id(s.group) end
    for _, id in ipairs({ s.prompt_win, s.win }) do
        if api.nvim_win_is_valid(id) then api.nvim_win_close(id, true) end
    end
    if restore and api.nvim_win_is_valid(s.origin) then
        api.nvim_set_current_win(s.origin)
    end
end

local function accept(s, index)
    local item = s.matches[index or selected(s)]
    if not item then return end
    close(s)
    if not api.nvim_win_is_valid(s.origin) then return end
    api.nvim_set_current_win(s.origin)
    local ok, err
    if s.kind == "buffers" then
        if not api.nvim_buf_is_valid(item.bufnr) or not vim.bo[item.bufnr].buflisted then return end
        ok, err = pcall(api.nvim_win_set_buf, s.origin, item.bufnr)
    else
        ok, err = pcall(vim.cmd.edit, { args = { item.filename }, magic = { file = false } })
    end
    if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
end

local function picker_config(count)
    return ui.float_config(math.min(13, math.max(2, count + 1)))
end

local function layout(s)
    local cfg = picker_config(#s.matches)
    local row = cfg.row
    cfg.row, cfg.height = row + 3, math.max(1, cfg.height - 1)
    api.nvim_win_set_config(s.win, cfg)
    api.nvim_win_set_config(s.prompt_win, {
        relative = "editor", row = row, col = cfg.col,
        width = cfg.width, height = 1,
    })
end

local function draw(s)
    if s.closed then return end
    local lines = {}
    for _, item in ipairs(s.matches) do
        if s.kind == "buffers" then
            lines[#lines + 1] = (item.bufnr == s.current and "> " or "  ")
                .. string.format("%-" .. s.id_width .. "s  ", tostring(item.bufnr))
                .. item.label .. (vim.bo[item.bufnr].modified and " [+]" or "")
        else
            lines[#lines + 1] = "  " .. item.label
        end
    end
    if #s.matches == 0 then lines[1] = "  No matches" end
    vim.bo[s.buf].modifiable = true
    api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
    vim.bo[s.buf].modifiable = false
end

local function refresh(s)
    if s.closed then return end
    local query = table.concat(api.nvim_buf_get_lines(s.prompt, 0, -1, false), " ")
    -- Pasted multiline text must not turn the one-line search into an editor.
    if api.nvim_buf_line_count(s.prompt) > 1 then
        api.nvim_buf_set_lines(s.prompt, 0, -1, false, { query })
        api.nvim_win_set_cursor(s.prompt_win, { 1, #query })
    end
    if s.kind == "buffers" then
        s.items = vim.tbl_filter(function(item)
            return api.nvim_buf_is_valid(item.bufnr) and vim.bo[item.bufnr].buflisted
        end, s.items)
    end
    local id = query:match("^(%d+)$")
    if query == "" then
        s.matches = s.items
    elseif id and s.kind == "buffers" then
        s.matches = vim.tbl_filter(function(item)
            return item.bufnr == tonumber(id)
        end, s.items)
    else
        s.matches = vim.fn.matchfuzzy(s.items, query, { key = "label" })
    end
    if s.kind ~= "buffers" and #s.matches > 20 then
        s.matches = vim.list_slice(s.matches, 1, 20)
    end
    layout(s)
    draw(s)
    api.nvim_win_set_cursor(s.win, { 1, 0 })
end

local function delete_selected(s)
    local index = selected(s)
    local item = s.matches[index]
    if not item then return end
    local ok, err = pcall(api.nvim_win_call, s.origin, function()
        api.nvim_buf_delete(item.bufnr, { force = false })
    end)
    if not ok then
        vim.notify(tostring(err), vim.log.levels.WARN)
        return
    end
    refresh(s)
    api.nvim_win_set_cursor(s.win, { math.max(1, math.min(index, #s.matches)), 0 })
end

local function open_picker(kind, query)
    kind = kind or "buffers"
    if active then close(active) end
    local s = {
        origin = api.nvim_get_current_win(), current = api.nvim_get_current_buf(),
        items = {}, matches = {}, id_width = 2, kind = kind,
    }
    local infos = kind == "buffers" and vim.fn.getbufinfo({ buflisted = 1 }) or {}
    -- Keep positions stable when switching files or reopening the picker.
    table.sort(infos, function(a, b)
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
    local cfg = picker_config(#s.items)
    s.win = ui.open_float(s.buf, true, cfg)
    s.prompt_win = ui.open_float(s.prompt, false, {
        relative = "editor", row = cfg.row, col = cfg.col,
        width = cfg.width, height = 1, border = "rounded",
        title = " " .. kind:gsub("^%l", string.upper) .. " ", title_pos = "left",
    })
    active = s
    for _, win in ipairs({ s.win, s.prompt_win }) do
        vim.wo[win].wrap = false
        vim.wo[win].scrolloff = 0
        vim.wo[win].sidescrolloff = 0
    end
    vim.wo[s.win].cursorline = true
    vim.wo[s.win].winhighlight = vim.wo[s.win].winhighlight .. ",CursorLine:PmenuSel"
    local function move(delta)
        if #s.matches == 0 then return end
        api.nvim_win_set_cursor(s.win, {
            math.max(1, math.min(#s.matches, selected(s) + delta)), 0,
        })
    end
    local function search()
        api.nvim_set_current_win(s.prompt_win)
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
        if buf == s.buf and kind == "buffers" then map("dd", function() delete_selected(s) end, "n") end
        -- Use the native mode transition so a following Esc reaches the normal map.
        map("<Esc>", "<Esc>", "i")
        for _, key in ipairs({ "/", "i" }) do
            map(key, function() search() end, "n")
        end
        map("<C-c>", function() close(s) end)
        map("<CR>", function() accept(s) end)
        map("l", function() accept(s) end, "n")
        for _, key in ipairs({ "<Down>", "<C-n>" }) do map(key, function() move(1) end) end
        for _, key in ipairs({ "<Up>", "<C-p>" }) do map(key, function() move(-1) end) end
        map("<ScrollWheelDown>", function() move(1) end)
        map("<ScrollWheelUp>", function() move(-1) end)
        map("<LeftMouse>", function()
            local mouse = vim.fn.getmousepos()
            if mouse.winid == s.win and mouse.line >= 1 then
                local index = mouse.line
                if index <= #s.matches then accept(s, index) end
            elseif mouse.winid == s.prompt_win then
                api.nvim_win_set_cursor(s.prompt_win, { 1, math.min(
                    math.max(0, mouse.column - 1), #api.nvim_get_current_line()) })
            end
        end)
    end
    s.group = api.nvim_create_augroup("PersonalBuffers", { clear = true })
    api.nvim_create_autocmd("InsertLeave", {
        group = s.group, buffer = s.prompt, callback = function()
            if not s.closed then api.nvim_set_current_win(s.win) end
        end,
    })
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
    if query and query ~= "" then
        api.nvim_buf_set_lines(s.prompt, 0, -1, false, { query })
        refresh(s)
    end
    if kind == "files" then
        local cwd = vim.fn.getcwd()
        if vim.fn.executable("rg") ~= 1 then
            vim.notify("ripgrep (rg) is not installed", vim.log.levels.ERROR)
        else
            s.job = vim.system({ "rg", "--files", "--hidden", "-g", "!.git", "-g", "!node_modules" },
                { cwd = cwd, text = true }, function(result)
                vim.schedule(function()
                    if s.closed then return end
                    s.job = nil
                    if result.code ~= 0 and result.code ~= 1 then
                        vim.notify(vim.trim(result.stderr or "rg failed"), vim.log.levels.ERROR)
                        return
                    end
                    for path in (result.stdout or ""):gmatch("[^\r\n]+") do
                        s.items[#s.items + 1] = {
                            filename = vim.fs.joinpath(cwd, path),
                            label = path:gsub("[%z\1-\31\127]", " "),
                        }
                    end
                    refresh(s)
                end)
            end)
        end
    end
    layout(s)
    draw(s)
    for index, item in ipairs(s.matches) do
        if item.bufnr == s.current then
            api.nvim_win_set_cursor(s.win, { index, 0 })
            break
        end
    end
    vim.cmd.stopinsert()
end


local function setup_picker()
    api.nvim_create_user_command("Oldfiles", "browse oldfiles", { desc = "Browse recent files" })
    for name, kind in pairs({ Files = "files", Buffers = "buffers" }) do
        api.nvim_create_user_command(name, function(args)
            open_picker(kind, args.args)
        end, { nargs = "*", desc = "Choose " .. kind })
    end
    local group = api.nvim_create_augroup("PersonalPicker", { clear = true })
    api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function()
        if active then close(active) end
    end })
end

-- File explorer and Git ---------------------------------------------------
local function setup_files()
    vim.pack.add({
        "https://github.com/nvim-mini/mini.files",
        "https://github.com/nvim-mini/mini-git",
    })

    local git_group = api.nvim_create_augroup("PersonalMiniGit", { clear = true })
    api.nvim_create_autocmd("User", {
        group = git_group,
        pattern = "MiniGitUpdated",
        callback = function(args)
            local summary = vim.b[args.buf].minigit_summary or {}
            local xy, mark = summary.status or "", ""
            if xy == "??" then mark = "?"
            elseif xy:find("U", 1, true) or xy == "AA" or xy == "DD" then mark = "U"
            elseif xy:find("D", 1, true) then mark = "D"
            elseif xy:find("A", 1, true) then mark = "A"
            elseif xy:find("[MT]") then mark = "M"
            elseif xy:find("[RC]") then mark = xy:match("[RC]")
            end
            vim.b[args.buf].minigit_summary_string = mark == "" and "" or (" [" .. mark .. "]")
        end,
    })
    require("mini.git").setup()

    local gs, diff_win
    local function highlight_changes(enabled)
        gs.toggle_linehl(enabled)
        gs.toggle_deleted(enabled)
    end
    for key, direction in pairs({ n = "next", N = "prev" }) do
        vim.keymap.set("n", key, function()
            if diff_win and api.nvim_win_is_valid(diff_win)
                and api.nvim_win_get_tabpage(diff_win) == api.nvim_get_current_tabpage()
                and vim.b.gitsigns_status_dict then
                return "<Cmd>Gitsigns nav_hunk " .. direction .. "<CR>"
            end
            return key
        end, { expr = true, desc = "Navigate Git hunks or search matches" })
    end
    api.nvim_create_autocmd("WinClosed", {
        group = git_group,
        callback = function(args)
            if tonumber(args.match) == diff_win then
                diff_win = nil
                highlight_changes(false)
            end
        end,
    })
    local building_list = false
    vim.keymap.set("n", "<leader>g", function()
        local list = vim.fn.getqflist({ title = 0, winid = 0 })
        if list.title == "Git changed files" and list.winid ~= 0 then
            vim.cmd.cclose()
            return
        end
        if building_list then return end
        if not gs then
            vim.pack.add({ "https://github.com/lewis6991/gitsigns.nvim" })
            gs = require("gitsigns")
            gs.setup({ signcolumn = false, numhl = false, linehl = false })
            vim.keymap.set("n", "<leader>G", gs.preview_hunk_inline, { desc = "Preview Git hunk inline" })
        end
        building_list = true
        gs.setqflist("all", { open = false }, function(err)
            building_list = false
            if err then
                vim.notify(tostring(err), vim.log.levels.ERROR)
                return
            end
            local files, seen = {}, {}
            for _, item in ipairs(vim.fn.getqflist()) do
                if not seen[item.bufnr] then
                    seen[item.bufnr] = true
                    item.text = ""
                    table.insert(files, item)
                end
            end
            vim.fn.setqflist({}, "r", { title = "Git changed files", items = files })
            vim.cmd.copen()
            diff_win = vim.fn.getqflist({ winid = 0 }).winid
            highlight_changes(true)
        end)
    end, { desc = "Toggle Git changed files" })

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

    local files_group = api.nvim_create_augroup("PersonalMiniFiles", { clear = true })
    api.nvim_create_autocmd("User", {
        group = files_group,
        pattern = "MiniFilesWindowUpdate",
        callback = function(args)
            local win = args.data.win_id
            local config = api.nvim_win_get_config(win)
            config.height, config.border = math.min(config.height, 18), "rounded"
            api.nvim_win_set_config(win, config)
            vim.wo[win].number = false
            vim.wo[win].relativenumber = false
            vim.wo[win].signcolumn = "no"
            vim.wo[win].statuscolumn = ""
            vim.wo[win].winblend = 0
        end,
    })

    api.nvim_create_autocmd("User", {
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
        require("mini.files").open(api.nvim_buf_get_name(0))
    end, { desc = "Open Mini.Files", })

    vim.keymap.set("n", "<leader>E", function()
        vim.ui.open(vim.fn.getcwd())
    end, { desc = "Open file manager", })

end

-- Quickfix search, symbols and diagnostics --------------------------------
local process, generation = nil, 0

local function show_quickfix(title, items, empty_message, format)
    vim.fn.setqflist({}, " ", { title = title, items = items, quickfixtextfunc = format })
    if #items == 0 then
        vim.cmd.cclose()
        vim.notify(empty_message)
    else
        vim.cmd("botright copen")
    end
end

local function grep(pattern)
    if vim.fn.executable("rg") ~= 1 then
        vim.notify("ripgrep (rg) is not installed", vim.log.levels.ERROR)
        return
    end
    generation = generation + 1
    local request, cwd = generation, vim.fn.getcwd()
    if process then process:kill(15) end
    process = vim.system({ "rg", "--json", "--smart-case", "--", pattern, "." },
        { cwd = cwd, text = true }, function(result)
            vim.schedule(function()
                if request ~= generation then return end
                process = nil
                if result.code > 1 then
                    vim.notify(vim.trim(result.stderr or "rg failed"), vim.log.levels.ERROR)
                    return
                end
                local items = {}
                for line in (result.stdout or ""):gmatch("[^\n]+") do
                    local event = vim.json.decode(line)
                    if event.type == "match" then
                        local d = event.data
                        local path = d.path.text or vim.base64.decode(d.path.bytes)
                        local content = d.lines.text or vim.base64.decode(d.lines.bytes)
                        for _, match in ipairs(d.submatches) do
                            items[#items + 1] = {
                                filename = vim.fs.joinpath(cwd, path),
                                lnum = d.line_number, col = match.start + 1,
                                text = content:gsub("[\r\n]+$", ""),
                            }
                        end
                    end
                end
                show_quickfix("rg: " .. pattern, items, "No matches: " .. pattern)
            end)
        end)
end

local function symbol_text(info)
    local entries = vim.fn.getqflist({ id = info.id, items = 0 }).items
    local max_line, max_col = 0, 0
    for _, item in ipairs(entries) do
        max_line = math.max(max_line, item.lnum)
        max_col = math.max(max_col, item.col)
    end
    local format = string.format("%%%dd:%%%dd  %%s", #tostring(max_line), #tostring(max_col))
    local lines = {}
    for i = info.start_idx, info.end_idx do
        local item = entries[i]
        lines[#lines + 1] = string.format(format, item.lnum, item.col, item.text)
    end
    return lines
end

local function treesitter_items(buf)
    local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
    assert(lang, "No Tree-sitter language for this buffer")
    local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
    assert(ok and parser, "Tree-sitter parser unavailable; install it with :TSInstall " .. lang)
    local query = vim.treesitter.query.get(lang, "locals")
    assert(query, "No Tree-sitter locals query for " .. lang)
    local items, seen = {}, {}
    for _, tree in ipairs(parser:parse()) do
        local root = tree:root()
        local scopes = {}
        for id, node in query:iter_captures(root, buf, 0, -1) do
            if query.captures[id] == "local.scope" and node:id() ~= root:id() then
                scopes[node:id()] = true
            end
        end
        for id, node in query:iter_captures(root, buf, 0, -1) do
            local capture = query.captures[id]
            if capture == "local.definition" or capture:match("^local%.definition%.") then
                -- Associated receivers are references, not additional declarations.
                if capture ~= "local.definition.associated" then
                    local row, col = node:range()
                    local key = row .. ":" .. col
                    if not seen[key] then
                        seen[key] = true
                        local kind = capture:match("^local%.definition%.(.+)$") or "definition"
                        local depth, ancestor = 0, node:parent()
                        local section_heading = kind == "heading" and (lang == "markdown" or lang == "typst")
                        while ancestor do
                            if section_heading and ancestor:type() == "section" then
                                depth = depth + 1
                            elseif not section_heading and scopes[ancestor:id()] then
                                local name = ancestor:field("name")[1]
                                if not name or name:id() ~= node:id() then depth = depth + 1 end
                            end
                            ancestor = ancestor:parent()
                        end
                        -- The nearest section belongs to the heading itself.
                        if section_heading then depth = math.max(0, depth - 1) end
                        local label = vim.treesitter.get_node_text(node, buf)
                        if lang == "typst" and section_heading then
                            label = label:gsub("^=+%s*", "")
                        end
                        items[#items + 1] = { bufnr = buf, lnum = row + 1, col = col + 1,
                            text = string.rep("    ", depth) .. "[" .. kind .. "] " .. label }
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b) return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col) end)
    return items
end


local function open_symbols(query)
    local ok, items = pcall(treesitter_items, api.nvim_get_current_buf())
    if not ok then
        vim.notify(tostring(items), vim.log.levels.ERROR)
        return
    end
    if query ~= "" then
        local needle = query:lower()
        items = vim.tbl_filter(function(item)
            return item.text:lower():find(needle, 1, true) ~= nil
        end, items)
    end
    show_quickfix("Symbols", items, "No symbols found", symbol_text)
end

local function setup_quickfix()
    local group = api.nvim_create_augroup("PersonalQuickfix", { clear = true })
    api.nvim_create_user_command("Grep", function(args) grep(args.args) end,
        { nargs = "+", desc = "Search cwd into quickfix" })
    api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function()
        generation = generation + 1
        if process then process:kill(15) end
    end })
    api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "qf",
        callback = function(args)
            vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = args.buf, desc = "Close quickfix window" })
        end,
    })
    vim.keymap.set("n", "<leader>l", function()
        vim.diagnostic.open_float({
            scope = "line",
            source = true,
        })
    end, { desc = "Show line diagnostics" })
    vim.keymap.set("n", "<leader>L", function()
        if vim.fn.getloclist(0, { winid = 0 }).winid ~= 0 then
            vim.cmd("lclose")
        else
            vim.diagnostic.setloclist({ open = true })
        end
    end, { desc = "Toggle diagnostics loclist" })
    for _, name in ipairs({ "Symbols", "TreeSitter" }) do
        api.nvim_create_user_command(name, function(args) open_symbols(args.args) end,
            { nargs = "*", desc = "List Treesitter symbols in quickfix (optional text filter)" })
    end
end

function M.setup()
    setup_picker()
    setup_files()
    setup_quickfix()

    vim.keymap.set("n", "<leader>f", "<Cmd>Files<CR>", { desc = "Find files" })
    vim.keymap.set("n", "<leader>/", ":Grep ", { desc = "Search contents into quickfix" })
    vim.keymap.set("n", "<leader>s", "<Cmd>Symbols<CR>", { desc = "Show Treesitter symbols" })
    vim.keymap.set("n", "<leader>S", "<Cmd>Symbols<CR>", { desc = "Show Treesitter symbols" })
    vim.keymap.set("n", "<leader>o", "<Cmd>Buffers<CR>", { desc = "Choose buffer" })
end

return M
