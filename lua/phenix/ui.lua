local Window = require("phenix.window")

local M = {}

local UI = {}
UI.__index = UI

local transcript_namespace = vim.api.nvim_create_namespace("phenix-transcript")
local ui_by_buffer = setmetatable({}, { __mode = "v" })

local DEFAULT_RENDER_INTERVAL_MS = 33
local DEFAULT_MARKVIEW_RENDER_INTERVAL_MS = 150
local DEFAULT_WIDTH = 0.5
local DEFAULT_INPUT_HEIGHT = 0.33
local DEFAULT_INPUT_HEIGHT_MIN = 6
local DEFAULT_INPUT_HEIGHT_MAX = 20
local DEFAULT_IMAGE_HEIGHT = 5
local DEFAULT_IMAGE_WIDTH = 40
local FOLD_PREVIEW_LIMIT = 96

local function resolve_dimension(value, total, default, minimum, maximum)
	value = value == nil and default or value
	if type(value) ~= "number" then
		error("Phenix UI dimensions must be numbers", 3)
	end
	local size = value > 0 and value <= 1 and math.floor(total * value) or math.floor(value)
	return math.min(math.max(size, minimum), maximum)
end

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

local function clipboard_image_command(command)
	if command then
		return command
	end
	if vim.env.WAYLAND_DISPLAY and vim.fn.executable("wl-paste") == 1 then
		local types = vim.system({ "wl-paste", "--list-types" }, { text = true }):wait().stdout or ""
		for _, mime_type in ipairs({ "image/png", "image/jpeg", "image/webp", "image/gif" }) do
			if types:find(mime_type, 1, true) then
				return { "wl-paste", "--no-newline", "--type", mime_type }, mime_type
			end
		end
	end
	if vim.fn.executable("xclip") == 1 then
		return { "xclip", "-selection", "clipboard", "-t", "image/png", "-o" }, "image/png"
	end
	return nil
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

local function tool_main_parameter(value)
	local normalized = decode_structured_string(value)
	if type(normalized) ~= "table" or vim.islist(normalized) then
		return preview_scalar(normalized)
	end

	for _, key in ipairs({ "path", "file_path", "filePath", "command", "cmd", "query", "pattern", "url" }) do
		if normalized[key] ~= nil then
			return tostring(key) .. "=" .. preview_scalar(normalized[key])
		end
	end
	local key = sorted_keys(normalized)[1]
	return key and (tostring(key) .. "=" .. preview_scalar(normalized[key])) or ""
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
		PhenixWinbarTitle = "Title",
		PhenixWinbarReady = "DiagnosticOk",
		PhenixWinbarWorking = "DiagnosticWarn",
		PhenixWinbarError = "DiagnosticError",
		PhenixWinbarMuted = "Comment",
	}
	pcall(vim.api.nvim_set_hl, 0, "PhenixWinbar", {
		default = true,
		fg = "#c6d0f5",
		bg = "#303446",
	})
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

	local follow_up_buffer = nil

	local ui = setmetatable({
		transcript_buffer = transcript_buffer,
		input_buffer = input_buffer,
		follow_up_buffer = follow_up_buffer,
		follow_up_buffers = {},
		transcript_window = nil,
		input_window = nil,
		follow_up_window = nil,
		follow_up_windows = {},
		width = options.width,
		input_height = options.input_height,
		input_height_min = options.input_height_min or DEFAULT_INPUT_HEIGHT_MIN,
		input_height_max = options.input_height_max or DEFAULT_INPUT_HEIGHT_MAX,
		image_height = options.image_height or DEFAULT_IMAGE_HEIGHT,
		image_width = options.image_width or DEFAULT_IMAGE_WIDTH,
		image_paste_command = options.image_paste_command,
		image_buffer = nil,
		image_window = nil,
		image_ids = {},
		images = {},
		follow_up_height = options.follow_up_height,
		follow_up_height_min = options.follow_up_height_min or DEFAULT_INPUT_HEIGHT_MIN,
		follow_up_height_max = options.follow_up_height_max or DEFAULT_INPUT_HEIGHT_MAX,
		follow_ups = {},
		chat_mode = options.chat_mode == true,
		startup_banner_pending = true,
		startup_banner = "",
		render_interval = options.render_interval or DEFAULT_RENDER_INTERVAL_MS,
		render_scheduled = false,
		render_generation = 0,
		render_count = 0,
		markview = load_markview(),
		markview_render_interval = options.markview_render_interval or DEFAULT_MARKVIEW_RENDER_INTERVAL_MS,
		markview_render_scheduled = false,
		markview_render_generation = 0,
		markview_render_count = 0,
		window_group = nil,
		input_resize_autocmd = nil,
		input_resize_window_autocmd = nil,
		follow_up_resize_autocmd = nil,
		maximized = false,
		layout_options = {},
		context = vim.tbl_deep_extend("force", { status = "Starting" }, vim.deepcopy(options.context or {})),
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
		on_follow_up_edit = options.on_follow_up_edit or function()
			return true
		end,
	}, UI)

	ui_by_buffer[transcript_buffer] = ui
	ui.window_group = Window.group({
		on_close = function()
			ui.transcript_window = nil
			ui.input_window = nil
			ui.image_window = nil
			ui.image_ids = {}
			ui.follow_up_window = nil
			ui.follow_up_windows = {}
		end,
	})
	ui.window_group:add_buffer(transcript_buffer)
	ui.window_group:add_buffer(input_buffer)
	ui:_install_input_actions()
	ui:_install_transcript_actions()
	ui:_install_common_phenix_actions(transcript_buffer)
	ui:_install_common_phenix_actions(input_buffer)
	ui:_install_input_resize()
	ui:_install_follow_up_resize()
	return ui
end

function UI:_recreate_buffers()
	local transcript_buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(transcript_buffer, "phenix://transcript/" .. tostring(transcript_buffer))
	configure_buffer(transcript_buffer, "markdown", false)
	pcall(vim.treesitter.start, transcript_buffer, "markdown")

	local input_buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(input_buffer, "phenix://prompt/" .. tostring(input_buffer))
	configure_buffer(input_buffer, "text", true, "acwrite")
	vim.api.nvim_buf_set_lines(input_buffer, 0, -1, false, { "" })
	vim.api.nvim_set_option_value("modified", false, { buf = input_buffer })

	self.transcript_buffer = transcript_buffer
	self.input_buffer = input_buffer
	self.follow_up_buffer = nil
	self.follow_up_buffers = {}
	ui_by_buffer[transcript_buffer] = self
	for _, buffer in ipairs({ transcript_buffer, input_buffer }) do
		self.window_group:add_buffer(buffer)
	end
	self:_install_input_actions()
	self:_install_transcript_actions()
	self:_install_common_phenix_actions(transcript_buffer)
	self:_install_common_phenix_actions(input_buffer)
	self:_install_input_resize()
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
	vim.keymap.set({ "n", "i" }, "<C-v>", function()
		self:paste_image()
	end, {
		buffer = self.input_buffer,
		desc = "Phenix: paste clipboard image",
	})

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = self.input_buffer,
		callback = submit("send"),
		desc = "Phenix: send prompt when the prompt buffer is written",
	})
end

function UI:_install_transcript_actions()
	-- Redirect insert mode to input buffer
	vim.api.nvim_create_autocmd("InsertEnter", {
		buffer = self.transcript_buffer,
		callback = function()
			self:focus_input()
		end,
		desc = "Phenix: focus input when entering insert mode in transcript",
	})

	-- Redirect paste to input buffer
	vim.keymap.set({ "n", "v" }, "p", function()
		self:focus_input()
		vim.api.nvim_feedkeys("p", "n", false)
	end, {
		buffer = self.transcript_buffer,
		desc = "Phenix: paste into input buffer",
	})

	vim.keymap.set({ "n", "v" }, "P", function()
		self:focus_input()
		vim.api.nvim_feedkeys("P", "n", false)
	end, {
		buffer = self.transcript_buffer,
		desc = "Phenix: paste before into input buffer",
	})
end

function UI:_install_common_phenix_actions(buffer)
	-- Common phenix actions available in all phenix buffers
	vim.keymap.set("n", "<leader>po", "<Plug>(phenix-select-model)", {
		buffer = buffer,
		desc = "Phenix: select model or routing",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pc", "<Plug>(phenix-cancel)", {
		buffer = buffer,
		desc = "Phenix: cancel response",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pC", "<Plug>(phenix-toggle-chat-mode)", {
		buffer = buffer,
		desc = "Phenix: toggle chat mode",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pi", "<Plug>(phenix-toggle-info)", {
		buffer = buffer,
		desc = "Phenix: toggle session info",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pr", "<Plug>(phenix-restore)", {
		buffer = buffer,
		desc = "Phenix: restore session",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pF", "<Plug>(phenix-fork-session)", {
		buffer = buffer,
		desc = "Phenix: fork session",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pR", "<Plug>(phenix-rename-session)", {
		buffer = buffer,
		desc = "Phenix: rename session",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pk", "<Plug>(phenix-refresh-skills)", {
		buffer = buffer,
		desc = "Phenix: refresh skills",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pK", "<Plug>(phenix-select-callable)", {
		buffer = buffer,
		desc = "Phenix: select callable",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pS", "<Plug>(phenix-select-skill)", {
		buffer = buffer,
		desc = "Phenix: select skill",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pu", "<Plug>(phenix-refresh-catalogs)", {
		buffer = buffer,
		desc = "Phenix: refresh backend catalogs",
		remap = true,
	})
	vim.keymap.set("n", "<leader>pa", "<Plug>(phenix-authenticate)", {
		buffer = buffer,
		desc = "Phenix: authenticate provider",
		remap = true,
	})
	vim.keymap.set("n", "<leader>ps", "<Plug>(phenix-select-transcript)", {
		buffer = buffer,
		desc = "Phenix: select transcript",
		remap = true,
	})
end

function UI:_install_input_resize()
	local resize = function()
		self:_resize_input()
		self:_render_images()
	end
	self.input_resize_autocmd = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWinEnter" }, {
		buffer = self.input_buffer,
		callback = resize,
		desc = "Phenix: fit prompt window to wrapped input",
	})
	if not self.input_resize_window_autocmd then
		self.input_resize_window_autocmd = vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
			callback = resize,
			desc = "Phenix: refit prompt after window resize",
		})
	end
end

function UI:_install_follow_up_resize()
	self.follow_up_resize_autocmd = vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
		callback = function()
			self:_resize_follow_ups()
		end,
		desc = "Phenix: refit follow-up queue after window resize",
	})
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
	if self.startup_banner_pending then
		self.startup_banner = self.startup_banner .. (text or "")
		if not vim.startswith(self.startup_banner, "pi v") then
			if ("pi v"):sub(1, #self.startup_banner) == self.startup_banner then
				return
			end
			self.startup_banner_pending = false
			self:_append_stream("assistant", self.startup_banner, message_id)
			self.startup_banner = ""
			return
		end

		for _, mode in ipairs({ "low", "medium", "high", "max" }) do
			local _, end_index = self.startup_banner:find("mode:%s*" .. mode, 1)
			if end_index then
				local response = self.startup_banner:sub(end_index + 1):gsub("^%s+", "")
				self.startup_banner_pending = false
				self.startup_banner = ""
				self:_append_stream("assistant", response, message_id)
				return
			end
		end
		return
	end
	self:_append_stream("assistant", text, message_id)
end

function UI:append_thinking(text, message_id)
	self:_append_stream("thinking", text, message_id)
end

function UI:finish_response()
	if self.startup_banner_pending and self.startup_banner ~= "" then
		self.startup_banner_pending = false
		self:_append_stream("assistant", self.startup_banner)
		self.startup_banner = ""
	end
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
		table.insert(highlights, { line = line, end_col = #text, group = highlight })
		table.insert(lines, "")
		return line
	end

	for _, entry in ipairs(self.entries) do
		local kind = entry.kind
		local should_skip = self.chat_mode and (kind == "thinking" or kind == "tool" or kind == "system")

		if not should_skip then
			if #lines > 0 then
				table.insert(lines, "")
			end

			if kind == "user" then
				heading("## " .. (entry.label or "You"), "PhenixTranscriptUser")
				append_text(lines, entry.text)
			elseif kind == "assistant" then
				heading("## Phenix", "PhenixTranscriptAssistant")
				append_text(lines, entry.text)
			elseif kind == "thinking" then
				local header = heading("### Thinking", "PhenixTranscriptThinking")
				append_text(lines, entry.text)
				if #lines >= header then
					fold_ranges[entry.id] = {
						id = entry.id,
						start_line = header,
						end_line = #lines,
						expanded = entry.expanded,
					}
					local excerpt = collapse_preview(entry.text)
					fold_previews[header] = excerpt == "" and "Thinking" or ("Thinking · " .. excerpt)
				end
			elseif kind == "tool" then
				local status = entry.status and (" · " .. tostring(entry.status)) or ""
				local main_parameter = entry.input ~= nil and tool_main_parameter(entry.input) or ""
				local parameter_summary = main_parameter ~= "" and (" · " .. main_parameter) or ""
				local header = heading(
					"### Tool · " .. (entry.title or "tool") .. status .. parameter_summary,
					"PhenixTranscriptTool"
				)
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
						id = entry.id,
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
			elseif kind == "system" then
				heading("### " .. (entry.label or "System"), "PhenixTranscriptSystem")
				append_text(lines, entry.text or "")
			elseif kind == "error" then
				heading("### Error", "PhenixTranscriptError")
				append_text(lines, entry.text or "")
			end
		end
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = self.transcript_buffer })
	local changed = replace_changed_lines(self.transcript_buffer, lines)
	vim.api.nvim_buf_clear_namespace(self.transcript_buffer, transcript_namespace, 0, -1)
	for _, mark in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(self.transcript_buffer, transcript_namespace, mark.line - 1, 0, {
			end_col = mark.end_col,
			hl_group = mark.group,
			line_hl_group = mark.group,
			priority = 200,
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
	self:_update_transcript_winbar()
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
			local command = range.expanded and "foldopen" or "foldclose"
			vim.cmd(string.format("silent! %d%s", range.start_line, command))
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

function UI:show_transcript(buffer)
	if not self.transcript_window or not vim.api.nvim_win_is_valid(self.transcript_window) then
		return false
	end
	vim.api.nvim_win_set_buf(self.transcript_window, buffer)
	Window.configure_text(self.transcript_window)
	return true
end

function UI:show_main_transcript()
	return self:show_transcript(self.transcript_buffer)
end

function UI:focus_input()
	if not self:is_visible() then
		return
	end
	vim.api.nvim_set_current_win(self.input_window)
	vim.cmd("startinsert")
end

function UI:_update_transcript_winbar()
	if not self.transcript_window or not vim.api.nvim_win_is_valid(self.transcript_window) then
		return
	end

	local context = self.context or {}
	local status = context.status or "Starting"
	local status_highlight = ({
		Ready = "PhenixWinbarReady",
		Working = "PhenixWinbarWorking",
		Cancelling = "PhenixWinbarWorking",
		Error = "PhenixWinbarError",
		Offline = "PhenixWinbarError",
	})[status] or "PhenixWinbarMuted"
	local detail = ""
	if context.routing and context.routing ~= "" then
		detail = context.routing
	elseif context.model and context.backend and context.provider then
		detail = string.format("%s/%s/%s", context.backend, context.provider, context.model)
	end
	vim.api.nvim_set_option_value(
		"winbar",
		Window.line({
			hl = "PhenixWinbar",
			children = {
				{ text = " Phenix - ", hl = "PhenixWinbarTitle" },
				{ text = status, hl = status_highlight },
				detail ~= "" and { text = " " .. detail, hl = "PhenixWinbarMuted" } or nil,
				{ text = " ", hl = "PhenixWinbar" },
			},
		}),
		{ win = self.transcript_window }
	)
end

function UI:set_context(context)
	self.context = vim.tbl_deep_extend("force", self.context or {}, vim.deepcopy(context or {}))
	self:_update_transcript_winbar()
end

function UI:set_status(status)
	self.context.status = status
	self:_update_transcript_winbar()
end

function UI:toggle_chat_mode()
	self.chat_mode = not self.chat_mode
	self:_render_now()
	return self.chat_mode
end

function UI:set_chat_mode(enabled)
	local value = enabled == true
	if self.chat_mode == value then
		return self.chat_mode
	end
	self.chat_mode = value
	self:_render_now()
	return self.chat_mode
end

function UI:_clear_rendered_images()
	if vim.ui.img and type(vim.ui.img.del) == "function" then
		for _, id in ipairs(self.image_ids) do
			pcall(vim.ui.img.del, id)
		end
	end
	self.image_ids = {}
end

function UI:_render_images()
	self:_clear_rendered_images()
	if #self.images == 0 or not self.image_window or not vim.api.nvim_win_is_valid(self.image_window) then
		return
	end
	if #vim.api.nvim_list_uis() == 0 or not vim.ui.img or type(vim.ui.img.set) ~= "function" then
		return
	end
	local position = vim.fn.win_screenpos(self.image_window)
	for index, image in ipairs(self.images) do
		if image.mime_type == "image/png" then
			local ok, id = pcall(vim.ui.img.set, image.data, {
				row = position[1],
				col = position[2],
				width = self.image_width,
				height = math.max(1, math.floor(self.image_height / #self.images)),
				zindex = 50 + index,
			})
			if ok then
				table.insert(self.image_ids, id)
			end
		end
	end
end

function UI:_sync_image_window()
	if self.image_window and vim.api.nvim_win_is_valid(self.image_window) then
		self.window_group:detach_window(self.image_window)
	end
	self.image_window = nil
	self:_clear_rendered_images()
	if
		#self.images == 0
		or self.maximized
		or not self.input_window
		or not vim.api.nvim_win_is_valid(self.input_window)
	then
		return
	end
	if not self.image_buffer or not vim.api.nvim_buf_is_valid(self.image_buffer) then
		self.image_buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(self.image_buffer, "phenix://images/" .. tostring(self.image_buffer))
		configure_buffer(self.image_buffer, "text", false)
		self.window_group:add_buffer(self.image_buffer)
	end
	local labels = {}
	for index, image in ipairs(self.images) do
		table.insert(labels, string.format("Image %d · %s", index, image.mime_type))
	end
	vim.api.nvim_set_option_value("modifiable", true, { buf = self.image_buffer })
	vim.api.nvim_buf_set_lines(self.image_buffer, 0, -1, false, labels)
	vim.api.nvim_set_option_value("modifiable", false, { buf = self.image_buffer })
	vim.api.nvim_set_current_win(self.input_window)
	vim.cmd("aboveleft " .. tostring(self.image_height) .. "split")
	self.image_window = vim.api.nvim_get_current_win()
	self.window_group:add_window(self.image_window)
	vim.api.nvim_win_set_buf(self.image_window, self.image_buffer)
	vim.api.nvim_set_option_value("winfixheight", true, { win = self.image_window })
	Window.configure_text(self.image_window)
	self:_render_images()
end

function UI:add_image(data, mime_type)
	if type(data) ~= "string" or data == "" then
		return false
	end
	mime_type = mime_type or "image/png"
	if type(mime_type) ~= "string" or not mime_type:match("^image/") then
		return false
	end
	table.insert(self.images, { data = data, mime_type = mime_type })
	self:_sync_image_window()
	self:focus_input()
	return true
end

function UI:paste_image()
	local command, mime_type = clipboard_image_command(self.image_paste_command)
	if not command then
		vim.notify("Phenix: no image clipboard provider (install wl-clipboard or xclip)", vim.log.levels.WARN)
		return false
	end
	vim.system(command, { text = false }, function(result)
		vim.schedule(function()
			if result.code ~= 0 or not result.stdout or result.stdout == "" then
				vim.notify("Phenix: clipboard does not contain an image", vim.log.levels.WARN)
				return
			end
			if self:add_image(result.stdout, mime_type or "image/png") then
				vim.notify("Phenix: image added to prompt")
			end
		end)
	end)
	return true
end

function UI:_resize_input()
	if self.maximized or not self.input_window or not vim.api.nvim_win_is_valid(self.input_window) then
		return
	end

	local visual_lines = nil
	local ok, height = pcall(vim.api.nvim_win_text_height, self.input_window, { start_row = 0, end_row = -1 })
	if ok and type(height) == "table" then
		visual_lines = height.all
	end
	if not visual_lines then
		visual_lines = math.max(vim.api.nvim_buf_line_count(self.input_buffer), 1)
	end

	local target = math.min(math.max(visual_lines, self.input_height_min), self.input_height_max)
	if vim.api.nvim_win_get_height(self.input_window) ~= target then
		vim.api.nvim_win_set_height(self.input_window, target)
	end
end

function UI:_resize_follow_up(index)
	local window = self.follow_up_windows[index]
	if not window or not vim.api.nvim_win_is_valid(window) then
		return
	end
	local visual_lines = nil
	local ok, height = pcall(vim.api.nvim_win_text_height, window, { start_row = 0, end_row = -1 })
	if ok and type(height) == "table" then
		visual_lines = height.all
	end
	visual_lines = visual_lines or math.max(vim.api.nvim_buf_line_count(self.follow_up_buffers[index]), 1)
	local target = math.min(math.max(visual_lines, self.follow_up_height_min), self.follow_up_height_max)
	if vim.api.nvim_win_get_height(window) ~= target then
		vim.api.nvim_win_set_height(window, target)
	end
end

function UI:_resize_follow_ups()
	for index in ipairs(self.follow_up_windows) do
		self:_resize_follow_up(index)
	end
end

function UI:_clear_follow_up_windows()
	for _, window in ipairs(self.follow_up_windows) do
		self.window_group:detach_window(window)
	end
	self.follow_up_windows = {}
	self.follow_up_window = nil
end

function UI:_sync_follow_up_window()
	self:_clear_follow_up_windows()
	if
		self.maximized
		or #self.follow_ups == 0
		or not self.input_window
		or not vim.api.nvim_win_is_valid(self.input_window)
	then
		return
	end

	for index = 1, #self.follow_ups do
		vim.api.nvim_set_current_win(self.input_window)
		vim.cmd("aboveleft " .. tostring(self.follow_up_height_max) .. "split")
		local window = vim.api.nvim_get_current_win()
		self.follow_up_windows[index] = window
		self.window_group:add_window(window)
		vim.api.nvim_win_set_buf(window, self.follow_up_buffers[index])
		vim.api.nvim_set_option_value("winfixheight", true, { win = window })
		vim.api.nvim_set_option_value(
			"winbar",
			Window.line({
				hl = "PhenixWinbar",
				children = {
					{ text = string.format(" Follow-up %d/%d ", index, #self.follow_ups), hl = "PhenixWinbarTitle" },
				},
			}),
			{ win = window }
		)
		vim.api.nvim_set_option_value("winhighlight", "WinBar:PhenixWinbar", { win = window })
		Window.configure_text(window)
		self:_resize_follow_up(index)
	end
	self.follow_up_window = self.follow_up_windows[1]
	self:focus_input()
end

function UI:set_follow_ups(follow_ups)
	self:_clear_follow_up_windows()
	self.follow_ups = vim.deepcopy(follow_ups or {})
	for index, text in ipairs(self.follow_ups) do
		local buffer = self.follow_up_buffers[index]
		if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
			buffer = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(buffer, "phenix://follow-up/" .. tostring(buffer))
			configure_buffer(buffer, "text", true)
			self.follow_up_buffers[index] = buffer
			self.window_group:add_buffer(buffer)
			local queue_index = index
			vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
				buffer = buffer,
				callback = function()
					local value = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n"))
					self.on_follow_up_edit(queue_index, value)
				end,
				desc = "Phenix: update queued follow-up",
			})
		end
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, split_text(text))
		vim.api.nvim_set_option_value("modified", false, { buf = buffer })
	end
	for index = #self.follow_up_buffers, #self.follow_ups + 1, -1 do
		local buffer = self.follow_up_buffers[index]
		self.window_group:remove_buffer(buffer)
		pcall(vim.api.nvim_buf_delete, buffer, { force = true })
		table.remove(self.follow_up_buffers, index)
	end
	self.follow_up_buffer = self.follow_up_buffers[1]
	self:_sync_follow_up_window()
end

function UI:submit_input(behavior)
	local lines = vim.api.nvim_buf_get_lines(self.input_buffer, 0, -1, false)
	local text = vim.trim(table.concat(lines, "\n"))
	if text == "" and #self.images == 0 then
		return false
	end
	local images = {}
	for _, image in ipairs(self.images) do
		table.insert(images, { type = "image", data = vim.base64.encode(image.data), mimeType = image.mime_type })
	end

	if self.on_submit(text, behavior or "send", images) == false then
		return false
	end

	self.images = {}
	self:_sync_image_window()
	vim.api.nvim_buf_set_lines(self.input_buffer, 0, -1, false, { "" })
	vim.api.nvim_set_option_value("modified", false, { buf = self.input_buffer })
	if self.maximized then
		self:toggle_maximize()
	else
		self:_resize_input()
	end
	return true
end

function UI:mount(options)
	options = options or {}
	if not vim.api.nvim_buf_is_valid(self.transcript_buffer) then
		self:_recreate_buffers()
	end
	if self:is_visible() then
		self:focus_input()
		return
	end

	-- Handle tab creation for fullscreen mode
	if options.tab then
		vim.cmd("tabnew")
	end
	self:hide()

	self.maximized = false
	self.layout_options = vim.deepcopy(options)
	self.input_height_min = options.input_height_min or self.input_height_min
	self.input_height_max = options.input_height_max or self.input_height_max
	self.image_height = options.image_height or self.image_height
	self.image_width = options.image_width or self.image_width
	self.follow_up_height_min = options.follow_up_height_min or self.follow_up_height_min
	self.follow_up_height_max = options.follow_up_height_max or self.follow_up_height_max

	local width = resolve_dimension(
		options.width or self.width,
		vim.o.columns,
		DEFAULT_WIDTH,
		20,
		math.max(vim.o.columns - 1, 20)
	)
	local input_height = resolve_dimension(
		options.input_height or self.input_height,
		vim.o.lines,
		DEFAULT_INPUT_HEIGHT,
		options.input_height_min or self.input_height_min,
		options.input_height_max or self.input_height_max
	)

	-- Sidebar mode: split layout
	if not options.tab then
		vim.cmd("botright vsplit")
		self.transcript_window = vim.api.nvim_get_current_win()
		self.window_group:add_window(self.transcript_window)
		vim.api.nvim_win_set_buf(self.transcript_window, self.transcript_buffer)
		vim.api.nvim_win_set_width(self.transcript_window, width)
		vim.api.nvim_set_option_value("winfixwidth", true, { win = self.transcript_window })
		Window.configure_text(self.transcript_window)
		vim.api.nvim_set_option_value("foldmethod", "manual", { win = self.transcript_window })
		vim.api.nvim_set_option_value("foldenable", true, { win = self.transcript_window })
		vim.api.nvim_set_option_value("foldtext", "v:lua.require('phenix.ui').foldtext()", { win = self.transcript_window })
		self:_update_transcript_winbar()
	else
		-- Fullscreen tab mode: take over the entire tab
		vim.api.nvim_set_current_buf(self.transcript_buffer)
		self.transcript_window = vim.api.nvim_get_current_win()
		self.window_group:add_window(self.transcript_window)
		vim.api.nvim_set_option_value("foldmethod", "manual", { win = self.transcript_window })
		vim.api.nvim_set_option_value("foldenable", true, { win = self.transcript_window })
		vim.api.nvim_set_option_value("foldtext", "v:lua.require('phenix.ui').foldtext()", { win = self.transcript_window })
		self:_update_transcript_winbar()
	end

	vim.cmd("belowright " .. tostring(input_height) .. "split")
	self.input_window = vim.api.nvim_get_current_win()
	self.window_group:add_window(self.input_window)
	vim.api.nvim_win_set_buf(self.input_window, self.input_buffer)
	vim.api.nvim_set_option_value("winfixheight", true, { win = self.input_window })
	Window.configure_text(self.input_window)
	self:_sync_image_window()
	self:_sync_follow_up_window()

	if self.render_scheduled then
		self:_flush_render()
	else
		self:_render_now()
	end
	self:_apply_folds()
	self:_resize_input()
	self:follow()
	self:focus_input()
end

function UI:hide()
	self:_clear_rendered_images()
	self.window_group:unmount()
	self.input_window = nil
	self.transcript_window = nil
	self.follow_up_window = nil
	self.follow_up_windows = {}
end

function UI:toggle_maximize()
	if self.maximized then
		self.maximized = false
		self:hide()
		self:mount(self.layout_options)
		return
	end
	if not self:is_visible() then
		return
	end

	self.maximized = true
	local transcript_window = self.transcript_window
	local follow_up_windows = self.follow_up_windows
	self.transcript_window = nil
	self.follow_up_window = nil
	self.follow_up_windows = {}
	for _, window in ipairs(follow_up_windows) do
		self.window_group:detach_window(window)
	end
	if transcript_window and vim.api.nvim_win_is_valid(transcript_window) then
		self.window_group:detach_window(transcript_window)
	end
	if self.input_window and vim.api.nvim_win_is_valid(self.input_window) then
		vim.api.nvim_set_current_win(self.input_window)
		vim.cmd("startinsert")
	end
end

function UI:toggle(options)
	if self:is_visible() then
		self:hide()
	else
		self:mount(options)
	end
end

function UI:permission(params, respond)
	local options = params.options or {}
	if #options == 0 then
		respond(nil)
		return
	end

	vim.ui.select(options, {
		prompt = (params.toolCall or {}).title or "Phenix permission",
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
	self.window_group:destroy()
	if self.input_resize_autocmd then
		pcall(vim.api.nvim_del_autocmd, self.input_resize_autocmd)
		self.input_resize_autocmd = nil
	end
	if self.input_resize_window_autocmd then
		pcall(vim.api.nvim_del_autocmd, self.input_resize_window_autocmd)
		self.input_resize_window_autocmd = nil
	end
	if self.follow_up_resize_autocmd then
		pcall(vim.api.nvim_del_autocmd, self.follow_up_resize_autocmd)
		self.follow_up_resize_autocmd = nil
	end
	if self.markview and vim.api.nvim_buf_is_valid(self.transcript_buffer) then
		pcall(self.markview.clear, self.transcript_buffer)
	end
	ui_by_buffer[self.transcript_buffer] = nil
end

M.UI = UI

return M
