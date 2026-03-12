local wezterm = require "wezterm"

--- Bootstrap: locate nap.wz's plugin_dir and add it to package.path
--- so that internal modules (nap.*) can be required.
local function bootstrap()
  local sep = package.config:sub(1, 1)

  -- Find ourselves in wezterm.plugin.list()
  for _, p in ipairs(wezterm.plugin.list()) do
    if p.url:find("nap.wz", 1, true) then
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
local config_module = require "nap.config"
local imports = require "nap.import"
local lockfile = require "nap.lockfile"
local merge = require "nap.merge"
local spec = require "nap.spec"
local updates = require "nap.updates"
local util = require "nap.util"

local ui_ok, ui = pcall(require, "nap.ui")
if not ui_ok then
  util.warn("could not load UI module: " .. tostring(ui))
  ui = nil
end

local M = {}

--- Internal state persisted across calls.
local _state = {
  nap_config = {},
  lockfile_path = nil,
  lock_data = nil,
  resolved = {},
}

---Main entry point. Declares plugins and applies them to the config.
---
---Usage:
---```lua
---local wezterm = require "wezterm"
---local nap = wezterm.plugin.require "https://github.com/sravioli/nap.wz"
---
---return nap.setup(
---  wezterm.config_builder(),
---  {
---    { "owner/plugin-name", opts = { key = "value" } },
---    { import = "wez_plugins.core" },
---  },
---  {
---    lockfile = "nap-lock.lua",
---    integrations = { input_selector = true, command_palette = true },
---    updates = { enabled = false },
---  }
---)
---```
---
---@param config table  WezTerm config builder (from wezterm.config_builder())
---@param specs table   List of plugin spec entries
---@param nap_opts table? Configuration for nap behavior (lockfile, ui, integrations, updates, keymaps)
---@return table config
function M.setup(config, specs, nap_opts)
  specs = specs or {}
  nap_opts = nap_opts or {}

  -- Normalize nap configuration with defaults
  local nap_config = config_module.normalize(nap_opts)

  -- Extract lockfile path from config
  local lockfile_path = nap_config.lockfile.path

  _state.lockfile_path = lockfile_path
  _state.nap_config = nap_config

  -- Read advisory lockfile
  if lockfile_path then
    _state.lock_data = lockfile.read(lockfile_path)
  end

  -- 1. Expand top-level imports
  local expanded = imports.expand(specs)

  -- 2. Normalize each spec (with built-in defaults)
  local normalized = {}
  for i, raw in ipairs(expanded) do
    normalized[#normalized + 1] = spec.normalize(raw, i)
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
  apply.run(config, merged)

  -- 6. Schedule non-blocking update checks if enabled
  updates.check_updates_async(merged, nap_config.updates)

  return config
end

---WezTerm plugin protocol compatibility wrapper.
---Delegates to setup with empty specs and normalized opts.
---For declarative usage, call setup directly.
---@param config table
---@param opts table  Can include nap_opts like { lockfile, integrations, updates, etc }
---@return table config
function M.apply_to_config(config, opts)
  -- For compatibility, support nap_opts directly as second argument
  return M.setup(config, {}, opts)
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

---Return resolved specs, nap config, and lockfile data for debugging.
---@return table
function M.status()
  return {
    specs = _state.resolved,
    nap_config = _state.nap_config,
    lock_data = _state.lock_data,
  }
end

---Update all plugins via WezTerm's native mechanism and rewrite the lockfile.
function M.update_all_and_lock()
  wezterm.plugin.update_all()
  M.write_lockfile()
  util.info "updated all plugins and wrote lockfile"
end

---Return a reference to the internal state table.
---Intended for internal use by the UI module.
---@return table
function M._get_state()
  return _state
end

---Return a WezTerm action that opens the nap plugin manager UI.
---Bind this to a key in your config:
---```lua
---config.keys = {
---  { key = "p", mods = "LEADER", action = nap.action() },
---}
---```
---@return table action  a wezterm.action_callback
function M.action()
  if not ui then
    util.error "UI module not available; nap.action() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    ui.open(window, pane, _state)
  end)
end

---Return a WezTerm action that shows plugin status.
---@return table action
function M.action_status()
  if not ui then
    util.error "UI module not available; nap.action_status() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_status then
      ui.show_status(window, pane, _state)
    else
      util.warn "show_status not available in UI module"
    end
  end)
end

---Return a WezTerm action that updates all plugins.
---@return table action
function M.action_update_all()
  return wezterm.action_callback(function(_window, _pane)
    M.update_all_and_lock()
  end)
end

---Return a WezTerm action that shows the uninstall menu.
---@return table action
function M.action_uninstall()
  if not ui then
    util.error "UI module not available; nap.action_uninstall() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_uninstall then
      ui.show_uninstall(window, pane, _state)
    else
      util.warn "show_uninstall not available in UI module"
    end
  end)
end

---Return a WezTerm action that shows the enable/disable toggle menu.
---@return table action
function M.action_toggle()
  if not ui then
    util.error "UI module not available; nap.action_toggle() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_toggle then
      ui.show_toggle(window, pane, _state)
    else
      util.warn "show_toggle not available in UI module"
    end
  end)
end

---Return a WezTerm action that opens a plugin directory in a new tab.
---@return table action
function M.action_open_dir()
  if not ui then
    util.error "UI module not available; nap.action_open_dir() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_open_dir then
      ui.show_open_dir(window, pane, _state)
    else
      util.warn "show_open_dir not available in UI module"
    end
  end)
end

return M
