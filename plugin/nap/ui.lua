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

-- ────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ────────────────────────────────────────────────────────────────────────────

---Format a label with foreground color and optional icon.
---@param color string   AnsiColor name (e.g. "Green", "Red")
---@param icon string    Nerd Font glyph
---@param text string
---@return string
local function colored(color, icon, text)
  return wezterm.format {
    { Foreground = { AnsiColor = color } },
    { Text = icon .. "  " .. text },
  }
end

---Build a display label for a plugin spec.
---@param s table    a resolved spec
---@param env table  environment table
---@return string
local function plugin_label(s, env)
  local enabled = apply.is_enabled(s, env)
  local badge = enabled
      and wezterm.format {
        { Foreground = { AnsiColor = "Green" } },
        { Text = " ● " },
      }
    or wezterm.format {
      { Foreground = { AnsiColor = "Red" } },
      { Text = " ○ " },
    }

  local name = s.name or "<unnamed>"
  local url = s._resolved_url or ""
  local prio = s.priority or 0

  return wezterm.format {
    { Attribute = { Intensity = "Bold" } },
    { Text = name },
    { Attribute = { Intensity = "Normal" } },
    { Foreground = { AnsiColor = "Fuchsia" } },
    { Text = "  " .. url },
    { Foreground = { AnsiColor = "Teal" } },
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
  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import then
      choices[#choices + 1] = {
        label = plugin_label(s, state.env),
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
      fuzzy = true,
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
  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import and s._resolved_url then
      choices[#choices + 1] = {
        label = plugin_label(s, state.env),
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
      fuzzy = true,
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
  local choices = {}
  for _, s in ipairs(state.resolved) do
    if not s.import and s._resolved_url then
      local enabled = apply.is_enabled(s, state.env)
      local action_label = enabled and "Disable" or "Enable"
      local icon = enabled
          and nf("cod_circle_filled", "+")
        or nf("cod_circle_outline", "-")
      local label_color = enabled and "Green" or "Red"

      choices[#choices + 1] = {
        label = colored(label_color, icon, action_label .. ": " .. (s.name or "<unnamed>")),
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
      fuzzy = true,
      choices = choices,
      action = wezterm.action_callback(function(_w, _p, id, _label)
        if not id then
          return
        end

        for _, s in ipairs(state.resolved) do
          if s.name == id then
            local was_enabled = apply.is_enabled(s, state.env)
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
            { Foreground = { AnsiColor = "Fuchsia" } },
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
      fuzzy = true,
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
---@return table[]
local function build_top_choices()
  return {
    {
      label = colored("Blue", nf("fa_list_ul", "*"), "Status"),
      id = "status",
    },
    {
      label = colored("Green", nf("fa_refresh", "*"), "Update All"),
      id = "update_all",
    },
    {
      label = colored("Red", nf("fa_trash", "*"), "Uninstall"),
      id = "uninstall",
    },
    {
      label = colored("Yellow", nf("fa_toggle_on", "*"), "Enable / Disable"),
      id = "toggle",
    },
    {
      label = colored("Fuchsia", nf("fa_folder_open", "*"), "Open Directory"),
      id = "open_dir",
    },
  }
end

---Open the top-level plugin manager UI.
---@param window table   WezTerm Window object
---@param pane table     WezTerm Pane object
---@param state table    internal nap state (resolved, env, lockfile_path, lock_data)
function M.open(window, pane, state)
  window:perform_action(
    act.InputSelector {
      title = "nap — Plugin Manager",
      description = "Select an action",
      fuzzy = true,
      choices = build_top_choices(),
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

return M
