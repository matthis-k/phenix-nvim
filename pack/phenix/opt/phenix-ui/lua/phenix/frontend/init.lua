---@class PhenixWindowApi
---@field line fun(part: string|number|{text?: string|number, hl?: string, children?: table[]}|nil): string
---@field set_options fun(window: integer, options: table<string, any>)
---@field configure_text fun(window: integer)
---@field scratch fun(name: string, opts?: table): integer, integer
---@field group fun(opts?: {on_close?: fun()}): PhenixWindowGroup

---@class PhenixWindowGroup
---@field add_window fun(self: PhenixWindowGroup, window: integer): integer
---@field add_buffer fun(self: PhenixWindowGroup, buffer: integer): integer
---@field remove_window fun(self: PhenixWindowGroup, window: integer)
---@field detach_window fun(self: PhenixWindowGroup, window: integer)
---@field remove_buffer fun(self: PhenixWindowGroup, buffer: integer)
---@field unmount fun(self: PhenixWindowGroup)
---@field close fun(self: PhenixWindowGroup)
---@field destroy fun(self: PhenixWindowGroup)

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

---@class PhenixAgentFrontend
---@field setup fun(options?: PhenixOptions): PhenixSettings
---@field toggle fun(options?: PhenixOptions): Phenix.Session
---@field maximize fun(): Phenix.Session|nil
---@field cancel fun(): boolean
---@field toggle_info fun(): boolean
---@field restore fun(): boolean
---@field select_transcript fun(): boolean
---@field select_model fun(): boolean
---@field authenticate fun(): boolean
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
---@field agent? PhenixAgentFrontend
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
---@field agent? PhenixSettings|table
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
---@field agent? table
---@field git? table
---@field lsp? table
---@field completion? table
---@field theme? table
---@field bars? table
---@field color_preview? table

---@class PhenixGlobal
---@field config PhenixConfig
---@field state PhenixState
---@field api PhenixApi

local M = {}

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

---@param name string
---@param implementation table
---@return table
function M.project_api(name, implementation)
  vim.validate("name", name, "string")
  vim.validate("implementation", implementation, "table")
  global.api[name] = implementation
  return implementation
end

---@param name string
---@param value table
---@return table
function M.project_config(name, value)
  vim.validate("name", name, "string")
  vim.validate("value", value, "table")
  local snapshot = vim.deepcopy(value)
  global.config[name] = snapshot
  return snapshot
end

---@param name string
---@param value table
---@return table
function M.project_state(name, value)
  vim.validate("name", name, "string")
  vim.validate("value", value, "table")
  local snapshot = vim.deepcopy(value)
  global.state[name] = snapshot
  return snapshot
end

---@return PhenixGlobal
function M.global()
  return global
end

return M
