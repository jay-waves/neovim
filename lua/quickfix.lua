local M = {}
local api = vim.api
local process, generation = nil, 0

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

local function publish(title, items, query, text_function)
    if query and query ~= "" then
        items = vim.tbl_filter(function(item)
            return (item.text or ""):lower():find(query:lower(), 1, true) ~= nil
        end, items)
    end
    table.sort(items, function(a, b)
        return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col)
    end)
    vim.fn.setqflist({}, " ", { title = title, items = items, quickfixtextfunc = text_function })
    if #items == 0 then
        vim.cmd("cclose")
        vim.notify("No symbols found", vim.log.levels.INFO)
    else
        vim.cmd("botright copen")
    end
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
    publish("Symbols", items, query, symbol_text)
end

function M.setup()
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

return M
