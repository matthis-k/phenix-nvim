local function fail(message)
  error("N4 smoke: " .. message, 0)
end

local function assert_true(value, message)
  if not value then
    fail(message)
  end
end

local function wait_for(predicate, message, timeout)
  if not vim.wait(timeout or 5000, predicate, 20) then
    fail(message)
  end
end

local function has_entry(session, kind, text)
  for _, entry in ipairs(session.ui.entries or {}) do
    if entry.kind == kind and (text == nil or tostring(entry.text or ""):find(text, 1, true)) then
      return true
    end
  end
  return false
end

local source = assert(debug.getinfo(1, "S").source:match("^@(.+)$"), "smoke test source path unavailable")
local test_root = vim.fs.dirname(source)
dofile(vim.fs.joinpath(test_root, "store_projection.lua"))
dofile(vim.fs.joinpath(test_root, "controller_reconciliation.lua"))

local python = vim.env.PHENIX_TEST_PYTHON or vim.fn.exepath("python3")
local fixture = vim.fs.joinpath(test_root, "fixture_conductor.py")
assert_true(python ~= "", "python3 is unavailable")
assert_true(vim.uv.fs_stat(fixture) ~= nil, "native conductor fixture is unavailable")

local markview_available = pcall(require, "markview")
local frontend = require("phenix.frontend")
local phenix = require("phenix")
assert_true(Phenix.api.acp == nil, "ACP protocol leaked into the public feature registry")
assert_true(Phenix.api.agent == phenix, "native agent frontend was not registered")
assert_true(frontend.require_api("agent") == phenix, "typed feature lookup did not resolve the native frontend")
assert_true(phenix.configuration == nil, "frontend runtime configuration API survived migration")
assert_true(phenix.start_workflow == nil, "unsupported workflow compatibility API survived migration")
assert_true(phenix.delegate == nil, "unsupported delegation compatibility API survived migration")

for _, plug in ipairs({
  "<Plug>(phenix-toggle)",
  "<Plug>(phenix-open-fullscreen)",
  "<Plug>(phenix-open-fullscreen-tab)",
  "<Plug>(phenix-maximize)",
  "<Plug>(phenix-toggle-info)",
  "<Plug>(phenix-restore)",
  "<Plug>(phenix-select-transcript)",
  "<Plug>(phenix-select-model)",
  "<Plug>(phenix-select-skill)",
  "<Plug>(phenix-authenticate)",
  "<Plug>(phenix-refresh-skills)",
  "<Plug>(phenix-cancel)",
  "<Plug>(phenix-shutdown)",
}) do
  assert_true(vim.fn.maparg(plug, "n", false, true).lhs ~= "", "missing public mapping: " .. plug)
end

phenix.setup({
  conductor_command = { python, fixture },
  conductor_cwd_arg = false,
})
assert_true(Phenix.config.agent.conductor_cwd_arg == false, "agent settings were not projected into Phenix.config")

local session = phenix.toggle({ cwd = vim.fn.getcwd() })
wait_for(function()
  return session:is_ready()
end, "native conductor session did not become ready")

assert_true(Phenix.state.agent.session == session, "live session was not projected into Phenix.state")
assert_true(session.controller ~= nil, "live session does not own a native conductor controller")
assert_true(session.acp == nil, "live session still exposes an ACP client")
assert_true(session:activity_state() == "settled", "new session is unexpectedly active")
assert_true(session.controller:state().connection == "connected", "controller is not connected")
assert_true(session.controller:session().default_target.value.model == "fixture-model", "catalog target was not selected")
assert_true(session.ui:is_visible(), "frontend UI was not visible after opening")
assert_true(not phenix.toggle_info(), "removed execution-tree info API unexpectedly remained active")

assert_true(phenix.refresh_skills(), "skill catalog refresh was rejected")
wait_for(function()
  return #phenix.skills() == 1
end, "skill catalog did not load")
local skills = phenix.skills()
assert_true(skills[1].id == "write", "unexpected bundled skill id")
assert_true(skills[1].invocation == "model_eligible", "write was not model eligible")
assert_true(session:state().skills[1].description:find("Writing documents for any audience", 1, true) ~= nil, "skill state lost its description")

assert_true(vim.bo[session.ui.transcript_buffer].filetype == "markdown", "transcript is not a markdown buffer")
assert_true(not vim.wo[session.ui.transcript_window].number, "transcript line numbers are enabled")
assert_true(not vim.wo[session.ui.transcript_window].relativenumber, "transcript relative line numbers are enabled")
assert_true(vim.wo[session.ui.transcript_window].statuscolumn == "", "transcript status column is enabled")
assert_true(vim.wo[session.ui.input_window].statuscolumn == "", "input status column is enabled")
assert_true(
  vim.api.nvim_win_get_width(session.ui.transcript_window) >= math.floor(vim.o.columns * 0.45),
  "default frontend width is not approximately half the editor"
)
assert_true(
  vim.api.nvim_win_get_height(session.ui.input_window) >= 6 and vim.api.nvim_win_get_height(session.ui.input_window) <= 20,
  "default prompt height did not respect its bounds"
)
vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "one", "two", "three", "four", "five", "six" })
session.ui:_resize_input()
assert_true(vim.api.nvim_win_get_height(session.ui.input_window) == 6, "prompt height did not fit its visual lines")
vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "" })
session.ui:_resize_input()
if markview_available then
  assert_true(
    vim.api.nvim_get_option_value("conceallevel", { win = session.ui.transcript_window }) == 3,
    "transcript window was not prepared for Markview conceal rendering"
  )
end

vim.api.nvim_set_current_win(session.ui.input_window)
assert_true(vim.fn.maparg("<CR>", "n", false, true).lhs ~= "", "normal Enter does not send")
assert_true(vim.fn.maparg("<S-CR>", "n", false, true).lhs ~= "", "normal Shift-Enter mapping disappeared")
assert_true(vim.fn.maparg("<M-CR>", "n", false, true).lhs ~= "", "normal Alt-Enter does not queue a follow-up")
assert_true(vim.fn.maparg("<CR>", "i") == "", "insert Enter should remain an ordinary newline")

vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "hello from neovim" })
vim.cmd("write")
wait_for(function()
  return session:activity_state() == "settled" and has_entry(session, "assistant", "echo: hello from neovim")
end, "writing the input buffer did not complete a native prompt")
local transcript = session.ui:text()
assert_true(transcript:find("## You", 1, true) ~= nil, "submitted input did not get a user transcript block")
assert_true(transcript:find("hello from neovim", 1, true) ~= nil, "submitted input text is missing")
assert_true(transcript:find("### Thinking", 1, true) ~= nil, "reasoning was not rendered as transcript detail")
assert_true(transcript:find("## Phenix", 1, true) ~= nil, "assistant transcript block is missing")
assert_true(transcript:find("echo: hello from neovim", 1, true) ~= nil, "assistant text was not rendered")

assert_true(session:prompt("/write rewrite this"), "explicit write prompt was rejected")
wait_for(function()
  return session:activity_state() == "settled" and has_entry(session, "assistant", "echo: /write rewrite this")
end, "explicit write request did not reach the conductor unchanged")

assert_true(session:prompt("rich transcript"), "rich transcript prompt was rejected")
wait_for(function()
  return session:activity_state() == "settled" and has_entry(session, "assistant", "echo: rich transcript")
end, "semantic transcript did not settle")
assert_true(has_entry(session, "user", "rich transcript"), "user input was not projected")
assert_true(has_entry(session, "thinking", "thinking about: rich transcript"), "reasoning was not projected")
assert_true(next(session.ui.tool_entries) ~= nil, "tool call was not projected")

transcript = session.ui:text()
assert_true(
  transcript:find("### Tool · read README · completed · path=README.md", 1, true) ~= nil,
  "tool call header did not summarize its primary parameter"
)
assert_true(transcript:find('`path`: "README.md"', 1, true) ~= nil, "tool input path is missing")
assert_true(
  transcript:find("```text\nfirst line\nsecond line\n```", 1, true) ~= nil,
  "multiline tool input was flattened instead of rendered as lines"
)
assert_true(transcript:find("README contents", 1, true) ~= nil, "tool output is missing")
assert_true(transcript:find("echo: rich transcript", 1, true) ~= nil, "assistant content after tool call is missing")
if markview_available then
  assert_true(session.ui.markview_render_count > 0, "Markview was available but never rendered the transcript")
end

local tool_range = assert(session.ui.fold_ranges["tool:fixture-tool"], "tool details did not receive a fold")
local tool_fold = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.foldclosed(tool_range.start_line)
end)
assert_true(tool_fold ~= -1, "tool details were not folded closed by default")
local tool_preview = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.foldtextresult(tool_range.start_line)
end)
assert_true(tool_preview:find("Tool · read README · completed", 1, true) ~= nil, "tool fold preview lost tool status")
assert_true(tool_preview:find("path=README.md", 1, true) ~= nil, "tool fold preview lost parameter summary")

local thinking_range = nil
for _, entry in ipairs(session.ui.entries) do
  if entry.kind == "thinking" and entry.text:find("rich transcript", 1, true) then
    thinking_range = session.ui.fold_ranges[entry.id]
    break
  end
end
assert_true(thinking_range ~= nil, "thinking detail did not receive a fold")
local thinking_preview = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.foldtextresult(thinking_range.start_line)
end)
assert_true(
  thinking_preview:find("Thinking · thinking about: rich transcript", 1, true) ~= nil,
  "thinking fold preview does not summarize the thought"
)
vim.api.nvim_win_call(session.ui.transcript_window, function()
  vim.cmd(string.format("silent! %dfoldopen", thinking_range.start_line))
end)
assert_true(
  vim.api.nvim_win_call(session.ui.transcript_window, function()
    return vim.fn.foldclosed(thinking_range.start_line)
  end) == -1,
  "thinking fold did not open before the update"
)
local thinking_entry = assert(session.ui.entries_by_id[thinking_range.id], "thinking entry disappeared before the update")
thinking_entry.text = thinking_entry.text .. " and preserving the open fold"
session.ui:_schedule_render()
session.ui:_flush_render()
local updated_thinking_range = assert(session.ui.fold_ranges[thinking_range.id], "thinking fold identity changed after update")
assert_true(session.ui.entries_by_id[thinking_range.id].expanded, "thinking fold state was not captured before update")
assert_true(
  vim.api.nvim_win_call(session.ui.transcript_window, function()
    return vim.fn.foldclosed(updated_thinking_range.start_line)
  end) == -1,
  "streamed transcript update closed an expanded fold"
)

vim.api.nvim_set_current_win(session.ui.transcript_window)
vim.api.nvim_win_set_cursor(session.ui.transcript_window, { 2, 0 })
vim.api.nvim_win_call(session.ui.transcript_window, function()
  vim.cmd("silent! normal! zt")
end)
local cursor_before_render = vim.api.nvim_win_get_cursor(session.ui.transcript_window)
local viewport_before_render = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.winsaveview().topline
end)
session.ui:append_assistant("cursor-safe tail", "cursor-safe")
session.ui:finish_response()
assert_true(
  vim.deep_equal(vim.api.nvim_win_get_cursor(session.ui.transcript_window), cursor_before_render),
  "transcript rendering did not preserve a non-tail cursor line"
)
local viewport_after_render = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.winsaveview().topline
end)
assert_true(viewport_after_render == viewport_before_render, "rendering moved the viewport away from a non-tail cursor")

local previous_last_line = vim.api.nvim_buf_line_count(session.ui.transcript_buffer)
vim.api.nvim_win_set_cursor(session.ui.transcript_window, { previous_last_line, 0 })
vim.api.nvim_win_call(session.ui.transcript_window, function()
  vim.cmd("silent! normal! zt")
end)
session.ui:append_assistant("bottom-follow tail\nsecond tail line", "bottom-follow")
session.ui:finish_response()
local new_last_line = vim.api.nvim_buf_line_count(session.ui.transcript_buffer)
assert_true(
  vim.api.nvim_win_get_cursor(session.ui.transcript_window)[1] == new_last_line,
  "tail-follow rendering did not keep the cursor on the new last line"
)
local visible_bottom = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.line("w$")
end)
assert_true(visible_bottom == new_last_line, "tail-follow rendering did not keep the last line at the viewport bottom")

vim.api.nvim_set_current_win(session.ui.input_window)
local renders_before_burst = session.ui.render_count
local markview_before_burst = session.ui.markview_render_count
for _ = 1, 64 do
  session.ui:append_assistant("x", "render-burst")
end
session.ui:finish_response()
wait_for(function()
  return session.ui:text():find(string.rep("x", 20), 1, true) ~= nil
end, "coalesced transcript render burst did not flush", 1000)
local burst_renders = session.ui.render_count - renders_before_burst
assert_true(burst_renders < 25, string.format("render burst caused %d full transcript renders", burst_renders))
if markview_available then
  local markview_burst = session.ui.markview_render_count - markview_before_burst
  assert_true(markview_burst < 5, string.format("render burst caused %d Markview reparses", markview_burst))
end

assert_true(session:prompt("hold"), "held prompt was rejected")
wait_for(function()
  return session:activity_state() == "running"
end, "held execution did not become active")

vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "afterwards" })
assert_true(session.ui:submit_input("follow_up"), "follow-up input was rejected while execution was active")
assert_true(#session.follow_ups == 1, "follow-up was not queued")
assert_true(session.ui.follow_up_window and vim.api.nvim_win_is_valid(session.ui.follow_up_window), "follow-up queue did not open")
vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "later" })
assert_true(session.ui:submit_input("follow_up"), "second follow-up input was rejected")
assert_true(#session.ui.follow_up_windows == 2, "each queued follow-up did not receive its own window")
assert_true(
  vim.wo[session.ui.follow_up_windows[1]].winbar:find("Follow-up 1/2", 1, true) ~= nil,
  "follow-up winbar did not show its queue position"
)
vim.api.nvim_buf_set_lines(session.ui.follow_up_buffers[1], 0, -1, false, { "edited afterwards" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = session.ui.follow_up_buffers[1] })
assert_true(session.follow_ups[1] == "edited afterwards", "editing a queued follow-up did not update pending state")
assert_true(session:steer("not supported") == false, "steering bypassed the normalized conductor protocol")
assert_true(phenix.cancel(), "cancel was rejected")
wait_for(function()
  return session:activity_state() == "settled"
end, "cancelled execution did not settle")
assert_true(#session.follow_ups == 0, "cancel retained queued follow-ups")
assert_true(session.ui.follow_up_window == nil, "cancel retained the follow-up queue window")

local previous_select = vim.ui.select
local selection_prompts = {}
local routing_choices_seen = false
vim.ui.select = function(items, options, callback)
  selection_prompts[#selection_prompts + 1] = options.prompt
  if options.prompt == "Model or routing" then
    local provider = nil
    local routes = 0
    for _, item in ipairs(items) do
      if item.kind == "routing" then
        routes = routes + 1
      elseif item.kind == "provider" and item.value and item.value.provider == "fixture" then
        provider = item
      end
    end
    assert_true(routes == 2, "model picker did not expose both routing profiles")
    assert_true(provider ~= nil, "model picker did not expose the fixture provider")
    routing_choices_seen = true
    callback(provider)
    return
  end
  if options.prompt and options.prompt:find("Model ·", 1, true) == 1 then
    for _, model in ipairs(items) do
      if model.target and model.target.model == "fixture-alt" then
        callback(model)
        return
      end
    end
  end
  callback(items[1])
end
assert_true(phenix.select_model(), "provider-first model picker was not opened")
wait_for(function()
  local current = session.controller:session()
  local catalogs = session.controller:state().catalogs
  return current
    and current.default_target.value.model == "fixture-alt"
    and catalogs[1]
    and catalogs[1].authentication_state == "authenticated"
end, "provider authentication and model selection did not complete")
assert_true(routing_choices_seen, "routing profiles were not shown in model selection")
assert_true(selection_prompts[1] == "Model or routing", "model selection did not start with provider/routing selection")
assert_true(
  vim.tbl_contains(selection_prompts, "Model · fixture"),
  "model selection did not continue to the selected provider's model list"
)
vim.ui.select = previous_select

previous_select = vim.ui.select
vim.ui.select = function(items, _, callback)
  callback(items[1])
end
assert_true(phenix.authenticate(), "authentication picker was not opened")
wait_for(function()
  local catalogs = session.controller:state().catalogs
  return catalogs[1] and catalogs[1].authentication_state == "authenticated"
end, "typed authentication selection did not update the catalog")
vim.ui.select = previous_select

local selected, selection_error = session.controller:use_session(session.session_id)
assert_true(selected ~= nil and selection_error == nil, "controller could not select an existing session")
local missing, missing_error = session.controller:use_session("missing-session")
assert_true(missing == nil and missing_error and missing_error.code == "unknown_session", "unknown session was not rejected")

local process = session.controller.client.transport.process
assert_true(process ~= nil and not session.controller.client.stopped, "native conductor process was not running")
phenix.toggle()
assert_true(not session.ui:is_visible(), "second toggle did not hide the frontend")
assert_true(session.controller:state().connection == "connected", "hiding the frontend changed conductor connection state")
assert_true(session.controller.client.transport.process == process, "hiding the frontend restarted conductor transport")
phenix.toggle()
assert_true(session.ui:is_visible(), "third toggle did not restore the frontend")
assert_true(session.ui:text():find("README contents", 1, true) ~= nil, "transcript did not survive frontend toggle")

local transcript_window = session.ui.transcript_window
local input_window = session.ui.input_window
vim.api.nvim_win_close(input_window, true)
wait_for(function()
  return not vim.api.nvim_win_is_valid(input_window)
    and not vim.api.nvim_win_is_valid(transcript_window)
    and not session.ui:is_visible()
end, "closing the prompt window did not close the transcript window group", 1000)
assert_true(session.controller:state().connection == "connected", "closing the UI group stopped the conductor")

phenix.toggle()
assert_true(session.ui:is_visible(), "frontend did not reopen after closing its prompt window")
transcript_window = session.ui.transcript_window
input_window = session.ui.input_window
vim.api.nvim_win_close(transcript_window, true)
wait_for(function()
  return not vim.api.nvim_win_is_valid(input_window)
    and not vim.api.nvim_win_is_valid(transcript_window)
    and not session.ui:is_visible()
end, "closing the transcript window did not close the prompt window group", 1000)
assert_true(session.controller:state().connection == "connected", "closing the transcript group stopped conductor")

phenix.toggle()
assert_true(session.ui:is_visible(), "frontend did not reopen after closing its transcript window")
assert_true(session.ui:text():find("README contents", 1, true) ~= nil, "transcript did not survive grouped window closing")

local tabs_before = #vim.api.nvim_list_tabpages()
phenix.toggle()
phenix.toggle({
  tab = true,
  fullscreen = true,
  width = 0.5,
  input_height = 0.25,
  input_height_min = 5,
  input_height_max = 5,
})
assert_true(#vim.api.nvim_list_tabpages() == tabs_before + 1, "tab toggle did not open a new tab")
assert_true(session.ui:is_visible(), "tab toggle did not mount the frontend")
assert_true(vim.api.nvim_win_get_height(session.ui.input_window) == 5, "per-call input height bounds were not applied")
assert_true(#vim.api.nvim_tabpage_list_wins(0) == 2, "fullscreen toggle did not close other windows in its tab")

phenix.maximize()
assert_true(not session.ui:is_visible(), "maximize did not hide the transcript")
assert_true(vim.api.nvim_get_current_win() == session.ui.input_window, "maximize did not focus the prompt")
vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "send from maximized prompt" })
assert_true(session.ui:submit_input("send"), "maximized prompt was not sent")
assert_true(session.ui:is_visible(), "sending from maximize did not restore the transcript")
wait_for(function()
  return session:activity_state() == "settled" and has_entry(session, "assistant", "echo: send from maximized prompt")
end, "maximized prompt did not finish")
phenix.maximize()
phenix.maximize()
assert_true(session.ui:is_visible(), "second maximize did not restore the transcript")

phenix.shutdown()
assert_true(phenix.current() == nil, "shutdown retained the live session")
assert_true(Phenix.state.agent.session == nil, "shutdown retained the projected agent session")
assert_true(session.controller.client.stopped, "shutdown did not stop the native conductor client")

print("N4 native conductor smoke passed")