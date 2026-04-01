local config = require("shipgit.config")
local ui = require("shipgit.ui")
local git = require("shipgit.git")
local filelist = require("shipgit.filelist")
local diff = require("shipgit.diff")

local M = {}

local function map(buf, key, action)
  vim.keymap.set("n", key, action, { buffer = buf, nowait = true, silent = true })
end

--- 全体の状態を更新して再描画
local function refresh(state)
  state.files = git.status()
  -- カーソルをクランプ
  local total = #(state.flat_files or {})
  if total == 0 then
    state.cursor = 1
  end
  filelist.render(state)
  diff.show_file(state)

  -- タイトル更新（merge/rebase 状態を表示）
  if ui.wins.frame and vim.api.nvim_win_is_valid(ui.wins.frame) then
    local branch = git.branch()
    local status_label = ""
    if git.is_merging() then
      status_label = " [MERGING]"
    elseif git.is_rebasing() then
      status_label = " [REBASING]"
    elseif git.is_cherry_picking() then
      status_label = " [CHERRY-PICKING]"
    end
    vim.api.nvim_win_set_config(ui.wins.frame, {
      title = " shipgit - " .. branch .. status_label .. " ",
      title_pos = "center",
    })
  end
end

function M.attach(state)
  M.attach_filelist(state)
  M.attach_diff(state)
end

function M.attach_filelist(state)
  local buf = ui.bufs.filelist
  local keys = config.values.keymaps

  -- ファイル移動
  map(buf, keys.next_file, function()
    state.cursor = math.min(state.cursor + 1, #(state.flat_files or {}))
    filelist.set_cursor(state)
    diff.show_file(state)
  end)

  map(buf, keys.prev_file, function()
    state.cursor = math.max(state.cursor - 1, 1)
    filelist.set_cursor(state)
    diff.show_file(state)
  end)

  -- h: ディレクトリ折りたたみ（ファイル上なら親を折りたたむ）
  map(buf, "h", function()
    if filelist.collapse(state) then
      filelist.render(state)
      diff.show_file(state)
    end
  end)

  -- l: ディレクトリトグル（閉じてたら開く、開いてたら閉じる）
  map(buf, "l", function()
    if filelist.toggle_dir(state) then
      filelist.render(state)
      diff.show_file(state)
    end
  end)

  -- Stage/Unstage トグル（ファイル or ディレクトリ or ハンク or conflict resolved）
  map(buf, keys.stage_toggle, function()
    local entry = filelist.get_selected(state)
    if not entry then
      return
    end
    if entry.hunk then
      -- ハンク単位のstage/unstage
      local out, code
      if entry.section == "staged" then
        out, code = git.unstage_hunk(entry.hunk)
      else
        out, code = git.stage_hunk(entry.hunk)
      end
      if code ~= 0 then
        vim.notify("shipgit: ハンクのstage失敗\n" .. (out or ""), vim.log.levels.ERROR)
      end
    elseif entry.section == "conflict" then
      git.mark_resolved(entry.file.path)
    elseif entry.section == "unstaged" then
      local path = entry.dir or entry.file.path
      git.stage(path)
    else
      local path = entry.dir or entry.file.path
      git.unstage(path)
    end
    refresh(state)
  end)

  -- 全 Stage/Unstage トグル
  map(buf, keys.stage_all, function()
    -- unstaged があれば全 stage、なければ全 unstage
    if #state.files.unstaged > 0 then
      git.stage_all()
    else
      git.unstage_all()
    end
    refresh(state)
  end)

  -- コミット
  map(buf, keys.commit, function()
    if #state.files.staged == 0 then
      vim.notify("shipgit: ステージされたファイルがありません", vim.log.levels.WARN)
      return
    end
    local input = require("shipgit.input")
    -- merge/cherry-pick 中はデフォルトメッセージを設定
    local default_msg = nil
    local msg_file = nil
    if git.is_merging() then
      msg_file = git.cwd .. "/.git/MERGE_MSG"
    elseif git.is_cherry_picking() then
      msg_file = git.cwd .. "/.git/CHERRY_PICK_HEAD"
      -- cherry-pick のメッセージは元コミットのメッセージを使う
      local head_out = git.show_cherry_pick_msg()
      if head_out then
        default_msg = head_out
      end
    end
    if not default_msg and msg_file then
      local f = io.open(msg_file, "r")
      if f then
        default_msg = vim.trim(f:read("*l") or "")
        f:close()
      end
    end
    input.open(function(msg)
      if msg and msg ~= "" then
        local _, code = git.commit(msg)
        if code ~= 0 then
          vim.notify("shipgit: コミット失敗", vim.log.levels.ERROR)
        end
        refresh(state)
      end
      ui.focus_filelist()
    end, default_msg)
  end)

  -- Push
  map(buf, keys.push, function()
    vim.notify("shipgit: pushing...", vim.log.levels.INFO)
    git.push_async(function(out, code)
      if code ~= 0 then
        vim.notify("shipgit: push 失敗\n" .. (out or ""), vim.log.levels.ERROR)
      else
        vim.notify("shipgit: push 完了", vim.log.levels.INFO)
      end
      refresh(state)
    end)
  end)

  -- Pull
  map(buf, keys.pull, function()
    vim.notify("shipgit: pulling...", vim.log.levels.INFO)
    git.pull_async(function(out, code)
      if code ~= 0 then
        vim.notify("shipgit: pull 失敗\n" .. (out or ""), vim.log.levels.ERROR)
      else
        vim.notify("shipgit: pull 完了", vim.log.levels.INFO)
      end
      refresh(state)
    end)
  end)

  -- Discard / Abort
  map(buf, keys.discard, function()
    -- merge/rebase 中なら abort を提示
    if git.is_merging() then
      vim.ui.select({ "Abort merge", "Cancel" }, {
        prompt = "Merge in progress",
      }, function(choice)
        if choice == "Abort merge" then
          git.merge_abort()
          vim.notify("shipgit: merge を中断しました", vim.log.levels.INFO)
          refresh(state)
          ui.focus_filelist()
        end
      end)
      return
    end

    if git.is_rebasing() then
      vim.ui.select({ "Abort rebase", "Cancel" }, {
        prompt = "Rebase in progress",
      }, function(choice)
        if choice == "Abort rebase" then
          git.rebase_abort()
          vim.notify("shipgit: rebase を中断しました", vim.log.levels.INFO)
          refresh(state)
          ui.focus_filelist()
        end
      end)
      return
    end

    if git.is_cherry_picking() then
      vim.ui.select({ "Abort cherry-pick", "Cancel" }, {
        prompt = "Cherry-pick in progress",
      }, function(choice)
        if choice == "Abort cherry-pick" then
          git.cherry_pick_abort()
          vim.notify("shipgit: cherry-pick を中断しました", vim.log.levels.INFO)
          refresh(state)
          ui.focus_filelist()
        end
      end)
      return
    end

    local entry = filelist.get_selected(state)
    if not entry then
      return
    end
    if entry.dir then
      -- ディレクトリ: 配下の全変更を破棄
      vim.ui.select({ "Yes", "No" }, {
        prompt = "Discard all changes in " .. entry.dir .. "/?",
      }, function(choice)
        if choice == "Yes" then
          git.discard_dir(entry.dir, state.files.unstaged)
          refresh(state)
          ui.focus_filelist()
        end
      end)
    elseif entry.file then
      vim.ui.select({ "Yes", "No" }, {
        prompt = "Discard changes to " .. entry.file.path .. "?",
      }, function(choice)
        if choice == "Yes" then
          git.discard(entry.file.path)
          refresh(state)
          ui.focus_filelist()
        end
      end)
    end
  end)

  -- ファイルを開く
  map(buf, keys.open_file, function()
    local entry = filelist.get_selected(state)
    if not entry then
      return
    end
    local filepath = git.cwd .. "/" .. entry.file.path
    ui.close()
    vim.schedule(function()
      vim.cmd("edit " .. vim.fn.fnameescape(filepath))
    end)
  end)

  -- プロジェクト切り替え
  map(buf, "<C-p>", function()
    local projects = require("shipgit.projects")
    projects.open(function(path)
      ui.close()
      vim.schedule(function()
        vim.cmd("cd " .. vim.fn.fnameescape(path))
        require("shipgit").open(path)
      end)
    end)
  end)

  -- ブランチ切り替え
  map(buf, keys.branches, function()
    local branches = require("shipgit.branches")
    branches.open(function()
      refresh(state)
      ui.focus_filelist()
    end)
  end)

  -- ブランチツリー
  map(buf, keys.tree, function()
    local tree = require("shipgit.tree")
    tree.open()
  end)

  -- Stash
  map(buf, keys.stash, function()
    ui._suspend_close = true
    local stash = require("shipgit.stash")
    stash.open(function()
      ui._suspend_close = false
      refresh(state)
      ui.focus_filelist()
    end, function()
      ui._suspend_close = false
      ui.focus_filelist()
    end)
  end)

  -- Commit log
  map(buf, keys.log, function()
    ui._suspend_close = true
    local log = require("shipgit.log")
    log.open(function()
      ui._suspend_close = false
      ui.focus_filelist()
    end)
  end)

  -- パネル切り替え
  map(buf, keys.focus_next, function()
    state.active_panel = "diff"
    ui.focus_diff()
  end)

  -- C-h / C-l でパネル移動
  map(buf, "<C-l>", function()
    state.active_panel = "diff"
    ui.focus_diff_left()
  end)

  -- 閉じる
  map(buf, keys.quit, function()
    ui.close()
  end)

  -- ヘルプ
  map(buf, keys.help, function()
    M.show_help()
  end)
end

function M.attach_diff(state)
  local keys = config.values.keymaps

  -- diff パネルではファイル全体をstage/unstage
  local function file_stage_action()
    local entry = filelist.get_selected(state)
    if not entry or not entry.file then return end
    if entry.section == "unstaged" then
      git.stage(entry.file.path)
    else
      git.unstage(entry.file.path)
    end
    refresh(state)
  end

  -- diff_left (old, 読み取り専用)
  local buf_left = ui.bufs.diff_left
  map(buf_left, keys.stage_toggle, file_stage_action)
  map(buf_left, keys.focus_next, function()
    state.active_panel = "filelist"
    ui.focus_filelist()
  end)
  map(buf_left, "<C-h>", function()
    state.active_panel = "filelist"
    ui.focus_filelist()
  end)
  map(buf_left, "<C-l>", function()
    state.active_panel = "diff"
    ui.focus_diff_right()
  end)
  map(buf_left, keys.quit, function()
    ui.close()
  end)
  map(buf_left, keys.help, function()
    M.show_help()
  end)

  -- diff_right (new, 編集可能)
  local buf_right = ui.bufs.diff_right
  map(buf_right, keys.stage_toggle, file_stage_action)
  map(buf_right, keys.focus_next, function()
    state.active_panel = "filelist"
    ui.focus_filelist()
  end)
  map(buf_right, "<C-h>", function()
    state.active_panel = "diff"
    ui.focus_diff_left()
  end)
  map(buf_right, keys.quit, function()
    ui.close()
  end)
  map(buf_right, keys.help, function()
    M.show_help()
  end)

  -- :w で右パネルの編集内容をワーキングツリーに保存
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf_right,
    callback = function()
      diff.save_right(state)
      vim.bo[buf_right].modified = false
      vim.schedule(function()
        refresh(state)
      end)
    end,
  })
end

function M.show_help()
  local keys = config.values.keymaps
  local lines = {
    " shipgit keybindings",
    "",
    " " .. keys.next_file .. " / " .. keys.prev_file .. "  ファイル移動",
    " " .. keys.stage_toggle .. "       stage/unstage (diffでハンク単位)",
    " " .. keys.stage_all .. "       全 stage/unstage",
    " " .. keys.commit .. "       コミット",
    " " .. keys.push .. "       push",
    " " .. keys.pull .. "       pull",
    " " .. keys.discard .. "       変更破棄",
    " " .. keys.open_file .. "       ファイルを開く",
    " " .. keys.branches .. "       ブランチ切り替え",
    " " .. keys.tree .. "       ブランチツリー",
    " " .. keys.stash .. "       stash",
    " " .. keys.log .. "       コミットログ",
    " C-p        プロジェクト切り替え",
    " " .. keys.focus_next .. "     パネル切り替え",
    " C-h / C-l  左右パネル移動",
    " :w         右パネル保存 (編集後)",
    " " .. keys.quit .. "       閉じる",
    "",
    " Press any key to close",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = 40
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    zindex = 70,
    title = " Help ",
    title_pos = "center",
  })

  -- ハイライト
  local ns = vim.api.nvim_create_namespace("shipgit_help")
  vim.api.nvim_buf_add_highlight(buf, ns, "ShipgitTitle", 0, 0, -1)
  for i = 2, #lines - 2 do
    vim.api.nvim_buf_add_highlight(buf, ns, "ShipgitHelpDesc", i, 0, -1)
  end

  -- 任意のキーで閉じる
  vim.keymap.set("n", "<Esc>", function()
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, nowait = true })

  -- 任意キー入力で閉じる
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      pcall(vim.api.nvim_win_close, win, true)
    end,
  })

  -- 任意キーで閉じる（全キー）
  for _, key in ipairs(vim.split("abcdefghijklmnopqrstuvwxyz0123456789 ", "")) do
    vim.keymap.set("n", key, function()
      pcall(vim.api.nvim_win_close, win, true)
    end, { buffer = buf, nowait = true })
  end
end

return M
