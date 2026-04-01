local M = {}

M.cwd = nil

function M.init(cwd)
  if cwd then
    M.cwd = cwd
  else
    -- 現在のバッファのファイルパスから git リポジトリルートを探す
    local buf_path = vim.api.nvim_buf_get_name(0)
    local dir = buf_path ~= "" and vim.fn.fnamemodify(buf_path, ":h") or vim.fn.getcwd()
    local out = vim.fn.system("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel")
    if vim.v.shell_error == 0 then
      M.cwd = vim.trim(out)
    else
      M.cwd = vim.fn.getcwd()
    end
  end
end

local function exec(cmd)
  local result = vim.fn.system(cmd)
  local code = vim.v.shell_error
  return result, code
end

local function git(args)
  return exec("git -C " .. vim.fn.shellescape(M.cwd) .. " " .. args)
end

--- 非同期で git コマンドを実行
--- @param args string
--- @param callback fun(out: string, code: number)
local function git_async(args, callback)
  local cmd = { "git", "-C", M.cwd }
  for word in args:gmatch("%S+") do
    table.insert(cmd, word)
  end
  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      local out = (obj.stdout or "") .. (obj.stderr or "")
      callback(out, obj.code)
    end)
  end)
end

function M.is_repo()
  local _, code = git("rev-parse --git-dir")
  return code == 0
end

function M.branch()
  local out, code = git("branch --show-current")
  if code ~= 0 then
    return "HEAD"
  end
  return vim.trim(out)
end

-- conflict を示す XY の組み合わせ
local CONFLICT_CODES = {
  ["DD"] = true, ["AU"] = true, ["UD"] = true,
  ["UA"] = true, ["DU"] = true, ["AA"] = true, ["UU"] = true,
}

--- git status --porcelain=v1 をパースして staged/unstaged/conflict に分類
--- @return { staged: FileInfo[], unstaged: FileInfo[], conflict: FileInfo[] }
--- FileInfo = { path: string, status: string, original_path: string|nil }
function M.status()
  local out, code = git("status --porcelain=v1")
  if code ~= 0 then
    return { staged = {}, unstaged = {}, conflict = {} }
  end

  local staged = {}
  local unstaged = {}
  local conflict = {}

  for line in out:gmatch("[^\n]+") do
    if #line >= 4 then
      local x = line:sub(1, 1) -- index status
      local y = line:sub(2, 2) -- worktree status
      local xy = x .. y
      local path_part = line:sub(4)

      -- リネーム: "old -> new"
      local original_path, filepath
      local arrow = path_part:find(" -> ")
      if arrow then
        original_path = path_part:sub(1, arrow - 1)
        filepath = path_part:sub(arrow + 4)
      else
        filepath = path_part
      end

      -- conflict
      if CONFLICT_CODES[xy] then
        table.insert(conflict, {
          path = filepath,
          status = xy,
          original_path = original_path,
        })
      else
        -- staged (index に変更あり)
        if x ~= " " and x ~= "?" then
          table.insert(staged, {
            path = filepath,
            status = x,
            original_path = original_path,
          })
        end

        -- unstaged (worktree に変更あり)
        if y ~= " " then
          local st = y
          if x == "?" then
            st = "?"
          end

          -- untracked ディレクトリの場合は中のファイルを列挙
          if st == "?" and filepath:sub(-1) == "/" then
            local dir_path = filepath:sub(1, -2)
            local files_out = vim.fn.globpath(M.cwd .. "/" .. dir_path, "**/*", false, true)
            for _, fullpath in ipairs(files_out) do
              if vim.fn.isdirectory(fullpath) == 0 then
                local rel = fullpath:sub(#M.cwd + 2)
                table.insert(unstaged, {
                  path = rel,
                  status = "?",
                })
              end
            end
          else
            table.insert(unstaged, {
              path = filepath,
              status = st,
              original_path = original_path,
            })
          end
        end
      end
    end
  end

  return { staged = staged, unstaged = unstaged, conflict = conflict }
end

--- merge/rebase 中かどうか
function M.is_merging()
  local _, code = git("rev-parse --verify MERGE_HEAD")
  return code == 0
end

function M.is_rebasing()
  local out = git("rev-parse --git-dir")
  local git_dir = vim.trim(out)
  return vim.fn.isdirectory(git_dir .. "/rebase-merge") == 1
    or vim.fn.isdirectory(git_dir .. "/rebase-apply") == 1
end

function M.merge_abort()
  return git("merge --abort")
end

function M.rebase_abort()
  return git("rebase --abort")
end

function M.is_cherry_picking()
  local _, code = git("rev-parse --verify CHERRY_PICK_HEAD")
  return code == 0
end

function M.cherry_pick_abort()
  return git("cherry-pick --abort")
end

function M.show_cherry_pick_msg()
  local out, code = git("log -1 --format=%s CHERRY_PICK_HEAD")
  if code ~= 0 or not out or out == "" then
    return nil
  end
  return vim.trim(out)
end

function M.rebase_continue()
  return git("rebase --continue")
end

--- conflict ファイルを resolved としてマーク
function M.mark_resolved(filepath)
  return git("add -- " .. vim.fn.shellescape(filepath))
end

--- stash 一覧を返す
--- @return { index: number, name: string, message: string }[]
function M.stash_list()
  local out, code = git("stash list --format='%gd|%s'")
  if code ~= 0 or not out or out == "" then
    return {}
  end
  local stashes = {}
  for line in out:gmatch("[^\n]+") do
    line = line:gsub("^'", ""):gsub("'$", "")
    local name, message = line:match("^(.+)|(.*)$")
    if name then
      table.insert(stashes, {
        index = #stashes,
        name = name,
        message = message or "",
      })
    end
  end
  return stashes
end

function M.stash_push(message)
  if message and message ~= "" then
    return git("stash push -m " .. vim.fn.shellescape(message))
  end
  return git("stash push")
end

function M.stash_pop(index)
  return git("stash pop stash@{" .. (index or 0) .. "}")
end

function M.stash_apply(index)
  return git("stash apply stash@{" .. (index or 0) .. "}")
end

function M.stash_drop(index)
  return git("stash drop stash@{" .. (index or 0) .. "}")
end

--- stash の変更ファイル一覧を返す
--- @param index number
--- @return { status: string, path: string }[]
function M.stash_files(index)
  local out, code = git("stash show --name-status stash@{" .. (index or 0) .. "}")
  if code ~= 0 or not out or out == "" then
    return {}
  end
  local files = {}
  for line in out:gmatch("[^\n]+") do
    local status, path = line:match("^(%a)%s+(.+)$")
    if status and path then
      table.insert(files, { status = status, path = path })
    end
  end
  return files
end

--- stash 内のファイル内容を返す
--- @param index number
--- @param filepath string
--- @return string|nil
function M.stash_show_file(index, filepath)
  local out, code = git("show stash@{" .. (index or 0) .. "}:" .. vim.fn.shellescape(filepath))
  if code ~= 0 then
    return nil
  end
  return out
end

--- stash の親コミットのファイル内容を返す
--- @param index number
--- @param filepath string
--- @return string|nil
function M.stash_show_parent_file(index, filepath)
  local out, code = git("show stash@{" .. (index or 0) .. "}^:" .. vim.fn.shellescape(filepath))
  if code ~= 0 then
    return nil
  end
  return out
end

--- コミットログを返す
--- @param count number|nil 取得件数（デフォルト50）
--- @return { hash: string, short_hash: string, subject: string, author: string, date: string }[]
function M.log(count, skip, branch)
  count = count or 50
  skip = skip or 0
  local skip_arg = skip > 0 and (" --skip=" .. skip) or ""
  local branch_arg = branch and (" " .. branch) or ""
  local out, code = git("log --format='%H|%h|%s|%an|%cr' -" .. count .. skip_arg .. branch_arg)
  if code ~= 0 or not out or out == "" then
    return {}
  end
  local commits = {}
  for line in out:gmatch("[^\n]+") do
    line = line:gsub("^'", ""):gsub("'$", "")
    local hash, short_hash, subject, author, date = line:match("^([^|]+)|([^|]+)|(.+)|([^|]+)|([^|]+)$")
    if hash then
      table.insert(commits, {
        hash = hash,
        short_hash = short_hash,
        subject = subject,
        author = author,
        date = date,
      })
    end
  end
  return commits
end

--- 特定コミットの変更ファイル一覧
--- @param hash string
--- @return { path: string, status: string }[]
function M.commit_files(hash)
  local out, code = git("diff-tree --root --no-commit-id -r --name-status " .. vim.fn.shellescape(hash))
  if code ~= 0 or not out or out == "" then
    return {}
  end
  local files = {}
  for line in out:gmatch("[^\n]+") do
    local status, path = line:match("^(%S+)%s+(.+)$")
    if status and path then
      table.insert(files, { path = path, status = status })
    end
  end
  return files
end

--- 特定コミットのファイル内容を取得
--- @param hash string コミットハッシュ
--- @param filepath string
function M.show_commit_file(hash, filepath)
  local out, code = git("show " .. vim.fn.shellescape(hash) .. ":" .. vim.fn.shellescape(filepath))
  if code ~= 0 then
    return nil
  end
  return out
end

function M.show_head(filepath)
  local out, code = git("show HEAD:" .. vim.fn.shellescape(filepath))
  if code ~= 0 then
    return nil
  end
  return out
end

function M.show_index(filepath)
  local out, code = git("show :" .. vim.fn.shellescape(filepath))
  if code ~= 0 then
    return nil
  end
  return out
end

function M.read_working(filepath)
  local fullpath = M.cwd .. "/" .. filepath
  local ok, lines = pcall(vim.fn.readfile, fullpath)
  if not ok then
    return nil
  end
  return table.concat(lines, "\n")
end

function M.stage(filepath)
  return git("add -- " .. vim.fn.shellescape(filepath))
end

function M.unstage(filepath)
  return git("restore --staged -- " .. vim.fn.shellescape(filepath))
end

function M.stage_all()
  return git("add -A")
end

function M.unstage_all()
  return git("restore --staged .")
end

function M.commit(message)
  return git("commit -m " .. vim.fn.shellescape(message))
end

function M.push()
  return git("push")
end

function M.push_async(callback)
  -- upstream 未設定の場合は --set-upstream origin を付ける
  local _, code = git("rev-parse --abbrev-ref --symbolic-full-name @{u}")
  if code ~= 0 then
    local branch = M.branch()
    git_async("push --set-upstream origin " .. branch, callback)
  else
    git_async("push", callback)
  end
end

function M.pull()
  return git("pull")
end

function M.pull_async(callback)
  git_async("pull", callback)
end

--- ローカルブランチ一覧を返す（最近使った順にソート、ahead/behind付き）
--- @return { name: string, current: boolean, ahead: number, behind: number }[]
function M.branches()
  local out, code = git("for-each-ref --sort=-committerdate --format='%(refname:short)|%(HEAD)|%(upstream:track)|%(upstream)' refs/heads/")
  if code ~= 0 then
    -- フォールバック
    out, code = git("branch --no-color --sort=-committerdate")
    if code ~= 0 then
      return {}
    end
    local branches = {}
    for line in out:gmatch("[^\n]+") do
      local current = line:sub(1, 2) == "* "
      local name = vim.trim(line:sub(3))
      if name ~= "" then
        table.insert(branches, { name = name, current = current, ahead = 0, behind = 0, pushed = false })
      end
    end
    return branches
  end

  local branches = {}
  for line in out:gmatch("[^\n]+") do
    line = line:gsub("^'", ""):gsub("'$", "")
    local name, head, track, upstream = line:match("^(.+)|(.*)|(.*)|(.*)$")
    if name and name ~= "" then
      local ahead = tonumber((track or ""):match("ahead (%d+)")) or 0
      local behind = tonumber((track or ""):match("behind (%d+)")) or 0
      local has_upstream = upstream ~= nil and upstream ~= ""
      table.insert(branches, {
        name = name,
        current = head == "*",
        ahead = ahead,
        behind = behind,
        pushed = has_upstream,
      })
    end
  end

  -- 現在のブランチを先頭に
  table.sort(branches, function(a, b)
    if a.current then return true end
    if b.current then return false end
    return false
  end)

  return branches
end

--- リモートブランチ一覧を返す
--- @return { name: string, remote: string, short_name: string }[]
function M.remote_branches()
  local out, code = git("for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/")
  if code ~= 0 then
    return {}
  end
  local branches = {}
  for line in out:gmatch("[^\n]+") do
    line = line:gsub("^'", ""):gsub("'$", "")
    if line ~= "" and not line:match("/HEAD$") then
      local remote, short = line:match("^([^/]+)/(.+)$")
      table.insert(branches, {
        name = line,
        remote = remote or "",
        short_name = short or line,
      })
    end
  end
  return branches
end

function M.fetch()
  return git("fetch --all --prune")
end

function M.fetch_async(callback)
  git_async("fetch --all --prune", callback)
end

function M.checkout(branch_name)
  return git("checkout " .. vim.fn.shellescape(branch_name))
end

--- リモートブランチをローカルにチェックアウト
function M.checkout_remote(remote_branch, local_name)
  return git("checkout -b " .. vim.fn.shellescape(local_name) .. " " .. vim.fn.shellescape(remote_branch))
end

function M.create_branch(branch_name)
  return git("checkout -b " .. vim.fn.shellescape(branch_name))
end

function M.delete_branch(branch_name)
  return git("branch -d " .. vim.fn.shellescape(branch_name))
end

function M.delete_remote_branch(remote, branch_name)
  return git("push " .. vim.fn.shellescape(remote) .. " --delete " .. vim.fn.shellescape(branch_name))
end

function M.merge(branch_name)
  return git("merge " .. vim.fn.shellescape(branch_name))
end

function M.merge_async(branch_name, callback)
  git_async("merge " .. branch_name, callback)
end

function M.rebase(branch_name)
  return git("rebase " .. vim.fn.shellescape(branch_name))
end

function M.rebase_async(branch_name, callback)
  git_async("rebase " .. branch_name, callback)
end

function M.cherry_pick_async(hash, callback)
  git_async("cherry-pick " .. hash, callback)
end

--- ファイルのdiffをハンク単位で取得
--- @param filepath string
--- @param staged boolean
--- @return { header: string, start_old: number, start_new: number, count_old: number, count_new: number, lines: string[] }[]
function M.diff_hunks(filepath, staged)
  local flag = staged and "--cached " or ""
  local out, code = git("diff " .. flag .. "-- " .. vim.fn.shellescape(filepath))
  if code ~= 0 or not out or out == "" then
    return {}
  end

  local all_lines = vim.split(out, "\n", { plain = true })
  local hunks = {}
  local file_header = {}
  local current_hunk = nil

  for _, line in ipairs(all_lines) do
    if line:match("^@@") then
      -- 新しいハンク開始
      if current_hunk then
        table.insert(hunks, current_hunk)
      end
      local so, co, sn, cn = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
      current_hunk = {
        header = line,
        start_old = tonumber(so) or 0,
        count_old = tonumber(co) or 1,
        start_new = tonumber(sn) or 0,
        count_new = tonumber(cn) or 1,
        lines = { line },
      }
    elseif current_hunk then
      table.insert(current_hunk.lines, line)
    else
      -- ファイルヘッダー (diff --git, index, ---, +++)
      table.insert(file_header, line)
    end
  end
  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  -- 各ハンクにファイルヘッダーを付与
  for _, hunk in ipairs(hunks) do
    hunk.file_header = file_header
  end

  return hunks
end

--- ハンク1つをstage（git apply --cached）
--- @param hunk table diff_hunks() が返すハンク
function M.stage_hunk(hunk)
  local patch_lines = {}
  for _, line in ipairs(hunk.file_header) do
    table.insert(patch_lines, line)
  end
  for _, line in ipairs(hunk.lines) do
    table.insert(patch_lines, line)
  end
  table.insert(patch_lines, "")
  local patch = table.concat(patch_lines, "\n")
  local tmpfile = vim.fn.tempname()
  vim.fn.writefile(vim.split(patch, "\n", { plain = true }), tmpfile)
  local out, code = git("apply --cached -- " .. vim.fn.shellescape(tmpfile))
  os.remove(tmpfile)
  return out, code
end

--- ハンク1つをunstage（git apply --cached --reverse）
--- @param hunk table diff_hunks() が返すハンク
function M.unstage_hunk(hunk)
  local patch_lines = {}
  for _, line in ipairs(hunk.file_header) do
    table.insert(patch_lines, line)
  end
  for _, line in ipairs(hunk.lines) do
    table.insert(patch_lines, line)
  end
  table.insert(patch_lines, "")
  local patch = table.concat(patch_lines, "\n")
  local tmpfile = vim.fn.tempname()
  vim.fn.writefile(vim.split(patch, "\n", { plain = true }), tmpfile)
  local out, code = git("apply --cached --reverse -- " .. vim.fn.shellescape(tmpfile))
  os.remove(tmpfile)
  return out, code
end

function M.create_tag(tag_name, hash)
  if hash then
    return git("tag " .. vim.fn.shellescape(tag_name) .. " " .. hash)
  end
  return git("tag " .. vim.fn.shellescape(tag_name))
end

function M.delete_tag(tag_name)
  return git("tag -d " .. vim.fn.shellescape(tag_name))
end

function M.push_tag_async(tag_name, callback)
  git_async("push origin " .. tag_name, callback)
end

function M.graph()
  local out, code = git("log --graph --oneline --all --decorate --color=never -100")
  if code ~= 0 then
    return {}
  end
  return vim.split(out, "\n", { plain = true })
end

function M.discard(filepath)
  -- untracked ファイルは rm
  local status_out = git("status --porcelain=v1 -- " .. vim.fn.shellescape(filepath))
  if status_out and status_out:match("^%?%?") then
    local fullpath = M.cwd .. "/" .. filepath
    os.remove(fullpath)
    return "", 0
  end
  return git("checkout -- " .. vim.fn.shellescape(filepath))
end

--- ディレクトリ内の変更を全て破棄
--- @param dirpath string ディレクトリパス
--- @param files table unstaged ファイル一覧（state.files.unstaged）
function M.discard_dir(dirpath, files)
  local prefix = dirpath .. "/"
  -- untracked ファイルを削除
  for _, f in ipairs(files) do
    if f.path == dirpath or f.path:sub(1, #prefix) == prefix then
      if f.status == "?" then
        local fullpath = M.cwd .. "/" .. f.path
        os.remove(fullpath)
      end
    end
  end
  -- tracked ファイルの変更を復元
  return git("checkout -- " .. vim.fn.shellescape(dirpath))
end

return M
