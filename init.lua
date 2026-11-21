-- Keymap reference --------------------------------------------------------
-- Leader = Space. Leader shortcuts use Normal mode unless noted.
-- Space f/o       Find files / choose a buffer. Space / searches project text.
-- Space s or S    List symbols in the current file.
-- Space e/E       Open MiniFiles / open the working directory in the system file manager.
-- Space g         Toggle changed files and inline diffs, including deleted lines. n/N jump between hunks.
-- Space G         Preview the current hunk inline (available after the first Space g).
-- Space h         Show hover docs. Space l/L shows line diagnostics / toggles the diagnostics list.
-- Space w         Next window. Space Space returns to the previous buffer.
-- Space y/d/p     Copy, cut or paste using the system clipboard (Normal and Visual modes).
-- Ctrl-S saves; F2 opens completion; Ctrl-click opens a file; middle-click centers the cursor.
-- Picker: / or i to filter, Up/Down to select, Enter to open, Ctrl-C to close. In Buffers, dd deletes.
-- Quickfix: :cn / :cp for next / previous, q to close. In MiniFiles, L opens the system default app.
-- Surround: sa adds, sd deletes, sr replaces. Use b for Markdown bold (**text**).

-- Startup and platform settings -------------------------------------------
-- Set the libuv worker count before any plugin initializes the thread pool.
vim.env.UV_THREADPOOL_SIZE = "2"

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- The client terminal controls OSC 52 permissions. In tmux, enable set-clipboard for copying.
if vim.fn.has("linux") == 1 and (vim.env.SSH_TTY or vim.env.SSHORE_TTY) then
    vim.g.clipboard = "osc52"
end

if vim.fn.has("win32") == 1 then
    -- Convert Niubash TMPDIR before native Windows plugins use tempname().
    if vim.env.TMPDIR then
        local drive, path = vim.env.TMPDIR:match("^/([A-Za-z])/(.*)$")
        if drive then
            vim.env.TMPDIR = drive:upper() .. ":/" .. path
        end
    end

    require("ime").setup()
    require("compile").setup()
end

-- Editor settings and mappings --------------------------------------------
vim.opt.number = false
vim.opt.statuscolumn =
    "%s%=%{v:lnum == line('.') || v:lnum % 10 == 0 ? v:lnum : ''}   "

vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.wrap = false

vim.opt.scrolloff = 10
vim.opt.mousemodel = "extend"
vim.opt.mouse = "a"

vim.keymap.set({ "n", "v", "s", "o", "i", "c", "t" }, "<MiddleMouse>", "<Nop>")
vim.keymap.set({ "n", "x", "i" }, "<MiddleMouse>", "<Cmd>normal! zz<CR>", {
    desc = "Center cursor line",
})

vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.keymap.set("n", "j", "gj")
vim.keymap.set("n", "k", "gk")

vim.keymap.set("n", "<leader>h", vim.lsp.buf.hover, {
    desc = "Show documentation",
})

vim.keymap.set("n", "<C-LeftMouse>", "<LeftMouse>gf")

vim.keymap.set({ "n", "i", "x" }, "<C-s>", "<Cmd>write<CR>", { desc = "Save file" })

vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])
vim.keymap.set({ "n", "v" }, "<leader>d", [["+d]])
vim.keymap.set({ "n", "v" }, "<leader>p", [["+p]])

vim.api.nvim_create_user_command("CopyLocation", function()
    local path = vim.api.nvim_buf_get_name(0)
    if path == "" or vim.bo.buftype ~= "" then
        vim.notify("Current buffer has no file path", vim.log.levels.WARN)
        return
    end
    local location = string.format("%s:%d", path, vim.fn.line("."))
    if vim.fn.setreg("+", location, "v") == 0 then
        vim.notify(location)
    end
end, { desc = "Copy current file path and line number" })

-- Theme, interface and navigation -----------------------------------------
require("theme").setup({
    dark = "gruvbox",
    light = "alabaster",
})

vim.pack.add({
    "https://github.com/nvim-mini/mini.surround",
})

require("ui").setup()
require("finder").setup()

vim.opt.showtabline = 0

vim.keymap.set("n", "<leader>w", "<C-w>w")
vim.keymap.set("n", "<leader><leader>", "<cmd>b#<CR>")

-- Language support and editing plugins ------------------------------------
-- Completion must load before LSP capabilities are configured.
require("completion").setup()

require("lsp").setup()

require("mini.surround").setup({
    custom_surroundings = {
        b = {
            input = { "%*%*().-()%*%*" },
            output = { left = "**", right = "**" },
        },
    },
})

require("text-wrap").setup()
