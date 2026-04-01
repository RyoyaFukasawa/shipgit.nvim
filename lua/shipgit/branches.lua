local git = require("shipgit.git")

local M = {}

M._win = nil
M._buf = nil
M._branches = {}
M._tab = "local" -- "local" | "remote"
M._on_done = nil

function M.is_open()
  return M._win ~= nil and vim.api.nvim_win_is_valid(M._win)
end

local function get_selected(self)
  if not self._win or not vim.api.nvim_win_is_valid(self._win) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(self._win)
  local idx = cursor[1]
  if idx > #self._branches then
    return nil
  end
  return self._branches[idx]
end

--- ブランチ選択ウィンドウを開く
function M.open(on_done)
  if M.is_open() then
    return
  end
  M._on_done = on_done
  M._tab = "local"
  M._load_branches()
  M._create_window()
  M._render()
  M._setup_keymaps()
end

function M._load_branches()
  if M._tab == "local" then
    M._branches = git.branches()
  else
    M._branches = git.remote_branches()
  end
end

function M._create_window()
  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].bufhidden = "wipe"

  local width = 60
  local height = math.min(30, vim.o.lines - 4)

  M._win = vim.api.nvim_open_win(M._buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    zindex = 60,
    title = M._get_title(),
    title_pos = "center",
  })

  vim.wo[M._win].cursorline = true
end

function M._get_title()
  if M._tab == "local" then
    return " [Local] ] → Remote "
  else
    return " [ ← Local [Remote] "
  end
end

function M._render()
  local branches = M._branches
  local lines = {}
  local current_line = 1

  if M._tab == "local" then
    for i, b in ipairs(branches) do
      local prefix = b.current and "* " or "  "
      local status = ""
      if b.ahead and b.ahead > 0 and b.behind and b.behind > 0 then
        status = " ↑" .. b.ahead .. " ↓" .. b.behind
      elseif b.ahead and b.ahead > 0 then
        status = " ↑" .. b.ahead
      elseif b.behind and b.behind > 0 then
        status = " ↓" .. b.behind
      end
      table.insert(lines, prefix .. b.name .. status)
      if b.current then
        current_line = i
      end
    end
    table.insert(lines, "")
    table.insert(lines, " Space:checkout  M:merge  r:rebase  c:cherry-pick")
    table.insert(lines, " p:pull  P:push  n:new  d:delete  f:fetch")
    table.insert(lines, " ]/[:tab  q:close")
  else
    for _, b in ipairs(branches) do
      table.insert(lines, "  " .. b.name)
    end
    table.insert(lines, "")
    table.insert(lines, " Space:checkout to local  d:delete remote  f:fetch")
    table.insert(lines, " ]/[:tab  q:close")
  end

  vim.bo[M._buf].modifiable = true
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.bo[M._buf].modifiable = false

  -- タイトル更新
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_set_config(M._win, {
      title = M._get_title(),
      title_pos = "center",
    })
  end

  -- ハイライト
  local ns = vim.api.nvim_create_namespace("shipgit_branches")
  vim.api.nvim_buf_clear_namespace(M._buf, ns, 0, -1)

  if M._tab == "local" then
    for i, b in ipairs(branches) do
      local line_text = lines[i]
      if b.current then
        vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitStagedFile", i - 1, 0, -1)
      end
      local arrow_up = line_text:find("↑")
      if arrow_up then
        vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitStagedFile", i - 1, arrow_up - 1, -1)
      end
      local arrow_down = line_text:find("↓")
      if arrow_down then
        vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitUnstagedFile", i - 1, arrow_down - 1, -1)
      end
    end
  else
    for i, b in ipairs(branches) do
      -- リモート名部分をハイライト
      local slash = b.name:find("/")
      if slash then
        vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitHelpKey", i - 1, 2, 2 + slash)
      end
    end
  end

  -- フッター
  for i = #lines - 1, #lines do
    vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitHelpDesc", i - 1, 0, -1)
  end

  pcall(vim.api.nvim_win_set_cursor, M._win, { math.min(current_line, #branches), 0 })
end

function M._switch_tab()
  M._tab = M._tab == "local" and "remote" or "local"
  M._load_branches()
  M._render()
  -- keymaps はバッファに紐づいているのでそのまま
end

function M.close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    pcall(vim.api.nvim_win_close, M._win, true)
  end
  M._win = nil
  M._buf = nil
  M._branches = {}
end

function M._setup_keymaps()
  local buf = M._buf
  local on_done = M._on_done

  local function kmap(key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
  end

  -- ] / [: タブ切り替え
  kmap("]", function() M._switch_tab() end)
  kmap("[", function() M._switch_tab() end)

  -- f: fetch
  kmap("f", function()
    vim.notify("shipgit: fetching...", vim.log.levels.INFO)
    git.fetch_async(function(out, code)
      if code ~= 0 then
        vim.notify("shipgit: fetch 失敗\n" .. (out or ""), vim.log.levels.ERROR)
      else
        vim.notify("shipgit: fetch 完了", vim.log.levels.INFO)
      end
      M._load_branches()
      M._render()
    end)
  end)

  -- Enter: checkout
  kmap("<Space>", function()
    local b = get_selected(M)
    if not b then
      return
    end

    if M._tab == "local" then
      if b.current then
        return
      end
      M.close()
      vim.schedule(function()
        local out, code = git.checkout(b.name)
        if code ~= 0 then
          vim.notify("shipgit: checkout 失敗\n" .. (out or ""), vim.log.levels.ERROR)
        else
          vim.notify("shipgit: " .. b.name .. " に切り替え", vim.log.levels.INFO)
        end
        if on_done then on_done() end
      end)
    else
      -- リモートブランチをローカルにチェックアウト
      local local_name = b.short_name
      M.close()
      vim.schedule(function()
        vim.ui.input({ prompt = "Local branch name: ", default = local_name }, function(name)
          if not name or name == "" then
            return
          end
          local out, code = git.checkout_remote(b.name, name)
          if code ~= 0 then
            vim.notify("shipgit: checkout 失敗\n" .. (out or ""), vim.log.levels.ERROR)
          else
            vim.notify("shipgit: " .. name .. " を作成してcheckout", vim.log.levels.INFO)
          end
          if on_done then on_done() end
        end)
      end)
    end
  end)

  -- M: merge (local only)
  kmap("M", function()
    local b = get_selected(M)
    if not b then return end
    local branch_name = M._tab == "local" and b.name or b.name
    if M._tab == "local" and b.current then
      vim.notify("shipgit: 現在のブランチはmergeできません", vim.log.levels.WARN)
      return
    end
    local current = git.branch()
    M.close()
    vim.schedule(function()
      vim.ui.select({ "Yes", "No" }, {
        prompt = branch_name .. " → " .. current .. " にmergeしますか？",
      }, function(choice)
        if choice == "Yes" then
          vim.notify("shipgit: merging " .. branch_name .. " → " .. current .. "...", vim.log.levels.INFO)
          git.merge_async(branch_name, function(out, code)
            if code ~= 0 and git.is_merging() then
              vim.notify("shipgit: merge コンフリクトが発生しました。ファイルを編集して解消してください", vim.log.levels.WARN)
            elseif code ~= 0 then
              vim.notify("shipgit: merge 失敗\n" .. (out or ""), vim.log.levels.ERROR)
            else
              vim.notify("shipgit: " .. branch_name .. " を " .. current .. " にmergeしました", vim.log.levels.INFO)
            end
            if on_done then on_done() end
          end)
        end
      end)
    end)
  end)

  -- r: rebase (local only)
  kmap("r", function()
    if M._tab ~= "local" then return end
    local b = get_selected(M)
    if not b then return end
    if b.current then
      vim.notify("shipgit: 現在のブランチにはrebaseできません", vim.log.levels.WARN)
      return
    end
    M.close()
    vim.schedule(function()
      vim.ui.select({ "Yes", "No" }, {
        prompt = "Rebase onto " .. b.name .. "?",
      }, function(choice)
        if choice == "Yes" then
          vim.notify("shipgit: rebasing onto " .. b.name .. "...", vim.log.levels.INFO)
          git.rebase_async(b.name, function(out, code)
            if code ~= 0 then
              vim.notify("shipgit: rebase 失敗\n" .. (out or ""), vim.log.levels.ERROR)
            else
              vim.notify("shipgit: " .. b.name .. " にrebaseしました", vim.log.levels.INFO)
            end
            if on_done then on_done() end
          end)
        end
      end)
    end)
  end)

  -- c: cherry-pick（選択ブランチのログを表示）
  kmap("c", function()
    local b = get_selected(M)
    if not b then return end
    local branch_name = b.name
    M.close()
    vim.schedule(function()
      local log = require("shipgit.log")
      log.open(function()
        if on_done then on_done() end
      end, branch_name)
    end)
  end)

  -- p: pull
  kmap("p", function()
    M.close()
    vim.notify("shipgit: pulling...", vim.log.levels.INFO)
    git.pull_async(function(out, code)
      if code ~= 0 then
        vim.notify("shipgit: pull 失敗\n" .. (out or ""), vim.log.levels.ERROR)
      else
        vim.notify("shipgit: pull 完了", vim.log.levels.INFO)
      end
      if on_done then on_done() end
    end)
  end)

  -- P: push
  kmap("P", function()
    M.close()
    vim.notify("shipgit: pushing...", vim.log.levels.INFO)
    git.push_async(function(out, code)
      if code ~= 0 then
        vim.notify("shipgit: push 失敗\n" .. (out or ""), vim.log.levels.ERROR)
      else
        vim.notify("shipgit: push 完了", vim.log.levels.INFO)
      end
      if on_done then on_done() end
    end)
  end)

  -- d: delete
  kmap("d", function()
    local b = get_selected(M)
    if not b then return end

    if M._tab == "local" then
      if b.current then
        vim.notify("shipgit: 現在のブランチは削除できません", vim.log.levels.WARN)
        return
      end
      vim.ui.select({ "Yes", "No" }, {
        prompt = "Delete local branch " .. b.name .. "?",
      }, function(choice)
        if choice == "Yes" then
          local out, code = git.delete_branch(b.name)
          if code ~= 0 then
            vim.notify("shipgit: 削除失敗\n" .. (out or ""), vim.log.levels.ERROR)
          else
            vim.notify("shipgit: " .. b.name .. " を削除", vim.log.levels.INFO)
          end
          vim.schedule(function()
            M._load_branches()
            M._render()
            if on_done then on_done() end
          end)
        end
      end)
    else
      vim.ui.select({ "Yes", "No" }, {
        prompt = "Delete remote branch " .. b.name .. "? (git push --delete)",
      }, function(choice)
        if choice == "Yes" then
          local out, code = git.delete_remote_branch(b.remote, b.short_name)
          if code ~= 0 then
            vim.notify("shipgit: 削除失敗\n" .. (out or ""), vim.log.levels.ERROR)
          else
            vim.notify("shipgit: " .. b.name .. " を削除", vim.log.levels.INFO)
          end
          vim.schedule(function()
            M._load_branches()
            M._render()
            if on_done then on_done() end
          end)
        end
      end)
    end
  end)

  -- n: new branch (local only)
  kmap("n", function()
    M.close()
    vim.schedule(function()
      vim.ui.input({ prompt = "New branch name: " }, function(name)
        if name and name ~= "" then
          local out, code = git.create_branch(name)
          if code ~= 0 then
            vim.notify("shipgit: ブランチ作成失敗\n" .. (out or ""), vim.log.levels.ERROR)
          else
            vim.notify("shipgit: " .. name .. " を作成", vim.log.levels.INFO)
          end
          if on_done then on_done() end
        end
      end)
    end)
  end)

  -- q / Esc: 閉じる
  for _, key in ipairs({ "q", "<Esc>" }) do
    kmap(key, function()
      M.close()
    end)
  end
end

return M
