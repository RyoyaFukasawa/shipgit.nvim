local git = require("shipgit.git")

local M = {}

M._win = nil
M._buf = nil
M._stashes = {}

function M.is_open()
  return M._win ~= nil and vim.api.nvim_win_is_valid(M._win)
end

--- stash ウィンドウを開く
--- @param on_done fun() 操作後のコールバック
function M.open(on_done)
  if M.is_open() then
    return
  end

  M._stashes = git.stash_list()
  M._on_done = on_done
  M._create_window()
  M._render()
  M._setup_keymaps()
end

function M._create_window()
  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].bufhidden = "wipe"

  local width = 60
  local height = math.min(20, vim.o.lines - 4)

  M._win = vim.api.nvim_open_win(M._buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    zindex = 60,
    title = " Stash ",
    title_pos = "center",
  })

  vim.wo[M._win].cursorline = true
end

function M._render()
  local stashes = M._stashes
  local lines = {}

  if #stashes == 0 then
    table.insert(lines, "  (no stashes)")
  else
    for _, s in ipairs(stashes) do
      table.insert(lines, "  " .. s.name .. "  " .. s.message)
    end
  end

  table.insert(lines, "")
  table.insert(lines, " Space:pop  a:apply  d:drop  n:new stash  q:close")

  vim.bo[M._buf].modifiable = true
  vim.api.nvim_buf_set_lines(M._buf, 0, -1, false, lines)
  vim.bo[M._buf].modifiable = false

  -- ハイライト
  local ns = vim.api.nvim_create_namespace("shipgit_stash")
  vim.api.nvim_buf_clear_namespace(M._buf, ns, 0, -1)
  for i, s in ipairs(stashes) do
    -- stash 名をハイライト
    local name_end = #s.name + 2
    vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitHelpKey", i - 1, 2, name_end)
    -- メッセージ
    vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitGraphMessage", i - 1, name_end, -1)
  end
  -- フッター
  vim.api.nvim_buf_add_highlight(M._buf, ns, "ShipgitHelpDesc", #lines - 1, 0, -1)
end

function M.close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    pcall(vim.api.nvim_win_close, M._win, true)
  end
  M._win = nil
  M._buf = nil
  M._stashes = {}
end

local function get_selected(self)
  if not self._win or not vim.api.nvim_win_is_valid(self._win) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(self._win)
  local idx = cursor[1]
  if idx > #self._stashes then
    return nil
  end
  return self._stashes[idx]
end

function M._refresh()
  M._stashes = git.stash_list()
  M._render()
  if M._on_done then
    M._on_done()
  end
end

function M._setup_keymaps()
  local buf = M._buf
  local on_done = M._on_done

  local function kmap(key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
  end

  -- Space: pop
  kmap("<Space>", function()
    local s = get_selected(M)
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

  -- a: apply (削除せずに適用)
  kmap("a", function()
    local s = get_selected(M)
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
  kmap("d", function()
    local s = get_selected(M)
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
  kmap("n", function()
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

  -- q / Esc
  for _, key in ipairs({ "q", "<Esc>" }) do
    kmap(key, function()
      M.close()
    end)
  end
end

return M
