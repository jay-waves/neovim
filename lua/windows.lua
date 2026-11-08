local M = {}

function M.setup()
    -- Nushell receives filter input through stdin, not shell input redirection.
    vim.opt.shell = "nu.exe"
    vim.opt.shellcmdflag = "--stdin --no-newline -c"
    vim.opt.shelltemp = false
    vim.opt.shellquote = ""
    vim.opt.shellxquote = ""
    vim.opt.shellxescape = ""
    vim.opt.shellpipe = "out+err> %s"
    vim.opt.shellredir = "out+err> %s"

    -- Convert Niubash TMPDIR before native Windows plugins use tempname().
    if vim.env.TMPDIR then
        local drive, path = vim.env.TMPDIR:match("^/([A-Za-z])/(.*)$")
        if drive then
            vim.env.TMPDIR = drive:upper() .. ":/" .. path
        end
    end

    -- Switch Microsoft Pinyin between Chinese and English via Windows IME APIs.
    require("ime").setup()

    require("compile").setup()
end

return M
