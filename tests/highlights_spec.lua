describe("highlights", function()
  before_each(function()
    package.loaded["shipgit.config"] = nil
    package.loaded["shipgit.highlights"] = nil
  end)

  it("should create highlight groups from config", function()
    local config = require("shipgit.config")
    config.merge({})

    local highlights = require("shipgit.highlights")
    highlights.setup()

    -- ハイライトグループが作成されていることを確認
    local groups = {
      "ShipgitStagedHeader",
      "ShipgitUnstagedHeader",
      "ShipgitStagedFile",
      "ShipgitUnstagedFile",
      "ShipgitUntrackedFile",
      "ShipgitDirName",
      "ShipgitBorder",
      "ShipgitTitle",
      "ShipgitSeparator",
      "ShipgitDiffAdd",
      "ShipgitDiffChange",
      "ShipgitDiffDelete",
      "ShipgitDiffText",
      "ShipgitGraphCommit",
      "ShipgitGraphHash",
      "ShipgitGraphHead",
    }

    for _, name in ipairs(groups) do
      local hl = vim.api.nvim_get_hl(0, { name = name })
      assert.is_not_nil(hl, name .. " should exist")
    end
  end)

  it("should create graph line colors", function()
    local config = require("shipgit.config")
    config.merge({})

    local highlights = require("shipgit.highlights")
    highlights.setup()

    for i = 1, 8 do
      local name = "ShipgitGraphLine" .. i
      local hl = vim.api.nvim_get_hl(0, { name = name })
      assert.is_not_nil(hl, name .. " should exist")
      assert.is_not_nil(hl.fg, name .. " should have fg")
    end
  end)

  it("should respect custom highlight config", function()
    local config = require("shipgit.config")
    config.merge({
      highlights = {
        diff_add = { bg = "#112233" },
      },
    })

    local highlights = require("shipgit.highlights")
    highlights.setup()

    local hl = vim.api.nvim_get_hl(0, { name = "ShipgitDiffAdd" })
    -- nvim_get_hl returns bg as number
    assert.is_not_nil(hl.bg)
  end)
end)
