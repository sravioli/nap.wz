--- Test bootstrap: inject wezterm mock and set up package.path.
--- Referenced by .busted as `helper`.

-- Add the plugin directory to package.path so `require "nap.*"` works.
local sep = package.config:sub(1, 1)
local root = "plugin"
local pattern = root .. sep .. "?.lua"
if not package.path:find(pattern, 1, true) then
  package.path = pattern .. ";" .. root .. sep .. "?" .. sep .. "init.lua;" .. package.path
end

-- Add spec/support to path so mock_wezterm can be required.
local support = "spec" .. sep .. "support" .. sep .. "?.lua"
if not package.path:find(support, 1, true) then
  package.path = support .. ";" .. package.path
end

-- Inject the wezterm mock BEFORE any nap module loads.
package.loaded["wezterm"] = require "mock_wezterm"

--- Helper: unload all nap.* modules so each test file gets a fresh state.
--- Call this in before_each() when you need isolation.
local function reset_nap_modules()
  local to_remove = {}
  for name, _ in pairs(package.loaded) do
    if name:match "^nap%." then
      to_remove[#to_remove + 1] = name
    end
  end
  for _, name in ipairs(to_remove) do
    package.loaded[name] = nil
  end
  -- Reset wezterm mock state
  local wez = require "wezterm"
  wez._reset_logs()
  wez._plugin_list = {}
end

-- Expose as a global for test files.
_G.reset_nap_modules = reset_nap_modules
