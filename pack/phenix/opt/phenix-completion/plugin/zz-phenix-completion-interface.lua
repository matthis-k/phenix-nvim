require("phenix.frontend").provide("completion", {
  show = function()
    return require("blink.cmp").show()
  end,
  hide = function()
    return require("blink.cmp").hide()
  end,
})
