local wezterm = require "wezterm"

local apply = require "nap.apply"
local u = require "nap.util" ---@type Nap.Util

local act = wezterm.action

local M = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

---Safely retrieve a nerd font glyph, returning `fallback` when unavailable.
---@param name string    nerdfonts key (e.g. "fa_list_ul")
---@param fallback? string  fallback text (default: "")
---@return string
local nerdfonts = wezterm.nerdfonts or {}
local function nf(name, fallback)
  return nerdfonts[name] or fallback or ""
end

---Default icon definitions.
---Each key maps to { nerdfonts_key, fallback_text }.
---@type table<string, string[]>
local DEFAULT_ICONS = {
  plugin_enabled = { "cod_circle_filled", "●" },
  plugin_disabled = { "cod_circle_outline", "○" },
  toggle_enabled = { "cod_circle_filled", "+" },
  toggle_disabled = { "cod_circle_outline", "-" },
  status = { "fa_list_ul", "*" },
  update_all = { "fa_refresh", "*" },
  uninstall = { "fa_trash", "*" },
  toggle = { "fa_toggle_on", "*" },
  open_dir = { "fa_folder_open", "*" },
  clean = { "fa_eraser", "*" },
  snapshot = { "fa_camera", "*" },
  restore = { "fa_undo", "*" },
  update_one = { "fa_download", "*" },
}

---Resolve an icon from user overrides or defaults.
---If user passed a string for a key, use it directly.
---If user passed a table { nerdfonts_key, fallback }, resolve via nf().
---Otherwise fall back to DEFAULT_ICONS.
---@param icons_cfg table  resolved icons table from get_ui_config
---@param key string       semantic icon key
---@return string
local function icon(icons_cfg, key)
  local user = icons_cfg[key]
  if type(user) == "string" then
    return user
  end
  if type(user) == "table" then
    return nf(user[1], user[2])
  end
  local def = DEFAULT_ICONS[key]
  if def then
    return nf(def[1], def[2])
  end
  return ""
end

---Extract UI configuration from nap state.
---@param state table nap internal state
---@return table ui_config with defaults
local function get_ui_config(state)
  local ui = state.nap_config and state.nap_config.ui or {}

  -- Resolve icons: true/nil → all defaults, false → empty strings, table → merge
  local icons_cfg
  if ui.icons == false then
    icons_cfg = {}
    for key in pairs(DEFAULT_ICONS) do
      icons_cfg[key] = ""
    end
  elseif type(ui.icons) == "table" then
    icons_cfg = {}
    for key, def in pairs(DEFAULT_ICONS) do
      if ui.icons[key] ~= nil then
        icons_cfg[key] = ui.icons[key]
      else
        icons_cfg[key] = nf(def[1], def[2])
      end
    end
    -- Allow user-defined keys not in defaults
    for key, val in pairs(ui.icons) do
      if icons_cfg[key] == nil then
        icons_cfg[key] = val
      end
    end
  else
    icons_cfg = {}
    for key, def in pairs(DEFAULT_ICONS) do
      icons_cfg[key] = nf(def[1], def[2])
    end
  end

  return {
    fuzzy = ui.fuzzy ~= false,
    icons = icons_cfg,
    colorscheme = ui.colorscheme or "auto",
    height = ui.height, -- nil = auto
    show_url = ui.show_url ~= false,
    show_priority = ui.show_priority ~= false,
  }
end

---Get the active WezTerm colorscheme.
---Resolution order: config.colors (live) → config.color_scheme looked up in
---config.color_schemes (user-defined map) → empty table fallback.
---@return table colorscheme definition or empty table
local function get_active_colorscheme()
  local cfg = wezterm.config or {}

  if cfg.colors then
    return cfg.colors
  end

  local name = cfg.color_scheme
  if name and cfg.color_schemes then
    local scheme = cfg.color_schemes[name]
    if scheme then
      return scheme
    end
  end

  return {}
end

---Semantic color role mapping to ANSI color fallbacks.
---@type table<string, string>
local SEMANTIC_COLORS = {
  enabled = "Green", -- indicates enabled/success state
  disabled = "Red", -- indicates disabled/inactive state
  accent = "Cyan", -- highlights and links
  muted = "Gray", -- secondary text
  path = "Fuchsia", -- file/directory paths
  priority = "Teal", -- metadata like priority
  warning = "Yellow", -- warnings and alerts
}

---Resolve a semantic UI color role to an actual color with fallback.
---@param role string semantic role name (e.g. "enabled", "accent")
---@param colorscheme? table active colorscheme (optional)
---@return table color spec for wezterm.format
local function resolve_color(role, colorscheme)
  colorscheme = colorscheme or {}
  local fallback_ansi = SEMANTIC_COLORS[role] or "White"

  -- For now, use ANSI color fallbacks directly.
  -- Future: could look up semantic colors in colorscheme definition if available.
  return { AnsiColor = fallback_ansi }
end

---Format a label with foreground color and optional icon.
---@param color_role string semantic color role (e.g. "enabled", "path")
---@param icon string    Nerd Font glyph
---@param text string
---@param colorscheme? table active colorscheme
---@return string
local function colored(color_role, icon, text, colorscheme)
  return wezterm.format {
    { Foreground = resolve_color(color_role, colorscheme) },
    { Text = icon .. "  " .. text },
  }
end

---Build a display label for a plugin spec.
---@param s table a resolved spec
---@param ui_cfg table ui configuration from get_ui_config()
---@param colorscheme? table pre-resolved colorscheme (avoids repeated lookups)
---@return string
local function plugin_label(s, ui_cfg, colorscheme)
  local enabled = apply.is_enabled(s)
  colorscheme = colorscheme or get_active_colorscheme()

  local badge = enabled
      and wezterm.format {
        { Foreground = resolve_color("enabled", colorscheme) },
        { Text = " " .. icon(ui_cfg.icons, "plugin_enabled") .. " " },
      }
    or wezterm.format {
      { Foreground = resolve_color("disabled", colorscheme) },
      { Text = " " .. icon(ui_cfg.icons, "plugin_disabled") .. " " },
    }

  local name = s.name or "<unnamed>"
  local url = s._resolved_url or ""
  local prio = s.priority or 0

  local parts = {
    { Attribute = { Intensity = "Bold" } },
    { Text = name },
    { Attribute = { Intensity = "Normal" } },
  }

  if ui_cfg.show_url then
    parts[#parts + 1] = { Foreground = resolve_color("path", colorscheme) }
    parts[#parts + 1] = { Text = "  " .. url }
  end

  if ui_cfg.show_priority then
    parts[#parts + 1] = { Foreground = resolve_color("priority", colorscheme) }
    parts[#parts + 1] = { Text = ("  [P:%d]"):format(prio) }
  end

  return wezterm.format(parts) .. badge
end

-- ────────────────────────────────────────────────────────────────────────────
-- Operations
-- ────────────────────────────────────────────────────────────────────────────

---Build InputSelector args, including optional height.
---@param args table base InputSelector arguments
---@param ui_cfg table ui configuration
---@return table
local function input_selector_args(args, ui_cfg)
  if ui_cfg.height then
    args.height = ui_cfg.height
  end
  return args
end

---Show the status of all managed plugins (informational).
---@param window table
---@param pane table
---@param state table
local function show_status(window, pane, state)
  local ui_cfg = get_ui_config(state)
  local colorscheme = get_active_colorscheme()
  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import then
      choices[#choices + 1] = {
        label = plugin_label(s, ui_cfg, colorscheme),
        id = s.name or "",
      }
    end
  end

  if #choices == 0 then
    u.log.info "no managed plugins"
    return
  end

  window:perform_action(
    act.InputSelector(input_selector_args({
      title = "nap — Plugin Status",
      description = "All managed plugins (press Esc to close)",
      fuzzy = ui_cfg.fuzzy,
      choices = choices,
      action = wezterm.action_callback(function() end),
    }, ui_cfg)),
    pane
  )
end

---Update all plugins.
---@param _window table
---@param _pane table
---@param state table
local function do_update_all(_window, _pane, state)
  local api = require "nap.api"
  api.update_all()
end

---Show a picker to update a single plugin.
---@param window table
---@param pane table
---@param state table
local function show_update_one(window, pane, state)
  local ui_cfg = get_ui_config(state)
  local colorscheme = get_active_colorscheme()
  local icons = ui_cfg and ui_cfg.icons or {}

  local choices = {}
  for _, s in ipairs(state.resolved or {}) do
    if s._resolved_url and s.name then
      local ic = apply.is_enabled(s) and icon(icons, "plugin_enabled")
        or icon(icons, "plugin_disabled")
      choices[#choices + 1] = {
        label = colored("accent", ic, s.name, colorscheme),
        id = s.name,
      }
    end
  end

  window:perform_action(
    act.InputSelector(input_selector_args({
      title = "nap — Update Plugin",
      description = "Select a plugin to update",
      fuzzy = ui_cfg.fuzzy,
      choices = choices,
      action = wezterm.action_callback(function(_w, _p, id, _label)
        if not id then
          return
        end
        local api = require "nap.api"
        local ok, err = api.update_one(id)
        if not ok then
          u.log.error("update failed: %s", err or "unknown")
        end
      end),
    }, ui_cfg)),
    pane
  )
end

---Show the uninstall picker.
---Deletes the plugin's clone directory and removes it from resolved state.
---@param window table
---@param pane table
---@param state table
---Delete a plugin directory from disk using wezterm.run_child_process.
---@param plugin_dir string  absolute path to the plugin directory
---@param label string       human-readable name for logging
---@return boolean ok
local function delete_plugin_dir(plugin_dir, label)
  local cmd
  if u.is_windows() then
    cmd = { "cmd", "/c", "rmdir", "/s", "/q", plugin_dir }
  else
    cmd = { "rm", "-rf", plugin_dir }
  end
  local ok = pcall(wezterm.run_child_process, cmd)
  if ok then
    u.log.info("deleted '%s' (%s)", label, plugin_dir)
  else
    u.log.error("failed to delete '%s' (%s)", label, plugin_dir)
  end
  return ok
end

local function show_uninstall(window, pane, state)
  local ui_cfg = get_ui_config(state)
  local colorscheme = get_active_colorscheme()

  -- Build URL→plugin_dir map once to avoid repeated plugin.list() scans.
  local dir_map = {}
  for _, p in ipairs(wezterm.plugin.list()) do
    dir_map[p.url] = p.plugin_dir
  end

  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import and s._resolved_url then
      choices[#choices + 1] = {
        label = plugin_label(s, ui_cfg, colorscheme),
        id = s.name or "",
      }
    end
  end

  if #choices == 0 then
    u.log.info "no plugins to uninstall"
    return
  end

  window:perform_action(
    act.InputSelector(input_selector_args({
      title = "nap — Uninstall Plugin",
      description = "Select a plugin to remove from disk",
      fuzzy = ui_cfg.fuzzy,
      choices = choices,
      action = wezterm.action_callback(function(_w, _p, id, _label)
        if not id then
          return
        end

        -- Find the spec
        local target
        for _, s in ipairs(state.resolved) do
          if s.name == id then
            target = s
            break
          end
        end
        if not target or not target._resolved_url then
          u.log.warn("cannot find spec for '%s'", id)
          return
        end

        local plugin_dir = dir_map[target._resolved_url]
        if plugin_dir then
          delete_plugin_dir(plugin_dir, id)
        else
          u.log.warn("plugin_dir not found for '%s'", id)
        end

        -- Remove from resolved state
        for i, s in ipairs(state.resolved) do
          if s.name == id then
            table.remove(state.resolved, i)
            break
          end
        end
      end),
    }, ui_cfg)),
    pane
  )
end

---Show the enable/disable toggle picker.
---Flips the `enabled` field at runtime (does not persist across restarts).
---@param window table
---@param pane table
---@param state table
local function show_toggle(window, pane, state)
  local ui_cfg = get_ui_config(state)
  local colorscheme = get_active_colorscheme()
  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import and s._resolved_url then
      local enabled = apply.is_enabled(s)
      local action_label = enabled and "Disable" or "Enable"
      local toggle_icon = enabled and icon(ui_cfg.icons, "toggle_enabled")
        or icon(ui_cfg.icons, "toggle_disabled")
      local label_role = enabled and "enabled" or "disabled"

      choices[#choices + 1] = {
        label = colored(
          label_role,
          toggle_icon,
          action_label .. ": " .. (s.name or "<unnamed>"),
          colorscheme
        ),
        id = s.name or "",
      }
    end
  end

  if #choices == 0 then
    u.log.info "no plugins to toggle"
    return
  end

  window:perform_action(
    act.InputSelector(input_selector_args({
      title = "nap — Enable / Disable",
      description = "Toggle a plugin (runtime only, lost on restart)",
      fuzzy = ui_cfg.fuzzy,
      choices = choices,
      action = wezterm.action_callback(function(_w, _p, id, _label)
        if not id then
          return
        end

        for _, s in ipairs(state.resolved) do
          if s.name == id then
            local was_enabled = apply.is_enabled(s)
            s.enabled = not was_enabled
            local new_status = s.enabled and "enabled" or "disabled"
            u.log.info("'%s' is now %s (takes effect on config reload)", id, new_status)
            break
          end
        end
      end),
    }, ui_cfg)),
    pane
  )
end

---Show the directory opener picker.
---Opens a new terminal tab in the selected plugin's clone directory.
---@param window table
---@param pane table
---@param state table
local function show_open_dir(window, pane, state)
  local ui_cfg = get_ui_config(state)
  local colorscheme = get_active_colorscheme()

  -- Build URL→plugin_dir map once to avoid repeated plugin.list() scans.
  local dir_map = {}
  for _, p in ipairs(wezterm.plugin.list()) do
    dir_map[p.url] = p.plugin_dir
  end

  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import and s._resolved_url then
      local plugin_dir = dir_map[s._resolved_url]
      if plugin_dir then
        choices[#choices + 1] = {
          label = wezterm.format {
            { Attribute = { Intensity = "Bold" } },
            { Text = s.name or "<unnamed>" },
            { Attribute = { Intensity = "Normal" } },
            { Foreground = resolve_color("path", colorscheme) },
            { Text = "  " .. plugin_dir },
          },
          id = s.name or "",
        }
      end
    end
  end

  if #choices == 0 then
    u.log.info "no plugin directories found"
    return
  end

  window:perform_action(
    act.InputSelector(input_selector_args({
      title = "nap — Open Plugin Directory",
      description = "Select a plugin to open its directory in a new tab",
      fuzzy = ui_cfg.fuzzy,
      choices = choices,
      action = wezterm.action_callback(function(w, p, id, _label)
        if not id then
          return
        end

        for _, s in ipairs(state.resolved) do
          if s.name == id and s._resolved_url then
            local dir = dir_map[s._resolved_url]
            if dir then
              w:perform_action(act.SpawnCommandInNewTab { cwd = dir }, p)
            end
            break
          end
        end
      end),
    }, ui_cfg)),
    pane
  )
end

---Show the orphan cleanup picker.
---Lists plugins installed on disk but not declared in specs.
---@param window table
---@param pane table
---@param state table
local function show_clean(window, pane, state)
  local ui_cfg = get_ui_config(state)

  -- Build set of declared URLs
  local declared_urls = {}
  for _, s in ipairs(state.resolved) do
    if s._resolved_url then
      declared_urls[s._resolved_url] = true
    end
  end

  -- Find orphans
  local orphans = {}
  for _, p in ipairs(wezterm.plugin.list()) do
    if not declared_urls[p.url] and not p.url:find("nap%.wz", 1, false) then
      local name = p.url:match "([^/]+)/?$" or p.url
      name = name:gsub("%.git$", "")
      orphans[#orphans + 1] = {
        label = wezterm.format {
          { Text = name .. "  " },
          { Text = p.url },
        },
        id = p.url,
        plugin_dir = p.plugin_dir,
        name = name,
      }
    end
  end

  if #orphans == 0 then
    u.log.info "no orphan plugins found"
    return
  end

  -- Build a url → orphan map for lookup in callback
  local orphan_map = {}
  for _, o in ipairs(orphans) do
    orphan_map[o.id] = o
  end

  window:perform_action(
    act.InputSelector(input_selector_args({
      title = "nap — Clean Orphan Plugins",
      description = "Select an orphan plugin to remove from disk",
      fuzzy = ui_cfg.fuzzy,
      choices = orphans,
      action = wezterm.action_callback(function(_w, _p, id, _label)
        if not id then
          return
        end
        local orphan = orphan_map[id]
        if orphan and orphan.plugin_dir then
          delete_plugin_dir(orphan.plugin_dir, orphan.name)
        end
      end),
    }, ui_cfg)),
    pane
  )
end

-- ────────────────────────────────────────────────────────────────────────────
-- Lockfile operations
-- ────────────────────────────────────────────────────────────────────────────

---Take a lockfile snapshot.  Delegates to api.snapshot().
---@param _window table
---@param _pane table
---@param state table
local function do_snapshot(_window, _pane, state)
  local api = require "nap.api"
  api.snapshot()
end

---Restore plugins from the lockfile.  Delegates to api.restore().
---@param _window table
---@param _pane table
---@param state table
local function do_restore(_window, _pane, state)
  local api = require "nap.api"
  api.restore()
end

-- ────────────────────────────────────────────────────────────────────────────
-- Top-level menu
-- ────────────────────────────────────────────────────────────────────────────

---Build the top-level choices list.
---Deferred to call-time so that wezterm.nerdfonts is fully available.
---@param ui_cfg table       ui configuration from get_ui_config()
---@param colorscheme? table active colorscheme (optional)
---@return table[]
local function build_top_choices(ui_cfg, colorscheme)
  colorscheme = colorscheme or get_active_colorscheme()
  local icons = ui_cfg and ui_cfg.icons or {}
  return {
    {
      label = colored("accent", icon(icons, "status"), "Status", colorscheme),
      id = "status",
    },
    {
      label = colored("enabled", icon(icons, "update_all"), "Update All", colorscheme),
      id = "update_all",
    },
    {
      label = colored("enabled", icon(icons, "update_one"), "Update Plugin", colorscheme),
      id = "update_one",
    },
    {
      label = colored("warning", icon(icons, "uninstall"), "Uninstall", colorscheme),
      id = "uninstall",
    },
    {
      label = colored("accent", icon(icons, "toggle"), "Enable / Disable", colorscheme),
      id = "toggle",
    },
    {
      label = colored("path", icon(icons, "open_dir"), "Open Directory", colorscheme),
      id = "open_dir",
    },
    {
      label = colored("warning", icon(icons, "clean"), "Clean Orphans", colorscheme),
      id = "clean",
    },
    {
      label = colored(
        "accent",
        icon(icons, "snapshot"),
        "Snapshot Lockfile",
        colorscheme
      ),
      id = "snapshot",
    },
    {
      label = colored("warning", icon(icons, "restore"), "Restore Lockfile", colorscheme),
      id = "restore",
    },
  }
end

---Open the top-level plugin manager UI.
---@param window table   WezTerm Window object
---@param pane table     WezTerm Pane object
---@param state table    internal nap state (resolved, nap_config)
function M.open(window, pane, state)
  local ui_cfg = get_ui_config(state)
  local colorscheme = get_active_colorscheme()
  window:perform_action(
    act.InputSelector(input_selector_args({
      title = "nap — Plugin Manager",
      description = "Select an action",
      fuzzy = ui_cfg.fuzzy,
      choices = build_top_choices(ui_cfg, colorscheme),
      action = wezterm.action_callback(function(w, p, id, _label)
        if not id then
          return
        end

        if id == "status" then
          show_status(w, p, state)
        elseif id == "update_all" then
          do_update_all(w, p, state)
        elseif id == "update_one" then
          show_update_one(w, p, state)
        elseif id == "uninstall" then
          show_uninstall(w, p, state)
        elseif id == "toggle" then
          show_toggle(w, p, state)
        elseif id == "open_dir" then
          show_open_dir(w, p, state)
        elseif id == "clean" then
          show_clean(w, p, state)
        elseif id == "snapshot" then
          do_snapshot(w, p, state)
        elseif id == "restore" then
          do_restore(w, p, state)
        end
      end),
    }, ui_cfg)),
    pane
  )
end

-- Export public operations for direct action binding
M.show_status = show_status
M.show_uninstall = show_uninstall
M.show_toggle = show_toggle
M.show_open_dir = show_open_dir
M.show_clean = show_clean
M.do_update_all = do_update_all
M.show_update_one = show_update_one
M.do_snapshot = do_snapshot
M.do_restore = do_restore

return M
