local wezterm = require "wezterm"

local util = require "nap.util"

local M = {}

---Resolve whether a spec is enabled.
---@param s table
---@param env table
---@return boolean
function M.is_enabled(s, env)
  local enabled = s.enabled
  if enabled == nil then
    return true
  end
  if type(enabled) == "function" then
    local ok, result = pcall(enabled, env)
    if not ok then
      util.error(
        ("error evaluating enabled for '%s': %s")
          :format(s.name or "<unnamed>", result)
      )
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
---@param config table   WezTerm config builder
---@param specs table[]  merged and normalized specs
---@param env table      environment table from setup opts
function M.run(config, specs, env)
  local sorted = M.sort(specs)

  for _, s in ipairs(sorted) do
    local label = s.name or "<unnamed>"

    if not M.is_enabled(s, env) then
      util.info(("skipping disabled plugin '%s'"):format(label))
      goto continue
    end

    local url = s._resolved_url
    if not url then
      util.error(("plugin '%s' has no URL; skipping"):format(label))
      goto continue
    end

    local ok, plugin = pcall(wezterm.plugin.require, url)
    if not ok then
      util.error(
        ("failed to load plugin '%s' (%s): %s"):format(label, url, plugin)
      )
      goto continue
    end

    local opts = s.opts or {}

    if type(s.config) == "function" then
      -- Custom config function overrides the default apply
      local cok, cerr = pcall(s.config, plugin, config, opts)
      if not cok then
        util.error(
          ("error in config fn for '%s': %s"):format(label, cerr)
        )
      end
    elseif type(plugin.apply_to_config) == "function" then
      local aok, aerr = pcall(plugin.apply_to_config, config, opts)
      if not aok then
        util.error(
          ("error in apply_to_config for '%s': %s"):format(label, aerr)
        )
      end
    else
      util.warn(
        ("plugin '%s' has no apply_to_config function"):format(label)
      )
    end

    ::continue::
  end
end

return M
