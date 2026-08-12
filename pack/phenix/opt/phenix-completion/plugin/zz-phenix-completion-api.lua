require("phenix.frontend").register_api("completion", {
  show = function()
    return require("blink.cmp").show()
  end,
  hide = function()
    return require("blink.cmp").hide()
  end,
}, {
  contract = { show = "function", hide = "function" },
})
