vim.g.mapleader = " "
vim.g.maplocalleader = " "

local phenix = require("phenix")
phenix.setup()

local function map(lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, {
    desc = "Phenix: " .. desc,
    silent = true,
  })
end

map("<leader>po", "<cmd>PhenixOpen<cr>", "open session")
map("<leader>pn", "<cmd>PhenixNew<cr>", "new session")
map("<leader>pp", "<cmd>PhenixPrompt<cr>", "prompt / focus composer")
map("<leader>pc", "<cmd>PhenixConfig<cr>", "configure session")
map("<leader>px", "<cmd>PhenixCancel<cr>", "cancel prompt")
map("<leader>pq", "<cmd>PhenixClose<cr>", "close session")

require("which-key").add({
  { "<leader>p", group = "Phenix" },
})
