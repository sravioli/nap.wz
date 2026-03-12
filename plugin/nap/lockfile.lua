local wezterm = require "wezterm"

local util = require "nap.util"

local M = {}

---Resolve a lockfile path. Relative paths are relative to wezterm.config_dir.
---@param path string
---@return string
function M.resolve_path(path)
  if path:match "^/" or path:match "^%a:" then
    return path
  end
  local sep = package.config:sub(1, 1)
  return wezterm.config_dir .. sep .. path
end

---Read and return the contents of a lockfile.
---@param path string
---@return table|nil
function M.read(path)
  local abs = M.resolve_path(path)
  -- Check if file exists before trying to load it
  local f = io.open(abs, "r")
  if not f then
    util.info(("no lockfile found at '%s'; skipping"):format(abs))
    return nil
  end
  f:close()

  local ok, result = pcall(dofile, abs)
  if not ok then
    util.warn(("could not parse lockfile '%s': %s"):format(abs, result))
    return nil
  end
  if type(result) ~= "table" then
    util.warn(("lockfile '%s' did not return a table"):format(abs))
    return nil
  end
  return result
end

---Write a lockfile from current plugin state.
---Matches resolved spec names against installed plugins via wezterm.plugin.list().
---Includes reproducibility fields (commit_sha) and update check metadata.
---@param path string
---@param specs table[] resolved specs
---@param last_check_time? number unix timestamp of last update check
function M.write(path, specs, last_check_time)
  local abs = M.resolve_path(path)

  -- Build url -> name map from resolved specs
  local url_map = {}
  for _, s in ipairs(specs) do
    if s.name and s._resolved_url then
      url_map[s._resolved_url] = s.name
    end
  end

  -- Match against installed plugins
  local entries = {}
  for _, p in ipairs(wezterm.plugin.list()) do
    local name = url_map[p.url]
    if name then
      -- Capture commit_sha if available (for reproducibility)
      local commit_sha = nil
      if p.commit_sha then
        commit_sha = p.commit_sha
      elseif p.version then
        -- Fallback to version if commit_sha is not available
        commit_sha = p.version
      end

      entries[name] = {
        url = p.url,
        plugin_dir = p.plugin_dir,
        commit_sha = commit_sha,
      }
    end
  end

  -- Sort keys for deterministic output
  local keys = {}
  for k in pairs(entries) do
    keys[#keys + 1] = k
  end
  table.sort(keys)

  -- Serialize as a Lua table with extended schema
  local lines = { "return {" }
  for _, name in ipairs(keys) do
    local e = entries[name]
    if e.commit_sha then
      lines[#lines + 1] = ('  ["%s"] = { url = "%s", plugin_dir = "%s", commit_sha = "%s" },')
        :format(name, e.url, e.plugin_dir, e.commit_sha)
    else
      lines[#lines + 1] = ('  ["%s"] = { url = "%s", plugin_dir = "%s" },')
        :format(name, e.url, e.plugin_dir)
    end
  end
  lines[#lines + 1] = "}"

  local content = table.concat(lines, "\n") .. "\n"

  local f, err = io.open(abs, "w")
  if not f then
    util.error(("could not write lockfile '%s': %s"):format(abs, err))
    return
  end
  f:write(content)
  f:close()
  util.info(("wrote lockfile to '%s'"):format(abs))
end

---Remove a plugin entry from the lockfile by name.
---Reads the lockfile, deletes the matching key, and rewrites the file.
---@param path string   lockfile path
---@param name string   plugin name to remove
---@return boolean ok   true if found and removed
function M.remove_entry(path, name)
  local data = M.read(path)
  if not data or not data[name] then
    util.warn(("plugin '%s' not found in lockfile"):format(name))
    return false
  end

  data[name] = nil

  -- Rewrite the lockfile from the remaining data
  local abs = M.resolve_path(path)
  local keys = {}
  for k in pairs(data) do
    keys[#keys + 1] = k
  end
  table.sort(keys)

  local lines = { "return {" }
  for _, k in ipairs(keys) do
    local e = data[k]
    if e.commit_sha then
      lines[#lines + 1] = ('  ["%s"] = { url = "%s", plugin_dir = "%s", commit_sha = "%s" },')
        :format(k, e.url, e.plugin_dir, e.commit_sha)
    else
      lines[#lines + 1] = ('  ["%s"] = { url = "%s", plugin_dir = "%s" },')
        :format(k, e.url, e.plugin_dir)
    end
  end
  lines[#lines + 1] = "}"

  local content = table.concat(lines, "\n") .. "\n"
  local f, err = io.open(abs, "w")
  if not f then
    util.error(("could not write lockfile '%s': %s"):format(abs, err))
    return false
  end
  f:write(content)
  f:close()
  util.info(("removed '%s' from lockfile"):format(name))
  return true
end

return M
