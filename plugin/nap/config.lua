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
  keymaps = false, -- No auto-generated keymaps by default
  updates = {
    enabled = false,
    interval_hours = 24,
    startup_delay_ms = 1000,
    timeout_ms = 5000,
    notify = "off", -- "off" | "log" | "event" | "both"
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
    colorscheme = "auto", -- "auto" | "light" | "dark" | custom table
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

---Validate that a nap_opts field is a table, logging an error and returning nil on failure.
---@param key string  field name, for the error message
---@param value any   the value to check
---@return table|nil  the value if valid, nil otherwise
local function expect_table(key, value)
  if value == nil then
    return nil -- missing is fine; defaults will apply
  end
  if type(value) ~= "table" then
    util.error(
      ("nap_opts.%s must be a table, got %s — ignoring and using defaults"):format(
        key,
        type(value)
      )
    )
    return nil
  end
  return value
end

---Normalize and validate nap_opts, applying defaults.
---@param nap_opts table? Raw nap options from setup()
---@return table normalized config
function M.normalize(nap_opts)
  nap_opts = nap_opts or {}

  if type(nap_opts) ~= "table" then
    util.error(
      ("nap_opts must be a table, got %s — using all defaults"):format(type(nap_opts))
    )
    nap_opts = {}
  end

  -- Validate each table-valued field up front so merge_tables never receives a non-table.
  local integrations = expect_table("integrations", nap_opts.integrations)
  local updates      = expect_table("updates",      nap_opts.updates)
  local lockfile_opt = expect_table("lockfile",     nap_opts.lockfile)
  local ui           = expect_table("ui",           nap_opts.ui)

  -- keymaps is allowed to be false (opt-out) or a table (opt-in config)
  local keymaps = nap_opts.keymaps
  if keymaps ~= nil and keymaps ~= false and type(keymaps) ~= "table" then
    util.error(
      ("nap_opts.keymaps must be false or a table, got %s — using default"):format(
        type(keymaps)
      )
    )
    keymaps = nil
  end

  local config = {
    integrations = merge_tables(DEFAULTS.integrations, integrations),
    keymaps      = keymaps ~= nil and keymaps or DEFAULTS.keymaps,
    updates      = merge_tables(DEFAULTS.updates,      updates),
    lockfile     = merge_tables(DEFAULTS.lockfile,     lockfile_opt),
    ui           = merge_tables(DEFAULTS.ui,           ui),
  }

  -- Validate lockfile sub-fields
  if config.lockfile.path and type(config.lockfile.path) ~= "string" then
    util.error "nap_opts.lockfile.path must be a string — ignoring"
    config.lockfile.path = nil
  end

  -- Validate updates sub-fields
  if config.updates.enabled and config.updates.timeout_ms < 100 then
    util.warn(
      ("nap_opts.updates.timeout_ms is very short (%dms); consider a value ≥ 1000"):format(
        config.updates.timeout_ms
      )
    )
  end

  -- Validate UI sub-fields
  if type(config.ui.colorscheme) ~= "string" and type(config.ui.colorscheme) ~= "table" then
    util.error "nap_opts.ui.colorscheme must be a string or table — using default 'auto'"
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
