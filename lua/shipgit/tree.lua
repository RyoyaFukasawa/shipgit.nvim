local git = require("shipgit.git")
local config = require("shipgit.config")

local M = {}

M._win = nil
M._buf = nil

function M.is_open()
  return M._win ~= nil and vim.api.nvim_win_is_valid(M._win)
end

function M.open()
  if M.is_open() then
    return
  end

  local graph_lines = git.graph()

  -- 空行除去
  while #graph_lines > 0 and graph_lines[#graph_lines] == "" do
    table.remove(graph_lines)
  end

  if #graph_lines == 0 then
    vim.notify("shipgit: コミット履歴がありません", vim.log.levels.WARN)
    return
  end

  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].bufhidden = "wipe"

  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, graph_lines)
  vim.bo[M._buf].modifiable = false

  local cfg = config.values
  local width = math.floor(vim.o.columns * cfg.width)
  local height = math.floor(vim.o.lines * cfg.height)

  M._win = vim.api.nvim_open_win(M._buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    zindex = 60,
    title = " Branch Tree ",
    title_pos = "center",
  })

  vim.wo[M._win].cursorline = true
  vim.wo[M._win].wrap = false

  -- ハイライト適用
  M._apply_highlights(graph_lines)

  -- キーマップ
  local function kmap(key, fn)
    vim.keymap.set("n", key, fn, { buffer = M._buf, nowait = true, silent = true })
  end

  kmap("q", function() M.close() end)
  kmap("<Esc>", function() M.close() end)
end

local function graph_color_count()
  local cfg = require("shipgit.config").values
  local colors = cfg.highlights and cfg.highlights.graph_colors or {}
  return math.max(#colors, 1)
end

local function column_color(col)
  return "ShipgitGraphLine" .. ((col % graph_color_count()) + 1)
end

function M._apply_highlights(lines)
  local ns = vim.api.nvim_create_namespace("shipgit_tree")
  vim.api.nvim_buf_clear_namespace(M._buf, ns, 0, -1)

  for i, line in ipairs(lines) do
    local row = i - 1

    -- グラフ部分を解析
    local graph_end = 0
    local col_idx = 0  -- グラフ文字のカラム（スペース含む位置÷2で概算）
    for j = 1, #line do
      local c = line:sub(j, j)
      if c == "|" or c == "/" or c == "\\" or c == "-" or c == "_" then
        graph_end = j
        col_idx = math.floor((j - 1) / 2)
        vim.api.nvim_buf_add_highlight(M._buf, ns, column_color(col_idx), row, j - 1, j)
      elseif c == "*" then
        graph_end = j
        col_idx = math.floor((j - 1) / 2)
        vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphCommit", row, j - 1, j)
      elseif c == " " then
        graph_end = j
      else
        break
      end
    end

    -- グラフ以降の部分を解析
    local rest = line:sub(graph_end + 1)
    local offset = graph_end

    -- コミットハッシュ
    local hash_s, hash_e = rest:find("^(%x%x%x%x%x%x%x+)")
    if hash_s then
      vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphHash", row, offset + hash_s - 1, offset + hash_e)
    end

    -- デコレーション (HEAD -> branch, origin/branch, tag: v1.0)
    local deco_s, deco_e = line:find("%b()")
    if deco_s then
      vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphBranch", row, deco_s - 1, deco_e)

      local deco_content = line:sub(deco_s + 1, deco_e - 1)

      -- HEAD / HEAD -> を緑で
      local head_s, head_e = deco_content:find("HEAD%s*->%s*")
      if head_s then
        vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphHead", row, deco_s + head_s - 2, deco_s + head_e - 1)
      else
        local hs, he = deco_content:find("HEAD")
        if hs then
          vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphHead", row, deco_s + hs - 2, deco_s + he - 1)
        end
      end

      -- リモートブランチを赤で
      local search_start = 1
      while true do
        local rs, re = deco_content:find("[%w]+/[%w/%-_%.]+", search_start)
        if not rs then break end
        local ref = deco_content:sub(rs, re)
        if not ref:match("^HEAD") then
          vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphRemote", row, deco_s + rs - 2, deco_s + re - 1)
        end
        search_start = re + 1
      end

      -- tag: をオレンジで
      local tag_search = 1
      while true do
        local ts, te = deco_content:find("tag:%s*[%w%-_%.]+", tag_search)
        if not ts then break end
        vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphTag", row, deco_s + ts - 2, deco_s + te - 1)
        tag_search = te + 1
      end

      -- コミットメッセージ
      if deco_e < #line then
        vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphMessage", row, deco_e, #line)
      end
    else
      -- ハッシュの後はコミットメッセージ
      if hash_e then
        vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphMessage", row, offset + hash_e, #line)
      end
    end
  end
end

function M.close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    pcall(vim.api.nvim_win_close, M._win, true)
  end
  M._win = nil
  M._buf = nil
end

return M
