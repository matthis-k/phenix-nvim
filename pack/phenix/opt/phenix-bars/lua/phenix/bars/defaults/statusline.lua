local Frontend = require("phenix.frontend")
local devicons = require("nvim-web-devicons")

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

function M.mode_info()
  return modes[vim.api.nvim_get_mode().mode] or { text = "UNKNOWN", hl = "StlModeNormal" }
end

local function git()
  local ok, implementation = pcall(Frontend.require_api, "git")
  return ok and implementation or nil
end

local function git_status()
  local implementation = git()
  return implementation and implementation.status(vim.api.nvim_get_current_buf()) or nil
end

local function git_remote()
  local implementation = git()
  return implementation and implementation.remote(vim.api.nvim_get_current_buf()) or nil
end

local function sign(name, fallback)
  local value = vim.fn.sign_getdefined(name)[1] or {}
  value.text = value.text ~= "" and value.text or fallback
  value.texthl = value.texthl ~= "" and value.texthl or "DiagnosticDefault"
  return value
end

M.mode = {
  before = " ",
  after = " ",
  hl = function()
    return M.mode_info().hl
  end,
  text = function()
    return M.mode_info().text
  end,
}

local function diff(key, symbol, hl)
  return {
    hl = hl,
    text = function()
      local status = git_status()
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
      text = function()
        return git_status() and "" or ""
      end,
    },
    {
      hl = "StlGitBranch",
      text = function()
        local status = git_status()
        return status and status.head or ""
      end,
    },
    {
      hl = "StlGitRemoteAhead",
      text = function()
        local remote = git_remote()
        return remote and remote.ahead and remote.ahead > 0 and ("↑" .. remote.ahead) or ""
      end,
    },
    {
      hl = "StlGitRemoteBehind",
      text = function()
        local remote = git_remote()
        return remote and remote.behind and remote.behind > 0 and ("↓" .. remote.behind) or ""
      end,
    },
    {
      hl = "StlGitBranch",
      text = function()
        local remote = git_remote()
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
  children = function()
    local item = buffers[vim.api.nvim_get_current_buf()] or {}
    return {
      { hl = item.icon_hl, text = item.icon },
      { hl = "StlSectionB", text = item.filepath },
    }
  end,
}

M.modified = { text = function() return vim.bo.modified and "modified" or "" end }
M.readonly = { hl = "@error", text = function() return vim.bo.readonly and "readonly" or "" end }

local diagnostic_names = {
  [vim.diagnostic.severity.ERROR] = "DiagnosticSignError",
  [vim.diagnostic.severity.WARN] = "DiagnosticSignWarn",
  [vim.diagnostic.severity.INFO] = "DiagnosticSignInfo",
  [vim.diagnostic.severity.HINT] = "DiagnosticSignHint",
}

local function diagnostic(severity)
  local defined = sign(diagnostic_names[severity], "?")
  return {
    hl = defined.texthl,
    text = function()
      local count = #vim.diagnostic.get(0, { severity = severity })
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
        diagnostics,
      },
    },
    { text = "%=" },
    {
      hl = "StlSectionB",
      before = " ",
      after = " ",
      child_sep = " ",
      children = {
        { text = function() return vim.bo.filetype ~= "" and vim.bo.filetype or "none" end },
        { text = function() return vim.bo.fileencoding ~= "" and vim.bo.fileencoding or "utf-8" end },
      },
    },
    {
      before = " ",
      after = " ",
      hl = function()
        return M.mode_info().hl
      end,
      text = function()
        return string.format("%03d:%02d", vim.fn.line("."), vim.fn.col("."))
      end,
    },
  },
}

return M
