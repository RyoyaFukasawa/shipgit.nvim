-- テスト用の最小 init.lua
local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
vim.opt.rtp:prepend(plenary_path)

-- shipgit 自体をランタイムパスに追加
local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.rtp:prepend(plugin_path)
