require("phenix.frontend").provide("theme", {
  colors = function()
    return require("base16-colorscheme").colors
  end,
})
