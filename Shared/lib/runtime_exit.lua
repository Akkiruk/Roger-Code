local M = {}

function M.isTerminateError(err)
  local message = tostring(err or "")
  if message == "Terminated" then
    return true
  end

  return message:match("(^|[%s:])Terminated$") ~= nil
end

function M.classifyShellRun(callOk, shellOk, shellErr, opts)
  local options = opts or {}

  if not callOk then
    if M.isTerminateError(shellOk) then
      return false, "Terminated", "pcall_terminate"
    end

    return false, shellOk, "pcall_error"
  end

  if shellOk == false then
    if M.isTerminateError(shellErr) then
      return false, "Terminated", "shell_terminate"
    end

    local message = tostring(shellErr or "")
    if message == "" and options.emptyErrorMeansTerminate then
      return false, "Terminated", "empty_error_treated_as_terminate"
    end

    if message == "" then
      message = "Program failed"
    end

    return false, message, (message == "Program failed") and "empty_error" or "shell_error"
  end

  return true, nil, "ok"
end

return M