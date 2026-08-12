if vim.g.loaded_phenix_nvim then
  return
end
vim.g.loaded_phenix_nvim = true

local group = vim.api.nvim_create_augroup("PhenixNvim", { clear = true })
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = group,
  callback = function(args)
    if not vim.api.nvim_buf_is_valid(args.buf) then
      return
    end
    local name = vim.api.nvim_buf_get_name(args.buf)
    if not name:match("^phenix://transcript/") then
      return
    end

    local window = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(window) ~= args.buf then
      return
    end

    local ok, markview = pcall(require, "markview")
    if not ok then
      return
    end

    vim.api.nvim_set_option_value("conceallevel", 3, { win = window })
    vim.api.nvim_set_option_value("concealcursor", "nc", { win = window })
    if markview.actions and type(markview.actions.set_query) == "function" then
      pcall(markview.actions.set_query, args.buf)
    end
  end,
  desc = "Phenix: prepare transcript windows for Markview",
})

local phenix = require("phenix")
phenix._register_mappings()
phenix._register_shutdown()
