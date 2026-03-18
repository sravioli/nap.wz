local u = require "nap.util"
local wezterm = require "wezterm"

---@class Nap.Git
local M = {}

---Run a git command in the given plugin directory.
---Uses `wezterm.run_child_process()` which returns `(success, stdout, stderr)`.
---@param plugin_dir string  absolute path to the git repo
---@param args string[]  git subcommand and arguments (e.g. {"rev-parse", "HEAD"})
---@return boolean ok, string stdout, string stderr
function M.run(plugin_dir, args)
  local cmd = { "git", "-C", plugin_dir }
  for _, a in ipairs(args) do
    cmd[#cmd + 1] = a
  end
  local pcall_ok, success, stdout, stderr = pcall(wezterm.run_child_process, cmd)
  if not pcall_ok then
    -- pcall itself failed (e.g. git binary not found)
    return false, "", tostring(success)
  end
  return success, stdout or "", stderr or ""
end

---Get the current HEAD commit SHA.
---@param plugin_dir string
---@return string|nil sha  40-char hex string, or nil on failure
function M.rev_parse_head(plugin_dir)
  local ok, out = M.run(plugin_dir, { "rev-parse", "HEAD" })
  if not ok then
    return nil
  end
  return out:match "%S+"
end

---Checkout a branch, tag, or commit.
---@param plugin_dir string
---@param ref string  branch name, tag, or commit SHA
---@return boolean ok, string|nil err
function M.checkout(plugin_dir, ref)
  local ok, _, stderr = M.run(plugin_dir, { "checkout", ref })
  if not ok then
    return false, stderr
  end
  return true, nil
end

---Fetch from origin.
---@param plugin_dir string
---@param opts? { tags?: boolean }
---@return boolean ok, string|nil err
function M.fetch(plugin_dir, opts)
  local args = { "fetch", "origin" }
  if opts and opts.tags then
    args[#args + 1] = "--tags"
  end
  local ok, _, stderr = M.run(plugin_dir, args)
  if not ok then
    return false, stderr
  end
  return true, nil
end

---Get the current branch name, or nil if HEAD is detached.
---@param plugin_dir string
---@return string|nil branch
function M.current_branch(plugin_dir)
  local ok, out = M.run(plugin_dir, { "symbolic-ref", "--short", "HEAD" })
  if not ok then
    return nil
  end
  return out:match "%S+"
end

---Check if HEAD is detached.
---@param plugin_dir string
---@return boolean
function M.is_detached(plugin_dir)
  return M.current_branch(plugin_dir) == nil
end

---Fast-forward merge from a remote ref.
---@param plugin_dir string
---@param ref? string  remote ref (default: "origin/HEAD")
---@return boolean ok, string|nil err
function M.merge_ff(plugin_dir, ref)
  ref = ref or "origin/HEAD"
  local ok, _, stderr = M.run(plugin_dir, { "merge", "--ff-only", ref })
  if not ok then
    return false, stderr
  end
  return true, nil
end

---Get one-line log between two refs.
---@param plugin_dir string
---@param from_sha string  starting commit (exclusive)
---@param to_sha? string  ending commit (inclusive, default: "HEAD")
---@return string[]|nil lines  list of log lines, or nil on failure
function M.log_oneline(plugin_dir, from_sha, to_sha)
  to_sha = to_sha or "HEAD"
  local range = from_sha .. ".." .. to_sha
  local ok, out = M.run(plugin_dir, { "log", "--oneline", range })
  if not ok then
    return nil
  end
  local lines = {}
  for line in out:gmatch "[^\n]+" do
    lines[#lines + 1] = line
  end
  return lines
end

---Get the remote origin URL.
---@param plugin_dir string
---@return string|nil url
function M.remote_url(plugin_dir)
  local ok, out = M.run(plugin_dir, { "remote", "get-url", "origin" })
  if not ok then
    return nil
  end
  return out:match "%S+"
end

return M
