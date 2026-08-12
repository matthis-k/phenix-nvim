require("phenix.frontend").provide("git", {
  status = function(buf)
    return vim.b[buf or 0].gitsigns_status_dict
  end,
})
