local M = {}

local UI = {}
UI.__index = UI

local transcript_namespace = vim.api.nvim_create_namespace("phenix-transcript")
local ui_by_buffer = setmetatable({}, { __mode = "v" })

local DEFAULT_RENDER_INTERVAL_MS = 33
local DEFAULT_MARKVIEW_RENDER_INTERVAL_MS = 150
local FOLD_PREVIEW_LIMIT = 96

local function configure_buffer(buffer, filetype, modifiable, buftype)
  vim.api.nvim_set_option_value("buftype", buftype or "nofile", { buf = buffer })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buffer })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buffer })
  vim.api.nvim_set_option_value("filetype", filetype, { buf = buffer })
  vim.api.nvim_set_option_value("modifiable", modifiable, { buf = buffer })
end

local function split_text(text)
  return vim.split(text or "", "\n", { plain = true })
end

local function content_text(content)
  if type(content) ~= "table" then
    return ""
  end
  if content.type == "text" then
    return content.text or ""
  end
  return ""
end

local function first_non_nil(...)
  for index = 1, select("#", ...) do
    local value = select(index, ...)
    if value ~= nil then
      return value
    end
  end
  return nil
end

local function append_text(lines, text)
  vim.list_extend(lines, split_text(text))
end

local function append_fence(lines, language, text)
  table.insert(lines, "```" .. language)
  append_text(lines, text)
  table.insert(lines, "```")
end

local function json_scalar(value)
  local ok, encoded = pcall(vim.json.encode, value)
  return ok and encoded or vim.inspect(value)
end

local function sorted_keys(value)
  local keys = {}
  for key in pairs(value) do
    table.insert(keys, key)
  end
  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)
  return keys
end

local function pretty_json(value, depth)
  depth = depth or 0
  if type(value) ~= "table" then
    return json_scalar(value)
  end

  local indent = string.rep("  ", depth)
  local child_indent = string.rep("  ", depth + 1)
  if vim.islist(value) then
    if #value == 0 then
      return "[]"
    end
    local rendered = { "[" }
    for index, item in ipairs(value) do
      local suffix = index < #value and "," or ""
      table.insert(rendered, child_indent .. pretty_json(item, depth + 1) .. suffix)
    end
    table.insert(rendered, indent .. "]")
    return table.concat(rendered, "\n")
  end

  local keys = sorted_keys(value)
  if #keys == 0 then
    return "{}"
  end
  local rendered = { "{" }
  for index, key in ipairs(keys) do
    local suffix = index < #keys and "," or ""
    table.insert(
      rendered,
      child_indent .. json_scalar(tostring(key)) .. ": " .. pretty_json(value[key], depth + 1) .. suffix
    )
  end
  table.insert(rendered, indent .. "}")
  return table.concat(rendered, "\n")
end

local function decode_structured_string(value)
  if type(value) ~= "string" then
    return value, type(value) == "table"
  end
  local ok, decoded = pcall(vim.json.decode, value)
  if ok and type(decoded) == "table" then
    return decoded, true
  end
  return value, false
end

local function multiline_string(value)
  return type(value) == "string" and value:find("\n", 1, true) ~= nil
end

local function append_tool_value(lines, value)
  value = first_non_nil(value, "")
  local normalized, structured = decode_structured_string(value)

  if type(normalized) == "table" and not vim.islist(normalized) then
    local keys = sorted_keys(normalized)
    if #keys == 0 then
      append_fence(lines, "json", "{}")
      return
    end

    for index, key in ipairs(keys) do
      if index > 1 then
        table.insert(lines, "")
      end
      local item = normalized[key]
      local label = "`" .. tostring(key) .. "`"
      if multiline_string(item) then
        table.insert(lines, label .. ":")
        append_fence(lines, "text", item)
      elseif type(item) == "table" then
        table.insert(lines, label .. ":")
        append_fence(lines, "json", pretty_json(item))
      else
        table.insert(lines, label .. ": " .. json_scalar(item))
      end
    end
    return
  end

  if structured or type(normalized) ~= "string" then
    append_fence(lines, "json", pretty_json(normalized))
  elseif multiline_string(normalized) then
    append_fence(lines, "text", normalized)
  else
    append_fence(lines, "text", normalized)
  end
end

local function collapse_preview(text)
  local collapsed = vim.trim((text or ""):gsub("%s+", " "))
  if #collapsed > FOLD_PREVIEW_LIMIT then
    return collapsed:sub(1, FOLD_PREVIEW_LIMIT - 1) .. "…"
  end
  return collapsed
end

local function preview_scalar(value)
  if type(value) == "string" then
    local first_line = value:match("([^\n]*)") or value
    return collapse_preview(first_line)
  end
  if type(value) == "table" then
    return vim.islist(value) and "[…]" or "{…}"
  end
  return collapse_preview(json_scalar(value))
end

local function tool_input_preview(value)
  local normalized = decode_structured_string(value)
  if type(normalized) ~= "table" or vim.islist(normalized) then
    return preview_scalar(normalized)
  end

  local parts = {}
  for _, key in ipairs(sorted_keys(normalized)) do
    table.insert(parts, tostring(key) .. "=" .. preview_scalar(normalized[key]))
    if #parts == 2 then
      break
    end
  end
  return collapse_preview(table.concat(parts, " · "))
end

local function tool_output_text(value)
  if value == nil then
    return nil
  end
  if type(value) == "table" then
    if type(value.summary) == "string" then
      return value.summary
    end
    if type(value.output) == "string" then
      return value.output
    end
  end
  if type(value) == "string" then
    return value
  end
  return pretty_json(value)
end

local function define_highlights()
  local links = {
    PhenixTranscriptUser = "Title",
    PhenixTranscriptAssistant = "Function",
    PhenixTranscriptThinking = "Comment",
    PhenixTranscriptTool = "Special",
    PhenixTranscriptSystem = "Statement",
    PhenixTranscriptError = "DiagnosticError",
  }
  for name, link in pairs(links) do
    pcall(vim.api.nvim_set_hl, 0, name, { default = true, link = link })
  end
end

local function capture_position(window, buffer)
  if not window or not vim.api.nvim_win_is_valid(window) or not vim.api.nvim_buf_is_valid(buffer) then
    return nil
  end

  local line_count = math.max(vim.api.nvim_buf_line_count(buffer), 1)
  return vim.api.nvim_win_call(window, function()
    local cursor = vim.api.nvim_win_get_cursor(window)
    return {
      cursor = cursor,
      view = vim.fn.winsaveview(),
      at_last_line = cursor[1] == line_count,
    }
  end)
end

local function line_length(buffer, line)
  local value = vim.api.nvim_buf_get_lines(buffer, line - 1, line, false)[1] or ""
  return #value
end

local function restore_position(window, buffer, position)
  if not position or not window or not vim.api.nvim_win_is_valid(window) or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end

  local line_count = math.max(vim.api.nvim_buf_line_count(buffer), 1)
  vim.api.nvim_win_call(window, function()
    if position.at_last_line then
      local column = math.min(position.cursor[2] or 0, line_length(buffer, line_count))
      vim.api.nvim_win_set_cursor(window, { line_count, column })
      vim.cmd("silent! normal! zb")
      return
    end

    local line = math.min(math.max(position.cursor[1] or 1, 1), line_count)
    local view = vim.deepcopy(position.view or {})
    view.lnum = line
    view.col = math.min(position.cursor[2] or 0, line_length(buffer, line))
    vim.fn.winrestview(view)
  end)
end

local function replace_changed_lines(buffer, lines)
  local current = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local prefix = 0
  local shared = math.min(#current, #lines)
  while prefix < shared and current[prefix + 1] == lines[prefix + 1] do
    prefix = prefix + 1
  end

  local old_tail = #current
  local new_tail = #lines
  while old_tail > prefix and new_tail > prefix and current[old_tail] == lines[new_tail] do
    old_tail = old_tail - 1
    new_tail = new_tail - 1
  end

  if prefix == #current and prefix == #lines then
    return false
  end

  local replacement = {}
  for index = prefix + 1, new_tail do
    table.insert(replacement, lines[index])
  end
  vim.api.nvim_buf_set_lines(buffer, prefix, old_tail, false, replacement)
  return true
end

local function load_markview()
  local ok, markview = pcall(require, "markview")
  if ok and type(markview) == "table" and type(markview.render) == "function" then
    return markview
  end
  return nil
end

function M.foldtext()
  local ui = ui_by_buffer[vim.api.nvim_get_current_buf()]
  if not ui then
    return vim.fn.foldtext()
  end
  local preview = ui.fold_previews[vim.v.foldstart]
  if not preview then
    return vim.fn.foldtext()
  end
  return preview
end

function M.new(options)
  options = options or {}
  define_highlights()

  local transcript_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(transcript_buffer, "phenix://transcript/" .. tostring(transcript_buffer))
  configure_buffer(transcript_buffer, "markdown", false)
  pcall(vim.treesitter.start, transcript_buffer, "markdown")

  local input_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(input_buffer, "phenix://prompt/" .. tostring(input_buffer))
  configure_buffer(input_buffer, "text", true, "acwrite")
  vim.api.nvim_buf_set_lines(input_buffer, 0, -1, false, { "" })
  vim.api.nvim_set_option_value("modified", false, { buf = input_buffer })

  local ui = setmetatable({
    transcript_buffer = transcript_buffer,
    input_buffer = input_buffer,
    transcript_window = nil,
    input_window = nil,
    width = options.width or 48,
    input_height = options.input_height or 4,
    render_interval = options.render_interval or DEFAULT_RENDER_INTERVAL_MS,
    render_scheduled = false,
    render_generation = 0,
    render_count = 0,
    markview = load_markview(),
    markview_render_interval = options.markview_render_interval or DEFAULT_MARKVIEW_RENDER_INTERVAL_MS,
    markview_render_scheduled = false,
    markview_render_generation = 0,
    markview_render_count = 0,
    window_group_closing = false,
    window_group_autocmd = nil,
    entries = {},
    entries_by_id = {},
    tool_entries = {},
    fold_ranges = {},
    fold_previews = {},
    active_stream = nil,
    next_entry_id = 1,
    on_submit = options.on_submit or function()
      return true
    end,
  }, UI)

  ui_by_buffer[transcript_buffer] = ui
  ui:_install_input_actions()
  ui:_install_window_group_actions()
  return ui
end

function UI:_install_input_actions()
  local function submit(behavior)
    return function()
      self:submit_input(behavior)
    end
  end

  vim.keymap.set("n", "<CR>", submit("send"), {
    buffer = self.input_buffer,
    desc = "Phenix: send prompt",
  })
  vim.keymap.set("n", "<S-CR>", submit("steer"), {
    buffer = self.input_buffer,
    desc = "Phenix: steer current response",
  })
  vim.keymap.set("n", "<M-CR>", submit("follow_up"), {
    buffer = self.input_buffer,
    desc = "Phenix: queue follow-up",
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = self.input_buffer,
    callback = submit("send"),
    desc = "Phenix: send prompt when the prompt buffer is written",
  })
end

function UI:_install_window_group_actions()
  self.window_group_autocmd = vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(args)
      local closed = tonumber(args.match)
      if closed then
        self:_window_closed(closed)
      end
    end,
    desc = "Phenix: close transcript and prompt windows as one group",
  })
end

function UI:_window_closed(closed)
  if self.window_group_closing then
    return
  end
  if closed ~= self.input_window and closed ~= self.transcript_window then
    return
  end

  self.window_group_closing = true
  local input_window = self.input_window
  local transcript_window = self.transcript_window
  self.input_window = nil
  self.transcript_window = nil

  for _, window in ipairs({ input_window, transcript_window }) do
    if window ~= closed and window and vim.api.nvim_win_is_valid(window) then
      pcall(vim.api.nvim_win_close, window, true)
    end
  end
  self.window_group_closing = false
end

function UI:_next_id(prefix)
  local id = string.format("%s:%d", prefix, self.next_entry_id)
  self.next_entry_id = self.next_entry_id + 1
  return id
end

function UI:_schedule_markview_render()
  if not self.markview or self.markview_render_scheduled or not vim.api.nvim_buf_is_valid(self.transcript_buffer) then
    return
  end

  self.markview_render_scheduled = true
  self.markview_render_generation = self.markview_render_generation + 1
  local generation = self.markview_render_generation
  vim.defer_fn(function()
    if not self.markview_render_scheduled or self.markview_render_generation ~= generation then
      return
    end
    self.markview_render_scheduled = false
    self:_render_markview_now()
  end, self.markview_render_interval)
end

function UI:_render_markview_now()
  if not self.markview or not vim.api.nvim_buf_is_valid(self.transcript_buffer) then
    return
  end

  local position = capture_position(self.transcript_window, self.transcript_buffer)
  local ok = pcall(self.markview.render, self.transcript_buffer, {
    enable = true,
    hybrid_mode = false,
  })
  if not ok then
    self.markview = nil
    return
  end

  restore_position(self.transcript_window, self.transcript_buffer, position)
  self.markview_render_count = self.markview_render_count + 1
end

function UI:_flush_markview_render()
  if not self.markview_render_scheduled then
    return
  end
  self.markview_render_scheduled = false
  self.markview_render_generation = self.markview_render_generation + 1
  self:_render_markview_now()
end

function UI:_schedule_render()
  if self.render_scheduled or not vim.api.nvim_buf_is_valid(self.transcript_buffer) then
    return
  end
  self.render_scheduled = true
  self.render_generation = self.render_generation + 1
  local generation = self.render_generation
  vim.defer_fn(function()
    if not self.render_scheduled or self.render_generation ~= generation then
      return
    end
    self.render_scheduled = false
    if vim.api.nvim_buf_is_valid(self.transcript_buffer) then
      self:_render_now()
    end
  end, self.render_interval)
end

function UI:_flush_render()
  if not vim.api.nvim_buf_is_valid(self.transcript_buffer) then
    return
  end
  self.render_scheduled = false
  self.render_generation = self.render_generation + 1
  self:_render_now()
  self:_flush_markview_render()
end

function UI:_append_entry(entry)
  entry.id = entry.id or self:_next_id(entry.kind)
  if entry.expanded == nil then
    entry.expanded = false
  end
  table.insert(self.entries, entry)
  self.entries_by_id[entry.id] = entry
  self.active_stream = nil
  self:_schedule_render()
  return entry
end

function UI:_append_stream(kind, text, message_id)
  if not text or text == "" then
    return
  end

  local key = kind .. ":" .. tostring(message_id or "")
  local entry = self.active_stream
  if not entry or entry.stream_key ~= key then
    entry = {
      id = self:_next_id(kind),
      kind = kind,
      text = "",
      stream_key = key,
      expanded = false,
    }
    table.insert(self.entries, entry)
    self.entries_by_id[entry.id] = entry
    self.active_stream = entry
  end
  entry.text = entry.text .. text
  self:_schedule_render()
end

function UI:append_user(text, label)
  text = vim.trim(text or "")
  if text == "" then
    return
  end
  self:_append_entry({
    kind = "user",
    label = label or "You",
    text = text,
  })
end

function UI:append_assistant(text, message_id)
  self:_append_stream("assistant", text, message_id)
end

function UI:append_thinking(text, message_id)
  self:_append_stream("thinking", text, message_id)
end

function UI:finish_response()
  self.active_stream = nil
  self:_flush_render()
end

function UI:append_error(message)
  self:_append_entry({
    kind = "error",
    text = tostring(message),
  })
  self:_flush_render()
end

function UI:_tool(update)
  local tool_call_id = update.toolCallId or update.tool_call_id
  if not tool_call_id then
    return nil
  end

  local id = "tool:" .. tostring(tool_call_id)
  local entry = self.tool_entries[id]
  if not entry then
    entry = {
      id = id,
      kind = "tool",
      title = tostring(update.title or tool_call_id),
      status = update.status or "pending",
      expanded = false,
    }
    self.tool_entries[id] = entry
    self.entries_by_id[id] = entry
    table.insert(self.entries, entry)
  end

  local fields = update.fields or update
  entry.title = tostring(first_non_nil(fields.title, update.title, entry.title))
  entry.status = first_non_nil(fields.status, update.status, entry.status)

  local input = first_non_nil(fields.rawInput, fields.raw_input, update.rawInput, update.raw_input)
  if input ~= nil then
    entry.input = vim.deepcopy(input)
  end

  local output = first_non_nil(fields.rawOutput, fields.raw_output, update.rawOutput, update.raw_output)
  if output ~= nil then
    entry.output = vim.deepcopy(output)
  end

  self.active_stream = nil
  return entry
end

function UI:append_update(update)
  if not update then
    return
  end

  local kind = update.sessionUpdate or update.session_update
  if kind == "agent_message_chunk" then
    self:append_assistant(content_text(update.content), update.messageId or update.message_id)
  elseif kind == "agent_thought_chunk" then
    self:append_thinking(content_text(update.content), update.messageId or update.message_id)
  elseif kind == "tool_call" or kind == "tool_call_update" then
    if self:_tool(update) then
      self:_schedule_render()
    end
  elseif kind == "plan" then
    self:_append_entry({
      kind = "system",
      label = "Plan",
      text = pretty_json(update.entries or update.plan or update),
    })
  end
end

function UI:_capture_fold_state()
  if not self.transcript_window or not vim.api.nvim_win_is_valid(self.transcript_window) then
    return
  end

  for id, range in pairs(self.fold_ranges) do
    local entry = self.entries_by_id[id]
    if entry then
      local closed = vim.api.nvim_win_call(self.transcript_window, function()
        return vim.fn.foldclosed(range.start_line)
      end)
      entry.expanded = closed == -1
    end
  end
end

function UI:_render_now()
  self:_capture_fold_state()
  local position = capture_position(self.transcript_window, self.transcript_buffer)

  local lines = {}
  local highlights = {}
  local fold_ranges = {}
  local fold_previews = {}

  local function heading(text, highlight)
    local line = #lines + 1
    table.insert(lines, text)
    table.insert(highlights, { line = line, group = highlight })
    table.insert(lines, "")
    return line
  end

  for _, entry in ipairs(self.entries) do
    if #lines > 0 then
      table.insert(lines, "")
    end

    if entry.kind == "user" then
      heading("## " .. (entry.label or "You"), "PhenixTranscriptUser")
      append_text(lines, entry.text)
    elseif entry.kind == "assistant" then
      heading("## Phenix", "PhenixTranscriptAssistant")
      append_text(lines, entry.text)
    elseif entry.kind == "thinking" then
      local header = heading("### Thinking", "PhenixTranscriptThinking")
      append_text(lines, entry.text)
      if #lines >= header then
        fold_ranges[entry.id] = {
          start_line = header,
          end_line = #lines,
          expanded = entry.expanded,
        }
        local excerpt = collapse_preview(entry.text)
        fold_previews[header] = excerpt == "" and "Thinking" or ("Thinking · " .. excerpt)
      end
    elseif entry.kind == "tool" then
      local status = entry.status and (" · " .. tostring(entry.status)) or ""
      local header = heading("### Tool · " .. (entry.title or "tool") .. status, "PhenixTranscriptTool")
      if entry.input ~= nil then
        table.insert(lines, "**Input**")
        table.insert(lines, "")
        append_tool_value(lines, entry.input)
      end
      if entry.output ~= nil then
        if #lines > header + 1 then
          table.insert(lines, "")
        end
        table.insert(lines, "**Output**")
        table.insert(lines, "")
        local output = tool_output_text(entry.output)
        if multiline_string(output) then
          append_fence(lines, "text", output)
        else
          append_text(lines, output or "")
        end
      end
      if #lines >= header then
        fold_ranges[entry.id] = {
          start_line = header,
          end_line = #lines,
          expanded = entry.expanded,
        }
        local preview = "Tool · " .. (entry.title or "tool")
        if entry.status then
          preview = preview .. " · " .. tostring(entry.status)
        end
        local input_preview = entry.input ~= nil and tool_input_preview(entry.input) or ""
        if input_preview ~= "" then
          preview = preview .. " · " .. input_preview
        end
        fold_previews[header] = collapse_preview(preview)
      end
    elseif entry.kind == "system" then
      heading("### " .. (entry.label or "System"), "PhenixTranscriptSystem")
      append_text(lines, entry.text or "")
    elseif entry.kind == "error" then
      heading("### Error", "PhenixTranscriptError")
      append_text(lines, entry.text or "")
    end
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = self.transcript_buffer })
  local changed = replace_changed_lines(self.transcript_buffer, lines)
  vim.api.nvim_buf_clear_namespace(self.transcript_buffer, transcript_namespace, 0, -1)
  for _, mark in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(self.transcript_buffer, transcript_namespace, mark.line - 1, 0, {
      line_hl_group = mark.group,
    })
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = self.transcript_buffer })

  self.fold_ranges = fold_ranges
  self.fold_previews = fold_previews
  self:_apply_folds()
  restore_position(self.transcript_window, self.transcript_buffer, position)
  if changed then
    self:_schedule_markview_render()
  end
  self.render_count = self.render_count + 1
end

function UI:_apply_folds()
  if not self.transcript_window or not vim.api.nvim_win_is_valid(self.transcript_window) then
    return
  end

  local ranges = {}
  for _, range in pairs(self.fold_ranges) do
    table.insert(ranges, range)
  end
  table.sort(ranges, function(left, right)
    return left.start_line < right.start_line
  end)

  vim.api.nvim_win_call(self.transcript_window, function()
    vim.cmd("silent! normal! zE")
    for _, range in ipairs(ranges) do
      if range.end_line >= range.start_line then
        vim.cmd(string.format("silent! %d,%dfold", range.start_line, range.end_line))
      end
    end
    for _, range in ipairs(ranges) do
      if not range.expanded then
        vim.cmd(string.format("silent! %dfoldclose", range.start_line))
      end
    end
  end)
end

function UI:text()
  return table.concat(vim.api.nvim_buf_get_lines(self.transcript_buffer, 0, -1, false), "\n")
end

function UI:is_visible()
  return self.transcript_window ~= nil
    and self.input_window ~= nil
    and vim.api.nvim_win_is_valid(self.transcript_window)
    and vim.api.nvim_win_is_valid(self.input_window)
end

function UI:follow()
  if not self:is_visible() then
    return
  end
  local count = math.max(vim.api.nvim_buf_line_count(self.transcript_buffer), 1)
  vim.api.nvim_win_call(self.transcript_window, function()
    vim.api.nvim_win_set_cursor(self.transcript_window, { count, 0 })
    vim.cmd("silent! normal! zb")
  end)
end

function UI:focus_input()
  if not self:is_visible() then
    return
  end
  vim.api.nvim_set_current_win(self.input_window)
  vim.cmd("startinsert")
end

function UI:submit_input(behavior)
  local lines = vim.api.nvim_buf_get_lines(self.input_buffer, 0, -1, false)
  local text = vim.trim(table.concat(lines, "\n"))
  if text == "" then
    return false
  end

  if self.on_submit(text, behavior or "send") == false then
    return false
  end

  vim.api.nvim_buf_set_lines(self.input_buffer, 0, -1, false, { "" })
  vim.api.nvim_set_option_value("modified", false, { buf = self.input_buffer })
  return true
end

function UI:mount()
  if self:is_visible() then
    self:focus_input()
    return
  end

  self:hide()

  vim.cmd("botright vsplit")
  self.transcript_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(self.transcript_window, self.transcript_buffer)
  vim.api.nvim_win_set_width(self.transcript_window, self.width)
  vim.api.nvim_set_option_value("winfixwidth", true, { win = self.transcript_window })
  vim.api.nvim_set_option_value("wrap", true, { win = self.transcript_window })
  vim.api.nvim_set_option_value("linebreak", true, { win = self.transcript_window })
  vim.api.nvim_set_option_value("foldmethod", "manual", { win = self.transcript_window })
  vim.api.nvim_set_option_value("foldenable", true, { win = self.transcript_window })
  vim.api.nvim_set_option_value("foldtext", "v:lua.require('phenix.ui').foldtext()", { win = self.transcript_window })

  vim.cmd("belowright " .. tostring(self.input_height) .. "split")
  self.input_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(self.input_window, self.input_buffer)
  vim.api.nvim_set_option_value("winfixheight", true, { win = self.input_window })
  vim.api.nvim_set_option_value("wrap", true, { win = self.input_window })
  vim.api.nvim_set_option_value("linebreak", true, { win = self.input_window })

  if self.render_scheduled then
    self:_flush_render()
  end
  self:_apply_folds()
  self:follow()
  self:focus_input()
end

function UI:hide()
  if self.window_group_closing then
    return
  end

  self.window_group_closing = true
  local input_window = self.input_window
  local transcript_window = self.transcript_window
  self.input_window = nil
  self.transcript_window = nil

  if input_window and vim.api.nvim_win_is_valid(input_window) then
    pcall(vim.api.nvim_win_close, input_window, true)
  end
  if transcript_window and vim.api.nvim_win_is_valid(transcript_window) then
    pcall(vim.api.nvim_win_close, transcript_window, true)
  end
  self.window_group_closing = false
end

function UI:toggle()
  if self:is_visible() then
    self:hide()
  else
    self:mount()
  end
end

function UI:permission(params, respond)
  local options = params.options or {}
  if #options == 0 then
    respond(nil)
    return
  end

  vim.ui.select(options, {
    prompt = ((params.toolCall or {}).title) or "Phenix permission",
    format_item = function(option)
      return option.name or option.optionId or "permission"
    end,
  }, function(option)
    respond(option and option.optionId or nil)
  end)
end

function UI:close()
  self.render_scheduled = false
  self.render_generation = self.render_generation + 1
  self.markview_render_scheduled = false
  self.markview_render_generation = self.markview_render_generation + 1
  self:hide()
  if self.window_group_autocmd then
    pcall(vim.api.nvim_del_autocmd, self.window_group_autocmd)
    self.window_group_autocmd = nil
  end
  if self.markview and vim.api.nvim_buf_is_valid(self.transcript_buffer) then
    pcall(self.markview.clear, self.transcript_buffer)
  end
  ui_by_buffer[self.transcript_buffer] = nil
  if vim.api.nvim_buf_is_valid(self.input_buffer) then
    pcall(vim.api.nvim_buf_delete, self.input_buffer, { force = true })
  end
  if vim.api.nvim_buf_is_valid(self.transcript_buffer) then
    pcall(vim.api.nvim_buf_delete, self.transcript_buffer, { force = true })
  end
end

M.UI = UI

return M
