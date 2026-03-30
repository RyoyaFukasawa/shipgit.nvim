local ui = require("shipgit.ui")

local M = {}

--- 折りたたみ状態を初期化（state に _collapsed テーブルを持たせる）
local function ensure_collapsed(state)
  if not state._collapsed then
    state._collapsed = {}
  end
end

--- ディレクトリの折りたたみをトグル
function M.toggle_dir(state)
  local entry = M.get_selected(state)
  if not entry or not entry.dir then
    return false
  end
  ensure_collapsed(state)
  local key = entry.section .. ":" .. entry.dir
  state._collapsed[key] = not state._collapsed[key]
  return true
end

--- ディレクトリを閉じる（カーソルがファイルの場合は親ディレクトリを閉じる）
function M.collapse(state)
  local entry = M.get_selected(state)
  if not entry then
    return false
  end
  ensure_collapsed(state)

  if entry.dir then
    -- ディレクトリ行：閉じる
    local key = entry.section .. ":" .. entry.dir
    if not state._collapsed[key] then
      state._collapsed[key] = true
      return true
    end
    return false
  end

  -- ファイル行：親ディレクトリを探して閉じ、カーソルをそこに移動
  if entry.file and entry._parent_dir then
    local key = entry.section .. ":" .. entry._parent_dir
    state._collapsed[key] = true
    -- カーソルを親ディレクトリに移動
    for i, e in ipairs(state.flat_files) do
      if e.dir == entry._parent_dir and e.section == entry.section then
        state.cursor = i
        break
      end
    end
    return true
  end

  return false
end

--- ディレクトリを展開
function M.expand(state)
  local entry = M.get_selected(state)
  if not entry or not entry.dir then
    return false
  end
  ensure_collapsed(state)
  local key = entry.section .. ":" .. entry.dir
  if state._collapsed[key] then
    state._collapsed[key] = false
    return true
  end
  return false
end

--- ファイル一覧バッファを描画する
function M.render(state)
  local buf = ui.bufs.filelist
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  ensure_collapsed(state)

  local lines = {}
  local highlights = {}
  local line_idx = 0

  state.flat_files = {}

  -- Conflict セクション（merge/rebase 中のみ）
  local conflict_count = #(state.files.conflict or {})
  if conflict_count > 0 then
    table.insert(lines, " Conflict (" .. conflict_count .. ")")
    table.insert(highlights, { line_idx, "ShipgitConflictHeader" })
    line_idx = line_idx + 1

    for _, f in ipairs(state.files.conflict) do
      local icon = M.status_icon(f.status)
      table.insert(lines, "  " .. icon .. " " .. f.path)
      table.insert(highlights, { line_idx, "ShipgitConflictFile" })
      table.insert(state.flat_files, { section = "conflict", file = f, line = line_idx })
      line_idx = line_idx + 1
    end

    table.insert(lines, "")
    line_idx = line_idx + 1
  end

  -- Unstaged セクション
  local unstaged_count = #state.files.unstaged
  table.insert(lines, " Unstaged (" .. unstaged_count .. ")")
  table.insert(highlights, { line_idx, "ShipgitUnstagedHeader" })
  line_idx = line_idx + 1

  if unstaged_count == 0 then
    table.insert(lines, "   (no changes)")
    line_idx = line_idx + 1
  else
    line_idx = M._render_section(state, "unstaged", state.files.unstaged, lines, highlights, line_idx, "ShipgitUnstagedFile", "ShipgitUntrackedFile")
  end

  -- 空行
  table.insert(lines, "")
  line_idx = line_idx + 1

  -- Staged セクション
  local staged_count = #state.files.staged
  table.insert(lines, " Staged (" .. staged_count .. ")")
  table.insert(highlights, { line_idx, "ShipgitStagedHeader" })
  line_idx = line_idx + 1

  if staged_count == 0 then
    table.insert(lines, "   (no changes)")
    line_idx = line_idx + 1
  else
    line_idx = M._render_section(state, "staged", state.files.staged, lines, highlights, line_idx, "ShipgitStagedFile", nil)
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- ハイライト適用
  local ns = vim.api.nvim_create_namespace("shipgit_filelist")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, hl[2], hl[1], 0, -1)
  end

  -- カーソル位置を復元
  M.set_cursor(state)
end

--- セクション（unstaged/staged）を描画
function M._render_section(state, section, files, lines, highlights, line_idx, file_hl, untracked_hl)
  local tree = M.build_tree(files)
  -- 折りたたまれているディレクトリのセット（子孫もスキップするため複数保持）
  local collapsed_dirs = {}

  for _, item in ipairs(tree) do
    -- 祖先のいずれかが折りたたまれているかチェック
    local is_hidden = false
    if item.parent_dir then
      for cdir, _ in pairs(collapsed_dirs) do
        if item.parent_dir == cdir or item.parent_dir:sub(1, #cdir + 1) == cdir .. "/" then
          is_hidden = true
          break
        end
      end
    end

    if is_hidden then
      -- スキップ
    elseif item.is_dir then
      local key = section .. ":" .. item.path
      local collapsed = state._collapsed[key]
      local icon = collapsed and "▸" or "▾"
      table.insert(lines, "  " .. item.indent .. icon .. " " .. item.name .. "/")
      table.insert(highlights, { line_idx, "ShipgitDirName" })
      table.insert(state.flat_files, { section = section, dir = item.path, line = line_idx })
      line_idx = line_idx + 1

      if collapsed then
        collapsed_dirs[item.path] = true
      else
        collapsed_dirs[item.path] = nil
      end
    else
      local icon_char = M.status_icon(item.file.status)
      local hl = file_hl
      if untracked_hl and item.file.status == "?" then
        hl = untracked_hl
      end
      table.insert(lines, "  " .. item.indent .. icon_char .. " " .. item.name)
      table.insert(highlights, { line_idx, hl })
      table.insert(state.flat_files, { section = section, file = item.file, line = line_idx, _parent_dir = item.parent_dir })
      line_idx = line_idx + 1
    end
  end

  return line_idx
end

--- カーソル位置をファイル行に設定
function M.set_cursor(state)
  local win = ui.wins.filelist
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  if not state.flat_files or #state.flat_files == 0 then
    return
  end

  state.cursor = math.max(1, math.min(state.cursor, #state.flat_files))

  local entry = state.flat_files[state.cursor]
  if entry then
    pcall(vim.api.nvim_win_set_cursor, win, { entry.line + 1, 0 })
  end
end

--- 現在選択中のファイルエントリを返す
function M.get_selected(state)
  if not state.flat_files or #state.flat_files == 0 then
    return nil
  end
  state.cursor = math.max(1, math.min(state.cursor, #state.flat_files))
  return state.flat_files[state.cursor]
end

--- ファイルリストからネストしたツリーノードを構築
--- @param files FileInfo[]
--- @return table ルートノード { children = { [name] = node }, files = {} }
function M._build_tree_nodes(files)
  local root = { children = {}, files = {}, _child_order = {} }

  for _, f in ipairs(files) do
    local parts = {}
    for part in f.path:gmatch("[^/]+") do
      table.insert(parts, part)
    end

    local node = root
    -- ディレクトリ部分をたどる
    for i = 1, #parts - 1 do
      local name = parts[i]
      if not node.children[name] then
        node.children[name] = { children = {}, files = {}, _child_order = {} }
        table.insert(node._child_order, name)
      end
      node = node.children[name]
    end
    -- ファイルを末端ノードに追加
    table.insert(node.files, { file = f, name = parts[#parts] })
  end

  return root
end

--- ツリーノードをフラットリストに変換（再帰）
--- 1つしか子を持たないディレクトリは圧縮して表示（例: src/components → 1行）
function M.build_tree(files)
  local root = M._build_tree_nodes(files)
  local result = {}
  M._flatten_node(root, result, 0, "")
  return result
end

function M._flatten_node(node, result, depth, prefix)
  local indent = string.rep("  ", depth)

  -- 子ディレクトリを先に表示
  for _, child_name in ipairs(node._child_order) do
    local child = node.children[child_name]
    local full_path = prefix == "" and child_name or (prefix .. "/" .. child_name)

    -- パス圧縮: 子ディレクトリが1つだけでファイルがない場合、結合して表示
    local display_name = child_name
    local compressed = child
    local compressed_path = full_path
    while #compressed._child_order == 1 and #compressed.files == 0 do
      local only_child_name = compressed._child_order[1]
      compressed = compressed.children[only_child_name]
      display_name = display_name .. "/" .. only_child_name
      compressed_path = compressed_path .. "/" .. only_child_name
    end

    -- ディレクトリにファイルか子ディレクトリがある場合のみ表示
    local has_content = #compressed.files > 0 or #compressed._child_order > 0
    if has_content then
      table.insert(result, {
        is_dir = true,
        name = display_name,
        path = compressed_path,
        indent = indent,
        parent_dir = prefix ~= "" and prefix or nil,
      })
      -- 再帰
      M._flatten_node(compressed, result, depth + 1, compressed_path)
    end
  end

  -- ファイルを表示
  for _, entry in ipairs(node.files) do
    table.insert(result, {
      is_dir = false,
      name = entry.name,
      path = entry.file.path,
      indent = indent,
      file = entry.file,
      parent_dir = prefix ~= "" and prefix or nil,
    })
  end
end

function M.status_icon(status)
  local icons = {
    M = "M",
    A = "+",
    D = "-",
    R = "R",
    C = "C",
    ["?"] = "?",
    U = "U",
    -- conflict
    UU = "!",
    AA = "!",
    DD = "!",
    AU = "!",
    UA = "!",
    DU = "!",
    UD = "!",
  }
  return icons[status] or status
end

return M
