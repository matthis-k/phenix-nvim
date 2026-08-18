require("phenix.frontend").project_api("theme", {
  colors = function()
    return require("base16-colorscheme").colors
  end,
})
