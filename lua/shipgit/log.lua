local git = require("shipgit.git")
local config = require("shipgit.config")

local M = {}

M._wins = {}    -- { list, diff_left, diff_right }
M._bufs = {}    -- { list, diff_left, diff_right }
M._commits = {}
M._selected_files = {}
M._file_cursor = 1
M._mode = "detail" -- "detail" | "diff"
M._current_commit = nil
M._on_close = nil

function M.is_open()
  return M._wins.list ~= nil and vim.api.nvim_win_is_valid(M._wins.list)
end

function M.open(on_close)
  if M.is_open() then
    return
  end

  M._on_close = on_close
  M._commits = git.log(100)
  if #M._commits == 0 then
    vim.notify("shipgit: コミット履歴がありません", vim.log.levels.WARN)
    return
  end

  M._mode = "detail"
  M._create_layout()
  M._render_list()
  M._show_detail(1)
  M._setup_keymaps()
end

local function create_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  return buf
end

function M._create_layout()
  local cfg = config.values
  local total_w = math.floor(vim.o.columns * cfg.width)
  local total_h = math.floor(vim.o.lines * cfg.height)
  local start_row = math.floor((vim.o.lines - total_h) / 2)
  local start_col = math.floor((vim.o.columns - total_w) / 2)

  local list_w = math.floor(total_w * 0.35)
  local right_w = total_w - list_w - 1
  local half_right = math.floor(right_w / 2)

  -- コミット一覧
  M._bufs.list = create_buf()
  M._wins.list = vim.api.nvim_open_win(M._bufs.list, true, {
    relative = "editor",
    row = start_row,
    col = start_col,
    width = list_w,
    height = total_h,
    style = "minimal",
    border = "rounded",
    zindex = 60,
    title = " Commit Log ",
    title_pos = "center",
  })
  vim.wo[M._wins.list].cursorline = true
  vim.wo[M._wins.list].wrap = false

  -- Diff左 (old)
  M._bufs.diff_left = create_buf()
  M._wins.diff_left = vim.api.nvim_open_win(M._bufs.diff_left, false, {
    relative = "editor",
    row = start_row,
    col = start_col + list_w + 1,
    width = half_right,
    height = total_h,
    style = "minimal",
    border = "rounded",
    zindex = 60,
    title = " Old ",
    title_pos = "center",
  })
  vim.wo[M._wins.diff_left].number = true
  vim.wo[M._wins.diff_left].wrap = false
  vim.wo[M._wins.diff_left].cursorline = true
  vim.wo[M._wins.diff_left].foldmethod = "diff"
  vim.wo[M._wins.diff_left].foldlevel = 99
  vim.api.nvim_set_option_value("winhighlight",
    "NormalFloat:Normal,DiffAdd:ShipgitDiffAdd,DiffChange:ShipgitDiffChange,DiffDelete:ShipgitDiffDelete,DiffText:ShipgitDiffText",
    { win = M._wins.diff_left })

  -- Diff右 (new)
  M._bufs.diff_right = create_buf()
  M._wins.diff_right = vim.api.nvim_open_win(M._bufs.diff_right, false, {
    relative = "editor",
    row = start_row,
    col = start_col + list_w + 1 + half_right,
    width = right_w - half_right,
    height = total_h,
    style = "minimal",
    border = "rounded",
    zindex = 60,
    title = " New ",
    title_pos = "center",
  })
  vim.wo[M._wins.diff_right].number = true
  vim.wo[M._wins.diff_right].wrap = false
  vim.wo[M._wins.diff_right].cursorline = true
  vim.wo[M._wins.diff_right].foldmethod = "diff"
  vim.wo[M._wins.diff_right].foldlevel = 99
  vim.api.nvim_set_option_value("winhighlight",
    "NormalFloat:Normal,DiffAdd:ShipgitDiffAdd,DiffChange:ShipgitDiffChange,DiffDelete:ShipgitDiffDelete,DiffText:ShipgitDiffText",
    { win = M._wins.diff_right })
end

function M._render_list()
  local lines = {}
  for _, c in ipairs(M._commits) do
    table.insert(lines, " " .. c.short_hash .. " " .. c.subject)
  end

  vim.bo[M._bufs.list].modifiable = true
  vim.api.nvim_buf_set_lines(M._bufs.list, 0, -1, false, lines)
  vim.bo[M._bufs.list].modifiable = false

  local ns = vim.api.nvim_create_namespace("shipgit_log_list")
  vim.api.nvim_buf_clear_namespace(M._bufs.list, ns, 0, -1)
  for i, c in ipairs(M._commits) do
    vim.api.nvim_buf_add_highlight(M._bufs.list, ns, "ShipgitGraphHash", i - 1, 1, 1 + #c.short_hash)
    vim.api.nvim_buf_add_highlight(M._bufs.list, ns, "ShipgitGraphMessage", i - 1, 1 + #c.short_hash + 1, -1)
  end
end

function M._show_detail(idx)
  if idx < 1 or idx > #M._commits then
    return
  end

  -- diff モード解除
  M._diffoff()

  local commit = M._commits[idx]
  M._current_commit = commit
  local files = git.commit_files(commit.hash)
  M._selected_files = files
  M._file_cursor = 1
  M._mode = "detail"

  -- 左パネルにコミット情報とファイル一覧を表示
  local lines = {
    " " .. commit.short_hash .. " " .. commit.subject,
    " " .. commit.author .. " · " .. commit.date,
    "",
  }

  if #files == 0 then
    table.insert(lines, " (no files changed)")
  else
    table.insert(lines, " Files (" .. #files .. "):")
    for _, f in ipairs(files) do
      local icon = M._status_icon(f.status)
      table.insert(lines, "  " .. icon .. " " .. f.path)
    end
  end

  M._set_buf(M._bufs.diff_left, lines)

  -- ハイライト
  local ns = vim.api.nvim_create_namespace("shipgit_log_detail")
  vim.api.nvim_buf_clear_namespace(M._bufs.diff_left, ns, 0, -1)
  vim.api.nvim_buf_add_highlight(M._bufs.diff_left, ns, "ShipgitTitle", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(M._bufs.diff_left, ns, "ShipgitHelpDesc", 1, 0, -1)
  local file_start = 4
  for i, f in ipairs(files) do
    local hl
    if f.status == "A" then hl = "ShipgitStagedFile"
    elseif f.status == "D" then hl = "ShipgitStatusDel"
    elseif f.status == "M" then hl = "ShipgitUnstagedFile"
    else hl = "ShipgitGraphMessage"
    end
    vim.api.nvim_buf_add_highlight(M._bufs.diff_left, ns, hl, file_start + i - 1, 0, -1)
  end

  -- 右パネルはヒント
  local hint = {
    "",
    "  j/k: コミット移動",
    "  Enter: ファイルのdiffを表示",
    "  C-h/C-l: パネル移動",
    "  q: 閉じる",
  }
  M._set_buf(M._bufs.diff_right, hint)
  local ns2 = vim.api.nvim_create_namespace("shipgit_log_hint")
  vim.api.nvim_buf_clear_namespace(M._bufs.diff_right, ns2, 0, -1)
  for i = 1, #hint do
    vim.api.nvim_buf_add_highlight(M._bufs.diff_right, ns2, "ShipgitHelpDesc", i - 1, 0, -1)
  end

  -- タイトル更新
  M._update_titles("Old", "New")
end

function M._show_file_diff(commit, filepath)
  M._mode = "diff"

  -- diff モード解除
  M._diffoff()

  local old_content = git.show_commit_file(commit.hash .. "~1", filepath) or ""
  local new_content = git.show_commit_file(commit.hash, filepath) or ""

  local old_lines = vim.split(old_content, "\n", { plain = true })
  local new_lines = vim.split(new_content, "\n", { plain = true })
  while #old_lines > 0 and old_lines[#old_lines] == "" do table.remove(old_lines) end
  while #new_lines > 0 and new_lines[#new_lines] == "" do table.remove(new_lines) end

  M._set_buf(M._bufs.diff_left, old_lines)
  M._set_buf(M._bufs.diff_right, new_lines)

  -- filetype
  local ft = vim.filetype.match({ filename = filepath }) or ""
  vim.bo[M._bufs.diff_left].filetype = ft
  vim.bo[M._bufs.diff_right].filetype = ft

  -- diffthis
  vim.api.nvim_set_current_win(M._wins.diff_left)
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(M._wins.diff_right)
  vim.cmd("diffthis")

  -- スクロール同期
  vim.wo[M._wins.diff_left].scrollbind = true
  vim.wo[M._wins.diff_right].scrollbind = true
  vim.wo[M._wins.diff_left].cursorbind = true
  vim.wo[M._wins.diff_right].cursorbind = true

  -- タイトル更新
  local short = vim.fn.fnamemodify(filepath, ":t")
  M._update_titles(short .. " (old)", short .. " (new)")

  -- コミット一覧にフォーカスを戻す
  vim.api.nvim_set_current_win(M._wins.list)
end

function M._diffoff()
  for _, name in ipairs({ "diff_left", "diff_right" }) do
    local win = M._wins[name]
    if win and vim.api.nvim_win_is_valid(win) then
      local prev = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(win)
      vim.cmd("diffoff")
      vim.api.nvim_set_current_win(prev)
    end
  end
end

function M._update_titles(left_title, right_title)
  if M._wins.diff_left and vim.api.nvim_win_is_valid(M._wins.diff_left) then
    vim.api.nvim_win_set_config(M._wins.diff_left, {
      title = " " .. left_title .. " ",
      title_pos = "center",
    })
  end
  if M._wins.diff_right and vim.api.nvim_win_is_valid(M._wins.diff_right) then
    vim.api.nvim_win_set_config(M._wins.diff_right, {
      title = " " .. right_title .. " ",
      title_pos = "center",
    })
  end
end

function M._set_buf(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M._status_icon(status)
  local icons = { M = "M", A = "+", D = "-", R = "R", C = "C" }
  return icons[status] or status
end

function M.close()
  M._diffoff()
  for _, win in pairs(M._wins) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  M._wins = {}
  M._bufs = {}
  M._commits = {}
  M._selected_files = {}
  M._current_commit = nil
  local cb = M._on_close
  M._on_close = nil
  if cb then
    vim.schedule(cb)
  end
end

function M._setup_keymaps()
  local function kmap(buf, key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
  end

  local all_bufs = { M._bufs.list, M._bufs.diff_left, M._bufs.diff_right }

  -- 全パネル共通: q, Esc, C-h, C-l
  for _, buf in ipairs(all_bufs) do
    kmap(buf, "q", function() M.close() end)
    kmap(buf, "<Esc>", function() M.close() end)

    kmap(buf, "<C-h>", function()
      local cur = vim.api.nvim_get_current_win()
      if cur == M._wins.diff_right then
        vim.api.nvim_set_current_win(M._wins.diff_left)
      elseif cur == M._wins.diff_left then
        vim.api.nvim_set_current_win(M._wins.list)
      end
    end)

    kmap(buf, "<C-l>", function()
      local cur = vim.api.nvim_get_current_win()
      if cur == M._wins.list then
        vim.api.nvim_set_current_win(M._wins.diff_left)
      elseif cur == M._wins.diff_left then
        vim.api.nvim_set_current_win(M._wins.diff_right)
      end
    end)
  end

  -- コミット一覧: j/k/Enter
  local list_buf = M._bufs.list

  kmap(list_buf, "j", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local idx = math.min(cursor[1] + 1, #M._commits)
    pcall(vim.api.nvim_win_set_cursor, M._wins.list, { idx, 0 })
    M._show_detail(idx)
  end)

  kmap(list_buf, "k", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local idx = math.max(cursor[1] - 1, 1)
    pcall(vim.api.nvim_win_set_cursor, M._wins.list, { idx, 0 })
    M._show_detail(idx)
  end)

  kmap(list_buf, "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local idx = cursor[1]
    if idx > #M._commits then return end
    local commit = M._commits[idx]
    local files = M._selected_files
    if #files == 0 then return end

    if #files == 1 then
      M._show_file_diff(commit, files[1].path)
      return
    end

    local items = {}
    for _, f in ipairs(files) do
      table.insert(items, f.path)
    end
    vim.ui.select(items, {
      prompt = "Select file:",
    }, function(choice)
      if choice then
        M._show_file_diff(commit, choice)
      end
    end)
  end)
end

return M
