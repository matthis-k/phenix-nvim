---@class PhenixKeymapAction
---@field interface string
---@field method string
---@field args? table

---@class PhenixKeymap
---@field mode string|string[]
---@field lhs string
---@field rhs? string|function
---@field action? PhenixKeymapAction
---@field opts? table

---@type PhenixKeymap[]
local maps = {
  {
    mode = "n",
    lhs = "<C-w>o",
    rhs = function()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_feedkeys(vim.keycode("<C-w>o"), "n", false)
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if buf ~= bufnr then
          vim.api.nvim_buf_delete(buf, {})
        end
      end
    end,
    opts = { desc = "Zoom window & wipe other buffers" },
  },
  { mode = "n", lhs = "<esc>", rhs = "<cmd>noh<CR>", opts = { desc = "Clear search highlight" } },
  { mode = "t", lhs = "<c-esc>", rhs = "<C-\\><C-n>", opts = { desc = "Leave terminal normal mode", silent = true } },
  {
    mode = "v",
    lhs = "/",
    rhs = function()
      vim.cmd('normal! "*y')
      local selection = vim.fn.getreg("*")
      vim.cmd("/" .. vim.fn.escape(selection, "\\/.*$^~[]"))
      vim.api.nvim_feedkeys(vim.keycode("N"), "n", false)
    end,
    opts = { noremap = true, silent = true, desc = "Search for selected text" },
  },

  { mode = "n", lhs = "j", rhs = "gj", opts = { desc = "Down (wrap-aware)" } },
  { mode = "n", lhs = "k", rhs = "gk", opts = { desc = "Up (wrap-aware)" } },
  { mode = "n", lhs = "<C-Left>", rhs = "<cmd>vertical resize -2<CR>", opts = { desc = "Narrow window" } },
  { mode = "n", lhs = "<C-Right>", rhs = "<cmd>vertical resize +2<CR>", opts = { desc = "Widen window" } },
  { mode = "n", lhs = "<C-Down>", rhs = "<cmd>resize -2<CR>", opts = { desc = "Shorten window" } },
  { mode = "n", lhs = "<C-Up>", rhs = "<cmd>resize +2<CR>", opts = { desc = "Taller window" } },

  { mode = "v", lhs = "<A-j>", rhs = ":m '>+1<CR>gv=gv", opts = { desc = "Move ↓ (block)" } },
  { mode = "v", lhs = "<A-k>", rhs = ":m '<-2<CR>gv=gv", opts = { desc = "Move ↑ (block)" } },
  { mode = "n", lhs = "<A-J>", rhs = "<cmd>m .+1<CR>==", opts = { desc = "Move ↓ (line)" } },
  { mode = "n", lhs = "<A-K>", rhs = "<cmd>m .-2<CR>==", opts = { desc = "Move ↑ (line)" } },
  { mode = "i", lhs = "<A-J>", rhs = "<Esc><cmd>m .+1<CR>==gi", opts = { desc = "Move ↓ (insert)" } },
  { mode = "i", lhs = "<A-K>", rhs = "<Esc><cmd>m .-2<CR>==gi", opts = { desc = "Move ↑ (insert)" } },

  { mode = { "n", "x", "o" }, lhs = "n", rhs = "'Nn'[v:searchforward]", opts = { expr = true, desc = "Next search result" } },
  { mode = { "n", "x", "o" }, lhs = "N", rhs = "'nN'[v:searchforward]", opts = { expr = true, desc = "Prev search result" } },
  { mode = "n", lhs = "H", rhs = "<cmd>bprevious<CR>", opts = { desc = "Prev buffer" } },
  { mode = "n", lhs = "L", rhs = "<cmd>bnext<CR>", opts = { desc = "Next buffer" } },
  { mode = "n", lhs = "gB", rhs = "<cmd>bprevious<CR>", opts = { desc = "Prev buffer" } },
  { mode = "n", lhs = "gb", rhs = "<cmd>bnext<CR>", opts = { desc = "Next buffer" } },

  { mode = "i", lhs = ",", rhs = ",<C-g>u", opts = { desc = "Comma (& undo-break)" } },
  { mode = "i", lhs = ".", rhs = ".<C-g>u", opts = { desc = "Dot (& undo-break)" } },
  { mode = "i", lhs = ";", rhs = ";<C-g>u", opts = { desc = "Semi (& undo-break)" } },
  { mode = "i", lhs = "<C-BS>", rhs = "<C-w>", opts = { desc = "Backspace word" } },
  { mode = "v", lhs = "<", rhs = "<gv", opts = { desc = "Indent left & keep selection" } },
  { mode = "v", lhs = ">", rhs = ">gv", opts = { desc = "Indent right & keep selection" } },

  { mode = "n", lhs = "<leader>t", action = { interface = "terminal", method = "toggle" }, opts = { desc = "Toggle terminal" } },
  { mode = "n", lhs = "<leader><leader>", action = { interface = "picker", method = "smart" }, opts = { desc = "Smart find files" } },
  { mode = "n", lhs = "<leader>bd", rhs = "<cmd>bdelete<cr>", opts = { desc = "Delete" } },
  { mode = "n", lhs = "<leader>bb", action = { interface = "picker", method = "buffers" }, opts = { desc = "List" } },
  { mode = "n", lhs = "<leader>bl", action = { interface = "picker", method = "buffers" }, opts = { desc = "List" } },
  { mode = "n", lhs = "<leader>b", rhs = "<nop>", opts = { desc = "Buffers" } },
  { mode = "n", lhs = "<leader>/", action = { interface = "picker", method = "grep" }, opts = { desc = "Live grep" } },
  { mode = "n", lhs = "<leader>:", action = { interface = "picker", method = "command_history" }, opts = { desc = "Command history" } },
  { mode = "n", lhs = "<leader>n", action = { interface = "notifier", method = "history" }, opts = { desc = "Notification history" } },
  { mode = "n", lhs = "<leader><esc>", action = { interface = "notifier", method = "hide" }, opts = { desc = "Dismiss notifications" } },
  { mode = "n", lhs = "<leader>e", action = { interface = "explorer", method = "open" }, opts = { desc = "File explorer" } },

  { mode = { "n", "x" }, lhs = "<leader>f", rhs = "<nop>", opts = { desc = "Find" } },
  { mode = "n", lhs = "<leader>fD", action = { interface = "picker", method = "diagnostics_buffer" }, opts = { desc = "Buffer diagnostics" } },
  { mode = "n", lhs = "<leader>fd", action = { interface = "picker", method = "diagnostics" }, opts = { desc = "Diagnostics" } },
  { mode = "n", lhs = "<leader>fb", action = { interface = "picker", method = "buffers" }, opts = { desc = "Buffers" } },
  { mode = "n", lhs = "<leader>ff", action = { interface = "picker", method = "files" }, opts = { desc = "Find files" } },
  { mode = "n", lhs = "<leader>fg", action = { interface = "picker", method = "git_files" }, opts = { desc = "Git files" } },
  { mode = "n", lhs = "<leader>fl", action = { interface = "picker", method = "lines" }, opts = { desc = "Buffer lines" } },
  { mode = "n", lhs = "<leader>fm", action = { interface = "picker", method = "marks" }, opts = { desc = "Marks" } },
  { mode = "n", lhs = "<leader>fp", action = { interface = "picker", method = "projects" }, opts = { desc = "Projects" } },
  { mode = "n", lhs = "<leader>fR", action = { interface = "picker", method = "rename_file" }, opts = { desc = "Rename file" } },
  { mode = "n", lhs = "<leader>fr", action = { interface = "picker", method = "recent" }, opts = { desc = "Recent files" } },
  { mode = { "n", "x" }, lhs = "<leader>fW", action = { interface = "picker", method = "grep_word" }, opts = { desc = "Search selection" } },
  { mode = "n", lhs = "<leader>fw", action = { interface = "picker", method = "grep" }, opts = { desc = "Word" } },

  { mode = "n", lhs = "<leader>s", rhs = "<nop>", opts = { desc = "Search" } },
  { mode = "n", lhs = "<leader>sa", action = { interface = "picker", method = "autocmds" }, opts = { desc = "Autocommands" } },
  { mode = "n", lhs = "<leader>sc", action = { interface = "picker", method = "commands" }, opts = { desc = "Commands" } },
  { mode = "n", lhs = "<leader>sH", action = { interface = "picker", method = "highlights" }, opts = { desc = "Highlights" } },
  { mode = "n", lhs = "<leader>sh", action = { interface = "picker", method = "help" }, opts = { desc = "Help" } },
  { mode = "n", lhs = "<leader>si", action = { interface = "picker", method = "icons" }, opts = { desc = "Icons" } },
  { mode = "n", lhs = "<leader>sk", action = { interface = "picker", method = "keymaps" }, opts = { desc = "Keymaps" } },
  { mode = "n", lhs = "<leader>sm", action = { interface = "picker", method = "man" }, opts = { desc = "Manpages" } },

  { mode = "n", lhs = "<leader>g", rhs = "<nop>", opts = { desc = "Git" } },
  { mode = "n", lhs = "<leader>gs", action = { interface = "picker", method = "git_status" }, opts = { desc = "Git status" } },
  { mode = "n", lhs = "<leader>gb", action = { interface = "picker", method = "git_branches" }, opts = { desc = "Git branches" } },
  { mode = "n", lhs = "<leader>gl", action = { interface = "picker", method = "git_log" }, opts = { desc = "Git log" } },
  { mode = "n", lhs = "<leader>gL", action = { interface = "picker", method = "git_log_line" }, opts = { desc = "Git log line" } },
  { mode = "n", lhs = "<leader>gd", action = { interface = "picker", method = "git_diff" }, opts = { desc = "Git diff" } },
  { mode = "n", lhs = "<leader>gS", action = { interface = "picker", method = "git_stash" }, opts = { desc = "Git stash" } },
  { mode = "n", lhs = "<leader>gi", action = { interface = "picker", method = "gh_issue" }, opts = { desc = "GitHub issues" } },
  { mode = "n", lhs = "<leader>gI", action = { interface = "picker", method = "gh_issue", args = { state = "all" } }, opts = { desc = "All GitHub issues" } },
  { mode = "n", lhs = "<leader>gp", action = { interface = "picker", method = "gh_pr" }, opts = { desc = "GitHub PRs" } },
  { mode = "n", lhs = "<leader>gP", action = { interface = "picker", method = "gh_pr", args = { state = "all" } }, opts = { desc = "All GitHub PRs" } },

  { mode = "n", lhs = "<leader>v", rhs = "<nop>", opts = { desc = "Vim" } },
  { mode = "n", lhs = "<leader>vd", action = { interface = "dashboard", method = "open" }, opts = { desc = "Dashboard" } },
  { mode = "n", lhs = "<leader>vv", rhs = "<cmd>cd " .. vim.fn.stdpath("config") .. " | e init.lua <CR>", opts = { desc = "Edit config" } },
  { mode = "n", lhs = "<leader>vc", rhs = "<Plug>(phenix-color-preview-toggle)", opts = { desc = "Toggle color preview", remap = true } },
  { mode = "n", lhs = "<leader>vs", action = { interface = "session", method = "pick" }, opts = { desc = "Sessions" } },

  { mode = "n", lhs = "<leader>q", rhs = "<nop>", opts = { desc = "Quickfix" } },
  { mode = "n", lhs = "<leader>qj", rhs = "<cmd>cnext<CR>", opts = { desc = "Next quickfix", silent = true } },
  { mode = "n", lhs = "<leader>qk", rhs = "<cmd>cprev<CR>", opts = { desc = "Prev quickfix", silent = true } },
  { mode = "n", lhs = "<leader>l", rhs = "<nop>", opts = { desc = "Lsp" } },

  { mode = "n", lhs = "gl", action = { interface = "lsp", method = "diagnostic_open" }, opts = { silent = true, desc = "Open diagnostics" } },
  { mode = "n", lhs = "<space>lk", action = { interface = "lsp", method = "diagnostic_prev" }, opts = { silent = true, desc = "Go to prev diagnostic" } },
  { mode = "n", lhs = "<space>lj", action = { interface = "lsp", method = "diagnostic_next" }, opts = { silent = true, desc = "Go to next diagnostic" } },
  { mode = "n", lhs = "gra", action = { interface = "lsp", method = "code_action" }, opts = { silent = true, desc = "Code action", lsp = { method = "textDocument/codeAction" } } },
  { mode = "n", lhs = "gD", action = { interface = "lsp", method = "declaration" }, opts = { silent = true, desc = "Go to declaration", lsp = { method = "textDocument/declaration" } } },
  { mode = "n", lhs = "gd", action = { interface = "picker", method = "lsp_definitions" }, opts = { silent = true, desc = "Go to definition", lsp = { method = "textDocument/definition" } } },
  { mode = "n", lhs = "K", action = { interface = "lsp", method = "hover" }, opts = { silent = true, desc = "Show hover information", lsp = { method = "textDocument/hover" } } },
  { mode = "n", lhs = "gri", action = { interface = "picker", method = "lsp_implementations" }, opts = { silent = true, desc = "Go to implementation", lsp = { method = "textDocument/implementation" } } },
  { mode = "n", lhs = "<space>li", action = { interface = "lsp", method = "inlay_toggle" }, opts = { silent = true, desc = "Toggle inlay hints", lsp = { method = "textDocument/inlayHint" } } },
  { mode = "n", lhs = "grr", action = { interface = "picker", method = "lsp_references" }, opts = { silent = true, desc = "Find references", lsp = { method = "textDocument/references" } } },
  { mode = "n", lhs = "grn", action = { interface = "lsp", method = "rename" }, opts = { silent = true, desc = "Rename symbol", lsp = { method = "textDocument/rename" } } },
  { mode = "n", lhs = "grd", action = { interface = "picker", method = "lsp_type_definitions" }, opts = { silent = true, desc = "Go to type definition", lsp = { method = "textDocument/typeDefinition" } } },
  { mode = "n", lhs = "<leader>lw", rhs = "<nop>", opts = { desc = "Workspace", lsp = { method = "workspace/workspaceFolders" } } },
  { mode = "n", lhs = "<space>lwa", action = { interface = "lsp", method = "workspace_add" }, opts = { silent = true, desc = "Add folder", lsp = { method = "workspace/workspaceFolders" } } },
  { mode = "n", lhs = "<space>lwr", action = { interface = "lsp", method = "workspace_remove" }, opts = { silent = true, desc = "Remove folder", lsp = { method = "workspace/workspaceFolders" } } },
  { mode = "n", lhs = "<space>lwl", action = { interface = "lsp", method = "workspace_list" }, opts = { silent = true, desc = "List folders", lsp = { method = "workspace/workspaceFolders" } } },
}

return {
  leader = " ",
  maps = maps,
}
