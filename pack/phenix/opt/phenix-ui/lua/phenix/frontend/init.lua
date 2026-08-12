---@generic T
---@class PhenixApiSurface<T>
---@field name string
---@field contract table<string, string>
---@field private implementation T|nil
local ApiSurface = {}
ApiSurface.__index = ApiSurface

---@generic T
---@param name string
---@param contract? table<string, string>
---@return PhenixApiSurface<T>
function ApiSurface.new(name, contract)
  vim.validate("name", name, "string")
  return setmetatable({
    name = name,
    contract = contract or {},
    implementation = nil,
  }, ApiSurface)
end

---@param implementation any
---@return any
function ApiSurface:bind(implementation)
  vim.validate("implementation", implementation, "table")
  if self.implementation ~= nil and self.implementation ~= implementation then
    error("Phenix API already has an implementation: " .. self.name)
  end
  for field, expected in pairs(self.contract) do
    local actual = type(implementation[field])
    if actual ~= expected then
      error(string.format("Phenix API %s.%s must be %s, got %s", self.name, field, expected, actual))
    end
  end
  self.implementation = implementation
  return implementation
end

---@return boolean
function ApiSurface:available()
  return self.implementation ~= nil
end

---@generic T
---@return T
function ApiSurface:get()
  if self.implementation == nil then
    error("Phenix API is unavailable: " .. self.name)
  end
  return self.implementation
end

---@class PhenixWindowApi
---@field set_options fun(window: integer, options: table<string, any>)
---@field configure_text fun(window: integer)
---@field scratch fun(name: string, opts?: table): integer, integer

---@class PhenixUi
---@field window PhenixWindowApi

---@class PhenixPicker
---@field smart fun(opts?: table): any
---@field buffers fun(opts?: table): any
---@field grep fun(opts?: table): any
---@field command_history fun(opts?: table): any
---@field diagnostics_buffer fun(opts?: table): any
---@field diagnostics fun(opts?: table): any
---@field files fun(opts?: table): any
---@field git_files fun(opts?: table): any
---@field lines fun(opts?: table): any
---@field marks fun(opts?: table): any
---@field projects fun(opts?: table): any
---@field rename_file fun(opts?: table): any
---@field recent fun(opts?: table): any
---@field grep_word fun(opts?: table): any
---@field autocmds fun(opts?: table): any
---@field commands fun(opts?: table): any
---@field highlights fun(opts?: table): any
---@field help fun(opts?: table): any
---@field icons fun(opts?: table): any
---@field keymaps fun(opts?: table): any
---@field man fun(opts?: table): any
---@field git_status fun(opts?: table): any
---@field git_branches fun(opts?: table): any
---@field git_log fun(opts?: table): any
---@field git_log_line fun(opts?: table): any
---@field git_diff fun(opts?: table): any
---@field git_stash fun(opts?: table): any
---@field gh_issue fun(opts?: table): any
---@field gh_pr fun(opts?: table): any
---@field lsp_definitions fun(opts?: table): any
---@field lsp_implementations fun(opts?: table): any
---@field lsp_references fun(opts?: table): any
---@field lsp_type_definitions fun(opts?: table): any

---@class PhenixTerminal
---@field toggle fun(opts?: table): any

---@class PhenixNotifier
---@field history fun(): any
---@field hide fun(): any

---@class PhenixExplorer
---@field open fun(opts?: table): any

---@class PhenixDashboard
---@field open fun(opts?: table): any

---@class PhenixSessionApi
---@field pick fun(): any
---@field save fun(name?: string): any
---@field load fun(name?: string): any

---@class PhenixGit
---@field status fun(buf?: integer): table|nil
---@field remote fun(buf?: integer): table|nil
---@field refresh fun()
---@field is_sign_namespace fun(namespace: string): boolean

---@class PhenixLsp
---@field diagnostic_open fun(): any
---@field diagnostic_prev fun(): any
---@field diagnostic_next fun(): any
---@field code_action fun(): any
---@field declaration fun(): any
---@field hover fun(): any
---@field inlay_toggle fun(): any
---@field rename fun(): any
---@field workspace_add fun(): any
---@field workspace_remove fun(): any
---@field workspace_list fun(): any

---@class PhenixCompletion
---@field show fun(): any
---@field hide fun(): any

---@class PhenixTheme
---@field colors fun(): table

---@class PhenixBars
---@field configure fun(options?: PhenixBarsConfig): table<string, PhenixBarsSurface>
---@field current fun(): table<string, PhenixBarsSurface>
---@field render fun(surface: string): string
---@field register_click fun(name: string, callback: function)
---@field render_part fun(part: PhenixBarsPart|string|number|false|nil): string

---@class PhenixColorPreview
---@field configure fun(options?: PhenixColorPreviewConfig): PhenixColorPreviewConfig
---@field is_open fun(): boolean
---@field close fun()
---@field toggle fun()

---@class PhenixAcpFrontend
---@field setup fun(options?: PhenixOptions): PhenixSettings
---@field toggle fun(options?: PhenixOptions): Phenix.Session
---@field maximize fun(): Phenix.Session|nil
---@field cancel fun(): boolean
---@field current fun(): Phenix.Session|nil
---@field shutdown fun()

---@class PhenixApi
---@field ui? PhenixUi
---@field picker? PhenixPicker
---@field terminal? PhenixTerminal
---@field notifier? PhenixNotifier
---@field explorer? PhenixExplorer
---@field dashboard? PhenixDashboard
---@field session? PhenixSessionApi
---@field acp? PhenixAcpFrontend
---@field git? PhenixGit
---@field lsp? PhenixLsp
---@field completion? PhenixCompletion
---@field theme? PhenixTheme
---@field bars? PhenixBars
---@field color_preview? PhenixColorPreview

---@class PhenixConfig
---@field ui? table
---@field picker? table
---@field terminal? table
---@field notifier? table
---@field explorer? table
---@field dashboard? table
---@field session? table
---@field acp? PhenixSettings|table
---@field git? table
---@field lsp? table
---@field completion? table
---@field theme? table
---@field bars? table
---@field color_preview? PhenixColorPreviewConfig|table

---@class PhenixState
---@field ui? table
---@field picker? table
---@field terminal? table
---@field notifier? table
---@field explorer? table
---@field dashboard? table
---@field session? table
---@field acp? { session?: Phenix.Session }
---@field git? table
---@field lsp? table
---@field completion? table
---@field theme? table
---@field bars? table
---@field color_preview? table

---@class PhenixApiRegistration
---@field contract? table<string, string>
---@field config? table
---@field state? table

---@class PhenixGlobal
---@field config PhenixConfig
---@field state PhenixState
---@field api PhenixApi
---@field require_api fun(name: string): any
---@field define_api fun(name: string, contract?: table<string, string>): PhenixApiSurface<any>
---@field register_api fun(name: string, implementation: table, opts?: PhenixApiRegistration): any

local M = {}
local definitions = {}

---@param owner table
---@param name string
---@return table
local function namespace(owner, name)
  local value = owner[name]
  if value == nil then
    value = {}
    owner[name] = value
  elseif type(value) ~= "table" then
    error(string.format("Phenix.%s must be a table, got %s", name, type(value)))
  end
  return value
end

local global = rawget(_G, "Phenix")
if global == nil then
  global = {}
  _G.Phenix = global
elseif type(global) ~= "table" then
  error(string.format("Phenix must be a table, got %s", type(global)))
end

global.config = namespace(global, "config")
global.state = namespace(global, "state")
global.api = namespace(global, "api")

---@param target table
---@param defaults? table
---@return table
local function apply_defaults(target, defaults)
  if defaults == nil then
    return target
  end
  vim.validate("defaults", defaults, "table")
  for key, value in pairs(defaults) do
    if target[key] == nil then
      target[key] = type(value) == "table" and vim.deepcopy(value) or value
    end
  end
  return target
end

---@param name string
---@param defaults? table
---@return table
function M.config(name, defaults)
  vim.validate("name", name, "string")
  local value = global.config[name]
  if value == nil then
    value = {}
    global.config[name] = value
  elseif type(value) ~= "table" then
    error(string.format("Phenix.config.%s must be a table, got %s", name, type(value)))
  end
  return apply_defaults(value, defaults)
end

---@param name string
---@param initial? table
---@return table
function M.state(name, initial)
  vim.validate("name", name, "string")
  if initial ~= nil then
    vim.validate("initial", initial, "table")
  end

  local value = global.state[name]
  if value == nil then
    value = initial or {}
    global.state[name] = value
  elseif type(value) ~= "table" then
    error(string.format("Phenix.state.%s must be a table, got %s", name, type(value)))
  elseif initial ~= nil and value ~= initial then
    for key, item in pairs(value) do
      if initial[key] == nil then
        initial[key] = item
      end
    end
    value = initial
    global.state[name] = value
  end
  return value
end

---@param name string
---@param contract? table<string, string>
---@return PhenixApiSurface<any>
function M.define_api(name, contract)
  vim.validate("name", name, "string")
  local surface = definitions[name]
  if surface then
    return surface
  end
  surface = ApiSurface.new(name, contract)
  definitions[name] = surface
  return surface
end

---@param name string
---@param implementation table
---@param opts? PhenixApiRegistration
---@return table
function M.register_api(name, implementation, opts)
  opts = opts or {}
  vim.validate("opts", opts, "table")

  local existing = global.api[name]
  if existing ~= nil and existing ~= implementation then
    error("Phenix API already registered: " .. name)
  end

  local surface = M.define_api(name, opts.contract)
  surface:bind(implementation)
  global.api[name] = implementation
  M.config(name, opts.config)
  M.state(name, opts.state)
  return implementation
end

---@param name string
---@return any
function M.require_api(name)
  local surface = definitions[name]
  if surface then
    return surface:get()
  end
  local implementation = global.api[name]
  if implementation == nil then
    error("Phenix API is unavailable: " .. tostring(name))
  end
  return implementation
end

---@return PhenixGlobal
function M.global()
  global.require_api = M.require_api
  global.define_api = M.define_api
  global.register_api = M.register_api
  return global
end

M.ApiSurface = ApiSurface
M.global()

return M
