---Public API for nap.wz. All user-facing functions live here.
---`plugin/init.lua` requires this module after bootstrapping package.path.

---@class Wezterm
local wezterm = require "wezterm" --[[@as Wezterm]]

local apply = require "nap.apply"
local config_module = require "nap.config"
local imports = require "nap.import"
local lockfile = require "nap.lockfile"
local merge = require "nap.merge"
local spec = require "nap.spec"
local u = require "nap.util" ---@type Nap.Util
local updates = require "nap.updates"

local _ui -- lazy-loaded on first action*() call

---Load the UI module on demand (avoids overhead when no action keys are bound).
---@return table|nil ui module or nil if unavailable
local function get_ui()
  if _ui == nil then
    local ok, mod = pcall(require, "nap.ui")
    if ok then
      _ui = mod
    else
      _ui = false
      u.log.warn("could not load UI module: %s", tostring(mod))
    end
  end
  return _ui or nil
end

local M = {}

---Internal state persisted across calls.
local _state = {
  nap_config = {},
  resolved = {},
  registry = {}, -- name -> resolved URL mapping for nap.require()
}

---Expand `dependencies` fields in raw specs.
---For each spec with a `dependencies` list, inject the dependency specs
---before the dependent in the output list, with priority bumped by 1.
---Handles shorthand strings (e.g. "owner/repo") expanded to full spec tables.
---Detects cycles by tracking visited names.
---@param raw_specs table[]  list of raw spec entries
---@return table[]  expanded list with dependencies injected
function M._expand_dependencies(raw_specs)
  local result = {}
  local visiting = {} -- cycle detection set

  local function expand(dep_spec, parent_priority, depth)
    if depth > 20 then
      u.log.warn "dependency chain too deep (>20); possible cycle, stopping expansion"
      return
    end

    -- Normalize shorthand strings to spec tables
    if type(dep_spec) == "string" then
      dep_spec = { dep_spec }
    end
    if type(dep_spec) ~= "table" then
      return
    end

    -- Derive a name for cycle detection
    local name = dep_spec.name or dep_spec[1]
    if name and visiting[name] then
      u.log.warn("circular dependency detected: '%s'; skipping", name)
      return
    end

    if name then
      visiting[name] = true
    end

    -- Recursively expand this spec's own dependencies first
    if dep_spec.dependencies then
      local dep_priority = (parent_priority or 0) + 1
      for _, sub_dep in ipairs(dep_spec.dependencies) do
        expand(sub_dep, dep_priority, depth + 1)
      end
    end

    -- Inject the dependency itself with boosted priority
    local injected = {}
    for k, v in pairs(dep_spec) do
      injected[k] = v
    end
    -- Copy shorthand [1] if present
    if dep_spec[1] then
      injected[1] = dep_spec[1]
    end
    injected.priority = math.max(injected.priority or 0, (parent_priority or 0) + 1)
    injected.dependencies = nil -- already expanded
    result[#result + 1] = injected

    if name then
      visiting[name] = nil
    end
  end

  for _, raw in ipairs(raw_specs) do
    -- Normalize shorthand strings to spec tables
    if type(raw) == "string" then
      raw = { raw }
    end
    if type(raw) ~= "table" then
      goto continue
    end

    -- Expand dependencies of this spec (injected before the spec itself)
    if raw.dependencies then
      local parent_name = raw.name or raw[1]
      local parent_priority = raw.priority or 0
      -- Mark parent as visiting to detect self-references
      if parent_name then
        visiting[parent_name] = true
      end
      for _, dep in ipairs(raw.dependencies) do
        expand(dep, parent_priority, 1)
      end
      if parent_name then
        visiting[parent_name] = nil
      end
    end
    -- Add the spec itself (without dependencies field, it's been expanded)
    local cleaned = {}
    for k, v in pairs(raw) do
      if k ~= "dependencies" then
        cleaned[k] = v
      end
    end
    if raw[1] then
      cleaned[1] = raw[1]
    end
    result[#result + 1] = cleaned
    ::continue::
  end

  return result
end

---Main entry point. Declares plugins and applies them to the config.
---
---Usage:
---```lua
---local wezterm = require "wezterm"
---local nap = require "nap"
---
---return nap.setup(
---  wezterm.config_builder(),
---  {
---    { "owner/plugin-name", opts = { key = "value" } },
---    { import = "wez_plugins.core" },
---  },
---  {
---    log_level = "info",
---    updates = { enabled = false },
---  }
---)
---```
---
---@param config   table   WezTerm config builder (from wezterm.config_builder())
---@param specs    table   List of plugin spec entries
---@param nap_opts table?  Configuration for nap behaviour (all fields optional)
---@return table config
function M.setup(config, specs, nap_opts)
  specs = specs or {}
  nap_opts = nap_opts or {}

  local nap_config = config_module.normalize(nap_opts)

  -- Apply log level as early as possible so subsequent calls respect it
  u.log.set_level(nap_config.log_level)

  _state.nap_config = nap_config

  -- 1. Expand top-level imports
  local expanded = imports.expand(specs)

  -- 1b. Expand dependencies: inject dependency specs before their dependents
  expanded = M._expand_dependencies(expanded)

  -- 2. Normalize each spec (with per-spec defaults from nap config)
  local spec_defaults = nap_config.specs.defaults
  local dev_config = nap_config.dev
  local normalized = {}
  for i, raw in ipairs(expanded) do
    normalized[#normalized + 1] = spec.normalize(raw, i, spec_defaults, dev_config)
  end

  -- 3. Validate
  for _, s in ipairs(normalized) do
    local ok, err = spec.validate(s)
    if not ok then
      u.log.warn(err)
    end
  end

  -- 3b. Warn about name conflicts from different URLs
  local _seen_urls = {}
  for _, s in ipairs(normalized) do
    if s.name and s._resolved_url then
      if _seen_urls[s.name] and _seen_urls[s.name] ~= s._resolved_url then
        u.log.warn(
          "multiple specs derive name '%s' from different URLs (%s vs %s); "
            .. "consider adding an explicit 'name' field to disambiguate",
          s.name,
          _seen_urls[s.name],
          s._resolved_url
        )
      end
      _seen_urls[s.name] = s._resolved_url
    end
  end

  -- 4. Merge by name
  local merged = merge.merge(normalized)
  _state.resolved = merged

  -- 4b. Build name→URL registry for nap.require()
  _state.registry = {}
  for _, s in ipairs(merged) do
    if s.name and s._resolved_url then
      _state.registry[s.name] = s._resolved_url
    end
  end

  -- 5. Apply all enabled plugins
  apply.run(config, merged, nap_config)

  -- 6. Schedule non-blocking update checks if enabled
  updates.check_updates_async(merged, nap_config.updates)

  -- 7. Register command palette entries when enabled
  if nap_config.integrations and nap_config.integrations.command_palette then
    local palette_actions = {
      { brief = "nap: Plugin Manager", action = M.action() },
      { brief = "nap: Plugin Status", action = M.action_status() },
      { brief = "nap: Update All", action = M.action_update_all() },
      { brief = "nap: Update Plugin", action = M.action_update_one() },
      { brief = "nap: Uninstall", action = M.action_uninstall() },
      { brief = "nap: Enable / Disable", action = M.action_toggle() },
      { brief = "nap: Open Plugin Dir", action = M.action_open_dir() },
      { brief = "nap: Snapshot Lockfile", action = M.action_snapshot() },
      { brief = "nap: Restore Lockfile", action = M.action_restore() },
    }
    wezterm.on("augment-command-palette", function(_window, _pane)
      return palette_actions
    end)
  end

  -- 8. Inject keybindings when keymaps is a table
  if type(nap_config.keymaps) == "table" then
    config.keys = config.keys or {}
    local km = nap_config.keymaps
    if km.toggle_input and type(km.toggle_input) == "table" then
      config.keys[#config.keys + 1] = {
        key = km.toggle_input.key,
        mods = km.toggle_input.mods,
        action = M.action(),
      }
    end
  end

  return config
end

---Require a plugin by short name or full URL.
---
---When called with a short name (e.g. `"warp"`), resolves it via the
---internal registry built during `setup()`. When called with a URL or
---GitHub shorthand (`"owner/repo"`), delegates directly to
---`wezterm.plugin.require()`.
---
---Usage:
---```lua
---local warp = nap.require "warp"        -- short name
---local bar  = nap.require "status-bar"   -- derived from URL
---
----- full URL still works
---local p = nap.require "https://github.com/owner/plugin"
---```
---
---@param name_or_url string  short name, GitHub shorthand, or full URL
---@return table plugin  the loaded plugin module
function M.require(name_or_url)
  -- Full URL: delegate directly
  if name_or_url:find("://", 1, true) then
    return wezterm.plugin.require(name_or_url)
  end

  -- GitHub shorthand (owner/repo): expand and delegate
  if name_or_url:match "^[%w%-_.]+/[%w%-_.]+" then
    return wezterm.plugin.require("https://github.com/" .. name_or_url)
  end

  -- Short name: look up in registry
  local url = _state.registry[name_or_url]
  if url then
    return wezterm.plugin.require(url)
  end

  -- Unknown name: actionable error
  local names = {}
  for k, _ in pairs(_state.registry) do
    names[#names + 1] = k
  end
  table.sort(names)

  local available = #names > 0 and "registered plugins: " .. table.concat(names, ", ")
    or "no plugins registered (has nap.setup() been called?)"

  error(
    (
      "[nap.wz] plugin '%s' not found in registry. "
      .. "Ensure it is included in your nap.setup() specs.\n"
      .. '  Example: { "owner/%s", name = "%s" }\n'
      .. "  %s"
    ):format(name_or_url, name_or_url, name_or_url, available),
    2
  )
end

---WezTerm plugin protocol compatibility wrapper.
---Delegates to setup() with empty specs and the provided opts.
---For declarative usage, call setup() directly.
---@param config table
---@param opts   table?  Can include any nap_opts fields
---@return table config
function M.apply_to_config(config, opts)
  return M.setup(config, {}, opts)
end

---Return resolved specs and nap config for debugging.
---@return table
function M.status()
  return {
    specs = _state.resolved,
    nap_config = _state.nap_config,
  }
end

---Update all plugins individually via git fetch + merge/checkout.
function M.update_all()
  for _, s in ipairs(_state.resolved) do
    if s._resolved_url and s.name then
      updates.update_plugin(s)
    end
  end
  u.log.info "updated all plugins"
end

---Update a single plugin by name.
---@param name string  plugin name
---@return boolean ok, string|nil err
function M.update_one(name)
  for _, s in ipairs(_state.resolved) do
    if s.name == name then
      return updates.update_plugin(s)
    end
  end
  return false, "plugin '" .. name .. "' not found"
end

---Detect orphan plugins: installed on disk but not declared in specs.
---Excludes nap.wz itself.
---@return table[] orphans  list of { url, plugin_dir, name }
function M.clean()
  local installed = wezterm.plugin.list()
  local declared_urls = {}
  for _, s in ipairs(_state.resolved) do
    if s._resolved_url then
      declared_urls[s._resolved_url] = true
    end
  end

  local orphans = {}
  for _, p in ipairs(installed) do
    -- Exclude nap.wz itself
    if not declared_urls[p.url] and not p.url:find("nap%.wz", 1, false) then
      local name = p.url:match "([^/]+)/?$" or p.url
      orphans[#orphans + 1] = {
        url = p.url,
        plugin_dir = p.plugin_dir,
        name = name:gsub("%.git$", ""),
      }
    end
  end

  return orphans
end

---Take a snapshot of current plugin commit SHAs and write to lockfile.
---@param path? string  override lockfile path (defaults to nap_config.lockfile)
---@return boolean ok, string|nil err
function M.snapshot(path)
  path = path or (_state.nap_config and _state.nap_config.lockfile)
  if not path then
    return false, "no lockfile path configured"
  end
  local data = lockfile.snapshot(_state.resolved)
  local ok, err = lockfile.write(path, data)
  if ok then
    u.log.info("snapshot written to %s", path)
  else
    u.log.error("failed to write snapshot: %s", err or "unknown")
  end
  return ok, err
end

---Restore plugins to commits recorded in lockfile.
---@param path? string  override lockfile path (defaults to nap_config.lockfile)
---@return table|nil results  per-plugin restore results, or nil on error
function M.restore(path)
  path = path or (_state.nap_config and _state.nap_config.lockfile)
  if not path then
    u.log.error "no lockfile path configured"
    return nil
  end
  local data, err = lockfile.read(path)
  if not data then
    u.log.error("failed to read lockfile: %s", err or "unknown")
    return nil
  end
  local results = lockfile.restore(_state.resolved, data)
  u.log.info("restore complete from %s", path)
  return results
end

---Return a reference to the internal state table.
---Intended for internal use by the UI module.
---@return table
function M._get_state()
  return _state
end

-- ─────────────────────────────────────────────────────────────
-- WezTerm action helpers
-- ─────────────────────────────────────────────────────────────

---Return a WezTerm action that opens the nap plugin manager UI.
---Bind this to a key in your config:
---```lua
---config.keys = {
---  { key = "p", mods = "LEADER", action = nap.action() },
---}
---```
---@return table action  a wezterm.action_callback
function M.action()
  local ui = get_ui()
  if not ui then
    u.log.error "UI module not available; nap.action() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    ui.open(window, pane, _state)
  end)
end

---Return a WezTerm action that shows plugin status.
---@return table action
function M.action_status()
  local ui = get_ui()
  if not ui then
    u.log.error "UI module not available; nap.action_status() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_status then
      ui.show_status(window, pane, _state)
    else
      u.log.warn "show_status not available in UI module"
    end
  end)
end

---Return a WezTerm action that updates all plugins.
---@return table action
function M.action_update_all()
  return wezterm.action_callback(function(_window, _pane)
    M.update_all()
  end)
end

---Return a WezTerm action that shows the per-plugin update picker.
---@return table action
function M.action_update_one()
  local ui = get_ui()
  if not ui then
    u.log.error "UI module not available; nap.action_update_one() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_update_one then
      ui.show_update_one(window, pane, _state)
    else
      u.log.warn "show_update_one not available in UI module"
    end
  end)
end

---Return a WezTerm action that shows the uninstall menu.
---@return table action
function M.action_uninstall()
  local ui = get_ui()
  if not ui then
    u.log.error "UI module not available; nap.action_uninstall() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_uninstall then
      ui.show_uninstall(window, pane, _state)
    else
      u.log.warn "show_uninstall not available in UI module"
    end
  end)
end

---Return a WezTerm action that shows the enable/disable toggle menu.
---@return table action
function M.action_toggle()
  local ui = get_ui()
  if not ui then
    u.log.error "UI module not available; nap.action_toggle() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_toggle then
      ui.show_toggle(window, pane, _state)
    else
      u.log.warn "show_toggle not available in UI module"
    end
  end)
end

---Return a WezTerm action that opens a plugin directory in a new tab.
---@return table action
function M.action_open_dir()
  local ui = get_ui()
  if not ui then
    u.log.error "UI module not available; nap.action_open_dir() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_open_dir then
      ui.show_open_dir(window, pane, _state)
    else
      u.log.warn "show_open_dir not available in UI module"
    end
  end)
end

---Return a WezTerm action that opens the orphan cleanup picker.
---@return table
function M.action_clean()
  local ui = get_ui()
  if not ui then
    u.log.error "UI module not available; nap.action_clean() is a no-op"
    return wezterm.action.Nop
  end
  return wezterm.action_callback(function(window, pane)
    if ui.show_clean then
      ui.show_clean(window, pane, _state)
    else
      u.log.warn "show_clean not available in UI module"
    end
  end)
end

---Return a WezTerm action that takes a lockfile snapshot.
---@return table
function M.action_snapshot()
  return wezterm.action_callback(function(_window, _pane)
    M.snapshot()
  end)
end

---Return a WezTerm action that restores plugins from the lockfile.
---@return table
function M.action_restore()
  return wezterm.action_callback(function(_window, _pane)
    M.restore()
  end)
end

return M
