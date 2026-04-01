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

  describe("stash_files", function()
    it("should return files in stash", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      vim.fn.writefile({ "changed" }, tmpdir .. "/test.txt")
      vim.fn.writefile({ "new" }, tmpdir .. "/new.txt")
      vim.fn.system("git -C " .. tmpdir .. " add .")
      vim.fn.system("git -C " .. tmpdir .. " stash push -m 'test'")

      git.init(tmpdir)
      local files = git.stash_files(0)

      assert.is_true(#files >= 1)
      local paths = {}
      for _, f in ipairs(files) do
        paths[f.path] = f.status
      end
      assert.is_not_nil(paths["test.txt"])

      -- cleanup
      vim.fn.system("git -C " .. tmpdir .. " stash drop")
      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("stash_show_file", function()
    it("should return file content from stash", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "original" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      vim.fn.writefile({ "stashed content" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " stash push -m 'test'")

      git.init(tmpdir)
      local content = git.stash_show_file(0, "test.txt")
      assert.is_not_nil(content)
      assert.is_true(content:find("stashed content") ~= nil)

      local parent = git.stash_show_parent_file(0, "test.txt")
      assert.is_not_nil(parent)
      assert.is_true(parent:find("original") ~= nil)

      vim.fn.system("git -C " .. tmpdir .. " stash drop")
      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("log with branch and skip", function()
    it("should support skip parameter", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "1" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'first'")
      vim.fn.writefile({ "2" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'second'")
      vim.fn.writefile({ "3" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'third'")

      git.init(tmpdir)
      local all = git.log(10, 0)
      assert.equals(3, #all)

      local skipped = git.log(10, 1)
      assert.equals(2, #skipped)
      assert.equals("second", skipped[1].subject)

      vim.fn.delete(tmpdir, "rf")
    end)

    it("should support branch parameter", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "1" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'main commit'")
      vim.fn.system("git -C " .. tmpdir .. " checkout -b feature")
      vim.fn.writefile({ "2" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'feature commit'")
      vim.fn.system("git -C " .. tmpdir .. " checkout main")

      git.init(tmpdir)
      local main_log = git.log(10, 0, "main")
      assert.equals(1, #main_log)
      assert.equals("main commit", main_log[1].subject)

      local feature_log = git.log(10, 0, "feature")
      assert.equals(2, #feature_log)
      assert.equals("feature commit", feature_log[1].subject)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("cherry-pick", function()
    it("should detect cherry-picking state", function()
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
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'feature change'")
      local hash = vim.trim(vim.fn.system("git -C " .. tmpdir .. " rev-parse HEAD"))
      vim.fn.system("git -C " .. tmpdir .. " checkout main")
      vim.fn.writefile({ "main" }, tmpdir .. "/file.txt")
      vim.fn.system("git -C " .. tmpdir .. " add file.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'main change'")

      -- cherry-pick（conflict が起きる）
      vim.fn.system("git -C " .. tmpdir .. " cherry-pick " .. hash)

      git.init(tmpdir)
      assert.is_true(git.is_cherry_picking())

      git.cherry_pick_abort()
      assert.is_false(git.is_cherry_picking())

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("tag", function()
    it("should create and delete tags", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")

      git.init(tmpdir)
      local hash = vim.trim(vim.fn.system("git -C " .. tmpdir .. " rev-parse HEAD"))

      -- create tag
      local _, code = git.create_tag("v1.0.0", hash)
      assert.equals(0, code)

      -- verify tag exists
      local tag_out = vim.trim(vim.fn.system("git -C " .. tmpdir .. " tag -l v1.0.0"))
      assert.equals("v1.0.0", tag_out)

      -- create tag with slash
      local _, code2 = git.create_tag("ios/v1.0.0", hash)
      assert.equals(0, code2)

      -- delete tag
      local _, code3 = git.delete_tag("v1.0.0")
      assert.equals(0, code3)
      local tag_out2 = vim.trim(vim.fn.system("git -C " .. tmpdir .. " tag -l v1.0.0"))
      assert.equals("", tag_out2)

      -- delete slash tag
      local _, code4 = git.delete_tag("ios/v1.0.0")
      assert.equals(0, code4)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("discard", function()
    it("should discard changes to a file", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "original" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      vim.fn.writefile({ "changed" }, tmpdir .. "/test.txt")

      git.init(tmpdir)
      git.discard("test.txt")

      local content = vim.fn.readfile(tmpdir .. "/test.txt")
      assert.equals("original", content[1])

      vim.fn.delete(tmpdir, "rf")
    end)

    it("should discard directory changes", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.mkdir(tmpdir .. "/src", "p")
      vim.fn.writefile({ "a" }, tmpdir .. "/src/a.txt")
      vim.fn.writefile({ "b" }, tmpdir .. "/src/b.txt")
      vim.fn.system("git -C " .. tmpdir .. " add .")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      vim.fn.writefile({ "changed a" }, tmpdir .. "/src/a.txt")
      vim.fn.writefile({ "changed b" }, tmpdir .. "/src/b.txt")

      git.init(tmpdir)
      local files = git.status().unstaged
      git.discard_dir("src", files)

      local a = vim.fn.readfile(tmpdir .. "/src/a.txt")
      local b = vim.fn.readfile(tmpdir .. "/src/b.txt")
      assert.equals("a", a[1])
      assert.equals("b", b[1])

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("push_async upstream detection", function()
    it("should detect missing upstream", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")

      git.init(tmpdir)
      -- upstream が設定されていないことを確認
      local _, code = git._test_has_upstream and git._test_has_upstream() or nil, nil
      -- rev-parse で直接テスト
      local out = vim.fn.system("git -C " .. tmpdir .. " rev-parse --abbrev-ref --symbolic-full-name @{u} 2>&1")
      assert.is_true(out:find("no upstream") ~= nil or out:find("fatal") ~= nil)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("branches pushed flag", function()
    it("should mark branches without upstream as unpushed", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")

      git.init(tmpdir)
      local branches = git.branches()

      assert.is_true(#branches >= 1)
      -- ローカルのみのブランチは pushed = false
      for _, b in ipairs(branches) do
        assert.is_false(b.pushed)
      end

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("diff_hunks", function()
    it("should parse hunks from diff", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      -- 10行のファイルを作成
      local original = {}
      for i = 1, 10 do
        original[i] = "line " .. i
      end
      vim.fn.writefile(original, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      -- 1行目と10行目を変更（離れているので2つのハンクになる）
      local modified = vim.deepcopy(original)
      modified[1] = "changed line 1"
      modified[10] = "changed line 10"
      vim.fn.writefile(modified, tmpdir .. "/test.txt")

      git.init(tmpdir)
      local hunks = git.diff_hunks("test.txt", false)

      assert.is_true(#hunks >= 1)
      assert.is_not_nil(hunks[1].header)
      assert.is_not_nil(hunks[1].start_old)
      assert.is_not_nil(hunks[1].start_new)
      assert.is_not_nil(hunks[1].count_old)
      assert.is_not_nil(hunks[1].count_new)
      assert.is_not_nil(hunks[1].lines)
      assert.is_not_nil(hunks[1].file_header)

      vim.fn.delete(tmpdir, "rf")
    end)

    it("should return empty for clean file", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "hello" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")

      git.init(tmpdir)
      local hunks = git.diff_hunks("test.txt", false)
      assert.equals(0, #hunks)

      vim.fn.delete(tmpdir, "rf")
    end)
  end)

  describe("hunk stage/unstage", function()
    it("should stage a single hunk", function()
      local tmpdir = vim.fn.tempname()
      vim.fn.mkdir(tmpdir, "p")
      vim.fn.system("git -C " .. tmpdir .. " init")
      vim.fn.system("git -C " .. tmpdir .. " config user.email 'test@test.com'")
      vim.fn.system("git -C " .. tmpdir .. " config user.name 'test'")
      vim.fn.writefile({ "line1", "line2", "line3" }, tmpdir .. "/test.txt")
      vim.fn.system("git -C " .. tmpdir .. " add test.txt")
      vim.fn.system("git -C " .. tmpdir .. " commit -m 'init'")
      vim.fn.writefile({ "changed", "line2", "line3" }, tmpdir .. "/test.txt")

      git.init(tmpdir)
      local hunks = git.diff_hunks("test.txt", false)
      assert.is_true(#hunks >= 1)

      -- hunk をステージ
      local _, code = git.stage_hunk(hunks[1])
      assert.equals(0, code)

      -- staged に変更がある
      local status = git.status()
      assert.equals(1, #status.staged)
      assert.equals(0, #status.unstaged)

      -- hunk をアンステージ
      local staged_hunks = git.diff_hunks("test.txt", true)
      assert.is_true(#staged_hunks >= 1)
      local _, code2 = git.unstage_hunk(staged_hunks[1])
      assert.equals(0, code2)

      local status2 = git.status()
      assert.equals(0, #status2.staged)
      assert.equals(1, #status2.unstaged)

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
