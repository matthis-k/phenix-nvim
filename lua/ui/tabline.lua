local util = require("utils")
local devicons = require("nvim-web-devicons")

local M = {}
local cache = {}

function M.init_cache()
  cache = {}
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.buflisted(buf) ~= 0 and vim.bo[buf].filetype ~= "qf" then
      local fname = vim.fn.fnamemodify(vim.fn.bufname(buf), ":t")
      if fname == "" then
        fname = "[No Name]"
      end
      local icon, icon_hl = devicons.get_icon(fname, vim.fn.fnamemodify(fname, ":e"), { default = true })
      cache[buf] = {
        cur = current == buf,
        fname = fname,
        icon = icon or "",
        icon_hl = icon_hl or "Normal",
      }
    end
  end
end

local function get_sign(name, fallback)
  local sign = vim.fn.sign_getdefined(name)[1] or {}
  sign.text = sign.text ~= "" and sign.text or fallback
  return sign
end

function M.buffer(buf)
  local item = cache[buf]
  if not item then
    return {}
  end
  local buffer_hl = item.cur and "TblCurrentBuffer" or "TblBuffer"
  return {
    name = "buffer",
    before = " ",
    hl = buffer_hl,
    children = {
      {
        hl = util.auto_hl({
          bg = util.to_hex(util.highlights[buffer_hl].bg),
          fg = util.to_hex(util.highlights[item.icon_hl].fg),
        }),
        text = item.icon,
      },
      {
        before = " ",
        hl = item.cur and "TblCurrentFilename" or "TblFilename",
        text = item.fname,
        on_click = "buffer_focus",
        on_click_param = tostring(buf),
      },
      {
        before = " ",
        child_sep = " ",
        children = function()
          local parts = {}
          local severities = {
            { severity = vim.diagnostic.severity.ERROR, sign = "DiagnosticSignError", fallback = "E", suffix = "DiagnosticError" },
            { severity = vim.diagnostic.severity.WARN, sign = "DiagnosticSignWarn", fallback = "W", suffix = "DiagnosticWarn" },
            { severity = vim.diagnostic.severity.INFO, sign = "DiagnosticSignInfo", fallback = "I", suffix = "DiagnosticInfo" },
            { severity = vim.diagnostic.severity.HINT, sign = "DiagnosticSignHint", fallback = "H", suffix = "DiagnosticHint" },
          }
          for _, definition in ipairs(severities) do
            local count = #vim.diagnostic.get(buf, { severity = definition.severity })
            if count > 0 then
              local sign = get_sign(definition.sign, definition.fallback)
              parts[#parts + 1] = {
                text = string.format("%d %s", count, util.utf8sub(sign.text, 1, 1)),
                hl = (item.cur and "TblCurrent" or "Tbl") .. definition.suffix,
              }
            end
          end
          return parts
        end,
      },
      {
        text = "󰖭",
        before = " ",
        after = " ",
        hl = item.cur and "TblCurrentCloseButton" or "TblCloseButton",
        on_click = "buffer_close",
        on_click_param = tostring(buf),
      },
    },
  }
end

M.buffers = {
  name = "buffers",
  hl = "TblSectionC",
  child_sep = " ",
  children = {
    {
      text = "Buffers",
      hl = function()
        return require("ui.statusline").mode_info().hl
      end,
      before = " ",
      after = " ",
    },
    {
      hl = "TblSectionC",
      children = function()
        local parts = {}
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if cache[buf] then
            parts[#parts + 1] = M.buffer(buf)
          end
        end
        return parts
      end,
      child_sep = " ",
    },
  },
}

function M.tab(tab)
  local current = vim.api.nvim_get_current_tabpage() == tab
  return {
    name = "tab",
    before = " ",
    hl = current and "TblCurrentTab" or "TblTab",
    children = {
      {
        text = tostring(vim.api.nvim_tabpage_get_number(tab)),
        on_click = "tab_focus",
        on_click_param = tostring(tab),
      },
      {
        text = "󰖭",
        before = " ",
        after = " ",
        hl = current and "TblCurrentTabCloseButton" or "TblTabCloseButton",
        on_click = "tab_close",
        on_click_param = tostring(tab),
      },
    },
  }
end

M.tabs = {
  name = "tabs",
  hl = "TblSectionC",
  child_sep = " ",
  children = {
    {
      children = function()
        local parts = {}
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
          parts[#parts + 1] = M.tab(tab)
        end
        return parts
      end,
      child_sep = " ",
    },
    {
      text = "Tabs",
      hl = function()
        return require("ui.statusline").mode_info().hl
      end,
      before = " ",
      after = " ",
    },
  },
}

M.whole = {
  children = {
    M.buffers,
    { text = "%=" },
    M.tabs,
  },
}

return M
