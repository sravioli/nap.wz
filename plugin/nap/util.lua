local wezterm = require "wezterm"

local M = {}

local PREFIX = "[nap.wz] "

---Log an informational message.
---@param msg string
function M.info(msg)
  wezterm.log_info(PREFIX .. msg)
end

---Log a warning message.
---@param msg string
function M.warn(msg)
  wezterm.log_warn(PREFIX .. msg)
end

---Log an error message.
---@param msg string
function M.error(msg)
  wezterm.log_error(PREFIX .. msg)
end

---Check if a table is a list (sequential integer keys starting at 1).
---@param t table
---@return boolean
function M.is_list(t)
  if type(t) ~= "table" then
    return false
  end
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count == #t
end

---Deep merge two tables. Values in `override` take precedence.
---Tables with string keys are recursively merged; lists are replaced.
---@param base table
---@param override table
---@return table
function M.deep_merge(base, override)
  local result = {}
  for k, v in pairs(base) do
    result[k] = v
  end
  for k, v in pairs(override) do
    if
      type(v) == "table"
      and type(result[k]) == "table"
      and not M.is_list(v)
      and not M.is_list(result[k])
    then
      result[k] = M.deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

---Deduplicate a list of strings, preserving order.
---@param list string[]
---@return string[]
function M.dedupe(list)
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
function M.is_windows()
  return package.config:sub(1, 1) == "\\"
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
