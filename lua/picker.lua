local M = {}
local api = vim.api
local style = require("ui")
local active
local kinds = { "files", "oldfiles" }
local binaries, search_path = {}, nil

-- Prefer Scoop's real binary, avoiding an extra shim process on Windows.
local function executable(name)
    if search_path ~= vim.env.PATH then binaries, search_path = {}, vim.env.PATH end
    if binaries[name] and vim.fn.executable(binaries[name]) == 1 then return binaries[name] end
    local path = vim.fn.exepath(name)
    if vim.fn.has("win32") == 1 and path ~= "" then
        local shim = path:gsub("%.[eE][xX][eE]$", ".shim")
        if vim.fn.filereadable(shim) == 1 then
            local target = table.concat(vim.fn.readfile(shim), "\n"):match('path%s*=%s*"([^"]+)"')
            if target and vim.fn.executable(target) == 1 then path = target end
        end
    end
    assert(path ~= "", "Executable not found: " .. name)
    binaries[name] = path
    return path
end

local function fzf_colors()
    local p = style.palette()
    local function color(value) return value and string.format("#%06x", value) or "-1" end
    local colors = { vim.o.background }
    for _, pair in ipairs({
        { "fg", p.fg }, { "bg", p.bg }, { "fg+", p.fg }, { "bg+", p.selected },
        { "gutter", p.bg }, { "hl", p.accent }, { "hl+", p.accent },
        { "query", p.fg }, { "prompt", p.fg }, { "pointer", p.accent },
        { "info", p.muted }, { "spinner", p.muted }, { "border", p.fg },
    }) do
        colors[#colors + 1] = pair[1] .. ":" .. color(pair[2])
    end
    return table.concat(colors, ",")
end

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "Pick" })
end

local function close(s)
    if s.closed then return end
    s.closed = true
    if active == s then active = nil end
    if s.job then pcall(vim.fn.jobstop, s.job) end
    if api.nvim_get_current_win() == s.win then vim.cmd.stopinsert() end
    if api.nvim_win_is_valid(s.win) then api.nvim_win_close(s.win, true) end
    if api.nvim_buf_is_valid(s.buf) then api.nvim_buf_delete(s.buf, { force = true }) end
    vim.fn.delete(s.input)
    vim.fn.delete(s.output)
end

local function jump(s, item)
    if not api.nvim_win_is_valid(s.origin) then return end
    api.nvim_set_current_win(s.origin)
    -- Structured arguments preserve spaces, #, %, and other filename characters.
    vim.cmd.edit({ args = { item.filename }, magic = { file = false } })
end

local function select_items(s, items)
    if s.closed then return end
    local walker = s.kind == "files"
    if #items == 0 and not walker then
        close(s)
        notify("No results")
        return
    end
    local lines = {}
    for i, item in ipairs(items) do
        local name = item.filename
        local label = vim.fs.relpath(s.cwd, name) or name
        lines[i] = i .. "\t" .. label:gsub("[%z\1-\31\127]", " ")
    end
    if not walker then vim.fn.writefile(lines, s.input) end
    s.height = walker and 12 or math.min(18, math.max(3, #items + 1))
    api.nvim_win_set_config(s.win, style.float_config(s.height))
    -- Only fixed shell syntax and environment paths reach the shell. The query
    -- goes directly to fzf via its option environment, never through the shell.
    local flags = ' --layout=reverse --border=none --no-multi'
        .. ' --no-bold --no-separator --no-scrollbar --info=inline-right --bind=esc:abort --prompt=": "'
        .. ' --color=' .. fzf_colors()
    if walker then
        flags = flags .. ' --walker=file --walker-skip=.git,node_modules --scheme=path --print0'
    else
        flags = flags .. ' --delimiter=\\t --with-nth=2..'
    end
    local function option(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
    local opts = "--query=" .. option(s.query)
    local command
    if vim.fn.has("win32") == 1 then
        -- Reopen console stdin so fzf detects a TTY and starts its walker.
        command = { vim.env.COMSPEC or "cmd.exe", "/d", "/s", "/c",
            '""%PICK_FZF%"' .. flags .. (walker and ' < CON' or ' < "%PICK_INPUT%"') .. ' > "%PICK_OUTPUT%""' }
    else
        command = { "sh", "-c", '"$PICK_FZF"' .. flags .. (walker and '' or ' < "$PICK_INPUT"') .. ' > "$PICK_OUTPUT"' }
    end
    api.nvim_buf_set_lines(s.buf, 0, -1, false, {})
    vim.bo[s.buf].buftype = ""
    vim.bo[s.buf].modified = false
    api.nvim_set_current_win(s.win)
    s.job = vim.fn.jobstart(command, {
        term = true, cwd = s.cwd,
        env = { PICK_FZF = s.fzf, PICK_INPUT = s.input, PICK_OUTPUT = s.output,
            COLORTERM = "truecolor",
            FZF_DEFAULT_OPTS = opts,
            FZF_DEFAULT_OPTS_FILE = "", FZF_DEFAULT_COMMAND = "" },
        on_exit = function(_, code)
            local function finish()
                if s.closed then
                    -- Windows can keep redirected files locked until the job exits.
                    vim.fn.delete(s.input)
                    vim.fn.delete(s.output)
                    return
                end
                local file = io.open(s.output, "rb")
                local output = file and file:read("*a") or ""
                if file then file:close() end
                local index = tonumber(output:match("^(%d+)\t"))
                local item = items[index]
                if walker and code == 0 then
                    local path = output:match("^([^%z]+)%z")
                    if path then item = { filename = vim.fs.normalize(vim.fs.joinpath(s.cwd, path)) } end
                end
                s.job = nil
                close(s)
                if code == 0 and item then
                    local ok, err = pcall(jump, s, item)
                    if not ok then notify(tostring(err), vim.log.levels.ERROR) end
                elseif code ~= 0 and code ~= 1 and code ~= 130 then
                    notify("fzf exited with code " .. code, vim.log.levels.ERROR)
                end
            end
            vim.schedule(finish)
        end,
    })
    if s.job <= 0 then error("Cannot start fzf") end
    -- Let ConPTY finish a pending resize before a key can terminate fzf.
    for key, bytes in pairs({ ["<Esc>"] = "\27", ["<CR>"] = "\r", ["<C-c>"] = "\3" }) do
        vim.keymap.set("t", key, function()
            local function send()
                if not s.closed and s.job then vim.fn.chansend(s.job, bytes) end
            end
            local delay = (s.resize_deadline or 0) - vim.uv.now()
            if delay > 0 then vim.defer_fn(send, delay) else send() end
        end, { buffer = s.buf })
    end
    vim.cmd.startinsert()
end


function M.open(kind, query)
    if active then close(active) end
    if not vim.tbl_contains(kinds, kind) then notify("Use " .. table.concat(kinds, ", "), vim.log.levels.ERROR); return end
    local s = { kind = kind, query = query or "", height = 3,
        origin = api.nvim_get_current_win(),
        cwd = vim.fn.getcwd(), input = vim.fn.tempname(), output = vim.fn.tempname() }
    local ok, err = pcall(function()
        s.fzf = executable("fzf")
        s.buf = api.nvim_create_buf(false, true)
        vim.bo[s.buf].bufhidden = "wipe"
        local cfg = style.float_config(s.height)
        cfg.style, cfg.title, cfg.title_pos = "minimal", " " .. kind .. " ", "left"
        s.win = api.nvim_open_win(s.buf, true, cfg)
        style.style_window(s.win)
        active = s
        vim.bo[s.buf].filetype = "picker"
        api.nvim_buf_set_lines(s.buf, 0, -1, false, { "Loading…  Esc to cancel" })
        for _, key in ipairs({ "<Esc>", "q" }) do
            vim.keymap.set("n", key, function() close(s) end, { buffer = s.buf })
        end
        api.nvim_create_autocmd("BufWipeout", { buffer = s.buf, once = true,
            callback = function() vim.schedule(function() close(s) end) end })
        if kind == "files" then
            select_items(s, {})
        elseif kind == "oldfiles" then
            local items, seen = {}, {}
            for _, path in ipairs(vim.v.oldfiles) do
                path = vim.fs.normalize(path)
                local key = vim.fn.has("win32") == 1 and path:lower() or path
                if not seen[key] and vim.fn.filereadable(path) == 1 then
                    seen[key] = true
                    items[#items + 1] = { filename = path }
                end
            end
            select_items(s, items)
        end
    end)
    if not ok then
        if s.win then close(s) end
        notify(tostring(err), vim.log.levels.ERROR)
    end
end

local process, generation = nil, 0

-- Parse only leading glob options; leave the remaining regex (including spaces
-- and backslashes) untouched. Use -- to search text starting with an option.
local function parse_grep(input)
    local globs, rest = {}, input
    while true do
        rest = rest:gsub("^%s+", "")
        if rest:match("^%-%-%s") then
            rest = rest:gsub("^%-%-%s+", "", 1)
            break
        end
        local flag, tail = rest:match("^(%S+)%s*(.*)$")
        if flag ~= "-g" and flag ~= "--glob" then break end
        local quote = tail:sub(1, 1)
        local glob
        if quote == "'" or quote == '"' then
            local ending = tail:find(quote, 2, true)
            if not ending then return nil, "Unclosed glob quote" end
            glob, rest = tail:sub(2, ending - 1), tail:sub(ending + 1)
            if rest ~= "" and not rest:match("^%s") then
                return nil, "Expected a space after glob"
            end
        else
            glob, rest = tail:match("^(%S+)%s*(.*)$")
        end
        if not glob or glob == "" then return nil, "Missing glob after " .. flag end
        globs[#globs + 1] = glob
    end
    if rest == "" then return nil, "Missing search pattern" end
    return rest, globs
end

local function grep(pattern, globs)
    if vim.fn.executable("rg") ~= 1 then
        vim.notify("ripgrep (rg) is not installed", vim.log.levels.ERROR)
        return
    end
    generation = generation + 1
    local request, cwd = generation, vim.fn.getcwd()
    if process then process:kill(15) end
    local command = { "rg", "--json", "--smart-case" }
    for _, glob in ipairs(globs or {}) do
        vim.list_extend(command, { "--glob", glob })
    end
    vim.list_extend(command, { "--", pattern, "." })
    process = vim.system(command,
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
                vim.fn.setqflist({}, " ", { title = "rg: " .. pattern, items = items })
                if #items == 0 then
                    vim.cmd("cclose")
                    vim.notify("No matches: " .. pattern)
                else
                    vim.cmd("botright copen")
                end
            end)
        end)
end


function M.setup()
    for _, name in ipairs({ "GrepQf", "Grep" }) do
        vim.api.nvim_create_user_command(name, function(args)
            local pattern, globs = parse_grep(args.args)
            if not pattern then vim.notify(globs, vim.log.levels.ERROR); return end
            grep(pattern, globs)
        end, { nargs = "+", desc = "Search cwd into quickfix: [-g glob ...] [--] regex" })
    end

    for name, kind in pairs({ Files = "files", Oldfiles = "oldfiles" }) do
        api.nvim_create_user_command(name, function(args)
            M.open(kind, args.args)
        end, { nargs = "*", desc = "Choose " .. kind })
    end
    local group = api.nvim_create_augroup("PersonalPicker", { clear = true })
    api.nvim_create_autocmd("VimResized", { group = group, callback = function()
        if active and api.nvim_win_is_valid(active.win) then
            api.nvim_win_set_config(active.win, style.float_config(active.height))
            if vim.fn.has("win32") == 1 then active.resize_deadline = vim.uv.now() + 200 end
        end
    end })
    api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function()
        if active then close(active) end
        generation = generation + 1
        if process then process:kill(15) end
    end })
end

return M
