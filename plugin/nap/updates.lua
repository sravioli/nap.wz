local wezterm = require "wezterm"

local git = require "nap.git"
local u = require "nap.util" ---@type Nap.Util

local M = {}

---Check if an update is available for a plugin by comparing local HEAD
---with the remote tracking ref after a fetch.
---@param spec table resolved spec with _resolved_url and name
---@param timeout_ms? number timeout in milliseconds (unused — kept for API compat)
---@return boolean has_update
local function has_update(spec, timeout_ms)
  local plugin_dir = u.find_plugin_dir(spec._resolved_url)
  if not plugin_dir then
    return false
  end

  local local_sha = git.rev_parse_head(plugin_dir)
  if not local_sha then
    return false
  end

  local fok = git.fetch(plugin_dir)
  if not fok then
    return false
  end

  -- Determine what we're tracking
  local pin_ref = spec.commit or spec.tag or spec.branch
  local remote_ref
  if pin_ref then
    -- For pinned plugins, compare against the pin ref
    remote_ref = pin_ref
  else
    -- For unpinned plugins, compare against FETCH_HEAD
    remote_ref = "FETCH_HEAD"
  end

  local rok, remote_sha = git.run(plugin_dir, { "rev-parse", remote_ref })
  if not rok or not remote_sha then
    return false
  end
  remote_sha = remote_sha:match "^(%S+)"
  if not remote_sha then
    return false
  end

  return local_sha ~= remote_sha
end

---Attempt has_update() up to (1 + retry_count) times, with a delay between tries.
---@param spec         table   resolved spec
---@param timeout_ms   number  per-attempt timeout in milliseconds
---@param retry_count  number  additional attempts after the first
---@param retry_delay_ms number milliseconds to wait between retries
---@return boolean has_update
local function has_update_with_retry(spec, timeout_ms, retry_count, retry_delay_ms)
  for attempt = 1, retry_count + 1 do
    local ok, result = pcall(has_update, spec, timeout_ms)
    if ok then
      return result
    end
    if attempt <= retry_count then
      u.log.warn(
        "update check attempt %d/%d failed for '%s'; retrying in %dms",
        attempt,
        retry_count + 1,
        spec.name,
        retry_delay_ms
      )
      -- Non-spinning sleep: prefer wezterm.sleep_ms when available.
      if wezterm.sleep_ms then
        wezterm.sleep_ms(retry_delay_ms)
      else
        local sleep_s = retry_delay_ms / 1000
        if package.config:sub(1, 1) == "\\" then
          os.execute("timeout /t " .. math.max(1, math.ceil(sleep_s)) .. " /nobreak >nul 2>&1")
        else
          os.execute("sleep " .. string.format("%g", sleep_s))
        end
      end
    else
      u.log.warn(
        "update check failed for '%s' after %d attempt(s): %s",
        spec.name,
        retry_count + 1,
        tostring(result)
      )
    end
  end
  return false
end

---Run a non-blocking update check on all plugins.
---Spawns a background task that emits events when complete.
---@param specs   table[]       resolved specs
---@param config  table?        updates configuration from nap_config.updates
function M.check_updates_async(specs, config)
  if not config or not config.enabled then
    return
  end

  if type(specs) ~= "table" then
    u.log.warn "invalid specs passed to check_updates_async"
    return
  end

  local timeout_ms = config.timeout_ms or 5000
  local retry_count = config.retry_count or 0
  local retry_delay = config.retry_delay_ms or 500
  local cooldown_s = config.cooldown_s or 0

  wezterm.background_task(function()
    local ok, err = pcall(function()
      local cache = u.get_cache()
      cache.update_timestamps = cache.update_timestamps or {}

      local updates_available = {}
      local check_time = os.time()

      for _, s in ipairs(specs) do
        if s._resolved_url and s.name then
          -- Skip if checked recently (within cooldown window)
          local last_check = cache.update_timestamps[s.name]
          if cooldown_s > 0 and last_check and (check_time - last_check) < cooldown_s then
            u.log.info("skipping update check for '%s' (cooldown)", s.name)
          else
            local update_status = has_update_with_retry(s, timeout_ms, retry_count, retry_delay)
            cache.update_timestamps[s.name] = os.time()
            if update_status then
              updates_available[#updates_available + 1] = s.name
            end
          end
        end
      end

      local payload = {
        check_time = check_time,
        update_count = #updates_available,
        plugins = updates_available,
      }

      wezterm.emit("nap-updates-checked", payload)
      if #updates_available > 0 then
        wezterm.emit("nap-updates-available", payload)
      end
    end)

    if not ok then
      u.log.error("update background task failed: %s", err)
    end
  end)
end

---Run update checks synchronously (for manual, explicit checks).
---Returns a list of plugin names with updates available.
---@param specs        table[]  resolved specs
---@param config       table?   updates configuration from nap_config.updates
---@return string[]    updates_available
function M.check_updates_sync(specs, config)
  config = config or {}
  local timeout_ms = config.timeout_ms or 5000
  local retry_count = config.retry_count or 0
  local retry_delay = config.retry_delay_ms or 500

  local updates_available = {}
  for _, s in ipairs(specs) do
    if s._resolved_url and s.name then
      if has_update_with_retry(s, timeout_ms, retry_count, retry_delay) then
        updates_available[#updates_available + 1] = s.name
      end
    end
  end
  return updates_available
end

---Update a single plugin: fetch, advance to latest (or pin ref), reload.
---@param spec table  resolved spec with _resolved_url, name, optional branch/tag/commit
---@return boolean ok, string|nil err
function M.update_plugin(spec)
  local label = spec.name or "<unnamed>"
  if not spec._resolved_url then
    return false, "no resolved URL for '" .. label .. "'"
  end

  local plugin_dir = u.find_plugin_dir(spec._resolved_url)
  if not plugin_dir then
    return false, "plugin directory not found for '" .. label .. "'"
  end

  local from_sha = git.rev_parse_head(plugin_dir)

  -- Fetch latest refs
  local fok = git.fetch(plugin_dir)
  if not fok then
    return false, "fetch failed for '" .. label .. "'"
  end

  local pin_ref = spec.commit or spec.tag or spec.branch
  if pin_ref then
    -- Pinned: checkout the specific ref
    local cok, cerr = git.checkout(plugin_dir, pin_ref)
    if not cok then
      return false, ("checkout '%s' failed for '%s': %s"):format(pin_ref, label, cerr or "unknown")
    end
  else
    -- Unpinned: fast-forward merge
    local mok, merr = git.merge_ff(plugin_dir)
    if not mok then
      return false, ("merge failed for '%s': %s"):format(label, merr or "unknown")
    end
  end

  local to_sha = git.rev_parse_head(plugin_dir)
  if from_sha == to_sha then
    u.log.info("'%s' already up to date (%s)", label, from_sha or "?")
  else
    u.log.info("updated '%s': %s -> %s", label, from_sha or "?", to_sha or "?")
  end

  return true, nil
end

return M
