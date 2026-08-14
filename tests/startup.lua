local source = assert(debug.getinfo(1, "S").source:match("^@(.+)$"), "startup test source path unavailable")
local test_root = vim.fs.dirname(source)

local packaged_config_dir = assert(vim.env.PHENIX_CONFIG_DIR, "packaged PHENIX_CONFIG_DIR is missing")
local packaged_config_file = vim.fs.joinpath(packaged_config_dir, "init.lua")
assert(vim.uv.fs_stat(packaged_config_file), "packaged Phenix config is missing: " .. packaged_config_file)

local config_file = vim.fs.joinpath(test_root, "startup_config.lua")

require("phenix").setup({ config_file = config_file })
assert(Phenix.config.acp.config_file == config_file, "startup fixture config was not projected")

dofile(vim.fs.joinpath(test_root, "startup_checks.lua"))
