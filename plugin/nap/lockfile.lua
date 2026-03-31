local git = require "nap.git"
local u = require "nap.util" ---@type Nap.Util

---@class Nap.Lockfile
local M = {}

---Take a snapshot of the current state of all resolved plugins.
---For each spec with a resolved URL and an existing plugin directory,
---records the current commit SHA and branch.
---@param specs table[]  resolved specs (from _state.resolved)
---@return table snapshot  { [name] = { url, commit, branch? } }
function M.snapshot(specs)
  local result = {}
  for _, s in ipairs(specs) do
    if s._resolved_url and s.name then
      local plugin_dir = u.find_plugin_dir(s._resolved_url)
      if plugin_dir then
        local sha = git.rev_parse_head(plugin_dir)
        local branch = git.current_branch(plugin_dir)
        if sha then
          result[s.name] = {
            url = s._resolved_url,
            commit = sha,
            branch = branch,
          }
        end
      end
    end
  end
  return result
end

---Serialize a snapshot table to a Lua source string.
---@param data table  snapshot data from snapshot()
---@return string lua_source
function M.serialize(data)
  local lines = { "return {" }
  -- Sort keys for deterministic output
  local keys = {}
  for k in pairs(data) do
    keys[#keys + 1] = k
  end
  table.sort(keys)

  for _, name in ipairs(keys) do
    local entry = data[name]
    lines[#lines + 1] = ("  [%q] = {"):format(name)
    lines[#lines + 1] = ("    url = %q,"):format(entry.url)
    lines[#lines + 1] = ("    commit = %q,"):format(entry.commit)
    if entry.branch then
      lines[#lines + 1] = ("    branch = %q,"):format(entry.branch)
    end
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "}\n"
  return table.concat(lines, "\n")
end

---Write a snapshot to a lockfile.
---@param path string  absolute path to the lockfile
---@param data table   snapshot data
---@return boolean ok, string|nil err
function M.write(path, data)
  local content = M.serialize(data)
  local f, err = io.open(path, "w")
  if not f then
    return false, err
  end
  f:write(content)
  f:close()
  return true, nil
end

---Read a lockfile.
---@param path string  absolute path to the lockfile
---@return table|nil data, string|nil err
function M.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil, "lockfile not found: " .. path
  end
  local content = f:read "*a"
  f:close()

  local fn, err = load(content, path, "t", {})
  if not fn then
    return nil, "failed to parse lockfile: " .. (err or "unknown error")
  end
  local ok, result = pcall(fn)
  if not ok then
    return nil, "failed to execute lockfile: " .. tostring(result)
  end
  if type(result) ~= "table" then
    return nil, "lockfile did not return a table"
  end
  return result, nil
end

---Restore plugins to the commits recorded in a lockfile.
---For each entry in the lockfile that matches a declared spec,
---fetches and checks out the recorded commit.
---@param specs table[]  resolved specs
---@param lockfile_data table  data from read()
---@return table results  { [name] = { ok, from_sha?, to_sha? } }
function M.restore(specs, lockfile_data)
  local results = {}
  local spec_by_name = {}
  for _, s in ipairs(specs) do
    if s.name then
      spec_by_name[s.name] = s
    end
  end

  for name, entry in pairs(lockfile_data) do
    local s = spec_by_name[name]
    if not s then
      u.log.warn("lockfile entry '%s' has no matching spec; skipping", name)
      results[name] = { ok = false, reason = "no matching spec" }
    elseif not s._resolved_url then
      u.log.warn("spec '%s' has no resolved URL; skipping restore", name)
      results[name] = { ok = false, reason = "no resolved URL" }
    else
      local plugin_dir = u.find_plugin_dir(s._resolved_url)
      if not plugin_dir then
        u.log.warn("plugin directory not found for '%s'; skipping restore", name)
        results[name] = { ok = false, reason = "plugin_dir not found" }
      else
        local from_sha = git.rev_parse_head(plugin_dir)
        local fok = git.fetch(plugin_dir)
        if not fok then
          u.log.warn("failed to fetch for '%s'; attempting checkout anyway", name)
        end
        local cok, cerr = git.checkout(plugin_dir, entry.commit)
        if cok then
          local to_sha = git.rev_parse_head(plugin_dir)
          u.log.info("restored '%s' to %s", name, entry.commit)
          results[name] = { ok = true, from_sha = from_sha, to_sha = to_sha }
        else
          u.log.error(
            "failed to restore '%s' to %s: %s",
            name,
            entry.commit,
            cerr or "unknown"
          )
          results[name] = { ok = false, reason = cerr }
        end
      end
    end
  end

  return results
end

return M
