local fixture = assert(vim.env.PHENIX_TEST_FIXTURE, "PHENIX_TEST_FIXTURE is required")
local python = assert(vim.env.PHENIX_TEST_PYTHON, "PHENIX_TEST_PYTHON is required")
local config_file = vim.env.PHENIX_TEST_CONFIG

if config_file and config_file ~= "" then
  local configuration = require("phenix.config").load(config_file):params()
  assert(configuration.input.definition_id == "phenix.harness")
  assert(configuration.input.router == "router.mixed")
  assert(#configuration.input.backends > 0)
  assert(#configuration.input.definitions > 0)
end

local markview_available = pcall(require, "markview")
local phenix = require("phenix")
phenix.setup({
  conductor_command = { python, fixture },
  conductor_cwd_arg = false,
  config = false,
})

assert(vim.fn.maparg("<leader>pp", "n") ~= "", "default Phenix toggle keymap was not installed")

local session = phenix.toggle({ cwd = vim.fn.getcwd() })
assert(vim.wait(5000, function()
  return session:is_ready()
end, 20), "Phenix ACP fixture session did not become ready")
assert(session.session_id == "fixture-session")
assert(session.root_node_id == "fixture-root")
assert(session.ui:is_visible(), "sidebar was not visible after the first toggle")
assert(vim.bo[session.ui.transcript_buffer].filetype == "markdown", "transcript is not a markdown buffer")

vim.api.nvim_set_current_win(session.ui.input_window)
assert(vim.fn.maparg("<CR>", "n") ~= "", "normal Enter does not send")
assert(vim.fn.maparg("<S-CR>", "n") ~= "", "normal Shift-Enter does not steer")
assert(vim.fn.maparg("<M-CR>", "n") ~= "", "normal Alt-Enter does not queue a follow-up")
assert(vim.fn.maparg("<CR>", "i") == "", "insert Enter should remain an ordinary newline")

vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "hello from neovim" })
vim.cmd("write")
assert(vim.wait(5000, function()
  return not session.prompting and session.ui:text():find("echo: hello from neovim", 1, true) ~= nil
end, 20), "writing the input buffer did not send the prompt")

local transcript = session.ui:text()
assert(transcript:find("## You", 1, true), "submitted input did not get a user transcript block")
assert(transcript:find("hello from neovim", 1, true), "submitted input text is missing")
assert(transcript:find("### Thinking", 1, true), "thinking was not rendered as transcript detail")
assert(transcript:find("## Phenix", 1, true), "assistant transcript block is missing")
assert(transcript:find("echo: hello from neovim", 1, true), "assistant text was not rendered")

vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "rich transcript" })
assert(session.ui:submit_input("send"), "normal send was rejected")
assert(vim.wait(5000, function()
  return not session.prompting and session.ui:text():find("README contents", 1, true) ~= nil
end, 20), "rich transcript fixture did not finish")

transcript = session.ui:text()
assert(transcript:find("### Tool · read README · completed", 1, true), "tool call header was not rendered distinctly")
assert(transcript:find('`path`: "README.md"', 1, true), "tool input path is missing")
assert(
  transcript:find("```text\nfirst line\nsecond line\n```", 1, true),
  "multiline tool input was flattened instead of rendered as lines"
)
assert(transcript:find("README contents", 1, true), "tool output is missing")
assert(transcript:find("**done** with the tool call", 1, true), "markdown assistant content is missing")
if markview_available then
  assert(session.ui.markview_render_count > 0, "Markview was available but never rendered the transcript")
end

local tool_range = assert(session.ui.fold_ranges["tool:fixture-tool"], "tool details did not receive a fold")
local tool_fold = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.foldclosed(tool_range.start_line)
end)
assert(tool_fold ~= -1, "tool details were not folded closed by default")
local tool_preview = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.foldtextresult(tool_range.start_line)
end)
assert(
  tool_preview:find("Tool · read README · completed", 1, true),
  "tool fold preview does not identify the tool and status"
)
assert(tool_preview:find("path=README.md", 1, true), "tool fold preview does not summarize parameters")

local thinking_range
for _, entry in ipairs(session.ui.entries) do
  if entry.kind == "thinking" and entry.text:find("rich transcript", 1, true) then
    thinking_range = session.ui.fold_ranges[entry.id]
    break
  end
end
assert(thinking_range, "thinking detail did not receive a fold")
local thinking_preview = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.foldtextresult(thinking_range.start_line)
end)
assert(
  thinking_preview:find("Thinking · thinking about: rich transcript", 1, true),
  "thinking fold preview does not summarize the thought"
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
assert(
  vim.deep_equal(vim.api.nvim_win_get_cursor(session.ui.transcript_window), cursor_before_render),
  "transcript rendering did not preserve a non-tail cursor line"
)
local viewport_after_render = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.winsaveview().topline
end)
assert(
  viewport_after_render == viewport_before_render,
  "transcript rendering moved the viewport while the cursor was away from the tail"
)

local previous_last_line = vim.api.nvim_buf_line_count(session.ui.transcript_buffer)
vim.api.nvim_win_set_cursor(session.ui.transcript_window, { previous_last_line, 0 })
vim.api.nvim_win_call(session.ui.transcript_window, function()
  vim.cmd("silent! normal! zt")
end)
session.ui:append_assistant("bottom-follow tail\nsecond tail line", "bottom-follow")
session.ui:finish_response()
local new_last_line = vim.api.nvim_buf_line_count(session.ui.transcript_buffer)
assert(
  vim.api.nvim_win_get_cursor(session.ui.transcript_window)[1] == new_last_line,
  "tail-follow rendering did not keep the cursor on the new last line"
)
local visible_bottom = vim.api.nvim_win_call(session.ui.transcript_window, function()
  return vim.fn.line("w$")
end)
assert(visible_bottom == new_last_line, "tail-follow rendering did not keep the last line at the viewport bottom")

vim.api.nvim_set_current_win(session.ui.input_window)
local renders_before_burst = session.ui.render_count
local markview_renders_before_burst = session.ui.markview_render_count
vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "render burst" })
vim.cmd("write")
assert(vim.wait(5000, function()
  return not session.prompting and session.ui:text():find(string.rep("x", 20), 1, true) ~= nil
end, 20), "streamed render burst did not finish")
local burst_renders = session.ui.render_count - renders_before_burst
assert(
  burst_renders < 25,
  string.format("stream burst caused %d full transcript renders instead of being coalesced", burst_renders)
)
if markview_available then
  local markview_burst_renders = session.ui.markview_render_count - markview_renders_before_burst
  assert(
    markview_burst_renders < 5,
    string.format("stream burst caused %d Markview reparses instead of being debounced", markview_burst_renders)
  )
end

vim.api.nvim_set_current_win(session.ui.input_window)
vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "scroll while streaming" })
vim.cmd("write")
assert(vim.wait(1000, function()
  return session.prompting
end, 10), "fixture prompt did not begin streaming")

vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "change direction" })
assert(session.ui:submit_input("steer"), "steering input was rejected while streaming")
assert(
  table.concat(vim.api.nvim_buf_get_lines(session.ui.input_buffer, 0, -1, false), "\n") == "",
  "steering input was not cleared after dispatch"
)

vim.api.nvim_buf_set_lines(session.ui.input_buffer, 0, -1, false, { "afterwards" })
assert(session.ui:submit_input("follow_up"), "follow-up input was rejected while streaming")
assert(
  table.concat(vim.api.nvim_buf_get_lines(session.ui.input_buffer, 0, -1, false), "\n") == "",
  "follow-up input was not cleared after queueing"
)

assert(vim.wait(5000, function()
  local text = session.ui:text()
  return not session.prompting
    and #session.follow_ups == 0
    and text:find("steered: change direction", 1, true) ~= nil
    and text:find("echo: afterwards", 1, true) ~= nil
end, 20), "steering/follow-up sequence did not complete")

transcript = session.ui:text()
assert(transcript:find("## Steer", 1, true), "steering was not represented in transcript chronology")
assert(transcript:find("## Follow-up", 1, true), "follow-up was not represented in transcript chronology")

local process = session.client.process
assert(process ~= nil and not session.client.stopped, "ACP process was not running")

phenix.toggle()
assert(not session.ui:is_visible(), "second toggle did not hide the sidebar")
assert(session.client.process == process and not session.client.stopped, "hiding the sidebar stopped the ACP process")

phenix.toggle()
assert(session.ui:is_visible(), "third toggle did not restore the sidebar")
assert(session.client.process == process and not session.client.stopped, "showing the sidebar restarted the ACP process")
assert(session.ui:text():find("README contents", 1, true), "transcript did not survive a sidebar toggle")

local transcript_window = session.ui.transcript_window
local input_window = session.ui.input_window
vim.api.nvim_win_close(input_window, true)
assert(vim.wait(1000, function()
  return not vim.api.nvim_win_is_valid(input_window)
    and not vim.api.nvim_win_is_valid(transcript_window)
    and not session.ui:is_visible()
end, 10), "closing the prompt window did not close the transcript window group")
assert(session.client.process == process and not session.client.stopped, "closing the UI window group stopped ACP")

phenix.toggle()
assert(session.ui:is_visible(), "sidebar did not reopen after closing its prompt window")
transcript_window = session.ui.transcript_window
input_window = session.ui.input_window
vim.api.nvim_win_close(transcript_window, true)
assert(vim.wait(1000, function()
  return not vim.api.nvim_win_is_valid(input_window)
    and not vim.api.nvim_win_is_valid(transcript_window)
    and not session.ui:is_visible()
end, 10), "closing the transcript window did not close the prompt window group")
assert(session.client.process == process and not session.client.stopped, "closing the transcript group stopped ACP")

phenix.toggle()
assert(session.ui:is_visible(), "sidebar did not reopen after closing its transcript window")
assert(session.ui:text():find("README contents", 1, true), "transcript did not survive grouped window closing")

phenix.shutdown()
assert(vim.wait(1000, function()
  return session.client.stopped
end, 20), "Phenix ACP fixture did not stop on shutdown")