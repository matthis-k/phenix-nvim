local constants = require("constants")
local opencode = require("opencode")

vim.o.autoread = true
vim.g.opencode_opts = vim.tbl_deep_extend("force", {
  ask = {
    prompt = "Ask opencode: ",
    snacks = { win = { border = constants.wins.border, title = "opencode", title_pos = "left", relative = "cursor", row = -3, col = 0 } },
  },
  select = { prompt = "opencode: ", snacks = { layout = { preset = "vscode" }, win = { border = constants.wins.border } } },
  provider = {
    enabled = "snacks",
    snacks = {
      auto_close = true,
      win = {
        position = "right",
        enter = false,
        border = constants.wins.border,
        wo = { winbar = "" },
        bo = { filetype = "opencode_terminal" },
      },
    },
  },
}, vim.g.opencode_opts or {})

vim.keymap.set({ "n", "x" }, "<leader>oa", function()
  opencode.ask("@this: ", { submit = true })
end, { desc = "Ask opencode" })
vim.keymap.set({ "n", "x" }, "<leader>os", function()
  opencode.select()
end, { desc = "Execute opencode action…" })
vim.keymap.set({ "n", "x" }, "<leader>op", function()
  opencode.prompt("@this")
end, { desc = "Add to opencode" })
vim.keymap.set("n", "<leader>oo", function()
  opencode.toggle()
end, { desc = "Toggle opencode" })
vim.keymap.set("n", "<leader>ok", function()
  opencode.command("session.half.page.up")
end, { desc = "opencode half page up" })
vim.keymap.set("n", "<leader>oj", function()
  opencode.command("session.half.page.down")
end, { desc = "opencode half page down" })
