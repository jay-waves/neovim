-- Set the libuv worker count before any plugin initializes the thread pool.
vim.env.UV_THREADPOOL_SIZE = "2"

-- Use Space as the leader before platform mappings are registered.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("remote").setup()

---------------------------------------------------------------------------
-- Windows-specific initialization
---------------------------------------------------------------------------
if vim.fn.has("win32") == 1 then
    require("windows").setup()
end

---------------------------------------------------------------------------
-- General configuration
---------------------------------------------------------------------------
vim.opt.number = false
vim.opt.statuscolumn =
    "%s%=%{v:lnum == line('.') || v:lnum % 10 == 0 ? v:lnum : ''}   "

vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.wrap = false

vim.opt.scrolloff = 10
vim.opt.mousemodel = "extend"
vim.opt.mouse = "a"

-- Disable middle-click paste; center the cursor line in editing modes.
vim.keymap.set({ "n", "v", "s", "o", "i", "c", "t" }, "<MiddleMouse>", "<Nop>")
vim.keymap.set({ "n", "x", "i" }, "<MiddleMouse>", "<Cmd>normal! zz<CR>", {
    desc = "Center cursor line",
})

vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- search
vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.keymap.set("n", "j", "gj")
vim.keymap.set("n", "k", "gk")

vim.keymap.set("n", "<leader>h", vim.lsp.buf.hover, {
    desc = "Show documentation",
})

--> Click + Ctrl to jump to file
vim.keymap.set("n", "<C-LeftMouse>", "<LeftMouse>gf")

--> Use Ctrl+S to save file
vim.keymap.set({ "n", "i", "x" }, "<C-s>", "<Cmd>write<CR>", { desc = "Save file" })

--> Use <leader>y, <leader>p to paste/yank system clipboards
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])
vim.keymap.set({ "n", "v" }, "<leader>d", [["+d]])
vim.keymap.set({ "n", "v" }, "<leader>p", [["+p]])


-- dark themes: nordbones, github, gruvbox, zenbones, flexoki
-- light themes: github_light, zenwritten_light, patana_light, alabaster, flexoki_light
-- Detect the Windows app theme once at startup.
require("theme").setup({
    dark = "gruvbox",
    light = "alabaster",
})

vim.pack.add({
    "https://github.com/nvim-mini/mini.surround",
})

require("cmdline").setup()
require("picker").setup()
require("quickfix").setup()
require("title").setup()
-- require("git").setup()

vim.opt.showtabline = 0

require("files").setup()

--> File picker; grep and symbols use quickfix.
vim.keymap.set("n", "<leader>f", ":Files<CR>", { desc = "Find files" })
vim.keymap.set("n", "<leader>/", ":Grep ", { desc = "Search contents into quickfix" })
vim.keymap.set("n", "<leader>s", "<Cmd>Symbols<CR>", { desc = "Show Treesitter symbols" })
vim.keymap.set("n", "<leader>S", "<Cmd>Symbols<CR>", { desc = "Show Treesitter symbols" })
vim.keymap.set("n", "<leader>b", function() require("buffers").open() end, { desc = "Choose buffer" })

-- Toggle between splits inside windows
vim.keymap.set("n", "<leader>w", "<C-w>w")
-- Toggle between alternative buffer
vim.keymap.set("n", "<leader><leader>", "<cmd>b#<CR>")

--> `gc` comment selections
--> `gf` jump to file
--> `gv` select last visual selection
--> `[n]gg / [n]G` jump to #n line

--> `==` tab this line
--> `gg=G` tab all fiels

--> `gqq` format this line
--> `gq`  format selections

--> Completion must load before LSP capabilities are configured.
require("completion").setup()

--> Language support: Treesitter and LSP
require("lsp").setup()

--> PlugIn: Mini.Surround
--> `sa` add , with selections
--> `sd` delete, without selection
--> `sr` replace
-->
require("mini.surround").setup({
    custom_surroundings = {
        b = {
            input = { "%*%*().-()%*%*" },
            output = { left = "**", right = "**" },
        },
    },
})

require("text-wrap").setup()
