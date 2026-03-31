local wezterm = require "wezterm"

local git = require "nap.git"
local u = require "nap.util" ---@type Nap.Util

local M = {}

---Resolve whether a spec is enabled.
---@param s table
---@return boolean
function M.is_enabled(s)
  local enabled = s.enabled
  if enabled == nil then
    return true
  end
  if type(enabled) == "function" then
    local ok, result = pcall(enabled)
    if not ok then
      u.log.error("error evaluating enabled for '%s': %s", s.name or "<unnamed>", result)
      return false
    end
    return result and true or false
  end
  return enabled and true or false
end

---Sort specs: descending priority, then ascending declaration order.
---Returns a new sorted table (does not mutate input).
---@param specs table[]
---@return table[]
function M.sort(specs)
  local sorted = {}
  for i, s in ipairs(specs) do
    sorted[i] = s
  end
  table.sort(sorted, function(a, b)
    local pa = a.priority or 0
    local pb = b.priority or 0
    if pa ~= pb then
      return pa > pb
    end
    return (a._index or 0) < (b._index or 0)
  end)
  return sorted
end

---Run the apply pipeline: sort, require, call apply_to_config or config fn.
---@param config table      WezTerm config builder
---@param specs table[]     merged and normalized specs
---@param nap_config table? nap configuration (for install.missing etc.)
function M.run(config, specs, nap_config)
  local sorted = M.sort(specs)
  local install_missing = true
  if nap_config and nap_config.install then
    if nap_config.install.missing == false then
      install_missing = false
    end
  end

  for _, s in ipairs(sorted) do
    local label = s.name or "<unnamed>"

    if not M.is_enabled(s) then
      u.log.info("skipping disabled plugin '%s'", label)
    elseif not s._resolved_url then
      u.log.error("plugin '%s' has no URL; skipping", label)
    elseif not install_missing and not u.find_plugin_dir(s._resolved_url) then
      u.log.info("skipping uninstalled plugin '%s' (install.missing = false)", label)
    else
      local url = s._resolved_url
      local ok, plugin = pcall(wezterm.plugin.require, url)
      if not ok then
        u.log.error("failed to load plugin '%s' (%s): %s", label, url, plugin)
      else
        -- Version pinning: checkout branch/tag/commit if specified
        local pin_ref = s.commit or s.tag or s.branch
        local pin_failed = false
        if pin_ref then
          local plugin_dir = u.find_plugin_dir(url)
          if plugin_dir then
            local cok, cerr = git.checkout(plugin_dir, pin_ref)
            if not cok then
              u.log.error(
                "failed to checkout '%s' for '%s': %s",
                pin_ref,
                label,
                cerr or "unknown error"
              )
              pin_failed = true
            else
              -- Reload the module from the pinned checkout
              local init_path = plugin_dir .. "/plugin/init.lua"
              local lok, loaded = pcall(dofile, init_path)
              if lok and loaded then
                plugin = loaded
              else
                u.log.warn("could not reload '%s' after checkout; using initial load", label)
              end
            end
          else
            u.log.warn("cannot pin '%s': plugin directory not found", label)
          end
        end

        if not pin_failed then
          local opts = s.opts or {}

          if type(s.config) == "function" then
            local cok, cerr = pcall(s.config, plugin, config, opts)
            if not cok then
              u.log.error("error in config fn for '%s': %s", label, cerr)
            end
          elseif type(plugin.apply_to_config) == "function" then
            local aok, aerr = pcall(plugin.apply_to_config, config, opts)
            if not aok then
              u.log.error("error in apply_to_config for '%s': %s", label, aerr)
            end
          else
            u.log.warn("plugin '%s' has no apply_to_config function", label)
          end
        end
      end
    end
  end
end

return M
