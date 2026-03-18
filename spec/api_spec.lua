describe("nap.api", function()
  local api, wez

  before_each(function()
    reset_nap_modules()
    wez = require "wezterm"
    api = require "nap.api"
  end)

  -- ── setup ─────────────────────────────────────────────────────

  describe("setup", function()
    it("returns the config object", function()
      local config = {}
      local result = api.setup(config, {}, {})
      assert.equal(config, result)
    end)

    it("defaults specs to empty table when nil", function()
      local config = {}
      local result = api.setup(config, nil, {})
      assert.equal(config, result)
    end)

    it("defaults nap_opts to empty table when nil", function()
      local config = {}
      local result = api.setup(config, {}, nil)
      assert.equal(config, result)
    end)

    it("applies plugins via apply_to_config", function()
      local called = false
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            called = true
          end,
        }
      end

      api.setup({}, {
        { "owner/test-plugin" },
      }, { log_level = "info" })

      assert.is_true(called)
    end)

    it("normalizes and merges duplicate specs", function()
      local call_count = 0
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            call_count = call_count + 1
          end,
        }
      end

      api.setup({}, {
        { "owner/plugin", priority = 5 },
        { "owner/plugin", opts = { a = 1 } },
      }, { log_level = "info" })

      -- merged into single spec, so only 1 apply call
      assert.equal(1, call_count)
    end)

    it("expands import specs", function()
      package.loaded["test_api_import"] = {
        { "imported/other-plugin" },
      }
      local called_urls = {}
      wez.plugin.require = function(url)
        called_urls[#called_urls + 1] = url
        return { apply_to_config = function() end }
      end

      api.setup({}, {
        { "direct/plugin" },
        { import = "test_api_import" },
      }, { log_level = "info" })

      assert.equal(2, #called_urls)
      package.loaded["test_api_import"] = nil
    end)

    it("validates specs and logs warnings for invalid ones", function()
      api.setup({}, {
        {}, -- no URL, no shorthand
      }, {})

      assert.truthy(#wez._logs.warn > 0)
    end)

    it("stores state accessible via _get_state", function()
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end

      api.setup({}, {
        { "owner/test-plugin" },
      }, { log_level = "info" })

      local state = api._get_state()
      assert.is_table(state.resolved)
      assert.is_table(state.nap_config)
      assert.equal(1, #state.resolved)
      assert.equal("info", state.nap_config.log_level)
    end)

    it("sets log level from nap_opts", function()
      api.setup({}, {}, { log_level = "info" })
      local u = require "nap.util"
      -- info messages should now be visible
      u.log.info "test message after setup"
      assert.equal(1, #wez._logs.info)
    end)

    it("registers command palette when enabled", function()
      local registered_events = {}
      wez.on = function(event_name, cb)
        registered_events[event_name] = cb
      end

      api.setup({}, {}, {
        integrations = { command_palette = true },
      })

      assert.is_function(registered_events["augment-command-palette"])
    end)

    it("does not register command palette when disabled", function()
      local registered_events = {}
      wez.on = function(event_name, cb)
        registered_events[event_name] = cb
      end

      api.setup({}, {}, {
        integrations = { command_palette = false },
      })

      assert.is_nil(registered_events["augment-command-palette"])
    end)

    it("command palette callback returns action entries", function()
      local palette_cb
      wez.on = function(event_name, cb)
        if event_name == "augment-command-palette" then
          palette_cb = cb
        end
      end

      api.setup({}, {}, {
        integrations = { command_palette = true },
      })

      local entries = palette_cb({}, {})
      assert.is_table(entries)
      assert.equal(9, #entries)
      assert.truthy(entries[1].brief:find "Plugin Manager")
      assert.truthy(entries[2].brief:find "Status")
      assert.truthy(entries[3].brief:find "Update All")
    end)

    it("threads dev config into spec normalization", function()
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end

      api.setup({}, {
        { "sravioli/my-plugin", dev = true },
      }, {
        dev = {
          path = "/home/dev/projects",
          patterns = { "sravioli" },
        },
        log_level = "info",
      })

      local state = api._get_state()
      assert.is_table(state.resolved)
      assert.equal(1, #state.resolved)
      -- URL should be resolved via dev pattern
      local url = state.resolved[1]._resolved_url
      assert.truthy(url:find "file://")
      assert.truthy(url:find "my%-plugin")
    end)

    it("handles empty specs list gracefully", function()
      local config = {}
      local result = api.setup(config, {}, {})
      assert.equal(config, result)
      local state = api._get_state()
      assert.same({}, state.resolved)
    end)

    it("schedules update checks when enabled", function()
      local bg_called = false
      wez.background_task = function(fn)
        bg_called = true
        fn()
      end

      api.setup({}, {
        { "owner/plugin" },
      }, {
        updates = { enabled = true },
        log_level = "info",
      })

      assert.is_true(bg_called)
    end)
  end)

  -- ── apply_to_config ───────────────────────────────────────────

  describe("apply_to_config", function()
    it("delegates to setup with empty specs", function()
      local config = {}
      local result = api.apply_to_config(config, { log_level = "error" })
      assert.equal(config, result)
      local state = api._get_state()
      assert.equal("error", state.nap_config.log_level)
    end)

    it("defaults opts to empty when nil", function()
      local config = {}
      local result = api.apply_to_config(config)
      assert.equal(config, result)
    end)
  end)

  -- ── status ────────────────────────────────────────────────────

  describe("status", function()
    it("returns specs and nap_config", function()
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end

      api.setup({}, {
        { "owner/test" },
      }, { log_level = "info" })

      local status = api.status()
      assert.is_table(status.specs)
      assert.is_table(status.nap_config)
      assert.equal(1, #status.specs)
    end)

    it("returns empty before setup is called", function()
      local status = api.status()
      assert.same({}, status.specs)
      assert.same({}, status.nap_config)
    end)
  end)

  -- ── update_all ────────────────────────────────────────────────

  describe("update_all", function()
    it("calls updates.update_plugin for each resolved spec", function()
      -- set up state with resolved specs
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end
      wez._plugin_list = {
        { url = "https://github.com/owner/a", plugin_dir = "/plugins/a" },
        { url = "https://github.com/owner/b", plugin_dir = "/plugins/b" },
      }
      api.setup({}, {
        { "owner/a", url = "https://github.com/owner/a" },
        { "owner/b", url = "https://github.com/owner/b" },
      })

      -- Track run_child_process calls (git operations)
      local git_calls = {}
      wez.run_child_process = function(cmd)
        git_calls[#git_calls + 1] = table.concat(cmd, " ")
        return true, "", ""
      end

      api.update_all()
      -- Should have made git calls for each plugin
      assert.is_true(#git_calls > 0)
    end)
  end)

  -- ── _get_state ────────────────────────────────────────────────

  describe("_get_state", function()
    it("returns state table with resolved and nap_config", function()
      local state = api._get_state()
      assert.is_table(state)
      assert.is_table(state.resolved)
      assert.is_table(state.nap_config)
    end)
  end)

  -- ── action helpers ────────────────────────────────────────────

  describe("action", function()
    it("returns an action_callback when UI loads", function()
      local result = api.action()
      assert.is_table(result)
      assert.equal("action_callback", result.type)
    end)

    it("returns Nop when UI fails to load", function()
      -- Break the UI module require
      package.loaded["nap.ui"] = nil
      package.preload["nap.ui"] = function()
        error "UI broken"
      end

      -- Force re-evaluation of _ui by reloading api
      reset_nap_modules()
      api = require "nap.api"

      local result = api.action()
      assert.equal("Nop", result.type)
      assert.truthy(#wez._logs.error > 0)

      package.preload["nap.ui"] = nil
    end)
  end)

  describe("action_status", function()
    it("returns an action_callback", function()
      local result = api.action_status()
      assert.equal("action_callback", result.type)
    end)
  end)

  describe("action_update_all", function()
    it("returns an action_callback", function()
      local result = api.action_update_all()
      assert.equal("action_callback", result.type)
    end)

    it("calls update_all when invoked", function()
      -- update_all now iterates resolved specs, not wezterm.plugin.update_all
      local u = require "nap.util"
      u.log.set_level "info"
      local action = api.action_update_all()
      -- invoke the callback — should not error even with empty state
      action.fn({}, {})
      -- Verify it logged
      assert.truthy(#wez._logs.info > 0)
    end)
  end)

  describe("action_uninstall", function()
    it("returns an action_callback", function()
      local result = api.action_uninstall()
      assert.equal("action_callback", result.type)
    end)
  end)

  describe("action_toggle", function()
    it("returns an action_callback", function()
      local result = api.action_toggle()
      assert.equal("action_callback", result.type)
    end)
  end)

  describe("action_open_dir", function()
    it("returns an action_callback", function()
      local result = api.action_open_dir()
      assert.equal("action_callback", result.type)
    end)
  end)

  -- ── lazy UI loading ───────────────────────────────────────────

  describe("lazy UI loading", function()
    it("caches the UI module after first load", function()
      local load_count = 0
      local fake_ui = {
        open = function() end,
        show_status = function() end,
        show_uninstall = function() end,
        show_toggle = function() end,
        show_open_dir = function() end,
      }
      package.preload["nap.ui"] = function()
        load_count = load_count + 1
        return fake_ui
      end

      reset_nap_modules()
      api = require "nap.api"

      -- First action triggers load
      api.action()
      assert.equal(1, load_count)

      -- Second action reuses cache
      api.action()
      assert.equal(1, load_count)

      package.preload["nap.ui"] = nil
    end)
  end)

  -- ── end-to-end pipeline ───────────────────────────────────────

  describe("end-to-end pipeline", function()
    it("import → normalize → validate → merge → apply → updates", function()
      -- Set up imported module
      package.loaded["e2e_mod"] = {
        { "imported/other-plugin", opts = { x = 1 } },
      }

      local applied_plugins = {}
      wez.plugin.require = function(url)
        return {
          apply_to_config = function(config, opts)
            applied_plugins[#applied_plugins + 1] = {
              url = url,
              opts = opts,
            }
          end,
        }
      end

      local emitted_events = {}
      wez.emit = function(event, payload)
        emitted_events[event] = payload
      end

      local config = {}
      api.setup(config, {
        { "direct/plugin", priority = 10, opts = { a = 1 } },
        { import = "e2e_mod" },
        { "direct/plugin", opts = { b = 2 } }, -- duplicate, will merge
      }, {
        log_level = "info",
        updates = { enabled = true },
      })

      -- Should have 2 unique plugins (direct merged + imported)
      assert.equal(2, #applied_plugins)

      -- direct/plugin should come first (higher priority after merge)
      assert.truthy(applied_plugins[1].url:find "direct/plugin")
      -- opts should be merged
      assert.equal(1, applied_plugins[1].opts.a)
      assert.equal(2, applied_plugins[1].opts.b)

      -- imported/other-plugin
      assert.truthy(applied_plugins[2].url:find "imported/other%-plugin")
      assert.equal(1, applied_plugins[2].opts.x)

      -- updates should have been checked
      assert.is_table(emitted_events["nap-updates-checked"])

      package.loaded["e2e_mod"] = nil
    end)

    it("apply respects spec-level enabled=false default", function()
      local called = false
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            called = true
          end,
        }
      end

      api.setup({}, {
        { "owner/plugin" },
      }, {
        specs = { defaults = { enabled = false } },
        log_level = "info",
      })

      assert.is_false(called)
    end)
  end)

  -- ── _expand_dependencies ────────────────────────────────────

  describe("_expand_dependencies", function()
    it("returns specs unchanged when no dependencies", function()
      local input = {
        { [1] = "owner/a", priority = 0 },
        { [1] = "owner/b", priority = 0 },
      }
      local result = api._expand_dependencies(input)
      assert.equal(2, #result)
      assert.equal("owner/a", result[1][1])
      assert.equal("owner/b", result[2][1])
    end)

    it("injects dependency before the dependent spec", function()
      local input = {
        {
          [1] = "owner/main",
          priority = 0,
          dependencies = {
            { [1] = "owner/dep" },
          },
        },
      }
      local result = api._expand_dependencies(input)
      assert.equal(2, #result)
      assert.equal("owner/dep", result[1][1])
      assert.equal("owner/main", result[2][1])
    end)

    it("boosts dependency priority above parent", function()
      local input = {
        {
          [1] = "owner/main",
          priority = 5,
          dependencies = {
            { [1] = "owner/dep", priority = 0 },
          },
        },
      }
      local result = api._expand_dependencies(input)
      assert.equal(6, result[1].priority) -- parent(5) + 1
    end)

    it("keeps higher explicit priority on dependency", function()
      local input = {
        {
          [1] = "owner/main",
          priority = 2,
          dependencies = {
            { [1] = "owner/dep", priority = 10 },
          },
        },
      }
      local result = api._expand_dependencies(input)
      assert.equal(10, result[1].priority) -- max(10, 2+1) = 10
    end)

    it("expands shorthand string dependencies", function()
      local input = {
        {
          [1] = "owner/main",
          dependencies = { "owner/dep" },
        },
      }
      local result = api._expand_dependencies(input)
      assert.equal(2, #result)
      assert.equal("owner/dep", result[1][1])
    end)

    it("handles deep dependencies (deps of deps)", function()
      local input = {
        {
          [1] = "owner/main",
          priority = 0,
          dependencies = {
            {
              [1] = "owner/mid",
              dependencies = {
                { [1] = "owner/deep" },
              },
            },
          },
        },
      }
      local result = api._expand_dependencies(input)
      assert.equal(3, #result)
      -- Deep dep comes first, then mid, then main
      assert.equal("owner/deep", result[1][1])
      assert.equal("owner/mid", result[2][1])
      assert.equal("owner/main", result[3][1])
    end)

    it("detects circular dependencies", function()
      local wez = require "wezterm"
      -- This creates a cycle via name: a depends on b, b depends on a
      -- Since we work with raw specs pre-normalization, cycle detection is by name/[1]
      local input = {
        {
          [1] = "owner/a",
          dependencies = {
            {
              [1] = "owner/a", -- self-referencing
            },
          },
        },
      }
      local result = api._expand_dependencies(input)
      -- Should not infinitely recurse; the self-ref is skipped
      assert.truthy(#wez._logs.warn > 0)
      assert.truthy(wez._logs.warn[1]:find "circular dependency")
    end)

    it("strips dependencies field from output specs", function()
      local input = {
        {
          [1] = "owner/main",
          dependencies = { "owner/dep" },
        },
      }
      local result = api._expand_dependencies(input)
      for _, s in ipairs(result) do
        assert.is_nil(s.dependencies)
      end
    end)

    it("handles empty dependencies list", function()
      local input = {
        { [1] = "owner/main", dependencies = {} },
      }
      local result = api._expand_dependencies(input)
      assert.equal(1, #result)
      assert.equal("owner/main", result[1][1])
    end)

    it("preserves non-dependency fields on injected specs", function()
      local input = {
        {
          [1] = "owner/main",
          dependencies = {
            { [1] = "owner/dep", opts = { theme = "dark" }, tag = "v1.0" },
          },
        },
      }
      local result = api._expand_dependencies(input)
      assert.same({ theme = "dark" }, result[1].opts)
      assert.equal("v1.0", result[1].tag)
    end)
  end)

  -- ── clean ───────────────────────────────────────────────────

  describe("clean", function()
    it("returns empty list when all installed plugins are declared", function()
      local wez = require "wezterm"
      wez._plugin_list = {
        { url = "https://github.com/owner/plugin-a", plugin_dir = "/plugins/a" },
      }

      api.setup({}, {
        { [1] = "owner/plugin-a" },
      })

      local orphans = api.clean()
      assert.equal(0, #orphans)
    end)

    it("detects orphan plugins not in specs", function()
      local wez = require "wezterm"
      wez._plugin_list = {
        { url = "https://github.com/owner/plugin-a", plugin_dir = "/plugins/a" },
        { url = "https://github.com/owner/orphan", plugin_dir = "/plugins/orphan" },
      }

      api.setup({}, {
        { [1] = "owner/plugin-a" },
      })

      local orphans = api.clean()
      assert.equal(1, #orphans)
      assert.equal("https://github.com/owner/orphan", orphans[1].url)
      assert.equal("/plugins/orphan", orphans[1].plugin_dir)
      assert.equal("orphan", orphans[1].name)
    end)

    it("excludes nap.wz itself from orphans", function()
      local wez = require "wezterm"
      wez._plugin_list = {
        { url = "https://github.com/sravioli/nap.wz", plugin_dir = "/plugins/nap.wz" },
        { url = "https://github.com/owner/orphan", plugin_dir = "/plugins/orphan" },
      }

      api.setup({}, {})

      local orphans = api.clean()
      assert.equal(1, #orphans)
      assert.equal("orphan", orphans[1].name)
    end)

    it("returns empty list when nothing is installed", function()
      local wez = require "wezterm"
      wez._plugin_list = {}

      api.setup({}, {})

      local orphans = api.clean()
      assert.equal(0, #orphans)
    end)

    it("strips .git suffix from orphan names", function()
      local wez = require "wezterm"
      wez._plugin_list = {
        { url = "https://github.com/owner/repo.git", plugin_dir = "/plugins/repo" },
      }

      api.setup({}, {})

      local orphans = api.clean()
      assert.equal(1, #orphans)
      assert.equal("repo", orphans[1].name)
    end)
  end)
end)
