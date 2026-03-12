---Configuration normalization and defaults for nap options.

local util = require "nap.util"

local M = {}

---Default nap options.
---@type table
local DEFAULTS = {
  integrations = {
    input_selector = true,
    command_palette = false,
  },
  keymaps = false,  -- No auto-generated keymaps by default
  updates = {
    enabled = false,
    interval_hours = 24,
    startup_delay_ms = 1000,
    timeout_ms = 5000,
    notify = "off",  -- "off" | "log" | "event" | "both"
    include_prerelease = false,
  },
  lockfile = {
    enabled = false,
    path = nil,
    write_on_update = true,
    pin_commits = true,
  },
  ui = {
    fuzzy = true,
    icons = true,
    colorscheme = "auto",  -- "auto" | "light" | "dark" | custom table
    width = 80,
  },
}

---Deep copy table.
---@param t table
---@return table
local function deep_copy(t)
  if type(t) ~= "table" then
    return t
  end
  local clone = {}
  for k, v in pairs(t) do
    clone[k] = deep_copy(v)
  end
  return clone
end

---Merge two tables, preferring values from override.
---@param base table
---@param override table
---@return table
local function merge_tables(base, override)
  local result = deep_copy(base)
  if not override then
    return result
  end
  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = merge_tables(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

---Normalize and validate nap_opts, applying defaults.
---@param nap_opts table? Raw nap options from setup()
---@return table normalized config
function M.normalize(nap_opts)
  nap_opts = nap_opts or {}

  local config = {
    integrations = merge_tables(DEFAULTS.integrations, nap_opts.integrations),
    keymaps = nap_opts.keymaps ~= nil and nap_opts.keymaps or DEFAULTS.keymaps,
    updates = merge_tables(DEFAULTS.updates, nap_opts.updates),
    lockfile = merge_tables(DEFAULTS.lockfile, nap_opts.lockfile),
    ui = merge_tables(DEFAULTS.ui, nap_opts.ui),
  }

  -- Extract lockfile path if provided at top level (shorthand: nap_opts.lockfile = "path")
  if type(nap_opts.lockfile) == "string" then
    config.lockfile.path = nap_opts.lockfile
  end

  -- Validate integrations settings
  if config.lockfile.path and config.lockfile.enabled == false then
    util.warn "lockfile path specified but lockfile.enabled=false; lockfile will not be used"
  end

  -- Validate update settings
  if config.updates.enabled and config.updates.timeout_ms < 100 then
    util.warn "update timeout is very short (" .. config.updates.timeout_ms .. "ms); consider increasing it"
  end

  -- Validate UI settings
  if type(config.ui.colorscheme) ~= "string" and type(config.ui.colorscheme) ~= "table" then
    util.warn "ui.colorscheme should be a string or table; using default 'auto'"
    config.ui.colorscheme = "auto"
  end

  return config
end

---Get the default configuration.
---@return table
function M.defaults()
  return deep_copy(DEFAULTS)
end

return M
