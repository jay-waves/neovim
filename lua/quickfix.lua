local M = {}
local api = vim.api
local generation, cancel = 0, nil

local function publish(title, items, query)
    if query and query ~= "" then
        items = vim.tbl_filter(function(item)
            return (item.text or ""):lower():find(query:lower(), 1, true) ~= nil
        end, items)
    end
    table.sort(items, function(a, b)
        return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col)
    end)
    vim.fn.setqflist({}, " ", { title = title, items = items })
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
        for id, node in query:iter_captures(tree:root(), buf, 0, -1) do
            local capture = query.captures[id]
            if capture == "local.definition" or capture:match("^local%.definition%.") then
                -- Associated receivers are references, not additional declarations.
                if capture ~= "local.definition.associated" then
                    local row, col = node:range()
                    local key = row .. ":" .. col
                    if not seen[key] then
                        seen[key] = true
                        local kind = capture:match("^local%.definition%.(.+)$") or "definition"
                        items[#items + 1] = { bufnr = buf, lnum = row + 1, col = col + 1,
                            text = "[" .. kind .. "] " .. vim.treesitter.get_node_text(node, buf) }
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b) return a.lnum < b.lnum or (a.lnum == b.lnum and a.col < b.col) end)
    return items
end


function M.open(kind, query)
    generation = generation + 1
    local request, source = generation, api.nvim_get_current_buf()
    if cancel then cancel(); cancel = nil end
    if kind == "treesitter" then
        local ok, items = pcall(treesitter_items, source)
        if not ok then vim.notify(tostring(items), vim.log.levels.ERROR); return end
        publish("TreeSitter: " .. api.nvim_buf_get_name(source), items, query)
        return
    end
    local method = "textDocument/documentSymbol"
    if #vim.lsp.get_clients({ bufnr = source, method = method }) == 0 then
        vim.notify("No LSP document-symbol provider for this buffer", vim.log.levels.INFO)
        return
    end
    cancel = vim.lsp.buf_request_all(source, method,
        { textDocument = { uri = vim.uri_from_bufnr(source) } }, function(results)
            if request ~= generation or not api.nvim_buf_is_valid(source) then return end
            cancel = nil
            local items, seen = {}, {}
            for id, response in pairs(results) do
                local client = vim.lsp.get_client_by_id(id)
                if response.err then vim.notify(response.err.message, vim.log.levels.WARN) end
                if client and response.result then
                    for _, item in ipairs(vim.lsp.util.symbols_to_items(response.result, source, client.offset_encoding)) do
                        local key = table.concat({ item.filename, item.lnum, item.col, item.text }, "\0")
                        if not seen[key] then
                            seen[key] = true
                            item.bufnr = source
                            items[#items + 1] = item
                        end
                    end
                end
            end
            publish("Symbols: " .. api.nvim_buf_get_name(source), items, query)
        end)
end

function M.setup()
    local group = api.nvim_create_augroup("PersonalQuickfix", { clear = true })
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
    for name, kind in pairs({ Symbols = "symbols", TreeSitter = "treesitter" }) do
        api.nvim_create_user_command(name, function(args) M.open(kind, args.args) end,
            { nargs = "*", desc = "List " .. kind .. " in quickfix (optional text filter)" })
    end
    api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            generation = generation + 1
            if cancel then cancel() end
        end,
    })
end

return M
