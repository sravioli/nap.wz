<div align="center">

# nap.wz

A **lazy.nvim-inspired plugin manager for [WezTerm]**, simple by design.

Declare your plugins. nap handles the rest.

[WezTerm]: https://wezterm.org

</div>

---

## Features

- **Declarative specs** - `"owner/repo"` shorthand, just like lazy.nvim
- **GitHub by default** - `"owner/repo"` auto-expands to `https://github.com/owner/repo`
- **Version pinning** - lock plugins to a `branch`, `tag`, or `commit`
- **Dependencies** - declare per-plugin dependencies with automatic ordering and cycle detection
- **Merge & override** - re-declare a plugin by name to override options across modules
- **Split configs** - organize specs into importable Lua modules
- **Priority ordering** - control plugin execution order with `priority`
- **Conditional loading** - enable/disable plugins based on hostname, OS, etc.
- **Custom apply** - override how a plugin is applied with a `config` function
- **Dev mode** - swap between remote and local checkout with `dev = true`
- **Lockfile** - snapshot and restore exact plugin commits for reproducibility
- **Orphan cleanup** - detect and remove plugins installed on disk but not declared
- **Per-plugin updates** - update individual plugins via git fetch + merge/checkout
- **Zero bootstrap** - ships as a native WezTerm plugin, no custom git logic
- **Plugin Manager UI** - `InputSelector`-based interface for status, update, uninstall, and more

## Installation

nap.wz is installed through WezTerm's built-in plugin system. No external
tooling required.

```lua
local wezterm = require "wezterm"
local nap = wezterm.plugin.require "https://github.com/sravioli/nap.wz"
```

That's it. WezTerm clones the repo on first load. To update nap itself, run
`wezterm.plugin.update_all()` from the [Debug Overlay] (default:
<kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>L</kbd>).

[Debug Overlay]: https://wezterm.org/troubleshooting.html#debug-overlay

## Quick Start

### Single File

The simplest setup - everything in your `~/.wezterm.lua`:

```lua
local wezterm = require "wezterm"
local nap = wezterm.plugin.require "https://github.com/sravioli/nap.wz"

return nap.setup(
  wezterm.config_builder(),
  {
    -- GitHub shorthand
    { "owner/status-bar.wezterm", opts = { location = "right" } },

    -- Higher priority runs first
    { "owner/theme.wezterm", priority = 1000, opts = { theme = "dracula" } },

    -- Pin to a specific tag
    { "owner/stable-plugin.wezterm", tag = "v2.1.0" },

    -- Only on work machines
    { "owner/work-tools.wezterm",
      enabled = function() return wezterm.hostname():match "work%-laptop" end,
    },
  },
  {
    lockfile = "nap-lock.lua",
    integrations = { input_selector = true, command_palette = false },
  }
)
```

### Structured (Recommended)

Split your specs into modules for better organization:

**`~/.wezterm.lua`**

```lua
local wezterm = require "wezterm"
local nap = wezterm.plugin.require "https://github.com/sravioli/nap.wz"

return nap.setup(
  wezterm.config_builder(),
  {
    { import = "plugins.ui" },
    { import = "plugins.tools" },

    -- Local overrides still work here
    { "owner/status-bar.wezterm", opts = { theme = "catppuccin" } },
  },
  {
    lockfile = "nap-lock.lua",
    integrations = { input_selector = true, command_palette = false },
    ui = { fuzzy = true, icons = true },
  }
)
```

**`~/.config/wezterm/plugins/ui.lua`**

```lua
return {
  { "owner/status-bar.wezterm", priority = 900, opts = { location = "right" } },
  { "owner/tab-style.wezterm", opts = { fancy = true } },
}
```

**`~/.config/wezterm/plugins/tools.lua`**

```lua
return {
  { "owner/session-manager.wezterm" },
  { "company/work-tools.wezterm",
    enabled = function() return wezterm.hostname():match "work%-laptop" end,
  },
}
```

### With Update Checks and Command Palette

Enable update checking and command palette integration:

```lua
local wezterm = require "wezterm"
local nap = wezterm.plugin.require "https://github.com/sravioli/nap.wz"

return nap.setup(
  wezterm.config_builder(),
  { "owner/plugin.wezterm" },
  {
    lockfile = "nap-lock.lua",
    updates = {
      enabled = true,
      interval_hours = 24,
      timeout_ms = 5000,
    },
    integrations = {
      input_selector = true,
      command_palette = true,
    },
    keymaps = {
      toggle_input = { mods = "CTRL|SHIFT", key = "m" },
    },
  }
)
```

## Plugin Spec

Each entry in `spec` is a table describing a plugin:

```lua
---@class WezPluginSpec
---@field [1]?         string                       -- "owner/repo" shorthand
---@field name?        string                       -- merge key (derived from URL if omitted)
---@field url?         string                       -- explicit full URL; overrides shorthand
---@field dir?         string                       -- local path (expands ~ and converts to file://)
---@field import?      string                       -- module name to require and splice specs from
---@field enabled?     boolean|fun():boolean         -- enable/disable; function evaluated at setup
---@field priority?    integer                       -- higher runs first (default: 0)
---@field dev?         boolean                       -- use dir as file:// URL instead of remote
---@field groups?      string[]                      -- optional tags for organization
---@field opts?        table                         -- passed to plugin.apply_to_config(config, opts)
---@field config?      fun(plugin, config, opts)     -- custom apply; replaces default apply_to_config
---@field branch?      string                       -- git branch to pin (mutually exclusive with tag/commit)
---@field tag?         string                       -- git tag to pin (mutually exclusive with branch/commit)
---@field commit?      string                       -- git commit SHA to pin (mutually exclusive with branch/tag)
---@field dependencies? table                       -- list of dependency specs
```

### Shorthand

The first positional element is the GitHub shorthand:

```lua
{ "owner/repo" }
-- expands to: https://github.com/owner/repo
```

### Explicit URL

Override the default GitHub host per plugin:

```lua
{ url = "https://gitlab.com/owner/repo.git" }
{ url = "git@github.com:owner/private-plugin.git" }
```

### Local Plugins

Point to a local checkout:

```lua
{ dir = "~/projects/my-plugin.wezterm" }
```

### Dev Mode

Switch between remote and local during development:

```lua
{ "owner/my-plugin", dev = true, dir = "~/projects/my-plugin" }
-- Uses file:// URL from dir when dev = true
-- Uses https://github.com/owner/my-plugin when dev = false or omitted
```

### Version Pinning

Lock a plugin to a specific branch, tag, or commit. Only one may be set:

```lua
-- Pin to a branch
{ "owner/theme.wezterm", branch = "v2" }

-- Pin to a tag
{ "owner/status-bar.wezterm", tag = "v1.3.0" }

-- Pin to an exact commit
{ "owner/session-manager.wezterm", commit = "a1b2c3d" }
```

After `wezterm.plugin.require()` clones the repo, nap runs
`git checkout <ref>` and reloads the plugin from the pinned state.

### Dependencies

Declare per-plugin dependencies. Dependencies are injected before their parent
in the spec list and inherit a priority one higher than the parent:

```lua
{
  "owner/fancy-bar.wezterm",
  dependencies = {
    { "owner/bar-utils.wezterm" },
    { "owner/icon-pack.wezterm", priority = 2000 },
  },
}
```

Cycle detection prevents circular dependency chains. Self-references are also
caught.

### Custom Config Function

Override how a plugin is applied:

```lua
{
  "owner/theme.wezterm",
  config = function(plugin, config, opts)
    plugin.apply_to_config(config, opts)
    config.color_scheme = "Catppuccin Mocha"
  end,
}
```

When `config` is provided, nap calls it instead of the plugin's
`apply_to_config`. The function receives the loaded plugin module, the WezTerm
config builder, and the resolved `opts` table.

### Conditional Plugins

```lua
{
  "owner/work-tools.wezterm",
  enabled = function()
    return wezterm.hostname():match "work%-laptop"
  end,
}
```

### Priority

Higher priority plugins are applied first:

```lua
{ "owner/base-theme", priority = 1000 }  -- applied first
{ "owner/status-bar", priority = 500 }   -- applied second
{ "owner/tweaks" }                        -- priority 0 (default), applied last
```

Plugins with the same priority are applied in declaration order.

## Merging & Overrides

When multiple specs share the same `name`, nap merges them:

- **`opts`** - deep-merged (later values override)
- **`groups`** - concatenated and deduped
- **Scalar fields** (`url`, `dev`, `dir`, `enabled`, `priority`, `config`, `branch`, `tag`, `commit`, `dependencies`) - later overrides earlier

This lets you import a plugin pack and override individual settings:

```lua
-- Imported from a shared module:
{ "owner/status-bar", opts = { theme = "dracula", location = "right" } }

-- Your local override:
{ "owner/status-bar", opts = { theme = "catppuccin" } }

-- Result after merge:
-- opts = { theme = "catppuccin", location = "right" }
```

## Imports

Use `{ import = "module.name" }` to load specs from another Lua module:

```lua
spec = {
  { import = "plugins.ui" },
  { import = "plugins.tools" },
}
```

The imported module must return a list of `WezPluginSpec` tables:

```lua
-- plugins/ui.lua
return {
  { "owner/status-bar.wezterm", priority = 900 },
  { "owner/tab-style.wezterm" },
}
```

> **Note:** Nested imports (an imported module containing further `{ import }`
> entries) are not supported in v1. They will be skipped with a warning.

## Lockfile

nap supports a lockfile to snapshot and restore exact plugin commits:

```lua
nap.setup(config, { ... }, {
  lockfile = "nap-lock.lua",
})
```

### Snapshot

`nap.snapshot()` records the current commit SHA and branch for every resolved
plugin and writes a Lua file to the configured `lockfile` path:

```lua
-- nap-lock.lua (generated)
return {
  ["owner/status-bar"] = {
    url = "https://github.com/owner/status-bar.wezterm",
    commit = "a1b2c3d4e5f6...",
    branch = "main",
  },
}
```

### Restore

`nap.restore()` reads the lockfile and checks out each plugin to the recorded
commit via `git fetch` + `git checkout`. Plugins missing from the lockfile or
without a matching spec are skipped.

### Helpers

| Method                | Description                                             |
| --------------------- | ------------------------------------------------------- |
| `nap.snapshot(path?)` | Write current commit SHAs to the lockfile               |
| `nap.restore(path?)`  | Restore plugins to the commits recorded in the lockfile |

## Full API

### `nap.setup(config, specs, nap_opts?)` → `config`

The main entry point. Declares specs, resolves imports, expands dependencies,
merges, and applies all enabled plugins to the config.

| Parameter  | Type              | Description                                     |
| ---------- | ----------------- | ----------------------------------------------- |
| `config`   | `table`           | WezTerm config builder                          |
| `specs`    | `WezPluginSpec[]` | List of plugin specs and/or imports             |
| `nap_opts` | `table?`          | nap configuration (lockfile, updates, UI, etc.) |

Returns the mutated config.

### `nap.apply_to_config(config, opts?)` → `config`

WezTerm plugin protocol compatibility wrapper. Delegates to `setup()` with
empty specs and the provided opts.

### `nap.status()` → `table`

Returns `{ specs, nap_config }` for debugging.

### `nap.update_all()`

Updates every declared plugin individually via `git fetch` +
`git merge --ff-only` (or `git checkout <ref>` for pinned plugins).

### `nap.update_one(name)` → `boolean, string?`

Updates a single plugin by name. Returns `(ok, err)`.

### `nap.clean()` → `table[]`

Detects orphan plugins installed on disk but not in your specs. Returns a list
of `{ url, plugin_dir, name }`. Excludes nap.wz itself.

### `nap.snapshot(path?)` → `boolean, string?`

Captures the current commit SHA and branch for every resolved plugin and writes
to the lockfile. Uses `nap_opts.lockfile` as the default path.

### `nap.restore(path?)` → `table?`

Reads the lockfile and restores each plugin to its recorded commit via
`git fetch` + `git checkout`. Returns per-plugin results `{ [name] = { ok, from_sha?, to_sha? } }`.

### `nap.action()` → `action`

Returns a WezTerm action that opens the nap plugin manager UI (see
[Plugin Manager UI](#plugin-manager-ui) below). Bind it to any key:

```lua
config.keys = {
  { key = "p", mods = "LEADER", action = nap.action() },
}
```

### Action Factories

Each operation is also available as a standalone action:

| Factory                   | Description                     |
| ------------------------- | ------------------------------- |
| `nap.action()`            | Open the full plugin manager UI |
| `nap.action_status()`     | Show plugin status              |
| `nap.action_update_all()` | Update all plugins              |
| `nap.action_update_one()` | Per-plugin update picker        |
| `nap.action_uninstall()`  | Plugin uninstall picker         |
| `nap.action_toggle()`     | Enable/disable picker           |
| `nap.action_open_dir()`   | Open plugin directory picker    |
| `nap.action_clean()`      | Orphan cleanup picker           |
| `nap.action_snapshot()`   | Take a lockfile snapshot        |
| `nap.action_restore()`    | Restore from lockfile           |

## Plugin Manager UI

nap includes a built-in management interface powered by WezTerm's
`InputSelector`. Open it by binding `nap.action()` to a key:

```lua
local wezterm = require "wezterm"
local nap = wezterm.plugin.require "https://github.com/sravioli/nap.wz"

local config = wezterm.config_builder()
nap.setup(config, { "owner/plugin.wezterm" })

config.keys = {
  { key = "p", mods = "LEADER", action = nap.action() },
}

return config
```

The first selector presents the available operations:

| Operation             | Description                                                          |
| --------------------- | -------------------------------------------------------------------- |
| **Status**            | List all managed plugins with name, URL, priority, and enabled state |
| **Update All**        | Fetch and update every declared plugin                               |
| **Update Plugin**     | Pick a single plugin to update                                       |
| **Uninstall**         | Pick a plugin to delete from disk                                    |
| **Enable / Disable**  | Toggle a plugin at runtime (does not persist across restarts)        |
| **Open Directory**    | Open a plugin's clone directory in a new terminal tab                |
| **Clean Orphans**     | Detect and remove plugins installed on disk but not declared         |
| **Snapshot Lockfile** | Save current commit SHAs to the lockfile                             |
| **Restore Lockfile**  | Restore plugins to the commits recorded in the lockfile              |

Selecting an operation that targets a specific plugin opens a second selector
listing the applicable plugins.

> **Note:** Enable/Disable changes are runtime-only. To permanently
> disable a plugin, set `enabled = false` in your spec.

## Events

nap emits WezTerm events for plugin update checks and other lifecycle events.
You can consume these events in your WezTerm config to build custom UI (like
status bar badges) or trigger actions.

### Update Check Events

When update checks are enabled, nap emits the following events:

#### `nap-updates-checked`

Emitted when an update check completes (with or without updates available).

**Payload:**

```lua
{
  check_time = os.time(),           -- Unix timestamp of check
  update_count = 2,                 -- Number of plugins with updates
  plugins = {"plugin1", "plugin2"}, -- List of plugin names with updates
}
```

#### `nap-updates-available`

Emitted only if updates are found (subset of `nap-updates-checked`).

**Payload:** Same as `nap-updates-checked`

### Example: Status Bar Badge

Display an indicator in your WezTerm status bar showing available updates:

```lua
local wezterm = require "wezterm"

wezterm.on("nap-updates-available", function(window, pane, payload)
  window:set_right_status(
    wezterm.format {
      { Foreground = { AnsiColor = "Yellow" } },
      { Text = " ◆ " .. payload.update_count .. " updates" },
    }
  )
end)
```

### Example: Custom Reaction

Trigger other actions when updates are available:

```lua
local wezterm = require "wezterm"

wezterm.on("nap-updates-available", function(window, pane, payload)
  -- Log available updates
  wezterm.log_info(
    "Updates available for: " .. table.concat(payload.plugins, ", ")
  )

  -- Optionally, show a notification or other custom behavior
end)
```

## Pipeline

When `setup()` is called, nap runs this pipeline:

1. **Expand imports** - splice imported module specs into the list
2. **Expand dependencies** - inject dependency specs with cycle detection
3. **Normalize** - resolve URLs, derive names, apply defaults
4. **Validate** - warn about specs with no resolvable URL; check pin mutual exclusivity
5. **Merge** - combine specs sharing the same `name`
6. **Sort** - order by descending `priority`, then declaration order
7. **Apply** - `wezterm.plugin.require()` each plugin, pin version if specified, and call `apply_to_config`

Failures at any step are logged and skipped - nap never aborts your config.

## URL Resolution

nap resolves plugin URLs with the following precedence:

| Condition                  | URL                             |
| -------------------------- | ------------------------------- |
| `dev = true` and `dir` set | `file://` from `dir`            |
| `url` set                  | `url` as-is                     |
| `"owner/repo"` shorthand   | `https://github.com/owner/repo` |
| `dir` set                  | `file://` from `dir`            |

## Migration Guide

### From Old API to New API

If you're using an older version of nap.wz, here's how to migrate to the new
`setup(config, specs, nap_opts)` signature:

**Before (Old API):**

```lua
return nap.setup(wezterm.config_builder(), {
  spec = { ... plugins ... },
  env = { hostname = wezterm.hostname() },
  lockfile = "nap-lock.lua",
})
```

**After (New API):**

```lua
return nap.setup(
  wezterm.config_builder(),
  { ... plugins ... },                    -- specs as second argument
  {
    lockfile = "nap-lock.lua",
    integrations = { input_selector = true, command_palette = false },
    ui = { fuzzy = true, icons = true },
  }
)
```

### Key Changes

1. **Specs as second argument**: Plugin specs are now the second parameter, not nested in
   `spec = { ... }`.

2. **No `env` parameter**: Plugins access `wezterm` directly in callbacks:

   ```lua
   enabled = function() return wezterm.hostname():match "work%" end
   ```

3. **Configuration in third parameter**: `lockfile`, `integrations`, `keymaps`, `updates`,
   and `ui` settings now go in `nap_opts` (the third parameter).

4. **Lockfile shorthand**: You can pass `lockfile` as a string directly:

   ```lua
   nap.setup(config, specs, { lockfile = "nap-lock.lua" })
   ```

## Non-Goals (v1)

nap is intentionally simpler than lazy.nvim:

- **No lazy loading** - no `event`, `ft`, `cmd`, `keys` equivalents
- **No recursive imports** - imports are top-level only
- **No lifecycle hooks** - just `apply_to_config` (or `config` function)

## Acknowledgements

nap.wz is heavily inspired by [**lazy.nvim**](https://github.com/folke/lazy.nvim)
by [Folke Lemaitre](https://github.com/folke). The declarative plugin spec
format, merge-by-name semantics, import system, and `"owner/repo"` shorthand
are all direct tributes to lazy.nvim's brilliant design. Thank you, Folke, for
setting the standard for plugin management ergonomics.

## License

Code: [GPL-2.0](LICENSE) · Documentation: [CC BY-NC 4.0](LICENSE-DOCS)
