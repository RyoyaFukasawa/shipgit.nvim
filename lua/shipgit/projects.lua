local M = {}

M._win = nil
M._buf = nil

local MAX_RECENT = 10
local DATA_DIR = vim.fn.stdpath("data") .. "/shipgit"
local DATA_FILE = DATA_DIR .. "/recent_projects.json"

function M.is_open()
  return M._win ~= nil and vim.api.nvim_win_is_valid(M._win)
end

--- 履歴ファイルを読み込む
--- @return string[]
function M._load()
  if vim.fn.filereadable(DATA_FILE) == 0 then
    return {}
  end
  local ok, content = pcall(vim.fn.readfile, DATA_FILE)
  if not ok or #content == 0 then
    return {}
  end
  local json_ok, data = pcall(vim.fn.json_decode, table.concat(content, "\n"))
  if not json_ok or type(data) ~= "table" then
    return {}
  end
  return data
end

--- 履歴ファイルに保存
--- @param projects string[]
function M._save(projects)
  vim.fn.mkdir(DATA_DIR, "p")
  local json = vim.fn.json_encode(projects)
  vim.fn.writefile({ json }, DATA_FILE)
end

--- プロジェクトを履歴に記録（先頭に追加、重複排除）
--- @param path string
function M.record(path)
  path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
  local projects = M._load()

  -- 既存エントリを除去
  local filtered = {}
  for _, p in ipairs(projects) do
    if p ~= path then
      table.insert(filtered, p)
    end
  end

  -- 先頭に追加
  table.insert(filtered, 1, path)

  -- 最大数に制限
  while #filtered > MAX_RECENT do
    table.remove(filtered)
  end

  M._save(filtered)
end

--- プロジェクト選択ウィンドウを開く
--- @param on_select fun(path: string) 選択時のコールバック
function M.open(on_select)
  if M.is_open() then
    return
  end

  local projects = M._load()
  if #projects == 0 then
    vim.notify("shipgit: プロジェクト履歴がありません", vim.log.levels.WARN)
    return
  end

  local current_cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p"):gsub("/$", "")

  local lines = {}
  local current_line = 1
  for i, p in ipairs(projects) do
    local display = vim.fn.fnamemodify(p, ":~")
    local prefix = p == current_cwd and "* " or "  "
    table.insert(lines, prefix .. display)
    if p == current_cwd then
      current_line = i
    end
  end

  table.insert(lines, "")
  table.insert(lines, " Space: open  d: remove  q: close")

  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].bufhidden = "wipe"

  vim.bo[M._buf].modifiable = true
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.bo[M._buf].modifiable = false

  local width = 60
  local height = math.min(#lines, 20)

  M._win = vim.api.nvim_open_win(M._buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    zindex = 60,
    title = " Recent Projects ",
    title_pos = "center",
  })

  vim.wo[M._win].cursorline = true

  -- ハイライト
  local ns = vim.api.nvim_create_namespace("shipgit_projects")
  for i, p in ipairs(projects) do
    if p == current_cwd then
      vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitStagedFile", i - 1, 0, -1)
    end
  end
  vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitHelpDesc", #lines - 1, 0, -1)

  pcall(vim.api.nvim_win_set_cursor, M._win, { current_line, 0 })

  local function close()
    if M._win and vim.api.nvim_win_is_valid(M._win) then
      pcall(vim.api.nvim_win_close, M._win, true)
    end
    M._win = nil
    M._buf = nil
  end

  local function kmap(key, fn)
    vim.keymap.set("n", key, fn, { buffer = M._buf, nowait = true, silent = true })
  end

  -- Enter: プロジェクトを選択
  kmap("<Space>", function()
    local cursor = vim.api.nvim_win_get_cursor(M._win)
    local idx = cursor[1]
    if idx > #projects then
      return
    end
    local selected = projects[idx]
    close()
    vim.schedule(function()
      if on_select then
        on_select(selected)
      end
    end)
  end)

  -- d: 履歴から削除
  kmap("d", function()
    local cursor = vim.api.nvim_win_get_cursor(M._win)
    local idx = cursor[1]
    if idx > #projects then
      return
    end
    table.remove(projects, idx)
    M._save(projects)
    -- 再描画
    close()
    vim.schedule(function()
      if #projects > 0 then
        M.open(on_select)
      end
    end)
  end)

  -- q / Esc: 閉じる
  for _, key in ipairs({ "q", "<Esc>" }) do
    kmap(key, function()
      close()
    end)
  end
end

return M
