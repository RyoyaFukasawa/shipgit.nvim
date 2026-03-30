describe("config", function()
  before_each(function()
    -- モジュールキャッシュをクリアして毎回新しい config を取得
    package.loaded["shipgit.config"] = nil
  end)

  it("should have default values", function()
    local config = require("shipgit.config")

    assert.equals(0.85, config.values.width)
    assert.equals(0.85, config.values.height)
    assert.equals("rounded", config.values.border)
    assert.equals(0.25, config.values.filelist_width)
  end)

  it("should have default keymaps", function()
    local config = require("shipgit.config")

    assert.equals("q", config.values.keymaps.quit)
    assert.equals("<Space>", config.values.keymaps.stage_toggle)
    assert.equals("a", config.values.keymaps.stage_all)
    assert.equals("c", config.values.keymaps.commit)
    assert.equals("P", config.values.keymaps.push)
    assert.equals("p", config.values.keymaps.pull)
    assert.equals("d", config.values.keymaps.discard)
    assert.equals("b", config.values.keymaps.branches)
    assert.equals("o", config.values.keymaps.open_file)
    assert.equals("t", config.values.keymaps.tree)
    assert.equals("s", config.values.keymaps.stash)
    assert.equals("g", config.values.keymaps.log)
  end)

  it("should merge user options", function()
    local config = require("shipgit.config")

    config.merge({
      width = 0.95,
      height = 0.95,
    })

    assert.equals(0.95, config.values.width)
    assert.equals(0.95, config.values.height)
    -- 他のデフォルト値は保持
    assert.equals("rounded", config.values.border)
  end)

  it("should deep merge keymaps", function()
    local config = require("shipgit.config")

    config.merge({
      keymaps = {
        quit = "x",
      },
    })

    assert.equals("x", config.values.keymaps.quit)
    -- 他のキーマップはデフォルトのまま
    assert.equals("<Space>", config.values.keymaps.stage_toggle)
  end)

  it("should deep merge highlights", function()
    local config = require("shipgit.config")

    config.merge({
      highlights = {
        diff_add = { bg = "#ff0000" },
      },
    })

    assert.equals("#ff0000", config.values.highlights.diff_add.bg)
    -- 他のハイライトはデフォルトのまま
    assert.is_not_nil(config.values.highlights.diff_delete)
  end)

  it("should not modify defaults", function()
    local config = require("shipgit.config")

    config.merge({ width = 1.0 })

    assert.equals(0.85, config.defaults.width)
    assert.equals(1.0, config.values.width)
  end)
end)
