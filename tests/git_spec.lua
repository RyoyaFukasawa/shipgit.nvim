local git = require("shipgit.git")

describe("git", function()
  describe("status parser", function()
    -- git.status() は実際の git コマンドを実行するので、
    -- パーサーのロジックを個別にテストする

    it("should detect staged files", function()
      -- git init して空のリポジトリで status を取得
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")

      -- ファイルを作成してステージ
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")

      git.init(tmpdir)
      local result = git.status()

      assert.is_not_nil(result.staged)
      assert.equals(1, #result.staged)
      assert.equals("test.txt", result.staged[1].path)
      assert.equals("A", result.staged[1].status)

      -- cleanup
      vim.fn.delete(tmpdir, "rf")
    end)

    it("should detect unstaged files", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")

      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")

      -- 変更を加える
      vim.fn.writefile({ "world" }, tmpdir .. "/test.txt")

      git.init(tmpdir)
      local result = git.status()

      assert.is_not_nil(result.unstaged)
      assert.equals(1, #result.unstaged)
      assert.equals("test.txt", result.unstaged[1].path)
      assert.equals("M", result.unstaged[1].status)

      vim.fn.delete(tmpdir, "rf")
    end)

    it("should detect untracked files", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")

      vim.fn.writefile({ "new" }, tmpdir .. "/new.txt")

      git.init(tmpdir)
      local result = git.status()

      assert.is_not_nil(result.unstaged)
      assert.is_true(#result.unstaged >= 1)
      local found = false
      for _, f in ipairs(result.unstaged) do
        if f.path == "new.txt" and f.status == "?" then
          found = true
        end
      end
      assert.is_true(found)

      vim.fn.delete(tmpdir, "rf")
    end)

    it("should detect conflict files", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")

      -- main にコミット
      vim.fn.writefile({ "line1" }, tmpdir .. "/file.txt")
      vim.fn.system("git -C " .. tmpdir .. " add file.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")

      -- ブランチ作成して変更
      vim.fn.system("git -C " .. tmpdir .. " checkout -b feature")
      vim.fn.writefile({ "feature" }, tmpdir .. "/file.txt")
      vim.fn.system("git -C " .. tmpdir .. " add file.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'feature'")

      -- main に戻って別の変更
      vim.fn.system("git -C " .. tmpdir .. " checkout main")
      vim.fn.writefile({ "main" }, tmpdir .. "/file.txt")
      vim.fn.system("git -C " .. tmpdir .. " add file.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'main change'")

      -- merge（conflict が起きる）
      vim.fn.system("git -C " .. tmpdir .. " merge feature")

      git.init(tmpdir)
      local result = git.status()

      assert.is_not_nil(result.conflict)
      assert.equals(1, #result.conflict)
      assert.equals("file.txt", result.conflict[1].path)

      -- cleanup
      vim.fn.system("git -C " .. tmpdir .. " merge --abort")
      vim.fn.delete(tmpdir, "rf")
    end)

    it("should return empty on clean repo", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")

      git.init(tmpdir)
      local result = git.status()

      assert.equals(0, #result.staged)
      assert.equals(0, #result.unstaged)
      assert.equals(0, #result.conflict)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("branch", function()
    it("should return current branch name", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")

      git.init(tmpdir)
      local branch = git.branch()

      assert.is_not_nil(branch)
      assert.is_true(branch == "main" or branch == "master")

      vim.fn.delete(tmpdir, "rf")
    end)

    it("should list branches", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      vim.fn.system("git -C " .. tmpdir .. " checkout -b feature")
      vim.fn.system("git -C " .. tmpdir .. " checkout main")

      git.init(tmpdir)
      local branches = git.branches()

      assert.is_true(#branches >= 2)
      local names = {}
      for _, b in ipairs(branches) do
        names[b.name] = true
      end
      assert.is_true(names["main"] or names["master"])
      assert.is_true(names["feature"])

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("stage/unstage", function()
    it("should stage and unstage a file", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      vim.fn.writefile({ "world" }, tmpdir .. "/test.txt")

      git.init(tmpdir)

      -- unstaged
      local s1 = git.status()
      assert.equals(1, #s1.unstaged)
      assert.equals(0, #s1.staged)

      -- stage
      git.stage("test.txt")
      local s2 = git.status()
      assert.equals(0, #s2.unstaged)
      assert.equals(1, #s2.staged)

      -- unstage
      git.unstage("test.txt")
      local s3 = git.status()
      assert.equals(1, #s3.unstaged)
      assert.equals(0, #s3.staged)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("commit", function()
    it("should create a commit", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")

      git.init(tmpdir)
      local _, code = git.commit("test commit")
      assert.equals(0, code)

      local result = git.status()
      assert.equals(0, #result.staged)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("stash", function()
    it("should stash and pop", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      vim.fn.writefile({ "changed" }, tmpdir .. "/test.txt")

      git.init(tmpdir)

      -- stash
      local _, code = git.stash_push("test stash")
      assert.equals(0, code)

      local s1 = git.status()
      assert.equals(0, #s1.unstaged)

      local stashes = git.stash_list()
      assert.is_true(#stashes >= 1)

      -- pop
      git.stash_pop(0)
      local s2 = git.status()
      assert.equals(1, #s2.unstaged)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("log", function()
    it("should return commit log", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'first commit'")
      vim.fn.writefile({ "world" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'second commit'")

      git.init(tmpdir)
      local commits = git.log(10)

      assert.equals(2, #commits)
      assert.equals("second commit", commits[1].subject)
      assert.equals("first commit", commits[2].subject)
      assert.is_not_nil(commits[1].hash)
      assert.is_not_nil(commits[1].short_hash)
      assert.is_not_nil(commits[1].author)

      vim.fn.delete(tmpdir, "rf")
    end)

    it("should return commit files", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/a.txt")
      vim.fn.writefile({ "world" }, tmpdir .. "/b.txt")
      vim.fn.system("git -C " .. tmpdir .. " add .")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'add two files'")

      git.init(tmpdir)
      local commits = git.log(1)
      local files = git.commit_files(commits[1].hash)

      assert.equals(2, #files)
      local paths = {}
      for _, f in ipairs(files) do
        paths[f.path] = f.status
      end
      assert.equals("A", paths["a.txt"])
      assert.equals("A", paths["b.txt"])

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("show_head / show_index", function()
    it("should return file content from HEAD", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello world" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")

      git.init(tmpdir)
      local content = git.show_head("test.txt")
      assert.is_not_nil(content)
      assert.is_true(content:find("hello world") ~= nil)

      vim.fn.delete(tmpdir, "rf")
    end)

    it("should return file content from index", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "staged content" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")

      git.init(tmpdir)
      local content = git.show_index("test.txt")
      assert.is_not_nil(content)
      assert.is_true(content:find("staged content") ~= nil)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("is_repo", function()
    it("should return true for git repo", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")

      git.init(tmpdir)
      assert.is_true(git.is_repo())

      vim.fn.delete(tmpdir, "rf")
    end)

    it("should return false for non-git directory", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")

      git.init(tmpdir)
      assert.is_false(git.is_repo())

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("merge", function()
    it("should detect merging state", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "line1" }, tmpdir .. "/file.txt")
      vim.fn.system("git -C " .. tmpdir .. " add file.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      vim.fn.system("git -C " .. tmpdir .. " checkout -b feature")
      vim.fn.writefile({ "feature" }, tmpdir .. "/file.txt")
      vim.fn.system("git -C " .. tmpdir .. " add file.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'feature'")
      vim.fn.system("git -C " .. tmpdir .. " checkout main")
      vim.fn.writefile({ "main" }, tmpdir .. "/file.txt")
      vim.fn.system("git -C " .. tmpdir .. " add file.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'main'")
      vim.fn.system("git -C " .. tmpdir .. " merge feature")

      git.init(tmpdir)
      assert.is_true(git.is_merging())

      git.merge_abort()
      assert.is_false(git.is_merging())

      vim.fn.delete(tmpdir, "rf")
    end)
  end)
end)
