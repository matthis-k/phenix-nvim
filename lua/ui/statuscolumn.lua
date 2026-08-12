local statuscolumn = require("phenix.bars.statuscolumn")

statuscolumn.configure_sign_column("misc", {
  width = 2,
  filter = function(namespace)
    return not (namespace:find("diagnostic%.signs") or namespace:match("gitsigns_signs.*"))
  end,
})

statuscolumn.configure_sign_column("diagnostic", {
  width = 2,
  filter = function(namespace)
    return namespace:find("diagnostic%.signs") ~= nil
  end,
})

statuscolumn.configure_sign_column("git", {
  width = 1,
  filter = function(namespace)
    return namespace:match("gitsigns_signs.*") ~= nil
  end,
})

local M = {}

M.whole = {
  children = {
    statuscolumn.sign_part("misc", { auto_hide = true }),
    statuscolumn.sign_part("diagnostic"),
    statuscolumn.fold_part({
      hl = "StcFold",
      current_hl = "StcFoldCurrent",
      on_click = "statuscolumn_fold",
    }),
    statuscolumn.number_part({
      hl = "StcLineNumber",
      current_hl = "StcCurrentLineNumber",
      on_click = "statuscolumn_number",
    }),
    statuscolumn.sign_part("git"),
  },
}

return M
