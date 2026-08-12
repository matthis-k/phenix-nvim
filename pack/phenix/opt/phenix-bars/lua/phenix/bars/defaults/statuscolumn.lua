local Frontend = require("phenix.frontend")
local statuscolumn = require("phenix.bars.statuscolumn")

local function is_git_namespace(namespace)
  local ok, git = pcall(Frontend.interface, "git")
  return ok and git.is_sign_namespace(namespace) or false
end

statuscolumn.configure_sign_column("misc", {
  width = 2,
  filter = function(namespace)
    return not namespace:find("diagnostic%.signs") and not is_git_namespace(namespace)
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
  filter = is_git_namespace,
})

return {
  whole = {
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
  },
}
