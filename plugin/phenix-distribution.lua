if vim.g.loaded_phenix_distribution then
  return
end
vim.g.loaded_phenix_distribution = true

-- Native packages are loaded in dependency order.  Third-party dependencies
-- are supplied by the immutable wrapper runtime before this config is sourced.
for _, package in ipairs({
  "phenix-core",
  "phenix-options",
  "phenix-theme",
  "phenix-bars-and-columns",
  "phenix-session",
  "phenix-snacks",
  "phenix-keymaps",
  "phenix-git",
  "phenix-lsp",
  "phenix-completion",
  "phenix-opencode",
}) do
  vim.cmd.packadd(package)
end
