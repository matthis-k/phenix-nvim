local constants = require("constants")
local conform = require("conform")

conform.setup({
  default_format_opts = { lsp_format = "prefer" },
  format_on_save = function(bufnr)
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return
    end
    return { timeout_ms = 500 }
  end,
})

vim.api.nvim_create_user_command("FormatOff", function(args)
  if args.bang then
    vim.b.disable_autoformat = true
  else
    vim.g.disable_autoformat = true
  end
end, { desc = "Disable autoformat-on-save", bang = true })
vim.api.nvim_create_user_command("FormatOn", function()
  vim.b.disable_autoformat = false
  vim.g.disable_autoformat = false
end, { desc = "Re-enable autoformat-on-save" })

vim.keymap.set("n", "<leader>vf", "<cmd>FormatOn<cr>", { silent = true, desc = "Re-enable autoformat-on-save" })
vim.keymap.set("n", "<leader>vF", "<cmd>FormatOff<cr>", { silent = true, desc = "Disable autoformat-on-save" })
vim.keymap.set("n", "<leader>l", "<nop>", { silent = true, desc = "Lsp" })
vim.keymap.set("n", "<leader>lf", function()
  conform.format({ async = true })
end, { silent = true, desc = "Format buffer" })
vim.keymap.set("v", "<space>lf", function()
  conform.format({
    async = true,
    range = {
      start = vim.api.nvim_buf_get_mark(0, "<"),
      ["end"] = vim.api.nvim_buf_get_mark(0, ">"),
    },
  })
end, { silent = true, desc = "Format range" })

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("PhenixLazydev", { clear = true }),
  pattern = "lua",
  callback = function()
    require("lazydev").setup({
      debug = false,
      runtime = vim.env.VIMRUNTIME,
      library = { { path = "luvit-meta/library", words = { "vim%.uv" } } },
      integrations = { lspconfig = false, cmp = false, coc = false },
      enabled = function(root_dir)
        return not vim.uv.fs_stat(root_dir .. "/.luarc.json")
      end,
    })
  end,
})

for _, server in ipairs({
  "clangd", "cssls", "jsonls", "lemminx", "lua_ls", "marksman", "nil_ls", "qmlls", "rust_analyzer", "taplo", "ts_ls",
}) do
  vim.lsp.enable(server, true)
end

vim.diagnostic.config({
  update_in_insert = true,
  virtual_text = false,
  underline = { severity = { vim.diagnostic.severity.ERROR } },
  severity_sort = true,
  signs = {
    text = vim.tbl_map(function(sign)
      return sign.text
    end, constants.signs.diagnostics),
    linehl = {},
    numhl = {},
  },
})

for _, sign in pairs(constants.signs.diagnostics) do
  vim.fn.sign_define(sign.name, { text = sign.text, texthl = sign.texthl })
end
