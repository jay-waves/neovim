-- Uses BudouX, a lightweight local phrase-segmentation library (about 15 KB
-- including its model; Python and installation overhead are separate).
-- Install: python -m pip install budoux
-- Neovim: require("text-wrap").setup().
-- Short lines are not automatically joined, to preserve existing layout; use J to join them manually.
-- Format the current line or selected lines: :WrapText [width] [language]
-- Defaults: 100 display columns and en,zh (Simplified Chinese plus English).
-- Other languages: zh-hans, zh-hant, ja, th; zh,en is equivalent to en,zh.
local M = {}

local segmenter = [=[
import json, re, sys
import budoux

parsers = {
    "en,zh": budoux.load_default_simplified_chinese_parser,
    "zh,en": budoux.load_default_simplified_chinese_parser,
    "zh": budoux.load_default_simplified_chinese_parser,
    "zh-hans": budoux.load_default_simplified_chinese_parser,
    "zh-hant": budoux.load_default_traditional_chinese_parser,
    "ja": budoux.load_default_japanese_parser,
    "th": budoux.load_default_thai_parser,
}
parser = parsers[sys.argv[1]]()

def segments(line):
    parts = []
    for segment in parser.parse(line):
        for part in re.findall(r"\s+|\S+", segment):
            if parts and re.search(r"[A-Za-z0-9]$", parts[-1]) and re.match(r"[A-Za-z0-9]", part):
                parts[-1] += part
            else:
                parts.append(part)
    return parts

json.dump([segments(line) for line in json.load(sys.stdin)], sys.stdout, ensure_ascii=False)
]=]

function M.setup()
    vim.api.nvim_create_user_command("WrapText", function(args)
        local width = tonumber(args.fargs[1] or "100")
        local language = args.fargs[2] or "en,zh"
        if not width or width < 1 or width % 1 ~= 0 then
            error("Width must be a positive integer")
        end
        if not vim.tbl_contains({ "en,zh", "zh,en", "zh", "zh-hans", "zh-hant", "ja", "th" }, language) then
            error("Language must be en,zh, zh,en, zh, zh-hans, zh-hant, ja, or th")
        end

        local lines = vim.api.nvim_buf_get_lines(0, args.line1 - 1, args.line2, false)
        local result = vim.system({ "python", "-X", "utf8", "-c", segmenter, language }, {
            stdin = vim.json.encode(lines),
            text = true,
        }):wait()
        if result.code ~= 0 then
            error("BudouX failed: " .. (result.stderr or ""))
        end

        local output = {}
        for _, segments in ipairs(vim.json.decode(result.stdout)) do
            local line = ""
            for _, segment in ipairs(segments) do
                if line ~= "" and vim.fn.strdisplaywidth(line .. segment) > width then
                    table.insert(output, line)
                    line = ""
                end
                line = line .. segment
            end
            table.insert(output, line)
        end
        vim.api.nvim_buf_set_lines(0, args.line1 - 1, args.line2, false, output)
        vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], 0 })
    end, { range = true, nargs = "*", desc = "Wrap lines using BudouX: [width] [language]" })
end

return M
