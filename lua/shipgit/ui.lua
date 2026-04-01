local config = require("shipgit.config")

local M = {}

-- ウィンドウ/バッファ参照
M.wins = {}
M.bufs = {}
M.autocmd_group = nil
M._suspend_close = false

local function create_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  return buf
end

local function calc_layout()
  local ew = vim.o.columns
  local eh = vim.o.lines
  local cfg = config.values

  local total_w = math.floor(ew * cfg.width)
  local total_h = math.floor(eh * cfg.height)
  local start_row = math.floor((eh - total_h) / 2)
  local start_col = math.floor((ew - total_w) / 2)

  -- 背景フレーム（border込み）
  local frame = {
    row = start_row,
    col = start_col,
    width = total_w,
    height = total_h,
  }

  -- 内部領域（border分を引く）
  local inner_w = total_w - 2
  local inner_h = total_h - 2
  local inner_row = start_row + 1
  local inner_col = start_col + 1

  -- ファイル一覧: 左 25%
  local fl_w = math.floor(inner_w * cfg.filelist_width)
  local filelist = {
    row = inner_row,
    col = inner_col,
    width = fl_w,
    height = inner_h,
  }

  -- セパレータ: 1列
  local sep = {
    row = inner_row,
    col = inner_col + fl_w,
    width = 1,
    height = inner_h,
  }

  -- diff領域: 残りを2等分
  local diff_total_w = inner_w - fl_w - 1
  local diff_w = math.floor(diff_total_w / 2)
  local diff_left = {
    row = inner_row,
    col = inner_col + fl_w + 1,
    width = diff_w,
    height = inner_h,
  }

  local diff_right = {
    row = inner_row,
    col = inner_col + fl_w + 1 + diff_w,
    width = diff_total_w - diff_w,
    height = inner_h,
  }

  return {
    frame = frame,
    filelist = filelist,
    separator = sep,
    diff_left = diff_left,
    diff_right = diff_right,
  }
end

function M.open(state)
  local layout = calc_layout()
  local cfg = config.values

  -- 背景フレーム
  M.bufs.frame = create_buf()
  M.wins.frame = vim.api.nvim_open_win(M.bufs.frame, false, {
    relative = "editor",
    row = layout.frame.row,
    col = layout.frame.col,
    width = layout.frame.width,
    height = layout.frame.height,
    style = "minimal",
    border = cfg.border,
    title = " shipgit - " .. (state.branch or "???") .. " ",
    title_pos = "center",
    zindex = 40,
    focusable = false,
  })
  vim.wo[M.wins.frame].winblend = 0
  vim.api.nvim_set_option_value("winhighlight", "NormalFloat:Normal,FloatBorder:ShipgitBorder,FloatTitle:ShipgitTitle", { win = M.wins.frame })

  -- ファイル一覧
  M.bufs.filelist = create_buf()
  M.wins.filelist = vim.api.nvim_open_win(M.bufs.filelist, true, {
    relative = "editor",
    row = layout.filelist.row,
    col = layout.filelist.col,
    width = layout.filelist.width,
    height = layout.filelist.height,
    style = "minimal",
    border = "none",
    zindex = 50,
    focusable = true,
  })
  vim.wo[M.wins.filelist].cursorline = true
  vim.wo[M.wins.filelist].wrap = false
  vim.api.nvim_set_option_value("winhighlight", "NormalFloat:Normal,CursorLine:ShipgitCursorLine", { win = M.wins.filelist })

  -- セパレータ
  M.bufs.separator = create_buf()
  local sep_lines = {}
  for _ = 1, layout.separator.height do
    table.insert(sep_lines, "│")
  end
  vim.api.nvim_buf_set_lines(M.bufs.separator, 0, -1, false, sep_lines)
  M.wins.separator = vim.api.nvim_open_win(M.bufs.separator, false, {
    relative = "editor",
    row = layout.separator.row,
    col = layout.separator.col,
    width = layout.separator.width,
    height = layout.separator.height,
    style = "minimal",
    border = "none",
    zindex = 45,
    focusable = false,
  })
  vim.api.nvim_set_option_value("winhighlight", "NormalFloat:ShipgitSeparator", { win = M.wins.separator })

  -- Diff左 (old)
  M.bufs.diff_left = create_buf()
  M.wins.diff_left = vim.api.nvim_open_win(M.bufs.diff_left, false, {
    relative = "editor",
    row = layout.diff_left.row,
    col = layout.diff_left.col,
    width = layout.diff_left.width,
    height = layout.diff_left.height,
    style = "minimal",
    border = "none",
    zindex = 50,
    focusable = true,
  })
  vim.wo[M.wins.diff_left].number = true
  vim.wo[M.wins.diff_left].wrap = false
  vim.wo[M.wins.diff_left].cursorline = true
  vim.wo[M.wins.diff_left].foldmethod = "diff"
  vim.wo[M.wins.diff_left].foldlevel = 99
  vim.api.nvim_set_option_value("winhighlight",
    "NormalFloat:Normal,DiffAdd:ShipgitDiffAdd,DiffChange:ShipgitDiffChange,DiffDelete:ShipgitDiffDelete,DiffText:ShipgitDiffText",
    { win = M.wins.diff_left })

  -- Diff右 (new)
  M.bufs.diff_right = create_buf()
  M.wins.diff_right = vim.api.nvim_open_win(M.bufs.diff_right, false, {
    relative = "editor",
    row = layout.diff_right.row,
    col = layout.diff_right.col,
    width = layout.diff_right.width,
    height = layout.diff_right.height,
    style = "minimal",
    border = "none",
    zindex = 50,
    focusable = true,
  })
  vim.wo[M.wins.diff_right].number = true
  vim.wo[M.wins.diff_right].wrap = false
  vim.wo[M.wins.diff_right].cursorline = true
  vim.wo[M.wins.diff_right].foldmethod = "diff"
  vim.wo[M.wins.diff_right].foldlevel = 99
  vim.api.nvim_set_option_value("winhighlight",
    "NormalFloat:Normal,DiffAdd:ShipgitDiffAdd,DiffChange:ShipgitDiffChange,DiffDelete:ShipgitDiffDelete,DiffText:ShipgitDiffText",
    { win = M.wins.diff_right })

  -- VimResized でリサイズ
  M.autocmd_group = vim.api.nvim_create_augroup("ShipgitResize", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = M.autocmd_group,
    callback = function()
      M.resize()
    end,
  })

  -- フォーカスがshipgit外に出たら閉じる
  vim.api.nvim_create_autocmd("WinLeave", {
    group = M.autocmd_group,
    callback = function()
      vim.schedule(function()
        if M._suspend_close then
          return
        end
        local cur_win = vim.api.nvim_get_current_win()
        local shipgit_wins = { M.wins.filelist, M.wins.diff_left, M.wins.diff_right }
        for _, w in ipairs(shipgit_wins) do
          if cur_win == w then
            return
          end
        end
        -- input ウィンドウが開いている間は閉じない
        local input = package.loaded["shipgit.input"]
        if input and input.is_open() then
          return
        end
        -- log ウィンドウが開いている間は閉じない
        local log = package.loaded["shipgit.log"]
        if log and log.is_open() then
          return
        end
        -- stash ウィンドウが開いている間は閉じない
        local stash = package.loaded["shipgit.stash"]
        if stash and stash.is_open() then
          return
        end
        -- branches ウィンドウが開いている間は閉じない
        local branches = package.loaded["shipgit.branches"]
        if branches and branches.is_open() then
          return
        end
        -- tree ウィンドウが開いている間は閉じない
        local tree = package.loaded["shipgit.tree"]
        if tree and tree.is_open() then
          return
        end
        -- projects ウィンドウが開いている間は閉じない
        local projects = package.loaded["shipgit.projects"]
        if projects and projects.is_open() then
          return
        end
        -- 現在のウィンドウがフローティングなら閉じない（ヘルプ、vim.ui.select 等）
        local win_config = vim.api.nvim_win_get_config(cur_win)
        if win_config.relative and win_config.relative ~= "" then
          return
        end
        M.close()
      end)
    end,
  })
end

function M.resize()
  if not M.wins.frame or not vim.api.nvim_win_is_valid(M.wins.frame) then
    return
  end

  local layout = calc_layout()

  local function reconfig(win, l)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        row = l.row,
        col = l.col,
        width = l.width,
        height = l.height,
      })
    end
  end

  local cfg = config.values
  vim.api.nvim_win_set_config(M.wins.frame, {
    relative = "editor",
    row = layout.frame.row,
    col = layout.frame.col,
    width = layout.frame.width,
    height = layout.frame.height,
    border = cfg.border,
  })

  reconfig(M.wins.filelist, layout.filelist)
  reconfig(M.wins.separator, layout.separator)
  reconfig(M.wins.diff_left, layout.diff_left)
  reconfig(M.wins.diff_right, layout.diff_right)

  -- セパレータ行数更新
  local sep_lines = {}
  for _ = 1, layout.separator.height do
    table.insert(sep_lines, "│")
  end
  vim.bo[M.bufs.separator].modifiable = true
  vim.api.nvim_buf_set_lines(M.bufs.separator, 0, -1, false, sep_lines)
  vim.bo[M.bufs.separator].modifiable = false
end

function M.close()
  -- サブウィンドウを先に閉じる
  local sub_modules = { "shipgit.branches", "shipgit.stash", "shipgit.log", "shipgit.tree", "shipgit.projects", "shipgit.input" }
  for _, mod_name in ipairs(sub_modules) do
    local mod = package.loaded[mod_name]
    if mod and mod.is_open and mod.is_open() and mod.close then
      pcall(mod.close)
    end
  end

  -- autocmd 削除
  if M.autocmd_group then
    pcall(vim.api.nvim_del_augroup_by_id, M.autocmd_group)
    M.autocmd_group = nil
  end

  -- diff モード解除
  for _, win_name in ipairs({ "diff_left", "diff_right" }) do
    local win = M.wins[win_name]
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
      vim.cmd("diffoff")
    end
  end

  -- ウィンドウを閉じる
  for name, win in pairs(M.wins) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    M.wins[name] = nil
  end

  -- バッファを削除
  for name, buf in pairs(M.bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    M.bufs[name] = nil
  end
end

function M.focus_filelist()
  if M.wins.filelist and vim.api.nvim_win_is_valid(M.wins.filelist) then
    vim.api.nvim_set_current_win(M.wins.filelist)
  end
end

function M.focus_diff()
  if M.wins.diff_left and vim.api.nvim_win_is_valid(M.wins.diff_left) then
    vim.api.nvim_set_current_win(M.wins.diff_left)
  end
end

function M.focus_diff_left()
  if M.wins.diff_left and vim.api.nvim_win_is_valid(M.wins.diff_left) then
    vim.api.nvim_set_current_win(M.wins.diff_left)
  end
end

function M.focus_diff_right()
  if M.wins.diff_right and vim.api.nvim_win_is_valid(M.wins.diff_right) then
    vim.api.nvim_set_current_win(M.wins.diff_right)
  end
end

return M
