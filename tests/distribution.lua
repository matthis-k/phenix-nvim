local phenix = require("phenix_nvim")
assert(type(phenix.toggle) == "function")
assert(type(phenix.send) == "function")
assert(type(phenix.reference) == "function")
assert(type(phenix.choose_session) == "function")
assert(type(phenix.choose_model) == "function")
assert(type(phenix.choose_routing_profile) == "function")

local config = require("phenix_nvim.config").get()
assert(type(config.command) == "string" and config.command ~= "")
assert(config.command ~= "phenix-acp", "Nix package must inject the packaged phenix-acp runtime")
assert(vim.fn.executable(config.command) == 1, "packaged phenix-acp runtime must be executable")

assert(vim.fn.exists(":PhenixToggle") == 2)
assert(vim.fn.exists(":PhenixSend") == 2)
assert(vim.fn.exists(":PhenixModel") == 2)
assert(vim.fn.exists(":PhenixRoute") == 2)

local statusline = require("phenix.bars.defaults.statusline")
assert(type(statusline.phenix.hl()) == "string")
assert(type(statusline.phenix.text()) == "string")

phenix.disconnect()
