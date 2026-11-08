local M = {}
local executables = { typ = "ypst.exe", md = "cmrak.exe", markdown = "cmrak.exe" }

function M.setup()
    local function compile(args)
        local buffer = vim.api.nvim_get_current_buf()
        vim.cmd.write()
        local file = vim.api.nvim_buf_get_name(buffer)
        local executable = executables[vim.fn.fnamemodify(file, ":e"):lower()]
        if not executable then
            vim.notify("Compile supports Typst and Markdown files", vim.log.levels.ERROR)
            return
        end
        local line = vim.api.nvim_win_get_cursor(0)[1]
        local command = { executable, "serve", file, "--root", vim.fn.getcwd(), "--fragment", "L" .. line }
        local ok, err = pcall(vim.system, command, { text = true }, function(result)
            vim.schedule(function()
                local lines = vim.split(vim.trim(result.stderr or ""), "\n")
                for i, text in ipairs(lines) do
                    if text:sub(1, 4) == [[\\?\]] then lines[i] = text:sub(5) end
                end
                local items = vim.fn.getqflist({
                    lines = lines,
                    efm = [[%f:%l:%c: %t%*[^:]: %m,%Eerror: %m,%-C%\s%#,%Z%\s%#--> %f:%l:%c,%-G%.%#]],
                }).items
                if result.code ~= 0 and #items == 0 then
                    local details = vim.trim(result.stderr or "")
                    items = { { text = details ~= "" and details or ("Compilation failed (exit " .. result.code .. ")"), type = "E" } }
                end
                vim.fn.setqflist({}, "r", { title = "Compile: " .. file, items = items })
                if result.code ~= 0 then
                    vim.cmd("botright copen")
                elseif vim.api.nvim_buf_is_valid(buffer) then
                    local url = vim.trim(result.stdout)
                    if not args.bang and vim.b[buffer].compile_preview_url == url then return end
                    local opened, process, open_error = pcall(vim.ui.open, url .. "#L" .. line)
                    if not opened or open_error then
                        vim.notify("Cannot open preview: " .. tostring(opened and open_error or process), vim.log.levels.ERROR)
                    else
                        vim.b[buffer].compile_preview_url = url
                    end
                end
            end)
        end)
        if not ok then vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Compile" }) end
    end
    for _, name in ipairs({ "Compile", "C" }) do
        vim.api.nvim_create_user_command(name, compile, {
            bang = true, desc = "Write and compile; ! opens the preview again",
        })
    end
end
return M
