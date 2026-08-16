local M = {}

local function label(choice)
  if choice.kind == "new" then
    return "New Phenix session"
  end
  local session = choice.session
  local name = type(session.name) == "string" and vim.trim(session.name) or ""
  if name ~= "" then
    return string.format("%s · %s", name, session.id)
  end
  return tostring(session.id)
end

function M.select(sessions, callback)
  assert(type(sessions) == "table", "session selector requires session summaries")
  assert(type(callback) == "function", "session selector requires callback")

  local choices = {}
  for _, session in ipairs(sessions) do
    choices[#choices + 1] = {
      kind = "existing",
      session_id = session.id,
      session = vim.deepcopy(session),
    }
  end
  choices[#choices + 1] = { kind = "new" }

  vim.ui.select(choices, {
    prompt = "Phenix session",
    format_item = label,
  }, function(choice)
    if not choice then
      callback(nil, {
        code = "session_selection_cancelled",
        message = "session selection was cancelled",
      })
      return
    end
    callback({
      kind = choice.kind,
      session_id = choice.session_id,
    }, nil)
  end)
end

return M
