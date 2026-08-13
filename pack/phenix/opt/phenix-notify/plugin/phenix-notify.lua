require("phenix.frontend").register_api("notifier", require("phenix.features.notifier"), {
  contract = { history = "function", hide = "function" },
})
