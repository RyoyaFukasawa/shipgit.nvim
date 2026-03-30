vim.api.nvim_create_user_command("Shipgit", function()
  require("shipgit").open()
end, { desc = "Open Shipgit" })

vim.api.nvim_create_user_command("ShipgitClose", function()
  require("shipgit").close()
end, { desc = "Close Shipgit" })

vim.api.nvim_create_user_command("ShipgitToggle", function()
  require("shipgit").toggle()
end, { desc = "Toggle Shipgit" })
