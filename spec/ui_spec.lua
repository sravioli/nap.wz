describe("nap.ui", function()
  local ui, wez, apply

  before_each(function()
    reset_nap_modules()
    wez = require "wezterm"
    apply = require "nap.apply"
    ui = require "nap.ui"
  end)

  -- ── helpers for mock window/pane ──────────────────────────────

  local function mock_window()
    local w = { _actions = {} }
    function w:perform_action(action, pane)
      self._actions[#self._actions + 1] = { action = action, pane = pane }
    end
    return w
  end

  local function mock_pane()
    return { pane_id = 1 }
  end

  -- ── helper: build a typical nap state ─────────────────────────

  local function make_state(specs, nap_config_overrides)
    local nc = nap_config_overrides or {}
    return {
      nap_config = {
        ui = nc.ui or {},
        log_level = nc.log_level or "warn",
      },
      resolved = specs or {},
    }
  end

  -- ── open ──────────────────────────────────────────────────────

  describe("open", function()
    it("performs InputSelector action on window", function()
      local w = mock_window()
      local p = mock_pane()

      ui.open(w, p, make_state({}, {}))

      assert.equal(1, #w._actions)
      assert.equal("InputSelector", w._actions[1].action.type)
    end)

    it("includes all nine top-level choices", function()
      local w = mock_window()
      local p = mock_pane()

      ui.open(w, p, make_state({}, {}))

      local args = w._actions[1].action.args
      assert.equal(9, #args.choices)
      local ids = {}
      for _, c in ipairs(args.choices) do
        ids[#ids + 1] = c.id
      end
      assert.same({
        "status",
        "update_all",
        "update_one",
        "uninstall",
        "toggle",
        "open_dir",
        "clean",
        "snapshot",
        "restore",
      }, ids)
    end)

    it("sets title on InputSelector", function()
      local w = mock_window()
      local p = mock_pane()

      ui.open(w, p, make_state({}, {}))

      local args = w._actions[1].action.args
      assert.truthy(args.title:find "Plugin Manager")
    end)

    it("dispatches to show_status when callback receives 'status'", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state({
        {
          name = "test-plugin",
          _resolved_url = "https://example.com/test",
          enabled = true,
        },
      }, {})

      ui.open(w, p, state)

      -- Extract the action callback and invoke with id="status"
      local open_action = w._actions[1].action.args.action
      assert.equal("action_callback", open_action.type)

      -- Reset actions to capture the sub-action
      w._actions = {}
      open_action.fn(w, p, "status", "")

      -- show_status should have performed another InputSelector
      assert.equal(1, #w._actions)
      assert.truthy(w._actions[1].action.args.title:find "Status")
    end)

    it("dispatches to update_all and logs", function()
      local w = mock_window()
      local p = mock_pane()
      local u = require "nap.util"
      u.log.set_level "info"

      ui.open(w, p, make_state({}, {}))

      local open_action = w._actions[1].action.args.action
      open_action.fn(w, p, "update_all", "")

      -- update_all now goes through api.update_all which logs
      assert.truthy(#wez._logs.info > 0)
    end)

    it("does nothing when callback id is nil (Esc pressed)", function()
      local w = mock_window()
      local p = mock_pane()

      ui.open(w, p, make_state({}, {}))

      local open_action = w._actions[1].action.args.action
      w._actions = {}
      open_action.fn(w, p, nil, nil)

      -- No sub-action should be triggered
      assert.equal(0, #w._actions)
    end)
  end)

  -- ── show_status ───────────────────────────────────────────────

  describe("show_status", function()
    it("shows InputSelector with plugin entries", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "plugin-a", _resolved_url = "https://example.com/a", enabled = true },
        { name = "plugin-b", _resolved_url = "https://example.com/b", enabled = false },
      }

      ui.show_status(w, p, state)

      assert.equal(1, #w._actions)
      local args = w._actions[1].action.args
      assert.equal(2, #args.choices)
      assert.equal("plugin-a", args.choices[1].id)
      assert.equal("plugin-b", args.choices[2].id)
    end)

    it("skips import-only specs", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "real", _resolved_url = "https://example.com/a", enabled = true },
        { import = "some.module" },
      }

      ui.show_status(w, p, state)

      local args = w._actions[1].action.args
      assert.equal(1, #args.choices)
    end)

    it("logs info when no managed plugins", function()
      local w = mock_window()
      local p = mock_pane()

      -- Set log level to info so we can capture the message
      local u = require "nap.util"
      u.log.set_level "info"

      ui.show_status(w, p, make_state {})

      assert.equal(0, #w._actions)
      assert.truthy(#wez._logs.info > 0)
    end)

    it("respects fuzzy=false in ui config", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/p", enabled = true } },
        { ui = { fuzzy = false } }
      )

      ui.show_status(w, p, state)

      local args = w._actions[1].action.args
      assert.is_false(args.fuzzy)
    end)
  end)

  -- ── show_uninstall ────────────────────────────────────────────

  describe("show_uninstall", function()
    it("shows InputSelector with uninstallable plugins", function()
      local w = mock_window()
      local p = mock_pane()
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/tmp/a" },
      }
      local state = make_state {
        { name = "plugin-a", _resolved_url = "https://example.com/a", enabled = true },
      }

      ui.show_uninstall(w, p, state)

      assert.equal(1, #w._actions)
      local args = w._actions[1].action.args
      assert.equal(1, #args.choices)
    end)

    it("skips specs without _resolved_url", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "no-url", enabled = true },
        { name = "has-url", _resolved_url = "https://example.com/a", enabled = true },
      }

      ui.show_uninstall(w, p, state)

      local args = w._actions[1].action.args
      assert.equal(1, #args.choices)
      assert.equal("has-url", args.choices[1].id)
    end)

    it("logs info when no plugins to uninstall", function()
      local w = mock_window()
      local p = mock_pane()
      local u = require "nap.util"
      u.log.set_level "info"

      ui.show_uninstall(w, p, make_state {})

      assert.equal(0, #w._actions)
      assert.truthy(#wez._logs.info > 0)
    end)

    it("callback removes spec from state on successful delete", function()
      local w = mock_window()
      local p = mock_pane()
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/tmp/nonexistent_for_test" },
      }
      local state = make_state {
        { name = "plugin-a", _resolved_url = "https://example.com/a", enabled = true },
        { name = "plugin-b", _resolved_url = "https://example.com/b", enabled = true },
      }

      ui.show_uninstall(w, p, state)

      local cb = w._actions[1].action.args.action
      -- invoke the callback with the selected id
      cb.fn(w, p, "plugin-a", "")

      -- plugin-a should be removed from state.resolved
      assert.equal(1, #state.resolved)
      assert.equal("plugin-b", state.resolved[1].name)
    end)

    it("callback does nothing when id is nil", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "plugin-a", _resolved_url = "https://example.com/a", enabled = true },
      }

      ui.show_uninstall(w, p, state)

      local cb = w._actions[1].action.args.action
      cb.fn(w, p, nil, nil)

      -- nothing removed
      assert.equal(1, #state.resolved)
    end)

    it("callback warns when spec not found", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "actual", _resolved_url = "https://example.com/a", enabled = true },
      }

      ui.show_uninstall(w, p, state)

      local cb = w._actions[1].action.args.action
      cb.fn(w, p, "nonexistent", "")

      assert.truthy(#wez._logs.warn > 0)
      assert.truthy(wez._logs.warn[1]:find "cannot find spec")
    end)
  end)

  -- ── show_toggle ───────────────────────────────────────────────

  describe("show_toggle", function()
    it("shows InputSelector with toggle entries", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "p1", _resolved_url = "https://example.com/a", enabled = true },
        { name = "p2", _resolved_url = "https://example.com/b", enabled = false },
      }

      ui.show_toggle(w, p, state)

      assert.equal(1, #w._actions)
      local args = w._actions[1].action.args
      assert.equal(2, #args.choices)
    end)

    it("callback toggles enabled to false", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "p1", _resolved_url = "https://example.com/a", enabled = true },
      }

      -- set log level so we can capture the toggle log
      local u = require "nap.util"
      u.log.set_level "info"

      ui.show_toggle(w, p, state)

      local cb = w._actions[1].action.args.action
      cb.fn(w, p, "p1", "")

      assert.is_false(state.resolved[1].enabled)
      assert.truthy(#wez._logs.info > 0)
      assert.truthy(wez._logs.info[1]:find "disabled")
    end)

    it("callback toggles enabled to true", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "p1", _resolved_url = "https://example.com/a", enabled = false },
      }

      local u = require "nap.util"
      u.log.set_level "info"

      ui.show_toggle(w, p, state)

      local cb = w._actions[1].action.args.action
      cb.fn(w, p, "p1", "")

      assert.is_true(state.resolved[1].enabled)
      assert.truthy(wez._logs.info[1]:find "enabled")
    end)

    it("callback does nothing when id is nil", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "p1", _resolved_url = "https://example.com/a", enabled = true },
      }

      ui.show_toggle(w, p, state)

      local cb = w._actions[1].action.args.action
      cb.fn(w, p, nil, nil)

      -- nothing changed
      assert.is_true(state.resolved[1].enabled)
    end)

    it("logs info when no plugins to toggle", function()
      local w = mock_window()
      local p = mock_pane()
      local u = require "nap.util"
      u.log.set_level "info"

      ui.show_toggle(w, p, make_state {})

      assert.equal(0, #w._actions)
      assert.truthy(#wez._logs.info > 0)
    end)

    it("multiple toggles flip back and forth", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { name = "p1", _resolved_url = "https://example.com/a", enabled = true },
      }

      -- Toggle 1: true → false
      ui.show_toggle(w, p, state)
      local cb1 = w._actions[1].action.args.action
      cb1.fn(w, p, "p1", "")
      assert.is_false(state.resolved[1].enabled)

      -- Toggle 2: false → true
      w._actions = {}
      ui.show_toggle(w, p, state)
      local cb2 = w._actions[1].action.args.action
      cb2.fn(w, p, "p1", "")
      assert.is_true(state.resolved[1].enabled)
    end)
  end)

  -- ── show_open_dir ─────────────────────────────────────────────

  describe("show_open_dir", function()
    it("shows InputSelector with plugins that have dirs", function()
      local w = mock_window()
      local p = mock_pane()
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/plugins/a" },
      }
      local state = make_state {
        { name = "p1", _resolved_url = "https://example.com/a", enabled = true },
      }

      ui.show_open_dir(w, p, state)

      assert.equal(1, #w._actions)
      local args = w._actions[1].action.args
      assert.equal(1, #args.choices)
      -- label should include plugin_dir path
      assert.truthy(args.choices[1].label:find "/plugins/a")
    end)

    it("skips plugins without known plugin_dir", function()
      local w = mock_window()
      local p = mock_pane()
      wez._plugin_list = {} -- no dirs known
      local state = make_state {
        { name = "p1", _resolved_url = "https://example.com/a", enabled = true },
      }

      local u = require "nap.util"
      u.log.set_level "info"

      ui.show_open_dir(w, p, state)

      assert.equal(0, #w._actions)
      assert.truthy(#wez._logs.info > 0)
    end)

    it("callback spawns new tab in plugin dir", function()
      local w = mock_window()
      local p = mock_pane()
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/plugins/a" },
      }
      local state = make_state {
        { name = "p1", _resolved_url = "https://example.com/a", enabled = true },
      }

      ui.show_open_dir(w, p, state)

      local cb = w._actions[1].action.args.action
      w._actions = {}
      cb.fn(w, p, "p1", "")

      -- Should have performed SpawnCommandInNewTab via perform_action
      assert.equal(1, #w._actions)
    end)

    it("callback does nothing when id is nil", function()
      local w = mock_window()
      local p = mock_pane()
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/plugins/a" },
      }
      local state = make_state {
        { name = "p1", _resolved_url = "https://example.com/a", enabled = true },
      }

      ui.show_open_dir(w, p, state)

      local cb = w._actions[1].action.args.action
      w._actions = {}
      cb.fn(w, p, nil, nil)

      assert.equal(0, #w._actions)
    end)
  end)

  -- ── do_update_all ─────────────────────────────────────────────

  describe("do_update_all", function()
    it("delegates to api.update_all", function()
      local u = require "nap.util"
      u.log.set_level "info"
      ui.do_update_all({}, {}, make_state {})
      -- api.update_all iterates specs and logs "updated all plugins"
      assert.truthy(#wez._logs.info > 0)
    end)
  end)

  -- ── icon resolution ───────────────────────────────────────────

  describe("icon resolution via get_ui_config", function()
    -- We test icon resolution through show_status labels, which use
    -- get_ui_config internally.

    it("uses default nerdfonts icons when icons=true", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/p", enabled = true } },
        { ui = { icons = true } }
      )

      ui.show_status(w, p, state)

      local label = w._actions[1].action.args.choices[1].label
      -- Mock nerdfonts returns <key>, so look for default icon name
      assert.truthy(label:find "<cod_circle_filled>")
    end)

    it("uses empty strings when icons=false", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/p", enabled = true } },
        { ui = { icons = false } }
      )

      ui.show_status(w, p, state)

      local label = w._actions[1].action.args.choices[1].label
      -- Should NOT contain nerdfonts placeholders
      assert.is_nil(label:find "<cod_circle_filled>")
    end)

    it("merges user icon overrides with defaults", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/p", enabled = true } },
        { ui = { icons = { plugin_enabled = "YES" } } }
      )

      ui.show_status(w, p, state)

      local label = w._actions[1].action.args.choices[1].label
      -- User override is a raw string
      assert.truthy(label:find "YES")
    end)

    it("allows user-defined custom icon keys", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/p", enabled = true } },
        { ui = { icons = { custom_key = "CUSTOM" } } }
      )

      -- open uses build_top_choices which accesses icons but custom_key isn't
      -- one of the standard keys; just verify no error
      ui.open(w, p, state)

      assert.equal(1, #w._actions)
    end)
  end)

  -- ── colorscheme resolution ────────────────────────────────────

  describe("colorscheme resolution", function()
    it("uses config.colors when set", function()
      wez.config = {
        colors = { foreground = "#fff" },
      }

      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/p", enabled = true } },
        {}
      )

      -- Should not error; colorscheme is used internally
      ui.show_status(w, p, state)
      assert.equal(1, #w._actions)
    end)

    it("uses color_schemes lookup when color_scheme is set", function()
      wez.config = {
        color_scheme = "Custom",
        color_schemes = {
          Custom = { foreground = "#aaa" },
        },
      }

      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/p", enabled = true } },
        {}
      )

      ui.show_status(w, p, state)
      assert.equal(1, #w._actions)
    end)

    it("falls back to empty table when no colorscheme info", function()
      wez.config = {}

      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/p", enabled = true } },
        {}
      )

      ui.show_status(w, p, state)
      assert.equal(1, #w._actions)
    end)
  end)

  -- ── plugin_label formatting ───────────────────────────────────

  describe("plugin_label formatting", function()
    it("includes plugin name in label", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        {
          name = "my-plugin",
          _resolved_url = "https://example.com/my-plugin",
          enabled = true,
        },
      }

      ui.show_status(w, p, state)

      local label = w._actions[1].action.args.choices[1].label
      assert.truthy(label:find "my%-plugin")
    end)

    it("includes URL when show_url is true", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/path", enabled = true } },
        { ui = { show_url = true } }
      )

      ui.show_status(w, p, state)

      local label = w._actions[1].action.args.choices[1].label
      assert.truthy(label:find "https://example%.com/path")
    end)

    it("excludes URL when show_url is false", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "https://example.com/path", enabled = true } },
        { ui = { show_url = false } }
      )

      ui.show_status(w, p, state)

      local label = w._actions[1].action.args.choices[1].label
      assert.is_nil(label:find "https://example%.com/path")
    end)

    it("includes priority when show_priority is true", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "x", enabled = true, priority = 5 } },
        { ui = { show_priority = true } }
      )

      ui.show_status(w, p, state)

      local label = w._actions[1].action.args.choices[1].label
      assert.truthy(label:find "%[P:5%]")
    end)

    it("excludes priority when show_priority is false", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "x", enabled = true, priority = 5 } },
        { ui = { show_priority = false } }
      )

      ui.show_status(w, p, state)

      local label = w._actions[1].action.args.choices[1].label
      assert.is_nil(label:find "%[P:")
    end)

    it("shows <unnamed> when name is nil", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state {
        { _resolved_url = "https://example.com/p", enabled = true },
      }

      ui.show_status(w, p, state)

      local label = w._actions[1].action.args.choices[1].label
      assert.truthy(label:find "<unnamed>")
    end)
  end)

  -- ── InputSelector height ──────────────────────────────────────

  describe("InputSelector height", function()
    it("includes height when set in ui config", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "x", enabled = true } },
        { ui = { height = 20 } }
      )

      ui.show_status(w, p, state)

      local args = w._actions[1].action.args
      assert.equal(20, args.height)
    end)

    it("omits height when not set", function()
      local w = mock_window()
      local p = mock_pane()
      local state = make_state(
        { { name = "p", _resolved_url = "x", enabled = true } },
        { ui = {} }
      )

      ui.show_status(w, p, state)

      local args = w._actions[1].action.args
      assert.is_nil(args.height)
    end)
  end)
end)
