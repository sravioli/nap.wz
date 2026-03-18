--- Minimal wezterm mock for unit-testing nap.wz modules outside WezTerm.
--- Inject this into package.loaded["wezterm"] before requiring nap modules.

local M = {}

-- ── Logging stubs ───────────────────────────────────────────────
-- Collect log messages for assertions.
M._logs = { info = {}, warn = {}, error = {} }

function M.log_info(msg)
  M._logs.info[#M._logs.info + 1] = msg
end

function M.log_warn(msg)
  M._logs.warn[#M._logs.warn + 1] = msg
end

function M.log_error(msg)
  M._logs.error[#M._logs.error + 1] = msg
end

function M._reset_logs()
  M._logs = { info = {}, warn = {}, error = {} }
end

-- ── Plugin list stub ────────────────────────────────────────────
M._plugin_list = {}

function M.plugin_list_set(list)
  M._plugin_list = list
end

M.plugin = {
  list = function()
    return M._plugin_list
  end,
  require = function(url)
    return { url = url, apply_to_config = function() end }
  end,
  update_all = function() end,
}

-- ── Subprocess stub ─────────────────────────────────────────────
--- Default stub returns success with empty output.
--- Override M.run_child_process in tests to inject custom behavior.
---@param cmd string[]
---@return boolean success, string stdout, string stderr
function M.run_child_process(cmd)
  return true, "", ""
end

-- ── Color / nerdfonts stubs ─────────────────────────────────────
M.nerdfonts = setmetatable({}, {
  __index = function(_, key)
    return "<" .. key .. ">"
  end,
})

M.color = {
  get_builtin_schemes = function()
    return {}
  end,
}

M.config = {
  color_scheme = "Default",
}

-- ── Action stubs ────────────────────────────────────────────────
M.action = {
  Nop = { type = "Nop" },
  InputSelector = function(args)
    return { type = "InputSelector", args = args }
  end,
  SpawnCommandInNewTab = function(args)
    return { type = "SpawnCommandInNewTab", args = args }
  end,
}

function M.action_callback(fn)
  return { type = "action_callback", fn = fn }
end

-- ── Misc stubs ──────────────────────────────────────────────────
M.home_dir = "/home/testuser"

--- Persistent GLOBAL table (mimics wezterm.GLOBAL across reloads).
M.GLOBAL = {}

function M.format(parts)
  local out = {}
  for _, p in ipairs(parts) do
    if p.Text then
      out[#out + 1] = p.Text
    end
  end
  return table.concat(out)
end

function M.background_task(fn)
  fn()
end

function M.emit(event_name, payload)
  -- no-op in tests
end

function M.on(event_name, callback)
  -- no-op in tests
end

return M
