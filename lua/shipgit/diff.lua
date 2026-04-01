local ui = require("shipgit.ui")
local git = require("shipgit.git")

local M = {}

--- 選択中のファイルの side-by-side diff を表示
--- @param state table
function M.show_file(state)
  local filelist = require("shipgit.filelist")
  local entry = filelist.get_selected(state)

  -- diff モード解除
  M.diffoff()

  if not entry then
    M.set_empty("ファイルが選択されていません")
    return
  end

  -- ディレクトリ行が選択された場合
  if entry.dir then
    M.set_empty(entry.dir .. "/ (ディレクトリ)")
    return
  end

  local filepath = entry.file.path
  local old_content, new_content

  if entry.section == "unstaged" then
    -- unstaged: old = HEAD (or index), new = working tree
    if entry.file.status == "?" then
      -- untracked: old は空
      old_content = ""
      new_content = git.read_working(filepath) or ""
    else
      old_content = git.show_index(filepath) or git.show_head(filepath) or ""
      new_content = git.read_working(filepath) or ""
    end
  else
    -- staged: old = HEAD, new = index
    if entry.file.status == "A" then
      old_content = ""
      new_content = git.show_index(filepath) or ""
    elseif entry.file.status == "D" then
      old_content = git.show_head(filepath) or ""
      new_content = ""
    else
      old_content = git.show_head(filepath) or ""
      new_content = git.show_index(filepath) or ""
    end
  end

  local old_lines = vim.split(old_content, "\n", { plain = true })
  local new_lines = vim.split(new_content, "\n", { plain = true })

  -- 末尾の空行を除去
  while #old_lines > 0 and old_lines[#old_lines] == "" do
    table.remove(old_lines)
  end
  while #new_lines > 0 and new_lines[#new_lines] == "" do
    table.remove(new_lines)
  end

  -- バッファに内容をセット
  M.set_buf_lines(ui.bufs.diff_left, old_lines)
  M.set_buf_lines(ui.bufs.diff_right, new_lines)

  -- 右パネル（new）を編集可能にする（unstaged のみ、ワーキングツリーを直接編集）
  state._current_filepath = filepath
  if not ui.bufs.diff_right or not vim.api.nvim_buf_is_valid(ui.bufs.diff_right) then
    return
  end
  pcall(vim.api.nvim_buf_set_name, ui.bufs.diff_right, "")
  if entry.section == "unstaged" and entry.file.status ~= "D" then
    pcall(vim.api.nvim_buf_set_name, ui.bufs.diff_right, "shipgit://" .. filepath)
    vim.bo[ui.bufs.diff_right].buftype = "acwrite"
    vim.bo[ui.bufs.diff_right].modifiable = true
    vim.bo[ui.bufs.diff_right].readonly = false
  else
    vim.api.nvim_buf_set_name(ui.bufs.diff_right, "shipgit://[readonly]/" .. filepath)
    vim.bo[ui.bufs.diff_right].buftype = "nofile"
  end

  -- filetype 設定（syntax highlight用）
  local ft = vim.filetype.match({ filename = filepath }) or ""
  vim.bo[ui.bufs.diff_left].filetype = ft
  vim.bo[ui.bufs.diff_right].filetype = ft

  -- diff モード有効化
  vim.api.nvim_set_current_win(ui.wins.diff_left)
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(ui.wins.diff_right)
  vim.cmd("diffthis")

  -- スクロール同期
  vim.wo[ui.wins.diff_left].scrollbind = true
  vim.wo[ui.wins.diff_right].scrollbind = true
  vim.wo[ui.wins.diff_left].cursorbind = true
  vim.wo[ui.wins.diff_right].cursorbind = true

  -- ハンク行が選択されている場合、そのハンク位置にスクロール
  if entry.hunk then
    local scroll_line = entry.hunk.start_new
    if ui.wins.diff_right and vim.api.nvim_win_is_valid(ui.wins.diff_right) then
      pcall(vim.api.nvim_win_set_cursor, ui.wins.diff_right, { math.max(scroll_line, 1), 0 })
    end
  end

  -- ファイル一覧にフォーカスを戻す
  if state.active_panel == "filelist" then
    ui.focus_filelist()
  end
end

function M.diffoff()
  for _, win_name in ipairs({ "diff_left", "diff_right" }) do
    local win = ui.wins[win_name]
    if win and vim.api.nvim_win_is_valid(win) then
      local prev_win = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(win)
      vim.cmd("diffoff")
      vim.api.nvim_set_current_win(prev_win)
    end
  end
end

function M.set_empty(msg)
  local lines = { "", "  " .. (msg or "") }
  M.set_buf_lines(ui.bufs.diff_left, lines)
  M.set_buf_lines(ui.bufs.diff_right, lines)
  vim.bo[ui.bufs.diff_left].filetype = ""
  vim.bo[ui.bufs.diff_right].filetype = ""
end

function M.set_buf_lines(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- カーソル位置のハンクをstage/unstageする
--- @param state table
function M.stage_hunk_at_cursor(state)
  local filelist = require("shipgit.filelist")
  local entry = filelist.get_selected(state)
  if not entry or entry.dir then
    return
  end

  local filepath = entry.file.path
  local is_staged = entry.section == "staged"

  local hunks = git.diff_hunks(filepath, is_staged)
  if #hunks == 0 then
    vim.notify("shipgit: ハンクが見つかりません", vim.log.levels.WARN)
    return
  end

  -- カーソル位置から対象の行番号を取得
  -- diffモードのウィンドウからカーソル行を取得
  local cursor_line = nil
  local cur_win = vim.api.nvim_get_current_win()
  if cur_win == ui.wins.diff_right then
    cursor_line = vim.api.nvim_win_get_cursor(cur_win)[1]
  elseif cur_win == ui.wins.diff_left then
    cursor_line = vim.api.nvim_win_get_cursor(cur_win)[1]
  end

  if not cursor_line then
    return
  end

  -- カーソル行がNeovimのdiffハイライト上にあるか確認
  local is_on_diff = vim.diff and true or true -- diffthis が有効な前提
  local hl_id = vim.fn.diff_hlID(cursor_line, 1)
  if hl_id == 0 then
    -- filler行（相手側に行がない）かチェック
    local filler = vim.fn.diff_filler(cursor_line)
    if filler == 0 then
      vim.notify("shipgit: カーソルがハンク上にありません", vim.log.levels.WARN)
      return
    end
  end

  -- カーソル行からgitハンクを特定
  -- Neovimのdiffとgitのdiffで行番号がずれうるため、最も近いハンクを選ぶ
  local target_hunk = nil
  local min_dist = math.huge
  if cur_win == ui.wins.diff_right then
    for _, hunk in ipairs(hunks) do
      local hunk_start = hunk.start_new
      local hunk_end = hunk.start_new + math.max(hunk.count_new, 1) - 1
      if cursor_line >= hunk_start and cursor_line <= hunk_end then
        target_hunk = hunk
        break
      end
      -- 最も近いハンクを記録
      local dist = math.min(math.abs(cursor_line - hunk_start), math.abs(cursor_line - hunk_end))
      if dist < min_dist then
        min_dist = dist
        target_hunk = hunk
      end
    end
  elseif cur_win == ui.wins.diff_left then
    for _, hunk in ipairs(hunks) do
      local hunk_start = hunk.start_old
      local hunk_end = hunk.start_old + math.max(hunk.count_old, 1) - 1
      if cursor_line >= hunk_start and cursor_line <= hunk_end then
        target_hunk = hunk
        break
      end
      local dist = math.min(math.abs(cursor_line - hunk_start), math.abs(cursor_line - hunk_end))
      if dist < min_dist then
        min_dist = dist
        target_hunk = hunk
      end
    end
  end

  if not target_hunk then
    vim.notify("shipgit: カーソルがハンク上にありません", vim.log.levels.WARN)
    return
  end

  local out, code
  if is_staged then
    out, code = git.unstage_hunk(target_hunk)
  else
    out, code = git.stage_hunk(target_hunk)
  end
  if code ~= 0 then
    vim.notify("shipgit: ハンクのstage失敗\n" .. (out or ""), vim.log.levels.ERROR)
  end
end

--- 右パネルの内容をワーキングツリーに保存
function M.save_right(state)
  if not state._current_filepath then
    return
  end
  local buf = ui.bufs.diff_right
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fullpath = git.cwd .. "/" .. state._current_filepath
  local ok, err = pcall(vim.fn.writefile, lines, fullpath)
  if ok then
    vim.notify("shipgit: 保存しました " .. state._current_filepath, vim.log.levels.INFO)
  else
    vim.notify("shipgit: 保存失敗 " .. (err or ""), vim.log.levels.ERROR)
  end
end

return M
