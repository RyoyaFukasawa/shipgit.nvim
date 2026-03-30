local filelist = require("shipgit.filelist")

describe("filelist", function()
  describe("status_icon", function()
    it("should return correct icons", function()
      assert.equals("M", filelist.status_icon("M"))
      assert.equals("+", filelist.status_icon("A"))
      assert.equals("-", filelist.status_icon("D"))
      assert.equals("R", filelist.status_icon("R"))
      assert.equals("?", filelist.status_icon("?"))
      assert.equals("!", filelist.status_icon("UU"))
      assert.equals("!", filelist.status_icon("AA"))
    end)

    it("should return raw status for unknown", function()
      assert.equals("X", filelist.status_icon("X"))
    end)
  end)

  describe("build_tree", function()
    it("should group files under same directory", function()
      local files = {
        { path = "src/a.ts", status = "M" },
        { path = "src/b.ts", status = "M" },
        { path = "README.md", status = "M" },
      }

      local tree = filelist.build_tree(files)

      -- src/ ディレクトリ、src/a.ts、src/b.ts、README.md
      assert.equals(4, #tree)
      assert.is_true(tree[1].is_dir)
      assert.equals("src", tree[1].name)
      assert.is_false(tree[2].is_dir)
      assert.equals("a.ts", tree[2].name)
      assert.is_false(tree[3].is_dir)
      assert.equals("b.ts", tree[3].name)
      assert.is_false(tree[4].is_dir)
      assert.equals("README.md", tree[4].name)
    end)

    it("should compress single-child directories", function()
      local files = {
        { path = "src/components/Button.tsx", status = "M" },
        { path = "src/components/Input.tsx", status = "M" },
      }

      local tree = filelist.build_tree(files)

      -- src/components/ (compressed), Button.tsx, Input.tsx
      assert.equals(3, #tree)
      assert.is_true(tree[1].is_dir)
      assert.equals("src/components", tree[1].name)
    end)

    it("should handle root-level files only", function()
      local files = {
        { path = "a.txt", status = "M" },
        { path = "b.txt", status = "A" },
      }

      local tree = filelist.build_tree(files)

      assert.equals(2, #tree)
      assert.is_false(tree[1].is_dir)
      assert.is_false(tree[2].is_dir)
    end)

    it("should handle nested directories", function()
      local files = {
        { path = "src/a.ts", status = "M" },
        { path = "src/utils/b.ts", status = "M" },
        { path = "src/utils/c.ts", status = "M" },
      }

      local tree = filelist.build_tree(files)

      -- src/ dir, utils/ dir, b.ts, c.ts, a.ts
      local dirs = {}
      local file_items = {}
      for _, item in ipairs(tree) do
        if item.is_dir then
          table.insert(dirs, item)
        else
          table.insert(file_items, item)
        end
      end

      assert.is_true(#dirs >= 1)
      assert.is_true(#file_items == 3)
    end)

    it("should set parent_dir for files under directories", function()
      local files = {
        { path = "src/a.ts", status = "M" },
        { path = "src/b.ts", status = "M" },
      }

      local tree = filelist.build_tree(files)

      for _, item in ipairs(tree) do
        if not item.is_dir then
          assert.equals("src", item.parent_dir)
        end
      end
    end)

    it("should handle empty file list", function()
      local tree = filelist.build_tree({})
      assert.equals(0, #tree)
    end)

    it("should handle single file in directory", function()
      local files = {
        { path = "src/only.ts", status = "M" },
      }

      local tree = filelist.build_tree(files)

      -- 1ファイルだけのディレクトリでもツリーノードが作られる
      -- ただし圧縮されて src ディレクトリ + only.ts
      assert.is_true(#tree >= 1)
    end)
  end)
end)
