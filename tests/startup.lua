local source = assert(debug.getinfo(1, "S").source:match("^@(.+)$"), "startup test source path unavailable")
local test_root = vim.fs.dirname(source)
local config_file = vim.fs.joinpath(test_root, "startup_config.lua")

require("phenix").setup({ config_file = config_file })
assert(Phenix.config.acp.config_file == config_file, "startup fixture config was not projected")

dofile(vim.fs.joinpath(test_root, "startup_checks.lua"))
