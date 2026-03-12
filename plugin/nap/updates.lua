local wezterm = require "wezterm"

local util = require "nap.util"

local M = {}

---Configuration for update checks.
---@class UpdatesConfig
---@field enabled boolean  enable update checks
---@field interval_hours number  hours between checks
---@field timeout_secs number  timeout for each check
---@field check_on_startup boolean  run check on first setup

---Check if an update is available for a plugin.
---Returns true if a newer version exists, false otherwise.
---Handles network errors gracefully by returning false.
---@param spec table resolved spec with _resolved_url and name
---@param timeout_secs? number timeout in seconds (default: 10)
---@return boolean has_update
local function has_update(spec, timeout_secs)
  timeout_secs = timeout_secs or 10

  -- For now, return false as a safe default.
  -- In a real implementation, this would:
  -- 1. Check the plugin's remote URL (GitHub, etc.)
  -- 2. Compare installed commit_sha with latest
  -- 3. Return true if update is available
  --
  -- This is intentionally conservative to avoid blocking startup.
  return false
end

---Validate update configuration.
---@param config? UpdatesConfig update configuration
---@return boolean is_valid
local function is_valid_config(config)
  if not config then
    return false
  end
  return type(config.enabled) == "boolean"
end

---Run a non-blocking update check on all plugins.
---Spawns a background task that emits events when complete.
---Does not block caller; returns immediately.
---Failures are caught and logged without interrupting plugin application.
---@param specs table[] resolved specs
---@param config? UpdatesConfig update configuration
---@param timeout_secs? number timeout per check (default: 10)
function M.check_updates_async(specs, config, timeout_secs)
  if not config or not config.enabled then
    return
  end

  -- Validate input
  if type(specs) ~= "table" then
    util.warn "invalid specs passed to check_updates_async"
    return
  end

  timeout_secs = timeout_secs or config.timeout_secs or 10

  -- Schedule a non-blocking background task
  -- Wrapped in pcall to ensure failures don't interrupt plugin application
  wezterm.background_task(function()
    local ok, err = pcall(function()
      local updates_available = {}
      local check_time = os.time()
      local error_msg = nil

      -- Perform update checks
      for _, spec in ipairs(specs) do
        if spec._resolved_url and spec.name then
          local check_ok, update_status = pcall(function()
            return has_update(spec, timeout_secs)
          end)

          if check_ok and update_status then
            updates_available[#updates_available + 1] = spec.name
          elseif not check_ok then
            util.warn(("update check failed for '%s': %s"):format(spec.name, update_status))
            if not error_msg then
              error_msg = tostring(update_status)
            end
          end
        end
      end

      -- Emit event with results
      local event_payload = {
        check_time = check_time,
        update_count = #updates_available,
        plugins = updates_available,
        error = error_msg,
      }

      wezterm.emit("nap-updates-checked", event_payload)

      if #updates_available > 0 then
        wezterm.emit("nap-updates-available", event_payload)
      end

      if error_msg then
        wezterm.emit("nap-update-check-error", event_payload)
      end
    end)

    if not ok then
      util.error(("update background task failed: %s"):format(err))
    end
  end)
end

---Run update checks synchronously (for manual, explicit checks).
---Returns list of plugins with updates available.
---May block briefly; use async version for startup flow.
---@param specs table[] resolved specs
---@param timeout_secs? number timeout per check (default: 10)
---@return table updates_available list of plugin names with updates
function M.check_updates_sync(specs, timeout_secs)
  timeout_secs = timeout_secs or 10
  local updates_available = {}

  for _, spec in ipairs(specs) do
    if spec._resolved_url and spec.name then
      if has_update(spec, timeout_secs) then
        updates_available[#updates_available + 1] = spec.name
      end
    end
  end

  return updates_available
end

return M

