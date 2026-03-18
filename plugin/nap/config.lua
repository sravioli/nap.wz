---Configuration normalization for nap options.
---The CONFIG_SCHEMA is the single source of truth for defaults and validation.
---All user options are optional; apply_defaults() fills in every field.

local schema = require "nap.schema"
local u = require "nap.util" ---@type Nap.Util

local M = {}

---Schema for nap configuration.
---Every leaf field carries a `default`, so apply_defaults({}, CONFIG_SCHEMA)
---yields a fully-populated config without any user input.
---@type table
local CONFIG_SCHEMA = {
  log_level = {
    type = "string",
    default = "warn",
    enum = { "debug", "info", "warn", "error" },
  },
  integrations = {
    type = "table",
    fields = {
      input_selector = { type = "boolean", default = true },
      command_palette = { type = "boolean", default = false },
    },
  },
  ---keymaps is false (opt-out) or a table (opt-in config).
  keymaps = {
    types = { "boolean", "table" },
    default = false,
  },
  dev = {
    type = "table",
    fields = {
      path = { type = "string", default = "~/projects" },
      patterns = { type = "table", default = {} },
      fallback = { type = "boolean", default = false },
    },
  },
  install = {
    type = "table",
    fields = {
      missing = { type = "boolean", default = true },
      auto_clean = { type = "boolean", default = false },
    },
  },
  lockfile = {
    type = "string",
  },
  updates = {
    type = "table",
    fields = {
      enabled = { type = "boolean", default = false },
      interval_hours = { type = "number", default = 24, min = 1 },
      startup_delay_ms = { type = "number", default = 1000, min = 0 },
      timeout_ms = { type = "number", default = 5000, min = 100 },
      notify = {
        type = "string",
        default = "off",
        enum = { "off", "log", "event", "both" },
      },
      include_prerelease = { type = "boolean", default = false },
      retry_count = { type = "number", default = 0, min = 0 },
      retry_delay_ms = { type = "number", default = 500, min = 0 },
      concurrency = { type = "number", default = nil, min = 1 },
      cooldown_s = { type = "number", default = 0, min = 0 },
    },
  },
  ui = {
    type = "table",
    fields = {
      fuzzy = { type = "boolean", default = true },
      icons = {
        types = { "boolean", "table" },
        default = true,
      },
      colorscheme = { types = { "string", "table" }, default = "auto" },
      height = { type = "number", default = nil },
      show_url = { type = "boolean", default = true },
      show_priority = { type = "boolean", default = true },
    },
  },
  specs = {
    type = "table",
    fields = {
      defaults = {
        type = "table",
        fields = {
          enabled = { type = "boolean", default = true },
          priority = { type = "number", default = 0 },
        },
      },
    },
  },
}

---Normalize and validate nap_opts, applying schema defaults.
---Bad values are logged but never thrown; defaults are always applied.
---@param nap_opts table? Raw nap options from setup()
---@return table normalized config (fully populated with defaults)
function M.normalize(nap_opts)
  if nap_opts == nil then
    return schema.apply_defaults({}, CONFIG_SCHEMA)
  end

  if type(nap_opts) ~= "table" then
    u.log.error("nap_opts must be a table, got %s — using all defaults", type(nap_opts))
    return schema.apply_defaults({}, CONFIG_SCHEMA)
  end

  -- Work on a shallow copy to avoid mutating the caller's table.
  local opts = {}
  for k, v in pairs(nap_opts) do
    opts[k] = v
  end

  -- Pre-check: detect bad types and nil them out so apply_defaults fills in
  -- the correct default. Logs an error for each so the user knows.
  for field, descriptor in pairs(CONFIG_SCHEMA) do
    local v = opts[field]
    if v ~= nil then
      local allowed = descriptor.types or (descriptor.type and { descriptor.type } or nil)
      if allowed then
        local matched = false
        for _, t in ipairs(allowed) do
          if type(v) == t then
            matched = true
            break
          end
        end
        if not matched then
          u.log.error(
            "nap_opts.%s must be %s, got %s — ignoring and using defaults",
            field,
            table.concat(allowed, "|"),
            type(v)
          )
          opts[field] = nil
        end
      end
    end
  end

  local config = schema.apply_defaults(opts, CONFIG_SCHEMA)

  local ok, errors = schema.validate(config, CONFIG_SCHEMA, "nap_opts")
  if not ok then
    for _, err in ipairs(errors) do
      u.log.error(err)
    end
  end

  return config
end

---Return the schema definition (for introspection or testing).
---@return table
function M.schema()
  return CONFIG_SCHEMA
end

---Return a fully-defaulted config (all user opts absent).
---@return table
function M.defaults()
  return schema.apply_defaults({}, CONFIG_SCHEMA)
end

return M
