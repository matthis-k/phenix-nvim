local Frontend = require("phenix.frontend")

return setmetatable({}, {
  __index = function(_, key)
    return Frontend.require_api("ui").window[key]
  end,
})
