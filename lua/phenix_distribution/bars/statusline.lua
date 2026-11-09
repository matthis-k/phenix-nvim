local devicons = require("nvim-web-devicons")
local diagnostic_signs = require("constants").signs.diagnostics

local M = {}

local modes = {
  n = { text = "NORMAL", hl = "StlModeNormal" },
  no = { text = "O‑PENDING", hl = "StlModeNormal" },
  nov = { text = "O‑PENDING", hl = "StlModeNormal" },
  noV = { text = "O‑PENDING", hl = "StlModeNormal" },
  ["\22"] = { text = "V‑BLOCK", hl = "StlModeVisual" },
  niI = { text = "NORMAL", hl = "StlModeNormal" },
  niR = { text = "NORMAL", hl = "StlModeNormal" },
  niV = { text = "NORMAL", hl = "StlModeNormal" },
  v = { text = "VISUAL", hl = "StlModeVisual" },
  vs = { text = "VISUAL", hl = "StlModeVisual" },
  V = { text = "V‑LINE", hl = "StlModeVisual" },
  Vs = { text = "V‑LINE", hl = "StlModeVisual" },
  s = { text = "SELECT", hl = "StlModeVisual" },
  S = { text = "S‑LINE", hl = "StlModeVisual" },
  ["\19"] = { text = "S‑BLOCK", hl = "StlModeVisual" },
  i = { text = "INSERT", hl = "StlModeInsert" },
  ic = { text = "INSERT", hl = "StlModeInsert" },
  ix = { text = "INSERT", hl = "StlModeInsert" },
  R = { text = "REPLACE", hl = "StlModeReplace" },
  Rc = { text = "REPLACE", hl = "StlModeReplace" },
  Rx = { text = "REPLACE", hl = "StlModeReplace" },
  Rv = { text = "V‑REPLACE", hl = "StlModeReplace" },
  Rvc = { text = "V‑REPLACE", hl = "StlModeReplace" },
  Rvx = { text = "V‑REPLACE", hl = "StlModeReplace" },
  c = { text = "COMMAND", hl = "StlModeCommand" },
  cv = { text = "EX", hl = "StlModeCommand" },
  ce = { text = "EX", hl = "StlModeCommand" },
  r = { text = "REPLACE", hl = "StlModeReplace" },
  rm = { text = "MORE", hl = "StlModeReplace" },
  ["r?"] = { text = "CONFIRM", hl = "StlModeReplace" },
  ["!"] = { text = "SHELL", hl = "StlModeCommand" },
  t = { text = "T‑INSERT", hl = "StlModeTerminalInsert" },
  nt = { text = "T‑NORMAL", hl = "StlModeTerminalNormal" },
}

local buffers = {}

local function target_buf(ctx)
  return (ctx and ctx.buf) or vim.api.nvim_get_current_buf()
end

local function target_win(ctx)
  return (ctx and ctx.win) or vim.api.nvim_get_current_win()
end

function M.init_cache()
  buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local file = vim.api.nvim_buf_get_name(buf)
      if file == "" then
        file = "[No Name]"
      end
      local short = file
      if #file > 70 and file ~= "[No Name]" then
        local name = vim.fn.fnamemodify(file, ":t")
        local parts = vim.split(vim.fn.fnamemodify(file, ":h"), "/")
        if #parts > 3 then
          parts = { parts[1], "...", parts[#parts - 1], parts[#parts] }
        end
        for index, part in ipairs(parts) do
          if #part > 5 then
            parts[index] = part:sub(1, 5) .. "…"
          end
        end
        short = table.concat(parts, "/") .. "/" .. name
      end
      local icon, icon_hl = devicons.get_icon(file, vim.fn.fnamemodify(file, ":e"), { default = true })
      buffers[buf] = { icon = icon or "", icon_hl = icon_hl or "Normal", filepath = short }
    end
  end
end

local function memo(ctx, key, compute)
  if ctx and ctx.memo then
    return ctx.memo(key, compute)
  end
  return compute()
end

function M.mode_info(ctx)
  return memo(ctx, "mode", function()
    return modes[vim.api.nvim_get_mode().mode] or { text = "UNKNOWN", hl = "StlModeNormal" }
  end)
end

local function git()
  return require("phenix.features.git")
end

local function git_status(ctx)
  return memo(ctx, "git_status", function()
    local implementation = git()
    return implementation and implementation.status(ctx and ctx.buf or vim.api.nvim_get_current_buf()) or nil
  end)
end

local function git_remote(ctx)
  return memo(ctx, "git_remote", function()
    local implementation = git()
    return implementation and implementation.remote(ctx and ctx.buf or vim.api.nvim_get_current_buf()) or nil
  end)
end

M.mode = {
  before = " ",
  after = " ",
  hl = function(ctx)
    return M.mode_info(ctx).hl
  end,
  text = function(ctx)
    return M.mode_info(ctx).text
  end,
}

local function diff(key, symbol, hl)
  return {
    hl = hl,
    text = function(ctx)
      local status = git_status(ctx)
      local count = status and status[key]
      return count and count > 0 and (symbol .. tostring(count)) or ""
    end,
  }
end

local git_part = {
  child_sep = " ",
  children = {
    {
      hl = "StlGitBranch",
      text = function(ctx)
        return git_status(ctx) and "" or ""
      end,
    },
    {
      hl = "StlGitBranch",
      text = function(ctx)
        local status = git_status(ctx)
        return status and status.head or ""
      end,
    },
    {
      hl = "StlGitRemoteAhead",
      text = function(ctx)
        local remote = git_remote(ctx)
        return remote and remote.ahead and remote.ahead > 0 and ("↑" .. remote.ahead) or ""
      end,
    },
    {
      hl = "StlGitRemoteBehind",
      text = function(ctx)
        local remote = git_remote(ctx)
        return remote and remote.behind and remote.behind > 0 and ("↓" .. remote.behind) or ""
      end,
    },
    {
      hl = "StlGitBranch",
      text = function(ctx)
        local remote = git_remote(ctx)
        return remote and not remote.error and remote.ahead == 0 and remote.behind == 0 and "✓" or ""
      end,
    },
    diff("added", "+", "StlGitAdded"),
    diff("changed", "~", "StlGitChanged"),
    diff("removed", "-", "StlGitDeleted"),
  },
}

M.filename = {
  child_sep = " ",
  children = function(ctx)
    local item = buffers[ctx and ctx.buf or vim.api.nvim_get_current_buf()] or {}
    return {
      { hl = item.icon_hl, text = item.icon },
      { hl = "StlSectionB", text = item.filepath },
    }
  end,
}

M.modified = {
  text = function(ctx)
    return vim.bo[target_buf(ctx)].modified and "modified" or ""
  end,
}
M.readonly = {
  hl = "@error",
  text = function(ctx)
    return vim.bo[target_buf(ctx)].readonly and "readonly" or ""
  end,
}

local function phenix_status(ctx)
  return memo(ctx, "phenix_status", function()
    local ok, status_api = pcall(require, "phenix_nvim.status")
    if not ok or type(status_api.get) ~= "function" then
      return nil
    end
    local status_ok, status = pcall(status_api.get)
    return status_ok and type(status) == "table" and status or nil
  end)
end

M.phenix = {
  hl = function(ctx)
    local status = phenix_status(ctx)
    local execution_state = status and status.execution_state or nil
    if execution_state == "running" or execution_state == "pending" then
      return "DiagnosticWarn"
    end
    if execution_state == "failed" or status and status.error then
      return "DiagnosticError"
    end
    return "DiagnosticOk"
  end,
  text = function(ctx)
    local status = phenix_status(ctx)
    if status == nil or status.session_id == nil then
      return ""
    end
    local execution_state = status.execution_state
    if execution_state == "running" or execution_state == "pending" then
      return "● Phenix running"
    end
    if execution_state == "failed" then
      return "✗ Phenix failed"
    end
    return "✓ Phenix settled"
  end,
}

local function diagnostic(severity)
  local defined = diagnostic_signs[severity] or { text = "?", texthl = "DiagnosticDefault" }
  return {
    hl = defined.texthl,
    text = function(ctx)
      local count = #vim.diagnostic.get(ctx and ctx.buf or 0, { severity = severity })
      return count > 0 and string.format("%d %s", count, vim.fn.strcharpart(defined.text, 0, 1)) or ""
    end,
  }
end

local diagnostics = {
  child_sep = " ",
  children = {
    diagnostic(vim.diagnostic.severity.ERROR),
    diagnostic(vim.diagnostic.severity.WARN),
    diagnostic(vim.diagnostic.severity.INFO),
    diagnostic(vim.diagnostic.severity.HINT),
  },
}

M.whole = {
  hl = "StlSectionC",
  children = {
    M.mode,
    {
      hl = "StlSectionB",
      before = " ",
      after = " ",
      child_sep = " ",
      children = {
        git_part,
        M.filename,
        { before = "[", after = "]", child_sep = " ", children = { M.modified, M.readonly } },
        M.phenix,
        diagnostics,
      },
    },
    { raw = "%=" },
    {
      hl = "StlSectionB",
      before = " ",
      after = " ",
      child_sep = " ",
      children = {
        { text = function(ctx)
          local ft = vim.bo[target_buf(ctx)].filetype
          return ft ~= "" and ft or "none"
        end },
        { text = function(ctx)
          local encoding = vim.bo[target_buf(ctx)].fileencoding
          return encoding ~= "" and encoding or "utf-8"
        end },
      },
    },
    {
      before = " ",
      after = " ",
      hl = function(ctx)
        return M.mode_info(ctx).hl
      end,
      text = function(ctx)
        local cursor = vim.api.nvim_win_get_cursor(target_win(ctx))
        return string.format("%03d:%02d", cursor[1], cursor[2] + 1)
      end,
    },
  },
}

return M
