---@generic T
---@class PhenixInterface<T>
---@field name string
---@field contract table<string, string>
---@field private implementation T|nil
local Interface = {}
Interface.__index = Interface

---@generic T
---@param name string
---@param contract? table<string, string>
---@return PhenixInterface<T>
function Interface.new(name, contract)
  vim.validate("name", name, "string")
  return setmetatable({
    name = name,
    contract = contract or {},
    implementation = nil,
  }, Interface)
end

---@param implementation any
---@return any
function Interface:implement(implementation)
  vim.validate("implementation", implementation, "table")
  for field, expected in pairs(self.contract) do
    local actual = type(implementation[field])
    if actual ~= expected then
      error(string.format("Phenix interface %s.%s must be %s, got %s", self.name, field, expected, actual))
    end
  end
  self.implementation = implementation
  return implementation
end

---@return boolean
function Interface:available()
  return self.implementation ~= nil
end

---@generic T
---@return T
function Interface:get()
  if self.implementation == nil then
    error("Phenix interface is unavailable: " .. self.name)
  end
  return self.implementation
end

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

---@class PhenixSessionFeature
---@field pick fun(): any
---@field save fun(name?: string): any
---@field load fun(name?: string): any

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

---@class PhenixAcpFrontend
---@field setup fun(options?: PhenixOptions): PhenixSettings
---@field toggle fun(options?: PhenixOptions): Phenix.Session
---@field maximize fun(): Phenix.Session|nil
---@field cancel fun(): boolean
---@field current fun(): Phenix.Session|nil
---@field shutdown fun()

---@class PhenixInterfaces
---@field picker? PhenixPicker
---@field terminal? PhenixTerminal
---@field notifier? PhenixNotifier
---@field explorer? PhenixExplorer
---@field dashboard? PhenixDashboard
---@field session? PhenixSessionFeature
---@field acp? PhenixAcpFrontend
---@field git? table
---@field lsp? PhenixLsp
---@field completion? table
---@field theme? table
---@field bars? table
---@field color_preview? table

---@class PhenixGlobal
---@field config table<string, any>
---@field state table<string, any>
---@field interfaces PhenixInterfaces
---@field interface fun(name: string): any
---@field define_interface fun(name: string, contract?: table<string, string>): PhenixInterface<any>
---@field provide fun(name: string, implementation: table, opts?: table): any

local M = {}
local definitions = {}

local global = rawget(_G, "Phenix")
if type(global) ~= "table" then
  global = {
    config = {},
    state = {},
    interfaces = {},
  }
  _G.Phenix = global
else
  global.config = global.config or {}
  global.state = global.state or {}
  global.interfaces = global.interfaces or {}
end

---@param name string
---@param contract? table<string, string>
---@return PhenixInterface<any>
function M.define_interface(name, contract)
  local interface = definitions[name]
  if interface then
    return interface
  end
  interface = Interface.new(name, contract)
  definitions[name] = interface
  return interface
end

---@param name string
---@param implementation table
---@param opts? { contract?: table<string, string>, config?: any, state?: any }
---@return table
function M.provide(name, implementation, opts)
  opts = opts or {}
  local interface = M.define_interface(name, opts.contract)
  interface:implement(implementation)
  global.interfaces[name] = implementation
  if opts.config ~= nil then
    global.config[name] = opts.config
  end
  if opts.state ~= nil then
    global.state[name] = opts.state
  elseif global.state[name] == nil then
    global.state[name] = {}
  end
  return implementation
end

---@param name string
---@return any
function M.interface(name)
  local interface = definitions[name]
  if interface then
    return interface:get()
  end
  local implementation = global.interfaces[name]
  if implementation == nil then
    error("Phenix interface is unavailable: " .. tostring(name))
  end
  return implementation
end

---@return PhenixGlobal
function M.global()
  global.interface = M.interface
  global.define_interface = M.define_interface
  global.provide = M.provide
  return global
end

M.Interface = Interface
M.global()

return M
