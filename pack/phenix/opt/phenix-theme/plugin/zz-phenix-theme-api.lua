require("phenix.frontend").register_api("theme", {
  colors = function()
    return require("base16-colorscheme").colors
  end,
}, {
  contract = { colors = "function" },
})
