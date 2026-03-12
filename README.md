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
- **Merge & override** - re-declare a plugin by name to override options across modules
- **Split configs** - organize specs into importable Lua modules
- **Priority ordering** - control plugin execution order with `priority`
- **Conditional loading** - enable/disable plugins based on hostname, OS, etc.
- **Custom apply** - override how a plugin is applied with a `config` function
- **Dev mode** - swap between remote and local checkout with `dev = true`
- **Advisory lockfile** - snapshot installed plugin state for reproducibility
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

return nap.setup(wezterm.config_builder(), {
  spec = {
    -- GitHub shorthand
    { "owner/status-bar.wezterm", opts = { location = "right" } },

    -- Higher priority runs first
    { "owner/theme.wezterm", priority = 1000, opts = { theme = "dracula" } },

    -- Only on work machines
    { "owner/work-tools.wezterm",
      enabled = function(env) return env.hostname:match "work%-laptop" end,
    },
  },
  env = { hostname = wezterm.hostname() },
})
```

### Structured (Recommended)

Split your specs into modules for better organization:

**`~/.wezterm.lua`**

```lua
local wezterm = require "wezterm"
local nap = wezterm.plugin.require "https://github.com/sravioli/nap.wz"

return nap.setup(wezterm.config_builder(), {
  spec = {
    { import = "plugins.ui" },
    { import = "plugins.tools" },

    -- Local overrides still work here
    { "owner/status-bar.wezterm", opts = { theme = "catppuccin" } },
  },
  env = { hostname = wezterm.hostname() },
  lockfile = "nap-lock.lua",
})
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
    enabled = function(env) return env.hostname:match "work%-laptop" end,
  },
}
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
---@field enabled?     boolean|fun(env):boolean      -- enable/disable; function receives env table
---@field priority?    integer                       -- higher runs first (default: 0)
---@field dev?         boolean                       -- use dir as file:// URL instead of remote
---@field groups?      string[]                      -- optional tags for organization
---@field opts?        table                         -- passed to plugin.apply_to_config(config, opts)
---@field config?      fun(plugin, config, opts)     -- custom apply; replaces default apply_to_config
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
  enabled = function(env)
    return env.hostname:match "work%-laptop"
  end,
}
```

The `env` table is whatever you pass in `setup()`:

```lua
env = {
  hostname = wezterm.hostname(),
  os = wezterm.target_triple,
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
- **Scalar fields** (`url`, `dev`, `dir`, `enabled`, `priority`, `config`) - later overrides earlier

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

nap supports an optional advisory lockfile to snapshot your plugin state:

```lua
nap.setup(config, {
  spec = { ... },
  lockfile = "nap-lock.lua",
})
```

### Helpers

| Method | Description |
|---|---|
| `nap.write_lockfile(path?)` | Write current plugin state to the lockfile |
| `nap.read_lockfile(path?)` | Read and return lockfile contents |
| `nap.update_all_and_lock()` | Run `wezterm.plugin.update_all()` then rewrite the lockfile |
| `nap.status()` | Return resolved specs, env, and lock data for debugging |

The lockfile is **advisory only** - it records plugin URLs and directories for
visibility and reproducibility but does not enforce specific commits. Strict
pinning may be added in a future version.

## Full API

### `nap.setup(config, opts)` → `config`

The main entry point. Declares specs, resolves imports, merges, and applies all
enabled plugins to the config.

| Option | Type | Description |
|---|---|---|
| `spec` | `WezPluginSpec[]` | List of plugin specs and/or imports |
| `defaults` | `table?` | Default `enabled` and `priority` for all specs |
| `env` | `table?` | Environment info passed to `enabled` functions |
| `lockfile` | `string?` | Path to advisory lockfile (relative to config dir) |

Returns the mutated config.

### `nap.apply_to_config(config, opts)` → `config`

Alias for `setup()`. Allows nap.wz to be used like any other WezTerm plugin.

### `nap.status()` → `table`

Returns `{ specs, env, lock_data }` for debugging.

### `nap.write_lockfile(path?)`

Writes the current plugin state to disk.

### `nap.read_lockfile(path?)` → `table|nil`

Reads and returns the lockfile contents.

### `nap.update_all_and_lock()`

Updates all plugins via WezTerm's native mechanism and rewrites the lockfile.

### `nap.action()` → `action`

Returns a WezTerm action that opens the nap plugin manager UI (see
[Plugin Manager UI](#plugin-manager-ui) below). Bind it to any key:

```lua
config.keys = {
  { key = "p", mods = "LEADER", action = nap.action() },
}
```

## Plugin Manager UI

nap includes a built-in management interface powered by WezTerm's
`InputSelector`. Open it by binding `nap.action()` to a key:

```lua
local wezterm = require "wezterm"
local nap = wezterm.plugin.require "https://github.com/sravioli/nap.wz"

local config = wezterm.config_builder()
nap.setup(config, { spec = { ... } })

config.keys = {
  { key = "p", mods = "LEADER", action = nap.action() },
}

return config
```

The first selector presents the available operations:

| Operation | Description |
|---|---|
| **Status** | List all managed plugins with name, URL, priority, and enabled state |
| **Update All** | Run `wezterm.plugin.update_all()` and rewrite the lockfile |
| **Uninstall** | Pick a plugin to delete from disk and remove from the lockfile |
| **Enable / Disable** | Toggle a plugin at runtime (does not persist across restarts) |
| **Open Directory** | Open a plugin's clone directory in a new terminal tab |

Selecting an operation that targets a specific plugin opens a second selector
listing the applicable plugins.

> **Note:** Enable/Disable changes are runtime-only. To permanently
> disable a plugin, set `enabled = false` in your spec.

## Pipeline

When `setup()` is called, nap runs this pipeline:

1. **Expand imports** - splice imported module specs into the list
2. **Normalize** - resolve URLs, derive names, apply defaults
3. **Validate** - warn about specs with no resolvable URL
4. **Merge** - combine specs sharing the same `name`
5. **Sort** - order by descending `priority`, then declaration order
6. **Apply** - `wezterm.plugin.require()` each plugin and call `apply_to_config`

Failures at any step are logged and skipped - nap never aborts your config.

## URL Resolution

nap resolves plugin URLs with the following precedence:

| Condition | URL |
|---|---|
| `dev = true` and `dir` set | `file://` from `dir` |
| `url` set | `url` as-is |
| `"owner/repo"` shorthand | `https://github.com/owner/repo` |
| `dir` set | `file://` from `dir` |

## Non-Goals (v1)

nap is intentionally simpler than lazy.nvim:

- **No lazy loading** - no `event`, `ft`, `cmd`, `keys` equivalents
- **No dependency graph** - ordering is via `priority` only
- **No recursive imports** - imports are top-level only
- **No strict lockfile enforcement** - advisory snapshots only
- **No lifecycle hooks** - just `apply_to_config` (or `config` function)

## Acknowledgements

nap.wz is heavily inspired by [**lazy.nvim**](https://github.com/folke/lazy.nvim)
by [Folke Lemaitre](https://github.com/folke). The declarative plugin spec
format, merge-by-name semantics, import system, and `"owner/repo"` shorthand
are all direct tributes to lazy.nvim's brilliant design. Thank you, Folke, for
setting the standard for plugin management ergonomics.

## License

Code: [GPL-2.0](LICENSE) · Documentation: [CC BY-NC 4.0](LICENSE-DOCS)
