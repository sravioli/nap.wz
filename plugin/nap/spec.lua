local wezterm = require "wezterm"

local util = require "nap.util"

local M = {}

local GITHUB_URL = "https://github.com/"

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
  -- Normalize to forward slashes for file:// URLs
  dir = dir:gsub("\\", "/")
  if dir:match "^/" then
    return "file://" .. dir
  end
  -- Windows absolute path (e.g. C:/Users/...)
  return "file:///" .. dir
end

---Resolve the URL for a spec.
---Precedence: dev+dir > url > [1] shorthand > dir > nil.
---@param raw table
---@return string|nil
function M.resolve_url(raw)
  if raw.dev and raw.dir then
    return M.dir_to_url(raw.dir)
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
---@param raw table
---@param index integer  declaration order
---@return table
function M.normalize(raw, index)
  local s = {}

  -- Copy non-integer keys
  for k, v in pairs(raw) do
    if type(k) ~= "number" then
      s[k] = v
    end
  end

  -- Internal metadata
  s._shorthand = raw[1]
  s._index = index
  s._resolved_url = M.resolve_url(raw)

  -- Derive name if missing
  if not s.name then
    if s._resolved_url then
      s.name = M.name_from_url(s._resolved_url)
    elseif raw[1] then
      s.name = raw[1]:match "[^/]+$" or raw[1]
    end
  end

  -- Apply built-in defaults
  if s.enabled == nil then
    s.enabled = true
  end
  if s.priority == nil then
    s.priority = 0
  end

  return s
end

---Validate a normalized spec.
---@param s table
---@return boolean ok
---@return string|nil err
function M.validate(s)
  if s.import then
    return true, nil
  end
  if not s._resolved_url then
    local label = s.name or s._shorthand or "<unnamed>"
    local msg = ("spec '%s' has no resolvable URL"):format(label)

    -- Provide hints based on what's missing
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
