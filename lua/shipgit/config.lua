local M = {}

M.defaults = {
  width = 0.85,
  height = 0.85,
  border = "rounded",
  filelist_width = 0.25,
  keymaps = {
    quit = "q",
    stage_toggle = "<Space>",
    stage_all = "a",
    commit = "c",
    push = "P",
    pull = "p",
    discard = "d",
    focus_next = "<Tab>",
    help = "?",
    next_file = "j",
    prev_file = "k",
    branches = "b",
    open_file = "o",
    tree = "t",
    stash = "s",
    log = "g",
  },
  highlights = {
    -- ファイル一覧
    staged_header = { fg = "#A0E860", bold = true },
    unstaged_header = { fg = "#FF9E58", bold = true },
    staged_file = { fg = "#A0E860" },
    unstaged_file = { fg = "#FF9E58" },
    untracked_file = { fg = "#78DCF0" },
    dir_name = { fg = "#D09CDF", bold = true },
    status_add = { fg = "#A0E860" },
    status_mod = { fg = "#FFD24A" },
    status_del = { fg = "#FF5080" },
    conflict_header = { fg = "#FF5080", bold = true },
    conflict_file = { fg = "#FF5080" },

    -- UI
    border = { fg = "#505870" },
    title = { fg = "#78DCF0", bold = true },
    separator = { fg = "#505870" },
    cursor_line = { bg = "#2a2e3f" },
    help_key = { fg = "#FFD24A" },
    help_desc = { fg = "#505870" },

    -- diff
    diff_add = { bg = "#1a3a1a" },
    diff_change = { bg = "#1a2a4a" },
    diff_delete = { bg = "#3a1a1a", fg = "#804040" },
    diff_text = { bg = "#2a4a6a" },

    -- ブランチツリー
    graph_commit = { fg = "#FFD24A", bold = true },
    graph_hash = { fg = "#56C5B8" },
    graph_head = { fg = "#A0E860", bold = true },
    graph_remote = { fg = "#FF5080" },
    graph_tag = { fg = "#FF9E58" },
    graph_branch = { fg = "#D09CDF" },
    graph_message = { fg = "#dadbc0" },
    graph_colors = {
      "#78DCF0",
      "#A0E860",
      "#FF5080",
      "#D09CDF",
      "#FF9E58",
      "#FFD24A",
      "#56C5B8",
      "#E06880",
    },
  },
}

M.values = vim.deepcopy(M.defaults)

function M.merge(opts)
  M.values = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
