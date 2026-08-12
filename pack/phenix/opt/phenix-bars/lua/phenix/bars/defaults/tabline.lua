local devicons = require("nvim-web-devicons")
local statusline = require("phenix.bars.defaults.statusline")

local M = {}
local cache = {}
local generated_highlights = {}

local function color(group, field)
  return vim.api.nvim_get_hl(0, { name = group, link = false })[field]
end

local function icon_highlight(background_group, foreground_group)
  local bg = color(background_group, "bg")
  local fg = color(foreground_group, "fg")
  local key = string.format("PhenixTabIcon_%s_%s", tostring(bg or "none"), tostring(fg or "none"))
  if not generated_highlights[key] then
    vim.api.nvim_set_hl(0, key, { bg = bg, fg = fg })
    generated_highlights[key] = true
  end
  return key
end

function M.init_cache()
  cache = {}
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.buflisted(buf) ~= 0 and vim.bo[buf].filetype ~= "qf" then
      local name = vim.fn.fnamemodify(vim.fn.bufname(buf), ":t")
      if name == "" then
        name = "[No Name]"
      end
      local icon, icon_hl = devicons.get_icon(name, vim.fn.fnamemodify(name, ":e"), { default = true })
      cache[buf] = {
        current = current == buf,
        name = name,
        icon = icon or "",
        icon_hl = icon_hl or "Normal",
      }
    end
  end
end

local function sign(name, fallback)
  local defined = vim.fn.sign_getdefined(name)[1] or {}
  defined.text = defined.text ~= "" and defined.text or fallback
  return defined
end

function M.buffer(buf)
  local item = cache[buf]
  if not item then
    return {}
  end
  local base = item.current and "TblCurrentBuffer" or "TblBuffer"
  return {
    before = " ",
    hl = base,
    children = {
      { hl = icon_highlight(base, item.icon_hl), text = item.icon },
      {
        before = " ",
        hl = item.current and "TblCurrentFilename" or "TblFilename",
        text = item.name,
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
              local defined = sign(definition.sign, definition.fallback)
              parts[#parts + 1] = {
                text = string.format("%d %s", count, vim.fn.strcharpart(defined.text, 0, 1)),
                hl = (item.current and "TblCurrent" or "Tbl") .. definition.suffix,
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
        hl = item.current and "TblCurrentCloseButton" or "TblCloseButton",
        on_click = "buffer_close",
        on_click_param = tostring(buf),
      },
    },
  }
end

M.buffers = {
  hl = "TblSectionC",
  child_sep = " ",
  children = {
    { text = "Buffers", hl = function() return statusline.mode_info().hl end, before = " ", after = " " },
    {
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
    before = " ",
    hl = current and "TblCurrentTab" or "TblTab",
    children = {
      { text = tostring(vim.api.nvim_tabpage_get_number(tab)), on_click = "tab_focus", on_click_param = tostring(tab) },
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
    { text = "Tabs", hl = function() return statusline.mode_info().hl end, before = " ", after = " " },
  },
}

M.whole = { children = { M.buffers, { text = "%=" }, M.tabs } }

return M
