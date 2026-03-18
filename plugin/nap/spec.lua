local wezterm = require "wezterm"

local schema = require "nap.schema"
local u = require "nap.util" ---@type Nap.Util

local M = {}

local GITHUB_URL = "https://github.com/"

---Schema for a plugin spec entry.
---Validates individual fields; URL-resolution logic is handled separately.
---@type table
local SPEC_SCHEMA = {
  name = { type = "string" },
  url = { type = "string" },
  dir = { type = "string" },
  dev = { type = "boolean", default = false },
  enabled = { types = { "boolean", "function" }, default = true },
  priority = { type = "number", default = 0, min = 0 },
  opts = { type = "table" },
  groups = { type = "table" },
  config = { type = "function" },
  import = { type = "string" },
  branch = { type = "string" },
  tag = { type = "string" },
  commit = { type = "string" },
  dependencies = { type = "table" },
}

---Expand a local directory path to a file:// URL.
---@param dir string
---@return string
function M.dir_to_url(dir)
  if dir:match "^file://" then
    return dir
  end
  if dir:sub(1, 1) == "~" then
    dir = wezterm.home_dir .. dir:sub(2)
  end
  dir = dir:gsub("\\", "/")
  if dir:match "^/" then
    return "file://" .. dir
  end
  return "file:///" .. dir
end

---Resolve the URL for a spec.
---Precedence: dev+dir > dev+dev_config (pattern match) > url > [1] shorthand > dir > nil.
---@param raw table
---@param dev_config? table  global dev settings from nap_config.dev
---@return string|nil
function M.resolve_url(raw, dev_config)
  if raw.dev and raw.dir then
    return M.dir_to_url(raw.dir)
  end

  -- dev flag with global dev.path + patterns matching
  if raw.dev and dev_config then
    local shorthand = raw[1]
    if shorthand and dev_config.path then
      for _, pattern in ipairs(dev_config.patterns or {}) do
        if shorthand:find(pattern, 1, true) then
          local name = shorthand:match "[^/]+$" or shorthand
          local dir = dev_config.path .. "/" .. name
          return M.dir_to_url(dir)
        end
      end
      -- dev=true but no pattern matched: fall back to git if allowed
      if dev_config.fallback then
        if raw.url then
          return raw.url
        end
        if shorthand and shorthand:match "^[%%w%%-%_.]+/[%%w%%-%_%.]+" then
          return GITHUB_URL .. shorthand
        end
      end
    end
  end

  if raw.url then
    return raw.url
  end
  local shorthand = raw[1]
  if shorthand and shorthand:match "^[%w%-_.]+/[%w%-_.]+" then
    return GITHUB_URL .. shorthand
  end
  if raw.dir then
    return M.dir_to_url(raw.dir)
  end
  return nil
end

---Derive a plugin name from a URL.
---Takes the last path component and strips a trailing .git suffix.
---@param url string
---@return string
function M.name_from_url(url)
  local name = url:match "([^/]+)/?$"
  if name then
    name = name:gsub("%.git$", "")
  end
  return name or url
end

---Normalize a raw spec entry: resolve URL, derive name, apply defaults.
---@param raw      table
---@param index    integer  declaration order
---@param defaults table?   per-spec defaults from nap_config.specs.defaults
---@param dev_config table?  global dev settings from nap_config.dev
---@return table
function M.normalize(raw, index, defaults, dev_config)
  defaults = defaults or {}
  local s = {}

  for k, v in pairs(raw) do
    if type(k) ~= "number" then
      s[k] = v
    end
  end

  s._shorthand = raw[1]
  s._index = index
  s._resolved_url = M.resolve_url(raw, dev_config)

  if not s.name then
    if s._resolved_url then
      s.name = M.name_from_url(s._resolved_url)
    elseif raw[1] then
      s.name = raw[1]:match "[^/]+$" or raw[1]
    end
  end

  -- Apply per-spec user defaults (explicit nil check avoids Lua and/or
  -- idiom swallowing `false`; e.g. specs.defaults.enabled = false must work)
  if s.enabled == nil then
    if defaults.enabled ~= nil then
      s.enabled = defaults.enabled
    else
      s.enabled = true
    end
  end
  if s.priority == nil then
    if defaults.priority ~= nil then
      s.priority = defaults.priority
    else
      s.priority = 0
    end
  end

  return s
end

---Validate a normalized spec, logging schema-level field errors.
---@param s table
---@return boolean ok
---@return string|nil err
function M.validate(s)
  -- Skip import-only specs (they are handled by import.lua)
  if s.import then
    return true, nil
  end

  -- Schema-level field validation
  local ok, errors =
    schema.validate(s, SPEC_SCHEMA, ("spec[%s]"):format(s.name or s._shorthand or "?"))
  if not ok then
    for _, err in ipairs(errors) do
      u.log.warn(err)
    end
  end

  -- Mutual exclusivity: at most one of branch, tag, commit
  local pin_count = 0
  if s.branch then
    pin_count = pin_count + 1
  end
  if s.tag then
    pin_count = pin_count + 1
  end
  if s.commit then
    pin_count = pin_count + 1
  end
  if pin_count > 1 then
    local label = s.name or s._shorthand or "<unnamed>"
    return false,
      ("spec '%s': only one of 'branch', 'tag', or 'commit' may be set"):format(label)
  end

  -- URL resolution is business logic, not schema
  if not s._resolved_url then
    local label = s.name or s._shorthand or "<unnamed>"
    local msg = ("spec '%s' has no resolvable URL"):format(label)

    if not s._shorthand and not s.url and not s.dir then
      msg = msg .. "; provide 'url', 'dir', or use shorthand 'owner/repo'"
    elseif s.dir and not s.url then
      msg = msg .. "; 'dev = true' is needed to use local 'dir' without a remote 'url'"
    end

    return false, msg
  end

  return true, nil
end

return M
