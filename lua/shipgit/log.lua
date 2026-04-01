local git = require("shipgit.git")
local config = require("shipgit.config")
local filelist = require("shipgit.filelist")

local M = {}

M._wins = {}    -- { list, diff_left, diff_right }
M._bufs = {}    -- { list, diff_left, diff_right }
M._commits = {}
M._current_commit = nil
M._on_close = nil
M._list_map = {} -- 各行が何を表すか: { type="commit"|"file"|"dir", ... }
M._collapsed = {} -- 折りたたみ状態 "commit_idx:dir_path" -> true
M._load_count = 30 -- 1回あたりの読み込み件数
M._no_more = false -- これ以上コミットがないか
M._branch = nil -- 表示対象ブランチ（nil=現在のブランチ）

function M.is_open()
  return M._wins.list ~= nil and vim.api.nvim_win_is_valid(M._wins.list)
end

function M.open(on_close, branch)
  if M.is_open() then
    return
  end

  M._on_close = on_close
  M._collapsed = {}
  M._no_more = false
  M._branch = branch
  M._commits = git.log(M._load_count, 0, branch)
  if #M._commits == 0 then
    vim.notify("shipgit: コミット履歴がありません", vim.log.levels.WARN)
    return
  end

  -- 各コミットのファイルツリーを事前取得し、初期状態は全て閉じる
  for i, c in ipairs(M._commits) do
    c._files = git.commit_files(c.hash)
    c._tree = filelist.build_tree(c._files)
    for _, item in ipairs(c._tree) do
      if item.is_dir then
        M._collapsed[i .. ":" .. item.path] = true
      end
    end
  end

  M._create_layout()
  M._render_list()
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
    title = " Commit Log" .. (M._branch and (" (" .. M._branch .. ")") or "") .. " ",
    title_pos = "center",
  })
  vim.wo[M._wins.list].cursorline = true
  vim.wo[M._wins.list].wrap = false

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

--- ツリーアイテムを list_map に追加（折りたたみ対応）
local function render_tree_items(tree, lines, map, commit_idx, base_indent, collapsed)
  local collapsed_dirs = {}

  for _, item in ipairs(tree) do
    local is_hidden = false
    if item.parent_dir then
      for cdir, _ in pairs(collapsed_dirs) do
        if item.parent_dir == cdir or item.parent_dir:sub(1, #cdir + 1) == cdir .. "/" then
          is_hidden = true
          break
        end
      end
    end

    if not is_hidden then
      if item.is_dir then
        local key = commit_idx .. ":" .. item.path
        local is_collapsed = collapsed[key]
        local icon = is_collapsed and "▸" or "▾"
        lines[#lines + 1] = base_indent .. item.indent .. icon .. " " .. item.name .. "/"
        map[#map + 1] = { type = "dir", commit_idx = commit_idx, dir_path = item.path }

        if is_collapsed then
          collapsed_dirs[item.path] = true
        else
          collapsed_dirs[item.path] = nil
        end
      else
        local icon = filelist.status_icon(item.file.status)
        lines[#lines + 1] = base_indent .. item.indent .. icon .. " " .. item.name
        map[#map + 1] = { type = "file", filepath = item.file.path, status = item.file.status, commit_idx = commit_idx, parent_dir = item.parent_dir }
      end
    end
  end
end

--- 左パネルを描画
function M._render_list()
  local lines = {}
  local map = {}
  local ns = vim.api.nvim_create_namespace("shipgit_log_list")

  for i, c in ipairs(M._commits) do
    lines[#lines + 1] = " " .. c.short_hash .. " " .. c.subject
    map[#map + 1] = { type = "commit", idx = i }

    render_tree_items(c._tree, lines, map, i, "    ", M._collapsed)
  end

  M._list_map = map
  M._set_buf(M._bufs.list, lines)

  -- ハイライト
  vim.api.nvim_buf_clear_namespace(M._bufs.list, ns, 0, -1)
  for i, entry in ipairs(map) do
    if entry.type == "commit" then
      local c = M._commits[entry.idx]
      vim.api.nvim_buf_add_highlight(M._bufs.list, ns, "ShipgitGraphHash", i - 1, 1, 1 + #c.short_hash)
      vim.api.nvim_buf_add_highlight(M._bufs.list, ns, "ShipgitGraphMessage", i - 1, 1 + #c.short_hash + 1, -1)
    elseif entry.type == "dir" then
      vim.api.nvim_buf_add_highlight(M._bufs.list, ns, "ShipgitDirName", i - 1, 0, -1)
    elseif entry.type == "file" then
      local hl
      if entry.status == "A" then hl = "ShipgitStagedFile"
      elseif entry.status == "D" then hl = "ShipgitStatusDel"
      elseif entry.status == "M" then hl = "ShipgitUnstagedFile"
      else hl = "ShipgitGraphMessage"
      end
      vim.api.nvim_buf_add_highlight(M._bufs.list, ns, hl, i - 1, 0, -1)
    end
  end

  -- 右パネルにヒント表示
  M._diffoff()
  local hint = {
    "",
    "  j/k: 移動  h/l: 折りたたみ",
    "  Enter: diff を表示",
    "  C-h/C-l: パネル移動",
    "  q: 閉じる",
  }
  M._set_buf(M._bufs.diff_left, hint)
  M._set_buf(M._bufs.diff_right, {})
  local ns2 = vim.api.nvim_create_namespace("shipgit_log_hint")
  vim.api.nvim_buf_clear_namespace(M._bufs.diff_left, ns2, 0, -1)
  for i = 1, #hint do
    vim.api.nvim_buf_add_highlight(M._bufs.diff_left, ns2, "ShipgitHelpDesc", i - 1, 0, -1)
  end
  M._update_titles("Old", "New")
end

function M._show_file_diff(commit, filepath)
  M._diffoff()

  local old_content = git.show_commit_file(commit.hash .. "~1", filepath) or ""
  local new_content = git.show_commit_file(commit.hash, filepath) or ""

  local old_lines = vim.split(old_content, "\n", { plain = true })
  local new_lines = vim.split(new_content, "\n", { plain = true })
  while #old_lines > 0 and old_lines[#old_lines] == "" do table.remove(old_lines) end
  while #new_lines > 0 and new_lines[#new_lines] == "" do table.remove(new_lines) end

  M._set_buf(M._bufs.diff_left, old_lines)
  M._set_buf(M._bufs.diff_right, new_lines)

  local ft = vim.filetype.match({ filename = filepath }) or ""
  vim.bo[M._bufs.diff_left].filetype = ft
  vim.bo[M._bufs.diff_right].filetype = ft

  vim.api.nvim_set_current_win(M._wins.diff_left)
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(M._wins.diff_right)
  vim.cmd("diffthis")

  vim.wo[M._wins.diff_left].scrollbind = true
  vim.wo[M._wins.diff_right].scrollbind = true
  vim.wo[M._wins.diff_left].cursorbind = true
  vim.wo[M._wins.diff_right].cursorbind = true

  local short = vim.fn.fnamemodify(filepath, ":t")
  M._update_titles(short .. " (old)", short .. " (new)")

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
  M._current_commit = nil
  M._list_map = {}
  M._collapsed = {}
  M._no_more = false
  M._branch = nil
  local cb = M._on_close
  M._on_close = nil
  if cb then
    vim.schedule(cb)
  end
end

--- 追加コミットを読み込む
local function load_more()
  if M._no_more then return false end
  local new_commits = git.log(M._load_count, #M._commits, M._branch)
  if #new_commits == 0 then
    M._no_more = true
    return false
  end
  local base = #M._commits
  for i, c in ipairs(new_commits) do
    c._files = git.commit_files(c.hash)
    c._tree = filelist.build_tree(c._files)
    for _, item in ipairs(c._tree) do
      if item.is_dir then
        M._collapsed[(base + i) .. ":" .. item.path] = true
      end
    end
    M._commits[#M._commits + 1] = c
  end
  if #new_commits < M._load_count then
    M._no_more = true
  end
  return true
end

--- カーソル位置を保持してリスト再描画
local function rerender_keeping_cursor()
  local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
  M._render_list()
  local total = #M._list_map
  local row = math.min(cursor[1], total)
  if row >= 1 then
    pcall(vim.api.nvim_win_set_cursor, M._wins.list, { row, 0 })
  end
end

--- カーソル行の entry に応じて動作
local function handle_cursor_move()
  if not M._wins.list or not vim.api.nvim_win_is_valid(M._wins.list) then return end
  local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
  local entry = M._list_map[cursor[1]]
  if not entry then return end

  if entry.type == "file" then
    M._current_commit = M._commits[entry.commit_idx]
    M._show_file_diff(M._current_commit, entry.filepath)
  elseif entry.type == "commit" then
    M._current_commit = M._commits[entry.idx]
    M._diffoff()
    local hint = {
      "",
      "  " .. M._current_commit.short_hash .. " " .. M._current_commit.subject,
      "  " .. M._current_commit.author .. " · " .. M._current_commit.date,
      "",
      "  j/k: 移動  h/l: 折りたたみ",
      "  Enter: diff を表示",
      "  c: cherry-pick",
      "  C-h/C-l: パネル移動",
      "  q: 閉じる",
    }
    M._set_buf(M._bufs.diff_left, hint)
    M._set_buf(M._bufs.diff_right, {})
    M._update_titles("Old", "New")
  end
end

function M._setup_keymaps()
  local function kmap(buf, key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
  end

  local all_bufs = { M._bufs.list, M._bufs.diff_left, M._bufs.diff_right }

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

  local list_buf = M._bufs.list

  -- j/k: カーソル移動
  kmap(list_buf, "j", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local total = #M._list_map
    local next_idx = cursor[1] + 1
    if next_idx > total then
      -- 末尾に到達したら追加読み込み
      if load_more() then
        M._render_list()
        pcall(vim.api.nvim_win_set_cursor, M._wins.list, { next_idx, 0 })
        handle_cursor_move()
      end
      return
    end
    pcall(vim.api.nvim_win_set_cursor, M._wins.list, { next_idx, 0 })
    handle_cursor_move()
    -- 末尾付近で先読み
    if next_idx >= total - 5 then
      if load_more() then
        rerender_keeping_cursor()
      end
    end
  end)

  kmap(list_buf, "k", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local prev_idx = cursor[1] - 1
    if prev_idx < 1 then return end
    pcall(vim.api.nvim_win_set_cursor, M._wins.list, { prev_idx, 0 })
    handle_cursor_move()
  end)

  -- h: 折りたたむ
  kmap(list_buf, "h", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local entry = M._list_map[cursor[1]]
    if not entry then return end

    if entry.type == "dir" then
      local key = entry.commit_idx .. ":" .. entry.dir_path
      if not M._collapsed[key] then
        M._collapsed[key] = true
        rerender_keeping_cursor()
      end
    elseif entry.type == "file" and entry.parent_dir then
      local key = entry.commit_idx .. ":" .. entry.parent_dir
      M._collapsed[key] = true
      rerender_keeping_cursor()
      for i, e in ipairs(M._list_map) do
        if e.type == "dir" and e.commit_idx == entry.commit_idx and e.dir_path == entry.parent_dir then
          pcall(vim.api.nvim_win_set_cursor, M._wins.list, { i, 0 })
          break
        end
      end
    end
  end)

  -- l: トグル（展開/折りたたみ）
  kmap(list_buf, "l", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local entry = M._list_map[cursor[1]]
    if not entry then return end

    if entry.type == "dir" then
      local key = entry.commit_idx .. ":" .. entry.dir_path
      M._collapsed[key] = not M._collapsed[key] or nil
      rerender_keeping_cursor()
    end
  end)

  -- Enter: diff 表示
  kmap(list_buf, "<CR>", function()
    handle_cursor_move()
  end)

  -- c: cherry-pick
  kmap(list_buf, "c", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local entry = M._list_map[cursor[1]]
    if not entry then return end

    -- ファイル行ならそのコミットを対象にする
    local commit_idx = entry.type == "commit" and entry.idx or entry.commit_idx
    if not commit_idx then return end
    local commit = M._commits[commit_idx]

    vim.ui.select({ "Yes", "No" }, {
      prompt = "Cherry-pick " .. commit.short_hash .. " " .. commit.subject .. "?",
    }, function(choice)
      if choice == "Yes" then
        vim.notify("shipgit: cherry-picking " .. commit.short_hash .. "...", vim.log.levels.INFO)
        git.cherry_pick_async(commit.hash, function(out, code)
          if code ~= 0 and git.is_cherry_picking() then
            vim.notify("shipgit: cherry-pick コンフリクトが発生しました。ファイルを編集して解消してください", vim.log.levels.WARN)
          elseif code ~= 0 then
            vim.notify("shipgit: cherry-pick 失敗\n" .. (out or ""), vim.log.levels.ERROR)
          else
            vim.notify("shipgit: " .. commit.short_hash .. " を cherry-pick しました", vim.log.levels.INFO)
          end
          if M._on_close then M._on_close() end
        end)
      end
    end)
  end)
end

return M
