local git = require("shipgit.git")
local config = require("shipgit.config")
local filelist = require("shipgit.filelist")

local M = {}

M._wins = {}    -- { list, diff_left, diff_right }
M._bufs = {}    -- { list, diff_left, diff_right }
M._stashes = {}
M._current_stash = nil
M._on_done = nil
M._on_close = nil
M._list_map = {} -- 各行が何を表すか: { type="stash"|"file"|"dir", ... }
M._collapsed = {} -- 折りたたみ状態 "stash_idx:dir_path" -> true

function M.is_open()
  return M._wins.list ~= nil and vim.api.nvim_win_is_valid(M._wins.list)
end

--- stash ウィンドウを開く
--- @param on_done fun() 操作後のコールバック
--- @param on_close fun()|nil 閉じた時のコールバック
function M.open(on_done, on_close)
  if M.is_open() then
    return
  end

  M._on_done = on_done
  M._on_close = on_close
  M._collapsed = {}
  M._stashes = git.stash_list()

  -- 各 stash のファイルツリーを事前取得し、初期状態は全て閉じる
  for i, s in ipairs(M._stashes) do
    s._files = git.stash_files(s.index)
    s._tree = filelist.build_tree(s._files)
    for _, item in ipairs(s._tree) do
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
    title = " Stash ",
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

--- ツリーアイテムを list_map に追加（再帰、折りたたみ対応）
local function render_tree_items(tree, lines, map, stash_idx, base_indent, collapsed)
  local collapsed_dirs = {}

  for _, item in ipairs(tree) do
    -- 祖先が折りたたまれているかチェック
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
        local key = stash_idx .. ":" .. item.path
        local is_collapsed = collapsed[key]
        local icon = is_collapsed and "▸" or "▾"
        lines[#lines + 1] = base_indent .. item.indent .. icon .. " " .. item.name .. "/"
        map[#map + 1] = { type = "dir", stash_idx = stash_idx, dir_path = item.path }

        if is_collapsed then
          collapsed_dirs[item.path] = true
        else
          collapsed_dirs[item.path] = nil
        end
      else
        local icon = filelist.status_icon(item.file.status)
        lines[#lines + 1] = base_indent .. item.indent .. icon .. " " .. item.name
        map[#map + 1] = { type = "file", filepath = item.file.path, status = item.file.status, stash_idx = stash_idx, parent_dir = item.parent_dir }
      end
    end
  end
end

--- 左パネルを描画
function M._render_list()
  local lines = {}
  local map = {}
  local ns = vim.api.nvim_create_namespace("shipgit_stash_list")

  if #M._stashes == 0 then
    lines[#lines + 1] = "  (no stashes)"
    map[#map + 1] = { type = "empty" }
  else
    for i, s in ipairs(M._stashes) do
      lines[#lines + 1] = " " .. s.name .. "  " .. s.message
      map[#map + 1] = { type = "stash", idx = i }

      render_tree_items(s._tree, lines, map, i, "    ", M._collapsed)
    end
  end

  M._list_map = map
  M._set_buf(M._bufs.list, lines)

  -- ハイライト
  vim.api.nvim_buf_clear_namespace(M._bufs.list, ns, 0, -1)
  for i, entry in ipairs(map) do
    if entry.type == "stash" then
      local s = M._stashes[entry.idx]
      local name_end = 1 + #s.name
      vim.api.nvim_buf_add_highlight(M._bufs.list, ns, "ShipgitHelpKey", i - 1, 1, name_end)
      vim.api.nvim_buf_add_highlight(M._bufs.list, ns, "ShipgitGraphMessage", i - 1, name_end, -1)
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
    "  Space: pop  a: apply  d: drop  n: new",
    "  q: 閉じる",
  }
  M._set_buf(M._bufs.diff_left, hint)
  M._set_buf(M._bufs.diff_right, {})
  local ns2 = vim.api.nvim_create_namespace("shipgit_stash_hint")
  vim.api.nvim_buf_clear_namespace(M._bufs.diff_left, ns2, 0, -1)
  for i = 1, #hint do
    vim.api.nvim_buf_add_highlight(M._bufs.diff_left, ns2, "ShipgitHelpDesc", i - 1, 0, -1)
  end
  M._update_titles("Old", "New")
end

function M._show_file_diff(stash, filepath)
  M._diffoff()

  local old_content = git.stash_show_parent_file(stash.index, filepath) or ""
  local new_content = git.stash_show_file(stash.index, filepath) or ""

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
  M._stashes = {}
  M._current_stash = nil
  M._list_map = {}
  M._collapsed = {}
  local cb = M._on_close
  M._on_close = nil
  if cb then
    vim.schedule(cb)
  end
end

function M._refresh()
  M._stashes = git.stash_list()
  M._collapsed = {}
  for i, s in ipairs(M._stashes) do
    s._files = git.stash_files(s.index)
    s._tree = filelist.build_tree(s._files)
    for _, item in ipairs(s._tree) do
      if item.is_dir then
        M._collapsed[i .. ":" .. item.path] = true
      end
    end
  end
  M._render_list()
  pcall(vim.api.nvim_win_set_cursor, M._wins.list, { 1, 0 })
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

local function get_selected_stash()
  if not M._wins.list or not vim.api.nvim_win_is_valid(M._wins.list) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
  local entry = M._list_map[cursor[1]]
  if not entry then return nil end
  if entry.type == "stash" then
    return M._stashes[entry.idx]
  elseif entry.type == "file" or entry.type == "dir" then
    return M._stashes[entry.stash_idx]
  end
  return nil
end

--- カーソル行の entry に応じて動作
local function handle_cursor_move()
  if not M._wins.list or not vim.api.nvim_win_is_valid(M._wins.list) then return end
  local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
  local entry = M._list_map[cursor[1]]
  if not entry then return end

  if entry.type == "file" then
    M._current_stash = M._stashes[entry.stash_idx]
    M._show_file_diff(M._current_stash, entry.filepath)
  elseif entry.type == "stash" then
    M._current_stash = M._stashes[entry.idx]
    M._diffoff()
    local hint = {
      "",
      "  j/k: 移動  h/l: 折りたたみ",
      "  Enter: diff を表示",
      "  C-h/C-l: パネル移動",
      "  Space: pop  a: apply  d: drop  n: new",
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

  local on_done = M._on_done
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
    if next_idx > total then return end
    pcall(vim.api.nvim_win_set_cursor, M._wins.list, { next_idx, 0 })
    handle_cursor_move()
  end)

  kmap(list_buf, "k", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local prev_idx = cursor[1] - 1
    if prev_idx < 1 then return end
    pcall(vim.api.nvim_win_set_cursor, M._wins.list, { prev_idx, 0 })
    handle_cursor_move()
  end)

  -- h: 折りたたむ（ファイル行なら親ディレクトリを閉じる）
  kmap(list_buf, "h", function()
    local cursor = vim.api.nvim_win_get_cursor(M._wins.list)
    local entry = M._list_map[cursor[1]]
    if not entry then return end

    if entry.type == "dir" then
      local key = entry.stash_idx .. ":" .. entry.dir_path
      if not M._collapsed[key] then
        M._collapsed[key] = true
        rerender_keeping_cursor()
      end
    elseif entry.type == "file" and entry.parent_dir then
      local key = entry.stash_idx .. ":" .. entry.parent_dir
      M._collapsed[key] = true
      rerender_keeping_cursor()
      -- カーソルを親ディレクトリ行に移動
      for i, e in ipairs(M._list_map) do
        if e.type == "dir" and e.stash_idx == entry.stash_idx and e.dir_path == entry.parent_dir then
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
      local key = entry.stash_idx .. ":" .. entry.dir_path
      M._collapsed[key] = not M._collapsed[key] or nil
      rerender_keeping_cursor()
    end
  end)

  -- Enter: diff 表示
  kmap(list_buf, "<CR>", function()
    handle_cursor_move()
  end)

  -- Space: pop
  kmap(list_buf, "<Space>", function()
    local s = get_selected_stash()
    if not s then return end
    M.close()
    vim.schedule(function()
      local out, code = git.stash_pop(s.index)
      if code ~= 0 then
        vim.notify("shipgit: stash pop 失敗\n" .. (out or ""), vim.log.levels.ERROR)
      else
        vim.notify("shipgit: stash を復元しました", vim.log.levels.INFO)
      end
      if on_done then on_done() end
    end)
  end)

  -- a: apply
  kmap(list_buf, "a", function()
    local s = get_selected_stash()
    if not s then return end
    local out, code = git.stash_apply(s.index)
    if code ~= 0 then
      vim.notify("shipgit: stash apply 失敗\n" .. (out or ""), vim.log.levels.ERROR)
    else
      vim.notify("shipgit: stash を適用しました（保持）", vim.log.levels.INFO)
    end
    if on_done then on_done() end
  end)

  -- d: drop
  kmap(list_buf, "d", function()
    local s = get_selected_stash()
    if not s then return end
    vim.ui.select({ "Yes", "No" }, {
      prompt = "Drop " .. s.name .. "?",
    }, function(choice)
      if choice == "Yes" then
        local out, code = git.stash_drop(s.index)
        if code ~= 0 then
          vim.notify("shipgit: stash drop 失敗\n" .. (out or ""), vim.log.levels.ERROR)
        else
          vim.notify("shipgit: " .. s.name .. " を削除しました", vim.log.levels.INFO)
        end
        vim.schedule(function()
          M._refresh()
        end)
      end
    end)
  end)

  -- n: new stash
  kmap(list_buf, "n", function()
    M.close()
    vim.schedule(function()
      vim.ui.input({ prompt = "Stash message (optional): " }, function(msg)
        local out, code = git.stash_push(msg)
        if code ~= 0 then
          vim.notify("shipgit: stash 失敗\n" .. (out or ""), vim.log.levels.ERROR)
        else
          vim.notify("shipgit: stash しました", vim.log.levels.INFO)
        end
        if on_done then on_done() end
      end)
    end)
  end)
end

return M
