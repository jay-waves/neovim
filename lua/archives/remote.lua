local M = {}
local active = false

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "Remote" })
end

local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function diagnostics(buf)
    if not vim.api.nvim_buf_is_valid(buf) then return "" end
    local count = vim.api.nvim_buf_line_count(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, math.max(0, count - 12), -1, false)
    return vim.trim(table.concat(vim.tbl_filter(function(line)
        return line:find("%S") and not line:match("^%[Process exited")
    end, lines), "\n"))
end

function M.open(host, directory)
    if active then
        notify("A remote connection is already open", vim.log.levels.WARN)
        return
    end
    if not host or host == "" or host:find("^%-") or host:find("[%s%c/\\]") then
        notify("Usage: :Remote [user@]host [directory]", vim.log.levels.ERROR)
        return
    end
    if vim.fn.executable("ssh") ~= 1 then
        notify("Missing local executable: ssh", vim.log.levels.ERROR)
        return
    end
    -- Optional future feature: copy local configuration to the remote before connecting.
    local script = "exec nvim"
    if directory and directory ~= "" then
        local path = quote(directory)
        if directory == "~" then
            path = '"$HOME"'
        elseif vim.startswith(directory, "~/") then
            path = '"$HOME"/' .. quote(directory:sub(3))
        end
        script = "cd " .. path .. " && " .. script
    end

    notify("Connecting to " .. host .. "…")
    local origin = vim.api.nvim_get_current_tabpage()
    vim.cmd.tabnew()
    local tab, buf = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_buf()
    vim.bo[buf].bufhidden = "wipe"
    for name, value in pairs({ number = false, relativenumber = false, signcolumn = "no", statuscolumn = "", winbar = "" }) do
        vim.wo[name] = value
    end
    active = true

    -- Global chrome is hidden only while the remote tab is selected.
    local hidden = { laststatus = 0, showtabline = 0, cmdheight = 0, showmode = false, ruler = false }
    local saved = {}
    for name in pairs(hidden) do saved[name] = vim.o[name] end
    local function chrome(options)
        for name, value in pairs(options) do vim.o[name] = value end
    end
    local event = vim.api.nvim_create_autocmd("TabEnter", {
        callback = function()
            chrome(vim.api.nvim_get_current_tabpage() == tab and hidden or saved)
        end,
    })
    chrome(hidden)

    local finished = false
    local function finish(code, reason)
        if finished then return end
        finished, active = true, false
        if code ~= 0 and not reason then reason = diagnostics(buf) end
        vim.cmd.stopinsert()
        vim.api.nvim_del_autocmd(event)
        chrome(saved)
        if vim.api.nvim_tabpage_is_valid(tab) then
            vim.api.nvim_set_current_tabpage(tab)
            vim.cmd.tabclose()
        end
        if vim.api.nvim_tabpage_is_valid(origin) then vim.api.nvim_set_current_tabpage(origin) end
        vim.schedule(function()
            if code == 0 then
                notify("Disconnected from " .. host .. "; returned to local Neovim")
            else
                if reason == "" then reason = "SSH connection or remote command failed" end
                notify(("%s failed (exit %d)\n%s"):format(host, code, reason), vim.log.levels.ERROR)
            end
        end)
    end

    local ok, job = pcall(vim.fn.jobstart, {
        "ssh", "-o", "ConnectTimeout=3", "-o", "ConnectionAttempts=1",
        "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
        "-t", host, "sh -c " .. quote(script),
    }, {
        term = true,
        on_exit = vim.schedule_wrap(function(_, code) finish(code) end),
    })
    if not ok or job <= 0 then
        finish(1, ok and "Could not start SSH" or tostring(job))
        return
    end
    vim.cmd.startinsert()
end

local function complete_host(lead, command, cursor)
    if not command:sub(1, cursor):match("^%s*Remote%s+%S*$") then return {} end
    local ok, lines = pcall(vim.fn.readfile, vim.fn.expand("~/.ssh/config"))
    if not ok then return {} end
    local hosts, seen = {}, {}
    for _, line in ipairs(lines) do
        local key, value = line:match("^%s*([%a]+)%s*(.*)$")
        if key and key:lower() == "host" then
            value = value:gsub("^=%s*", ""):gsub("#.*$", "")
            for host in value:gmatch("%S+") do
                host = host:gsub('^["\']', ""):gsub('["\']$', "")
                if not host:find("[*?!]") and not seen[host] and vim.startswith(host, lead) then
                    seen[host], hosts[#hosts + 1] = true, host
                end
            end
        end
    end
    table.sort(hosts)
    return hosts
end

function M.setup()
    vim.api.nvim_create_user_command("Remote", function(opts)
        local host, directory = opts.args:match("^%s*(%S+)%s*(.-)%s*$")
        -- Let CmdlineLeave finish before changing tabs or showing notifications.
        vim.schedule(function() M.open(host, directory) end)
    end, {
        nargs = "+",
        complete = complete_host,
        desc = "Open Neovim using the remote host's default configuration",
    })
end

return M
