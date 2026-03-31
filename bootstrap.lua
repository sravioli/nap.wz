--- nap.wz bootstrap file.
--- Copy this file to your WezTerm config directory as `nap.lua`, then use
--- `local nap = require "nap"` anywhere in your config.
---
--- WezTerm clones the plugin automatically on first load.
--- To update nap itself, run `wezterm.plugin.update_all()` from the Debug
--- Overlay (Ctrl+Shift+L).
return require("wezterm").plugin.require "https://github.com/sravioli/nap.wz"
