local M = {}

M._state = nil
M._augroup = nil

function M.setup(opts)
  local config = require("shipgit.config")
  config.merge(opts or {})
  require("shipgit.highlights").setup()
end

function M.open(cwd)
  -- 既に開いていたら閉じる
  if M._state then
    M.close()
  end

  local git = require("shipgit.git")
  git.init(cwd)

  if not git.is_repo() then
    vim.notify("shipgit: git リポジトリではありません", vim.log.levels.ERROR)
    return
  end

  -- プロジェクト履歴に記録
  local projects = require("shipgit.projects")
  projects.record(git.cwd)

  local branch = git.branch()
  local files = git.status()

  local state = {
    files = files,
    cursor = 1,
    active_panel = "filelist",
    branch = branch,
    flat_files = {},
  }
  M._state = state

  local ui = require("shipgit.ui")
  ui.open(state)

  local filelist = require("shipgit.filelist")
  filelist.render(state)

  local diff = require("shipgit.diff")
  diff.show_file(state)

  local keymaps = require("shipgit.keymaps")
  keymaps.attach(state)

  ui.focus_filelist()

  -- フォーカス復帰時に自動更新
  M._augroup = vim.api.nvim_create_augroup("ShipgitAutoRefresh", { clear = true })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = M._augroup,
    callback = function()
      if M._state then
        local s = M._state
        s.files = git.status()
        local total = #(s.flat_files or {})
        if total == 0 then
          s.cursor = 1
        end
        filelist.render(s)
        diff.show_file(s)
        -- タイトル更新
        if ui.wins.frame and vim.api.nvim_win_is_valid(ui.wins.frame) then
          local b = git.branch()
          local status_label = ""
          if git.is_merging() then
            status_label = " [MERGING]"
          elseif git.is_rebasing() then
            status_label = " [REBASING]"
          elseif git.is_cherry_picking() then
            status_label = " [CHERRY-PICKING]"
          end
          vim.api.nvim_win_set_config(ui.wins.frame, {
            title = " shipgit - " .. b .. status_label .. " ",
            title_pos = "center",
          })
        end
      end
    end,
  })
end

function M.close()
  if M._state then
    local filelist = require("shipgit.filelist")
    filelist.save_collapsed(M._state)
  end
  if M._augroup then
    vim.api.nvim_del_augroup_by_id(M._augroup)
    M._augroup = nil
  end
  local ui = require("shipgit.ui")
  ui.close()
  M._state = nil
end

function M.toggle()
  if M._state then
    M.close()
  else
    M.open()
  end
end

return M
