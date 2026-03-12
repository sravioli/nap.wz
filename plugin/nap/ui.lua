local wezterm = require "wezterm"

local apply = require "nap.apply"
local lockfile = require "nap.lockfile"
local util = require "nap.util"

local act = wezterm.action

local M = {}

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

---Safely retrieve a nerd font glyph, returning `fallback` when unavailable.
---@param name string    nerdfonts key (e.g. "fa_list_ul")
---@param fallback? string  fallback text (default: "")
---@return string
local function nf(name, fallback)
  local ok, glyph = pcall(function()
    return wezterm.nerdfonts[name]
  end)
  if ok and glyph then
    return glyph
  end
  return fallback or ""
end

---Extract UI configuration from nap state.
---@param state table nap internal state
---@return table ui_config with defaults
local function get_ui_config(state)
  local ui = state.nap_config and state.nap_config.ui or {}
  return {
    fuzzy = ui.fuzzy ~= false,  -- default true
    icons = ui.icons ~= false,  -- default true
    colorscheme = ui.colorscheme or "auto",
    width = ui.width or 80,
  }
end

---Get the active WezTerm colorscheme.
---@return table colorscheme definition or empty table on error
local function get_active_colorscheme()
  local ok, scheme = pcall(function()
    return wezterm.color.get_builtin_schemes()[wezterm.config.color_scheme]
  end)
  if ok and scheme then
    return scheme
  end
  return {}
end

---Semantic color role mapping to ANSI color fallbacks.
---@type table<string, string>
local SEMANTIC_COLORS = {
  enabled = "Green",      -- indicates enabled/success state
  disabled = "Red",       -- indicates disabled/inactive state
  accent = "Cyan",        -- highlights and links
  muted = "Gray",         -- secondary text
  path = "Fuchsia",       -- file/directory paths
  priority = "Teal",      -- metadata like priority
  warning = "Yellow",     -- warnings and alerts
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
---@return string
local function plugin_label(s)
  local enabled = apply.is_enabled(s)
  local colorscheme = get_active_colorscheme()

  local badge = enabled
      and wezterm.format {
        { Foreground = resolve_color("enabled", colorscheme) },
        { Text = " ● " },
      }
    or wezterm.format {
      { Foreground = resolve_color("disabled", colorscheme) },
      { Text = " ○ " },
    }

  local name = s.name or "<unnamed>"
  local url = s._resolved_url or ""
  local prio = s.priority or 0

  return wezterm.format {
    { Attribute = { Intensity = "Bold" } },
    { Text = name },
    { Attribute = { Intensity = "Normal" } },
    { Foreground = resolve_color("path", colorscheme) },
    { Text = "  " .. url },
    { Foreground = resolve_color("priority", colorscheme) },
    { Text = ("  [P:%d]"):format(prio) },
  } .. badge
end

-- ────────────────────────────────────────────────────────────────────────────
-- Operations
-- ────────────────────────────────────────────────────────────────────────────

---Show the status of all managed plugins (informational).
---@param window table
---@param pane table
---@param state table
local function show_status(window, pane, state)
  local ui_cfg = get_ui_config(state)
  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import then
      choices[#choices + 1] = {
        label = plugin_label(s),
        id = s.name or "",
      }
    end
  end

  if #choices == 0 then
    util.info "no managed plugins"
    return
  end

  window:perform_action(
    act.InputSelector {
      title = "nap — Plugin Status",
      description = "All managed plugins (press Esc to close)",
      fuzzy = ui_cfg.fuzzy,
      choices = choices,
      action = wezterm.action_callback(function() end),
    },
    pane
  )
end

---Update all plugins and rewrite the lockfile.
---@param _window table
---@param _pane table
---@param state table
local function do_update_all(_window, _pane, state)
  wezterm.plugin.update_all()
  if state.lockfile_path then
    lockfile.write(state.lockfile_path, state.resolved)
  end
  util.info "updated all plugins and wrote lockfile"
end

---Show the uninstall picker.
---Deletes the plugin's clone directory and removes it from the lockfile.
---@param window table
---@param pane table
---@param state table
local function show_uninstall(window, pane, state)
  local ui_cfg = get_ui_config(state)
  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import and s._resolved_url then
      choices[#choices + 1] = {
        label = plugin_label(s),
        id = s.name or "",
      }
    end
  end

  if #choices == 0 then
    util.info "no plugins to uninstall"
    return
  end

  window:perform_action(
    act.InputSelector {
      title = "nap — Uninstall Plugin",
      description = "Select a plugin to remove from disk",
      fuzzy = ui_cfg.fuzzy,
      choices = choices,
      action = wezterm.action_callback(function(_w, _p, id, _label)
        if not id then
          return
        end

        -- Find the spec and its plugin_dir
        local target
        for _, s in ipairs(state.resolved) do
          if s.name == id then
            target = s
            break
          end
        end
        if not target or not target._resolved_url then
          util.warn(("cannot find spec for '%s'"):format(id))
          return
        end

        local plugin_dir = util.find_plugin_dir(target._resolved_url)
        if plugin_dir then
          local cmd
          if util.is_windows() then
            cmd = ('rmdir /s /q "%s"'):format(plugin_dir)
          else
            cmd = ('rm -rf "%s"'):format(plugin_dir)
          end
          local ok = os.execute(cmd)
          if ok then
            util.info(("deleted '%s' (%s)"):format(id, plugin_dir))
          else
            util.error(("failed to delete '%s' (%s)"):format(id, plugin_dir))
          end
        else
          util.warn(("plugin_dir not found for '%s'"):format(id))
        end

        -- Remove from lockfile
        if state.lockfile_path then
          lockfile.remove_entry(state.lockfile_path, id)
        end

        -- Remove from resolved state
        for i, s in ipairs(state.resolved) do
          if s.name == id then
            table.remove(state.resolved, i)
            break
          end
        end
      end),
    },
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
      local icon = enabled
          and nf("cod_circle_filled", "+")
        or nf("cod_circle_outline", "-")
      local label_role = enabled and "enabled" or "disabled"

      choices[#choices + 1] = {
        label = colored(label_role, icon, action_label .. ": " .. (s.name or "<unnamed>"), colorscheme),
        id = s.name or "",
      }
    end
  end

  if #choices == 0 then
    util.info "no plugins to toggle"
    return
  end

  window:perform_action(
    act.InputSelector {
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
            util.info(
              ("'%s' is now %s (takes effect on config reload)"):format(
                id,
                new_status
              )
            )
            break
          end
        end
      end),
    },
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
  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import and s._resolved_url then
      local plugin_dir = util.find_plugin_dir(s._resolved_url)
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
    util.info "no plugin directories found"
    return
  end

  window:perform_action(
    act.InputSelector {
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
            local dir = util.find_plugin_dir(s._resolved_url)
            if dir then
              w:perform_action(
                act.SpawnCommandInNewTab { cwd = dir },
                p
              )
            end
            break
          end
        end
      end),
    },
    pane
  )
end

-- ────────────────────────────────────────────────────────────────────────────
-- Top-level menu
-- ────────────────────────────────────────────────────────────────────────────

---Build the top-level choices list.
---Deferred to call-time so that wezterm.nerdfonts is fully available.
---@param colorscheme? table active colorscheme (optional)
---@return table[]
local function build_top_choices(colorscheme)
  colorscheme = colorscheme or get_active_colorscheme()
  return {
    {
      label = colored("accent", nf("fa_list_ul", "*"), "Status", colorscheme),
      id = "status",
    },
    {
      label = colored("enabled", nf("fa_refresh", "*"), "Update All", colorscheme),
      id = "update_all",
    },
    {
      label = colored("warning", nf("fa_trash", "*"), "Uninstall", colorscheme),
      id = "uninstall",
    },
    {
      label = colored("accent", nf("fa_toggle_on", "*"), "Enable / Disable", colorscheme),
      id = "toggle",
    },
    {
      label = colored("path", nf("fa_folder_open", "*"), "Open Directory", colorscheme),
      id = "open_dir",
    },
  }
end

---Open the top-level plugin manager UI.
---@param window table   WezTerm Window object
---@param pane table     WezTerm Pane object
---@param state table    internal nap state (resolved, nap_config, lockfile_path, lock_data)
function M.open(window, pane, state)
  local ui_cfg = get_ui_config(state)
  local colorscheme = get_active_colorscheme()
  window:perform_action(
    act.InputSelector {
      title = "nap — Plugin Manager",
      description = "Select an action",
      fuzzy = ui_cfg.fuzzy,
      choices = build_top_choices(colorscheme),
      action = wezterm.action_callback(function(w, p, id, _label)
        if not id then
          return
        end

        if id == "status" then
          show_status(w, p, state)
        elseif id == "update_all" then
          do_update_all(w, p, state)
        elseif id == "uninstall" then
          show_uninstall(w, p, state)
        elseif id == "toggle" then
          show_toggle(w, p, state)
        elseif id == "open_dir" then
          show_open_dir(w, p, state)
        end
      end),
    },
    pane
  )
end

-- Export public operations for direct action binding
M.show_status = show_status
M.show_uninstall = show_uninstall
M.show_toggle = show_toggle
M.show_open_dir = show_open_dir
M.do_update_all = do_update_all

return M
