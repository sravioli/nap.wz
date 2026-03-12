local wezterm = require "wezterm"

--- Bootstrap: locate nap.wzt's plugin_dir and add it to package.path
--- so that internal modules (nap.*) can be required.
local function bootstrap()
  local sep = package.config:sub(1, 1)

  -- Find ourselves in wezterm.plugin.list()
  for _, p in ipairs(wezterm.plugin.list()) do
    if p.url:find("nap.wzt", 1, true) then
      local path_entry = p.plugin_dir
        .. sep
        .. "plugin"
        .. sep
        .. "?.lua"
      if not package.path:find(path_entry, 1, true) then
        package.path = package.path .. ";" .. path_entry
      end
      return p
    end
  end
end

bootstrap()

local apply = require "nap.apply"
local imports = require "nap.import"
local lockfile = require "nap.lockfile"
local merge = require "nap.merge"
local spec = require "nap.spec"
local util = require "nap.util"

local M = {}

--- Internal state persisted across calls.
local _state = {
  env = {},
  lockfile_path = nil,
  lock_data = nil,
  resolved = {},
}

---Main entry point. Declares plugins and applies them to the config.
---
---Usage:
---```lua
---local wezterm = require "wezterm"
---local nap = wezterm.plugin.require "https://github.com/sravioli/nap.wzt"
---
---return nap.setup(wezterm.config_builder(), {
---  spec = {
---    { "owner/plugin-name", opts = { key = "value" } },
---    { import = "wez_plugins.core" },
---  },
---  env = { hostname = wezterm.hostname() },
---  lockfile = "wezterm-plugins.lock.lua",
---})
---```
---
---@param config table  WezTerm config builder (from wezterm.config_builder())
---@param opts table    { spec, defaults, env, lockfile }
---@return table config
function M.setup(config, opts)
  opts = opts or {}
  local raw_specs = opts.spec or {}
  local defaults = opts.defaults or { enabled = true, priority = 0 }
  local env = opts.env or {}
  local lockfile_path = opts.lockfile

  _state.env = env
  _state.lockfile_path = lockfile_path

  -- Read advisory lockfile
  if lockfile_path then
    _state.lock_data = lockfile.read(lockfile_path)
  end

  -- 1. Expand top-level imports
  local expanded = imports.expand(raw_specs)

  -- 2. Normalize each spec
  local normalized = {}
  for i, raw in ipairs(expanded) do
    normalized[#normalized + 1] = spec.normalize(raw, defaults, i)
  end

  -- 3. Validate
  for _, s in ipairs(normalized) do
    local ok, err = spec.validate(s)
    if not ok then
      util.warn(err)
    end
  end

  -- 4. Merge by name
  local merged = merge.merge(normalized)
  _state.resolved = merged

  -- 5. Apply all enabled plugins
  apply.run(config, merged, env)

  return config
end

---WezTerm plugin protocol compatibility wrapper.
---Identical to setup(); allows nap.wzt to be used like a regular plugin.
---@param config table
---@param opts table
---@return table config
function M.apply_to_config(config, opts)
  return M.setup(config, opts)
end

---Read the lockfile.
---@param path? string  override path; defaults to the one from setup()
---@return table|nil
function M.read_lockfile(path)
  path = path or _state.lockfile_path
  if not path then
    util.warn "no lockfile path configured"
    return nil
  end
  return lockfile.read(path)
end

---Write the lockfile from current plugin state.
---@param path? string  override path
function M.write_lockfile(path)
  path = path or _state.lockfile_path
  if not path then
    util.warn "no lockfile path configured"
    return
  end
  lockfile.write(path, _state.resolved)
end

---Return resolved specs, env, and lockfile data for debugging.
---@return table
function M.status()
  return {
    specs = _state.resolved,
    env = _state.env,
    lock_data = _state.lock_data,
  }
end

---Update all plugins via WezTerm's native mechanism and rewrite the lockfile.
function M.update_all_and_lock()
  wezterm.plugin.update_all()
  M.write_lockfile()
  util.info "updated all plugins and wrote lockfile"
end

return M
