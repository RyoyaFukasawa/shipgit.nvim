local M = {}

M._state = nil

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
end

function M.close()
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
