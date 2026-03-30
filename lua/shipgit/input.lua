local M = {}

M._win = nil
M._buf = nil

function M.is_open()
  return M._win ~= nil and vim.api.nvim_win_is_valid(M._win)
end

--- コミットメッセージ入力ウィンドウを開く
--- @param on_confirm fun(msg: string|nil) 確定時のコールバック
function M.open(on_confirm)
  if M.is_open() then
    return
  end

  local width = 60
  local height = 1

  M._buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M._buf].buftype = "prompt"
  vim.bo[M._buf].bufhidden = "wipe"

  M._win = vim.api.nvim_open_win(M._buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    zindex = 60,
    title = " Commit Message ",
    title_pos = "center",
  })

  -- プロンプト設定
  vim.fn.prompt_setprompt(M._buf, "> ")
  vim.fn.prompt_setcallback(M._buf, function(text)
    M.close()
    if on_confirm then
      vim.schedule(function()
        on_confirm(text)
      end)
    end
  end)

  -- Esc でキャンセル
  vim.keymap.set("n", "<Esc>", function()
    M.close()
    if on_confirm then
      vim.schedule(function()
        on_confirm(nil)
      end)
    end
  end, { buffer = M._buf, nowait = true })

  -- q でもキャンセル（ノーマルモード）
  vim.keymap.set("n", "q", function()
    M.close()
    if on_confirm then
      vim.schedule(function()
        on_confirm(nil)
      end)
    end
  end, { buffer = M._buf, nowait = true })

  -- インサートモードで開始
  vim.cmd("startinsert")
end

function M.close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    pcall(vim.api.nvim_win_close, M._win, true)
  end
  M._win = nil
  M._buf = nil
end

return M
