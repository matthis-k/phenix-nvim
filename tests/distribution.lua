local phenix = require("phenix_nvim")

local config = require("phenix_nvim.config").get()
assert(type(config.command) == "string" and config.command ~= "")
assert(config.command ~= "phenix-acp", "distribution must inject the packaged Phenix command")
assert(vim.fn.executable(config.command) == 1, "packaged Phenix command must be executable")

assert(vim.fn.exists(":Phenix") == 2, "distribution must load the Phenix entry command")

local statusline = require("phenix.bars.defaults.statusline")
assert(type(statusline.phenix.hl()) == "string")
assert(type(statusline.phenix.text()) == "string")

phenix.disconnect()
print("phenix-nvim distribution configuration smoke passed")
