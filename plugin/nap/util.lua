local wezterm = require "wezterm"

---@class Nap.Util
---@field log Nap.Util.Log
---@field tbl Nap.Util.Tbl
local M = {}

---@class Nap.Util.Log
M.log = {}

local PREFIX = "[nap.wz] "
local LOG_LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local _log_level = LOG_LEVELS.warn

---Set the minimum log level. Messages below this threshold are suppressed.
---@param level string  "debug" | "info" | "warn" | "error"
function M.log.set_level(level)
  local n = LOG_LEVELS[level]
  if n then
    _log_level = n
  end
end

---Log an informational message (suppressed unless level is "info" or "debug").
---Accepts printf-style varargs: `log.info("loaded %d specs", count)`.
---When suppressed, no formatting is performed.
---@param fmt string
---@param ... any
function M.log.info(fmt, ...)
  if _log_level <= LOG_LEVELS.info then
    wezterm.log_info(PREFIX .. (select("#", ...) > 0 and fmt:format(...) or fmt))
  end
end

---Log a warning message (suppressed only at "error" level).
---Accepts printf-style varargs.
---@param fmt string
---@param ... any
function M.log.warn(fmt, ...)
  if _log_level <= LOG_LEVELS.warn then
    wezterm.log_warn(PREFIX .. (select("#", ...) > 0 and fmt:format(...) or fmt))
  end
end

---Log an error message. Always emitted, regardless of log level.
---Accepts printf-style varargs.
---@param fmt string
---@param ... any
function M.log.error(fmt, ...)
  wezterm.log_error(PREFIX .. (select("#", ...) > 0 and fmt:format(...) or fmt))
end

---@class Nap.Util.Tbl
M.tbl = {}

---Deep copy a value (tables are recursively cloned).
---@param t any
---@return any
function M.tbl.deep_copy(t)
  if type(t) ~= "table" then
    return t
  end
  local clone = {}
  for k, v in pairs(t) do
    clone[k] = M.tbl.deep_copy(v)
  end
  return clone
end

---Check if a table is a list (sequential integer keys starting at 1).
---@param t table
---@return boolean
function M.tbl.is_list(t)
  if type(t) ~= "table" then
    return false
  end
  local n = #t
  if n == 0 then
    return next(t) == nil
  end
  local count = 0
  for _ in pairs(t) do
    count = count + 1
    if count > n then
      return false
    end
  end
  return count == n
end

---Deep merge two tables. Values in `override` take precedence.
---Tables with string keys are recursively merged; lists are replaced.
---@param base table
---@param override table
---@return table
function M.tbl.deep_merge(base, override)
  local result = {}
  for k, v in pairs(base) do
    result[k] = v
  end
  for k, v in pairs(override) do
    if
      type(v) == "table"
      and type(result[k]) == "table"
      and not M.tbl.is_list(v)
      and not M.tbl.is_list(result[k])
    then
      result[k] = M.tbl.deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

---Deduplicate a list of strings, preserving order.
---@param list string[]
---@return string[]
function M.tbl.dedupe(list)
  local seen = {}
  local result = {}
  for _, v in ipairs(list) do
    if not seen[v] then
      seen[v] = true
      result[#result + 1] = v
    end
  end
  return result
end

---Check if the current OS is Windows.
---@return boolean
local IS_WINDOWS = package.config:sub(1, 1) == "\\"
function M.is_windows()
  return IS_WINDOWS
end

---Get the nap cache table from wezterm.GLOBAL.
---Lazily initialises wezterm.GLOBAL.__nap on first access.
---@return table cache  persistent cross-reload cache
function M.get_cache()
  wezterm.GLOBAL.__nap = wezterm.GLOBAL.__nap or {}
  return wezterm.GLOBAL.__nap
end

---Find the plugin_dir for a given resolved URL by searching wezterm.plugin.list().
---@param url string  the resolved URL to match
---@return string|nil plugin_dir  the local clone directory, or nil if not found
function M.find_plugin_dir(url)
  for _, p in ipairs(wezterm.plugin.list()) do
    if p.url == url then
      return p.plugin_dir
    end
  end
  return nil
end

return M
