local Acp = require("phenix.acp")
local Config = require("phenix.config")
local Info = require("phenix.info")
local Ui = require("phenix.ui")
local Window = require("phenix.window")

local M = {}

local Session = {}
Session.__index = Session

local function default_config_file()
	local configured = vim.env.PHENIX_CONFIG_DIR
	if configured and configured ~= "" then
		return vim.fs.joinpath(configured, "init.lua")
	end

	local xdg = vim.env.XDG_CONFIG_HOME
	if not xdg or xdg == "" then
		local home = vim.env.HOME
		if not home or home == "" then
			return nil
		end
		xdg = vim.fs.joinpath(home, ".config")
	end

	local candidate = vim.fs.joinpath(xdg, "phenix", "init.lua")
	if vim.uv.fs_stat(candidate) then
		return candidate
	end
	return nil
end

local function empty_object(value)
	if type(value) == "table" and next(value) == nil then
		return vim.empty_dict()
	end
	return value
end

local function wire_configuration(configuration)
	for _, backend in ipairs(configuration.input.backends or {}) do
		backend.environment = empty_object(backend.environment)
	end
	configuration.input.tools = empty_object(configuration.input.tools)
	return configuration
end

local function conductor_command(options, cwd)
	if options.conductor_command then
		local command = type(options.conductor_command) == "string" and { options.conductor_command }
			or vim.deepcopy(options.conductor_command)
		if options.conductor_cwd_arg ~= false then
			vim.list_extend(command, { "--cwd", cwd })
		end
		return command
	end

	local command = vim.env.PHENIX_CONDUCTOR_COMMAND
	if not command or command == "" then
		command = "phenix-conductor"
	end
	return { command, "--cwd", cwd }
end

local function format_rpc_error(prefix, error_value)
	if not error_value then
		return prefix
	end
	return string.format("%s: %s", prefix, error_value.message or vim.inspect(error_value))
end

local function optional_wire_value(value)
	if value == nil or value == vim.NIL then
		return nil
	end
	return value
end

function M.new(options)
	options = options or {}
	local cwd = vim.fs.normalize(options.cwd or vim.fn.getcwd())
	local session = setmetatable({
		cwd = cwd,
		options = vim.deepcopy(options),
		client = nil,
		ui = nil,
		session_id = nil,
		root_node_id = nil,
		ready = false,
		prompting = false,
		cancelling = false,
		follow_ups = {},
		workflows = {},
		configuration = nil,
		config_options = {},
		auth_terminal = nil,
		closed = false,
	}, Session)

	session.ui = Ui.new({
		width = options.width,
		input_height = options.input_height,
		input_height_min = options.input_height_min,
		input_height_max = options.input_height_max,
		image_height = options.image_height,
		image_width = options.image_width,
		image_paste_command = options.image_paste_command,
		follow_up_height = options.follow_up_height,
		follow_up_height_min = options.follow_up_height_min,
		follow_up_height_max = options.follow_up_height_max,
		on_submit = function(text, behavior, images)
			return session:submit(text, behavior, images)
		end,
		on_follow_up_edit = function(index, text)
			session:update_follow_up(index, text)
		end,
	})

	session.info = Info.new({
		on_select_node = function(node_id)
			session:show_node_transcript(node_id)
		end,
	})

	session.client = Acp.new({
		command = conductor_command(options, cwd),
		cwd = cwd,
		on_notification = function(method, params)
			session:_notification(method, params)
		end,
		on_permission = function(params, respond)
			session.ui:permission(params, respond)
		end,
		on_stderr = function(message)
			session.ui:append_error(vim.trim(message))
		end,
		on_exit = function(result)
			session.ready = false
			session.prompting = false
			session.cancelling = false
			if not session.closed then
				session.ui:set_status(result.code == 0 and "Offline" or "Error")
			end
			if not session.closed and result.code ~= 0 then
				session.ui:append_error("conductor exited: " .. vim.inspect(result))
			end
		end,
	})

	return session
end

function Session:_configuration_params()
	if self.options.config == false then
		return nil
	end
	local path = self.options.config_file
		or (type(self.options.config) == "string" and self.options.config)
		or default_config_file()
	if not path then
		return nil
	end
	local builder = Config.load(path)
	return {
		params = wire_configuration(builder:params()),
	}
end

function Session:_fail(message, error_value)
	self.ready = false
	self.prompting = false
	self.cancelling = false
	self.ui:set_status("Error")
	self.ui:append_error(format_rpc_error(message, error_value))
end

function Session:_ready_standard_session(result)
	self.session_id = assert(result and result.sessionId, "session/new did not return sessionId")
	self:_apply_config_options(result.configOptions or {})
	self.client:request("_phenix/session_tree/get", {
		tree_id = self.session_id,
	}, function(tree, tree_error)
		if tree_error then
			self:_fail("failed to resolve Phenix session tree", tree_error)
			return
		end
		self.root_node_id = assert(tree and tree.root, "session tree did not return a root node")
		self.main_tree_id = self.session_id
		self.tree = tree
		self.info:set_tree(tree)
		self.ready = true
		self.ui:set_status("Ready")
		if self.options.on_ready then
			self.options.on_ready(self)
		end
	end)
end

local function selected_option(config_options, category)
	for _, option in ipairs(config_options or {}) do
		if option.category == category and option.type == "select" then
			return option
		end
	end
	return nil
end

function Session:_apply_config_options(config_options)
	self.config_options = vim.deepcopy(config_options or {})
	local option = selected_option(self.config_options, "model")
	if not option then
		return
	end
	local value = tostring(option.currentValue or "")
	if vim.startswith(value, "routing/") then
		self.ui:set_context({ routing = value, backend = "", provider = "", model = "" })
	else
		local backend, provider, model = value:match("^([^/]+)/([^/]+)/(.+)$")
		self.ui:set_context({ routing = "", backend = backend, provider = provider, model = model })
	end
end

function Session:select_model()
	if self.closed or not self.ready or not self.session_id then
		vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
		return false
	end
	local option = selected_option(self.config_options, "model")
	if not option then
		vim.notify("Phenix: the session does not expose model or routing choices", vim.log.levels.WARN)
		return false
	end
	vim.ui.select(option.options or {}, {
		prompt = option.name or "Model / routing",
		format_item = function(item)
			local marker = item.value == option.currentValue and "● " or "  "
			return marker .. (item.name or item.value)
		end,
	}, function(choice)
		if not choice or choice.value == option.currentValue then
			return
		end
		self.client:request("session/set_config_option", {
			sessionId = self.session_id,
			configId = option.id,
			value = choice.value,
		}, function(result, error_value)
			if error_value then
				self.ui:append_error(format_rpc_error("failed to select model or routing", error_value))
				return
			end
			self:_apply_config_options((result or {}).configOptions or {})
		end)
	end)
	return true
end

local function auth_target(session, backend)
	return { tree_id = session.session_id, backend = backend }
end

function Session:_auth_terminal_finished(backend, flow_id, success, message)
	self.client:request("_phenix/backend/auth/terminal_finished", vim.tbl_extend("force", auth_target(self, backend), {
		flow_id = flow_id,
		success = success,
		message = message,
	}), function(result, error_value)
		if error_value then
			self.ui:append_error(format_rpc_error("failed to finish authentication", error_value))
			return
		end
		self:_handle_auth_events(backend, (result or {}).events or {})
	end)
end

function Session:_run_auth_command(backend, flow_id, command)
	local argv = { command.program }
	vim.list_extend(argv, command.arguments or {})
	local buffer, window = Window.scratch("phenix://auth/" .. flow_id, {
		enter = true,
		window = {
			width = math.max(40, math.floor(vim.o.columns * 0.7)),
			height = math.max(10, math.floor(vim.o.lines * 0.7)),
			row = math.max(0, math.floor(vim.o.lines * 0.15)),
			col = math.max(0, math.floor(vim.o.columns * 0.15)),
		},
	})
	local group = Window.group()
	group:add_buffer(buffer)
	group:add_window(window)
	self.auth_terminal = group
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buffer })
	vim.api.nvim_set_option_value("winbar", Window.line({
		hl = "PhenixWinbar",
		children = {
			{ text = " Phenix authentication ", hl = "PhenixWinbarTitle" },
			{ text = backend, hl = "PhenixWinbarMuted" },
		},
	}), { win = window })
	local environment = vim.fn.environ()
	for name, value in pairs(command.environment or {}) do
		environment[name] = value
	end
	local job = vim.fn.jobstart(argv, {
		term = true,
		cwd = self.cwd,
		env = environment,
		on_exit = function(_, code)
			vim.schedule(function()
				if not self.closed then
					local message = code == 0 and nil or "authentication command exited with code " .. code
					self:_auth_terminal_finished(backend, flow_id, code == 0, message)
				end
			end)
		end,
	})
	if job <= 0 then
		group:destroy()
		self.auth_terminal = nil
		self:_auth_terminal_finished(backend, flow_id, false, "failed to start authentication command")
		return
	end
	vim.cmd("startinsert")
end

function Session:_respond_to_auth_prompt(backend, flow_id, prompt)
	local function respond(response)
		self.client:request("_phenix/backend/auth/respond", vim.tbl_extend("force", auth_target(self, backend), {
			flow_id = flow_id,
			response = response,
		}), function(result, error_value)
			if error_value then
				self.ui:append_error(format_rpc_error("authentication response failed", error_value))
				return
			end
			self:_handle_auth_events(backend, (result or {}).events or {})
		end)
	end
	if prompt.kind == "select" then
		vim.ui.select(prompt.options or {}, { prompt = prompt.message, format_item = function(item)
			return item.label or item.id
		end }, function(choice)
			respond(choice and { kind = "selected", option_id = choice.id } or { kind = "cancelled" })
		end)
	elseif prompt.kind == "secret" then
		local secret = vim.fn.inputsecret(prompt.message .. " ")
		respond(secret ~= "" and { kind = "secret", secret = secret } or { kind = "cancelled" })
	else
		vim.ui.input({ prompt = prompt.message .. " ", default = prompt.placeholder }, function(value)
			local kind = prompt.kind == "manual_code" and "manual_code" or "text"
			local field = kind == "manual_code" and "code" or "text"
			respond(value and { kind = kind, [field] = value } or { kind = "cancelled" })
		end)
	end
end

function Session:_handle_auth_events(backend, events)
	for _, event in ipairs(events or {}) do
		if event.kind == "external_command_requested" then
			self:_run_auth_command(backend, event.flow_id, event.command)
		elseif event.kind == "auth_prompt_requested" then
			self:_respond_to_auth_prompt(backend, event.flow_id, event.prompt)
		elseif event.kind == "auth_notice" then
			local notice = event.notice or {}
			local user_code = optional_wire_value(notice.user_code)
			local verification_uri = optional_wire_value(notice.verification_uri)
			local message = optional_wire_value(notice.message)
				or optional_wire_value(notice.instructions)
				or optional_wire_value(notice.url)
				or (user_code and verification_uri and string.format("Open %s and enter %s", verification_uri, user_code))
			if message then
				vim.notify("Phenix authentication: " .. tostring(message))
			end
		elseif event.kind == "auth_finished" then
			local auth_error = optional_wire_value(event.error)
			if auth_error then
				self.ui:append_error("authentication failed: " .. tostring(auth_error))
			else
				vim.notify("Phenix: authenticated " .. event.provider_id)
			end
		end
	end
end

function Session:_select_auth_provider(backend, providers)
	if #providers == 0 then
		vim.notify("Phenix: " .. backend .. " does not advertise provider authentication", vim.log.levels.WARN)
		return
	end
	vim.ui.select(providers, { prompt = "Authenticate " .. backend, format_item = function(provider)
		local configured = provider.configured and " · configured" or ""
		return provider.display_name .. configured
	end }, function(provider)
		if not provider then
			return
		end
		local methods = provider.methods or {}
		if #methods == 0 then
			vim.notify("Phenix: " .. provider.display_name .. " exposes no supported authentication method", vim.log.levels.WARN)
			return
		end
		local function start(method)
			if not method then
				return
			end
			self.client:request("_phenix/backend/auth/start", vim.tbl_extend("force", auth_target(self, backend), {
				provider_id = provider.id,
				method = method,
			}), function(result, error_value)
				if error_value then
					self.ui:append_error(format_rpc_error("failed to start authentication", error_value))
					return
				end
				self:_handle_auth_events(backend, (result or {}).events or {})
			end)
		end
		if #methods == 1 then
			start(methods[1])
		else
			vim.ui.select(methods, { prompt = provider.display_name .. " authentication" }, start)
		end
	end)
end

function Session:authenticate()
	if self.closed or not self.ready or not self.session_id then
		vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
		return false
	end
	local backends = vim.deepcopy((self.configuration or {}).backend_ids or {})
	if #backends == 0 then
		vim.notify("Phenix: the active configuration has no authentication-capable backend", vim.log.levels.WARN)
		return false
	end
	local function load(backend)
		if not backend then
			return
		end
		self.client:request("_phenix/backend/auth_provider/list", auth_target(self, backend), function(result, error_value)
			if error_value then
				self.ui:append_error(format_rpc_error("failed to list authentication providers", error_value))
				return
			end
			self:_select_auth_provider(backend, (result or {}).providers or {})
		end)
	end
	if #backends == 1 then
		load(backends[1])
	else
		vim.ui.select(backends, { prompt = "Authenticate backend" }, load)
	end
	return true
end

function Session:_new_standard_session()
	self.client:request("session/new", {
		cwd = self.cwd,
		mcpServers = {},
	}, function(result, error_value)
		if error_value then
			self:_fail("failed to create ACP session", error_value)
			return
		end
		self:_ready_standard_session(result)
	end)
end

function Session:start()
	self.ui:mount(self.options)
	self.client:start(function(_, initialize_error)
		if initialize_error then
			self:_fail("failed to initialize conductor", initialize_error)
			return
		end

		local ok, configuration = pcall(function()
			return self:_configuration_params()
		end)
		if not ok then
			self:_fail("failed to load Phenix configuration: " .. tostring(configuration))
			return
		end

		if not configuration then
			self:_new_standard_session()
			return
		end

		self.ui:set_context({ routing = configuration.params.input.router })
		-- The client selected this source root and its definition descriptors;
		-- the conductor resolves, parses, validates, and freezes them.
		self.client:request("_phenix/config/load", configuration.params, function(_, config_error)
			if config_error then
				self:_fail("failed to load Phenix configuration", config_error)
				return
			end
			-- The conductor owns the frozen revision and its callable workflow
			-- catalog. Never reconstruct either from the frontend authoring input.
			self.client:request("_phenix/config/get", {}, function(snapshot, snapshot_error)
				if snapshot_error then
					self:_fail("failed to retrieve Phenix configuration", snapshot_error)
					return
				end
				local active = snapshot and snapshot.active
				if type(active) ~= "table" or type(active.workflows) ~= "table" then
					self:_fail("conductor returned no active Phenix workflow catalog")
					return
				end
				self.configuration = active
				self.workflows = vim.deepcopy(active.workflows)
				self:_new_standard_session()
			end)
		end)
	end)
	return self
end

function Session:is_ready()
	return self.ready and not self.closed
end

---@return "running"|"settled"|nil
function Session:activity_state()
	if self.closed or not self.ready then
		return nil
	end
	return (self.prompting or self.cancelling) and "running" or "settled"
end

function Session:_send_prompt(text, echo_label, images)
	self.prompting = true
	self.cancelling = false
	self.ui:set_status("Working")
	if echo_label then
		self.ui:append_user(text, echo_label)
	end

	self.client:request("session/prompt", {
		sessionId = self.session_id,
		prompt = vim.list_extend({ { type = "text", text = text } }, images or {}),
	}, function(_, error_value)
		self.prompting = false
		self.cancelling = false
		self.ui:set_status(error_value and "Error" or "Ready")
		self.ui:finish_response()
		if error_value then
			self:_fail("prompt failed", error_value)
			return
		end
		self:_send_next_follow_up()
	end)
	return true
end

function Session:_send_next_follow_up()
	if self.closed or self.prompting then
		return
	end
	local text
	repeat
		text = table.remove(self.follow_ups, 1)
	until text == nil or vim.trim(text) ~= ""
	self.ui:set_follow_ups(self.follow_ups)
	if text then
		self:_send_prompt(text, "Follow-up")
	end
end

function Session:update_follow_up(index, text)
	if self.closed or not self.follow_ups[index] then
		return false
	end
	self.follow_ups[index] = text
	return true
end

function Session:prompt(text, label, images)
	text = vim.trim(text or "")
	if text == "" and #(images or {}) == 0 then
		return false
	end
	if not self.ready or not self.session_id then
		vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
		return false
	end
	if self.prompting then
		vim.notify("Phenix: current response is still running", vim.log.levels.WARN)
		return false
	end

	return self:_send_prompt(text, label or "You", images)
end

function Session:cancel()
	if self.closed or not self.ready or not self.session_id then
		return false
	end
	if not self.prompting then
		return false
	end
	if self.cancelling then
		return true
	end

	self.cancelling = true
	self.ui:set_status("Cancelling")
	self.follow_ups = {}
	self.ui:set_follow_ups(self.follow_ups)
	local ok, error_message = self.client:notify("session/cancel", {
		sessionId = self.session_id,
	})
	if not ok then
		self.cancelling = false
		self.ui:append_error("failed to cancel current response: " .. tostring(error_message))
		return false
	end
	return true
end

function Session:steer(text)
	text = vim.trim(text or "")
	if text == "" then
		return false
	end
	if not self.ready or not self.session_id or not self.root_node_id then
		vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
		return false
	end
	if not self.prompting then
		vim.notify("Phenix: there is no active response to steer", vim.log.levels.WARN)
		return false
	end

	self.ui:append_user(text, "Steer")
	self.client:request("_phenix/node/execute", {
		tree_id = self.session_id,
		node_id = self.root_node_id,
		command = {
			kind = "steer",
			text = text,
			images = {},
		},
	}, function(_, error_value)
		if error_value then
			self.ui:append_error(format_rpc_error("steering failed", error_value))
		end
	end)
	return true
end

function Session:follow_up(text)
	text = vim.trim(text or "")
	if text == "" then
		return false
	end
	if not self.ready or not self.session_id then
		vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
		return false
	end

	if not self.prompting then
		return self:prompt(text, "Follow-up")
	end

	table.insert(self.follow_ups, text)
	self.ui:set_follow_ups(self.follow_ups)
	return true
end

---@return { id: string, title: string }[]
function Session:workflow_definitions()
	return vim.deepcopy(self.workflows or {})
end

---@return table|nil
function Session:configuration_snapshot()
	return vim.deepcopy(self.configuration)
end

---Invoke a public conductor ACP method for integrations that need protocol
---capabilities beyond the frontend's convenience actions.
---@param method string
---@param params? table
---@param callback? fun(result: table|nil, error: table|nil)
---@return boolean
function Session:request(method, params, callback)
	if self.closed or not self.client or self.client.stopped then
		return false
	end
	self.client:request(method, params or {}, callback)
	return true
end

---@param workflow_id string
---@param objective string
---@param difficulty? "d0"|"d1"|"d2"|"d3"|"d4"
---@return boolean
function Session:start_workflow(workflow_id, objective, difficulty)
	if self.closed or not self.ready or not self.session_id then
		vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
		return false
	end
	workflow_id = vim.trim(workflow_id or "")
	objective = vim.trim(objective or "")
	if workflow_id == "" or objective == "" then
		vim.notify("Phenix: workflow and objective are required", vim.log.levels.WARN)
		return false
	end
	self.client:request("_phenix/workflow/start", {
		tree_id = self.session_id,
		workflow = workflow_id,
		difficulty = difficulty,
		objective = objective,
	}, function(_, error_value)
		if error_value then
			self.ui:append_error(format_rpc_error("failed to start workflow", error_value))
			return
		end
		self:_refresh_tree()
	end)
	return true
end

---@param role string
---@param objective string
---@param difficulty? "d0"|"d1"|"d2"|"d3"|"d4"
---@param parent_node? string
---@return boolean
function Session:delegate(role, objective, difficulty, parent_node)
	if self.closed or not self.ready or not self.session_id then
		vim.notify("Phenix: session is not ready", vim.log.levels.WARN)
		return false
	end
	role = vim.trim(role or "")
	objective = vim.trim(objective or "")
	if role == "" or objective == "" then
		vim.notify("Phenix: delegate role and objective are required", vim.log.levels.WARN)
		return false
	end
	self.client:request("_phenix/node/delegate", {
		tree_id = self.session_id,
		parent_node = parent_node or self.root_node_id,
		role = role,
		difficulty = difficulty,
		objective = objective,
	}, function(_, error_value)
		if error_value then
			self.ui:append_error(format_rpc_error("failed to delegate", error_value))
			return
		end
		self:_refresh_tree()
	end)
	return true
end

function Session:submit(text, behavior, images)
	behavior = behavior or "send"
	if #(images or {}) > 0 and behavior ~= "send" then
		vim.notify("Phenix: images can only be sent with a new prompt", vim.log.levels.WARN)
		return false
	end
	if behavior == "steer" then
		return self:steer(text)
	elseif behavior == "follow_up" then
		return self:follow_up(text)
	end
	return self:prompt(text, nil, images)
end

function Session:_notification(method, params)
	if method == "_phenix/session_tree/updated" then
		self.tree = params.tree or params
		self.info:set_tree(self.tree)
		return
	end
	if method ~= "session/update" then
		return
	end
	if self.session_id and params.sessionId ~= self.session_id then
		return
	end
	self.ui:append_update(params.update or params)
end

function Session:_refresh_tree(callback)
	if not self.session_id or self.closed then
		return
	end
	self.client:request("_phenix/session_tree/get", { tree_id = self.session_id }, function(tree, error_value)
		if error_value then
			vim.notify(format_rpc_error("failed to refresh Phenix session tree", error_value), vim.log.levels.WARN)
			return
		end
		self.tree = tree
		self.info:set_tree(tree)
		if callback then
			callback(tree)
		end
	end)
end

function Session:toggle_info()
	if not self.ui:is_visible() then
		vim.notify("Phenix: open the session before opening its info panels", vim.log.levels.WARN)
		return false
	end
	local opened = self.info:toggle()
	if opened then
		self:_refresh_tree(function()
			self:_update_info_files(self.root_node_id)
		end)
	end
	return opened
end

function Session:_update_info_files(node_id)
	local tree = self.tree
	if not tree or not node_id then
		return
	end
	local descendants = {}
	local pending = 0
	local paths = {}
	local children = {}
	for _, node in ipairs(tree.nodes or {}) do
		children[node.parent or false] = children[node.parent or false] or {}
		table.insert(children[node.parent or false], node.id)
	end
	local function visit(id)
		table.insert(descendants, id)
		for _, child in ipairs(children[id] or {}) do
			visit(child)
		end
	end
	visit(node_id)
	for _, id in ipairs(descendants) do
		pending = pending + 1
		self.client:request("_phenix/node/transcript/get", {
			tree_id = self.session_id,
			node_id = id,
		}, function(transcript)
			for _, path in ipairs((transcript or {}).edited_paths or {}) do
				paths[path] = true
			end
			pending = pending - 1
			if pending == 0 then
				local sorted = vim.tbl_keys(paths)
				table.sort(sorted)
				self.info:set_files(sorted)
			end
		end)
	end
end

function Session:select_transcript()
	self:_refresh_tree(function(tree)
		vim.ui.select(tree.nodes or {}, {
			prompt = "Phenix session transcript",
			format_item = function(node)
				return string.format("%s · %s · %s", node.role, node.state, node.id)
			end,
		}, function(node)
			if node then
				self:show_node_transcript(node.id)
			end
		end)
	end)
end

function Session:restore()
	self.client:request("_phenix/session_tree/list", {}, function(result, error_value)
		if error_value then
			vim.notify(format_rpc_error("failed to list Phenix sessions", error_value), vim.log.levels.WARN)
			return
		end
		vim.ui.select((result or {}).trees or {}, {
			prompt = "Restore Phenix session",
			format_item = function(tree)
				return string.format("%s · %s", tree.tree_id, tree.definition_id)
			end,
		}, function(summary)
			if not summary then
				return
			end
			self.client:request("_phenix/session_tree/get", { tree_id = summary.tree_id }, function(tree, tree_error)
				if tree_error then
					vim.notify(format_rpc_error("failed to restore Phenix session", tree_error), vim.log.levels.WARN)
					return
				end
				self.session_id = tree.id
				self.root_node_id = tree.root
				self.tree = tree
				self.info:set_tree(tree)
				self.ready = true
				self:show_node_transcript(tree.root)
			end)
		end)
	end)
end

function Session:show_node_transcript(node_id)
	if node_id == self.root_node_id and self.session_id == self.main_tree_id then
		self.ui:show_main_transcript()
		self:_update_info_files(node_id)
		return
	end
	self.client:request("_phenix/node/transcript/get", {
		tree_id = self.session_id,
		node_id = node_id,
	}, function(transcript, error_value)
		if error_value then
			vim.notify(format_rpc_error("failed to load node transcript", error_value), vim.log.levels.WARN)
			return
		end
		local buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buffer, "phenix://transcript/" .. node_id)
		vim.bo[buffer].buftype = "nofile"
		vim.bo[buffer].bufhidden = "hide"
		vim.bo[buffer].swapfile = false
		vim.bo[buffer].filetype = "markdown"
		local lines = {}
		for _, event in ipairs((transcript or {}).events or {}) do
			if event.kind == "text" then
				vim.list_extend(lines, { "## Phenix", "", event.text, "" })
			elseif event.kind == "thought" then
				vim.list_extend(lines, { "### Thinking", "", event.text, "" })
			elseif event.kind == "tool_started" then
				vim.list_extend(lines, { "### Tool · " .. event.name, "", "```json", event.raw_input_json, "```", "" })
			elseif event.kind == "failed" then
				vim.list_extend(lines, { "### Error", "", event.message, "" })
			end
		end
		vim.bo[buffer].modifiable = true
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, #lines > 0 and lines or { "No transcript events." })
		vim.bo[buffer].modifiable = false
		self.ui:show_transcript(buffer)
		self:_update_info_files(node_id)
	end)
end

function Session:toggle_ui(options)
	if self.ui:is_visible() then
		self.info:hide()
	end
	self.ui:toggle(options)
end

function Session:toggle_maximize_input()
	self.ui:toggle_maximize()
end

function Session:focus_input()
	if not self.ui:is_visible() then
		self.ui:mount()
	else
		self.ui:focus_input()
	end
end

function Session:shutdown(close_ui)
	if self.closed then
		return
	end
	self.closed = true
	self.ready = false
	self.prompting = false
	self.cancelling = false
	self.follow_ups = {}
	self.ui:set_follow_ups(self.follow_ups)
	if self.auth_terminal then
		self.auth_terminal:destroy()
		self.auth_terminal = nil
	end

	local client = self.client
	if close_ui == false then
		if client then
			client:stop()
		end
	elseif self.session_id and client and not client.stopped then
		client:request("session/close", { sessionId = self.session_id }, function()
			client:stop()
		end)
	elseif client then
		client:stop()
	end

	if close_ui ~= false and self.ui then
		self.info:hide()
		self.ui:close()
	end
end

M.Session = Session

return M
