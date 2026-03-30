local M = {}

function M.setup()
  local cfg = require("shipgit.config").values
  local hl = cfg.highlights or {}

  -- ハイライトグループ名とconfigキーのマッピング
  local groups = {
    ShipgitStagedHeader = "staged_header",
    ShipgitUnstagedHeader = "unstaged_header",
    ShipgitStagedFile = "staged_file",
    ShipgitUnstagedFile = "unstaged_file",
    ShipgitUntrackedFile = "untracked_file",
    ShipgitDirName = "dir_name",
    ShipgitStatusAdd = "status_add",
    ShipgitStatusMod = "status_mod",
    ShipgitStatusDel = "status_del",
    ShipgitConflictHeader = "conflict_header",
    ShipgitConflictFile = "conflict_file",
    ShipgitBorder = "border",
    ShipgitTitle = "title",
    ShipgitSeparator = "separator",
    ShipgitCursorLine = "cursor_line",
    ShipgitHelpKey = "help_key",
    ShipgitHelpDesc = "help_desc",
    ShipgitDiffAdd = "diff_add",
    ShipgitDiffChange = "diff_change",
    ShipgitDiffDelete = "diff_delete",
    ShipgitDiffText = "diff_text",
    ShipgitGraphCommit = "graph_commit",
    ShipgitGraphHash = "graph_hash",
    ShipgitGraphHead = "graph_head",
    ShipgitGraphRemote = "graph_remote",
    ShipgitGraphTag = "graph_tag",
    ShipgitGraphBranch = "graph_branch",
    ShipgitGraphMessage = "graph_message",
  }

  for group_name, config_key in pairs(groups) do
    local val = hl[config_key]
    if val then
      vim.api.nvim_set_hl(0, group_name, val)
    end
  end

  -- グラフ線の色（列ごとにローテーション）
  local graph_colors = hl.graph_colors or {}
  for i, color in ipairs(graph_colors) do
    vim.api.nvim_set_hl(0, "ShipgitGraphLine" .. i, { fg = color })
  end
end

return M
