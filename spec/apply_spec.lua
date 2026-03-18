describe("nap.apply", function()
  local apply

  before_each(function()
    reset_nap_modules()
    apply = require "nap.apply"
  end)

  -- ── is_enabled ────────────────────────────────────────────────

  describe("is_enabled", function()
    it("returns true when enabled is nil", function()
      assert.is_true(apply.is_enabled {})
    end)

    it("returns true when enabled is true", function()
      assert.is_true(apply.is_enabled { enabled = true })
    end)

    it("returns false when enabled is false", function()
      assert.is_false(apply.is_enabled { enabled = false })
    end)

    it("evaluates function returning true", function()
      assert.is_true(apply.is_enabled {
        enabled = function()
          return true
        end,
      })
    end)

    it("evaluates function returning false", function()
      assert.is_false(apply.is_enabled {
        enabled = function()
          return false
        end,
      })
    end)

    it("returns false when function throws", function()
      local wez = require "wezterm"
      local result = apply.is_enabled {
        name = "bad-plugin",
        enabled = function()
          error "boom"
        end,
      }
      assert.is_false(result)
      assert.equal(1, #wez._logs.error)
    end)

    it("coerces truthy function result to true", function()
      assert.is_true(apply.is_enabled {
        enabled = function()
          return "yes"
        end,
      })
    end)

    it("coerces nil function result to false", function()
      assert.is_false(apply.is_enabled {
        enabled = function()
          return nil
        end,
      })
    end)
  end)

  -- ── sort ──────────────────────────────────────────────────────

  describe("sort", function()
    it("sorts by descending priority", function()
      local specs = {
        { name = "low", priority = 1, _index = 1 },
        { name = "high", priority = 10, _index = 2 },
        { name = "mid", priority = 5, _index = 3 },
      }
      local sorted = apply.sort(specs)
      assert.equal("high", sorted[1].name)
      assert.equal("mid", sorted[2].name)
      assert.equal("low", sorted[3].name)
    end)

    it("uses ascending _index for equal priority", function()
      local specs = {
        { name = "c", priority = 0, _index = 3 },
        { name = "a", priority = 0, _index = 1 },
        { name = "b", priority = 0, _index = 2 },
      }
      local sorted = apply.sort(specs)
      assert.equal("a", sorted[1].name)
      assert.equal("b", sorted[2].name)
      assert.equal("c", sorted[3].name)
    end)

    it("does not mutate the input array", function()
      local specs = {
        { name = "b", priority = 10, _index = 1 },
        { name = "a", priority = 0, _index = 2 },
      }
      apply.sort(specs)
      assert.equal("b", specs[1].name)
      assert.equal("a", specs[2].name)
    end)

    it("handles empty list", function()
      assert.same({}, apply.sort {})
    end)

    it("handles single element", function()
      local specs = { { name = "only", priority = 0, _index = 1 } }
      local sorted = apply.sort(specs)
      assert.equal(1, #sorted)
      assert.equal("only", sorted[1].name)
    end)

    it("defaults nil priority to 0", function()
      local specs = {
        { name = "explicit", priority = 5, _index = 1 },
        { name = "nil-prio", _index = 2 },
      }
      local sorted = apply.sort(specs)
      assert.equal("explicit", sorted[1].name)
      assert.equal("nil-prio", sorted[2].name)
    end)
  end)

  -- ── run ───────────────────────────────────────────────────────

  describe("run", function()
    it("calls apply_to_config on enabled plugins", function()
      local called_with = {}
      local wez = require "wezterm"
      wez.plugin.require = function(url)
        return {
          apply_to_config = function(config, opts)
            called_with.config = config
            called_with.opts = opts
          end,
        }
      end

      local config = {}
      local specs = {
        {
          name = "test",
          enabled = true,
          _resolved_url = "https://example.com/test",
          opts = { key = "val" },
          _index = 1,
          priority = 0,
        },
      }
      apply.run(config, specs)
      assert.equal(config, called_with.config)
      assert.same({ key = "val" }, called_with.opts)
    end)

    it("skips disabled plugins", function()
      local called = false
      local wez = require "wezterm"
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            called = true
          end,
        }
      end

      apply.run({}, {
        {
          name = "disabled",
          enabled = false,
          _resolved_url = "https://example.com",
          _index = 1,
          priority = 0,
        },
      })
      assert.is_false(called)
    end)

    it("uses custom config function when provided", function()
      local custom_called = false
      local wez = require "wezterm"
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end

      apply.run({}, {
        {
          name = "custom",
          enabled = true,
          _resolved_url = "https://example.com",
          config = function(plugin, config, opts)
            custom_called = true
          end,
          _index = 1,
          priority = 0,
        },
      })
      assert.is_true(custom_called)
    end)

    it("logs error when plugin.require fails", function()
      local wez = require "wezterm"
      wez.plugin.require = function()
        error "network error"
      end

      apply.run({}, {
        {
          name = "broken",
          enabled = true,
          _resolved_url = "https://example.com",
          _index = 1,
          priority = 0,
        },
      })
      assert.truthy(#wez._logs.error > 0)
      assert.truthy(wez._logs.error[1]:find "failed to load")
    end)

    it("logs error when apply_to_config throws", function()
      local wez = require "wezterm"
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            error "apply error"
          end,
        }
      end

      apply.run({}, {
        {
          name = "erroring",
          enabled = true,
          _resolved_url = "https://example.com",
          _index = 1,
          priority = 0,
        },
      })
      assert.truthy(#wez._logs.error > 0)
      assert.truthy(wez._logs.error[1]:find "error in apply_to_config")
    end)

    it("logs warn for plugin without apply_to_config", function()
      local wez = require "wezterm"
      wez.plugin.require = function()
        return {}
      end

      apply.run({}, {
        {
          name = "no-apply",
          enabled = true,
          _resolved_url = "https://example.com",
          _index = 1,
          priority = 0,
        },
      })
      assert.truthy(#wez._logs.warn > 0)
      assert.truthy(wez._logs.warn[1]:find "no apply_to_config")
    end)

    it("skips plugins without _resolved_url", function()
      local wez = require "wezterm"
      local called = false
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            called = true
          end,
        }
      end

      apply.run({}, {
        {
          name = "no-url",
          enabled = true,
          _index = 1,
          priority = 0,
        },
      })
      assert.is_false(called)
      assert.truthy(#wez._logs.error > 0)
      assert.truthy(wez._logs.error[1]:find "has no URL")
    end)

    it("skips uninstalled plugins when install.missing=false", function()
      local wez = require "wezterm"
      local called = false
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            called = true
          end,
        }
      end
      -- Empty plugin list means plugin is not installed
      wez._plugin_list = {}

      apply.run({}, {
        {
          name = "not-installed",
          enabled = true,
          _resolved_url = "https://example.com",
          _index = 1,
          priority = 0,
        },
      }, { install = { missing = false } })

      assert.is_false(called)
    end)

    it("loads installed plugins even when install.missing=false", function()
      local wez = require "wezterm"
      local called = false
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            called = true
          end,
        }
      end
      wez._plugin_list = {
        { url = "https://example.com", plugin_dir = "/some/path" },
      }

      apply.run({}, {
        {
          name = "installed",
          enabled = true,
          _resolved_url = "https://example.com",
          _index = 1,
          priority = 0,
        },
      }, { install = { missing = false } })

      assert.is_true(called)
    end)

    it("defaults install.missing=true (loads all plugins)", function()
      local wez = require "wezterm"
      local called = false
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            called = true
          end,
        }
      end
      wez._plugin_list = {}

      apply.run({}, {
        {
          name = "test",
          enabled = true,
          _resolved_url = "https://example.com",
          _index = 1,
          priority = 0,
        },
      })

      assert.is_true(called)
    end)

    it("evaluates enabled function during run", function()
      local wez = require "wezterm"
      local called = false
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            called = true
          end,
        }
      end

      apply.run({}, {
        {
          name = "dynamic",
          enabled = function()
            return false
          end,
          _resolved_url = "https://example.com",
          _index = 1,
          priority = 0,
        },
      })
      assert.is_false(called)
    end)

    it("logs error when config fn throws", function()
      local wez = require "wezterm"
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end

      apply.run({}, {
        {
          name = "bad-config-fn",
          enabled = true,
          _resolved_url = "https://example.com",
          config = function()
            error "config boom"
          end,
          _index = 1,
          priority = 0,
        },
      })
      assert.truthy(#wez._logs.error > 0)
      assert.truthy(wez._logs.error[1]:find "error in config fn")
    end)

    it("handles empty specs list", function()
      -- Should not error
      apply.run({}, {})
      assert.equal(0, #require("wezterm")._logs.error)
    end)

    -- ── version pinning ───────────────────────────────────────

    it("checks out pinned commit before applying", function()
      local wez = require "wezterm"
      local checkout_called_with
      wez.run_child_process = function(cmd)
        if cmd[4] == "checkout" then
          checkout_called_with = cmd[5]
        end
        return true, "", ""
      end
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/plugins/a" },
      }

      apply.run({}, {
        {
          name = "pinned",
          enabled = true,
          _resolved_url = "https://example.com/a",
          commit = "abc123",
          _index = 1,
          priority = 0,
        },
      })

      assert.equal("abc123", checkout_called_with)
    end)

    it("checks out pinned tag before applying", function()
      local wez = require "wezterm"
      local checkout_ref
      wez.run_child_process = function(cmd)
        if cmd[4] == "checkout" then
          checkout_ref = cmd[5]
        end
        return true, "", ""
      end
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/plugins/a" },
      }

      apply.run({}, {
        {
          name = "pinned-tag",
          enabled = true,
          _resolved_url = "https://example.com/a",
          tag = "v2.0",
          _index = 1,
          priority = 0,
        },
      })

      assert.equal("v2.0", checkout_ref)
    end)

    it("checks out pinned branch before applying", function()
      local wez = require "wezterm"
      local checkout_ref
      wez.run_child_process = function(cmd)
        if cmd[4] == "checkout" then
          checkout_ref = cmd[5]
        end
        return true, "", ""
      end
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/plugins/a" },
      }

      apply.run({}, {
        {
          name = "pinned-branch",
          enabled = true,
          _resolved_url = "https://example.com/a",
          branch = "develop",
          _index = 1,
          priority = 0,
        },
      })

      assert.equal("develop", checkout_ref)
    end)

    it("skips checkout for unpinned plugins", function()
      local wez = require "wezterm"
      local checkout_called = false
      wez.run_child_process = function(cmd)
        if cmd[4] == "checkout" then
          checkout_called = true
        end
        return true, "", ""
      end
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end

      apply.run({}, {
        {
          name = "unpinned",
          enabled = true,
          _resolved_url = "https://example.com",
          _index = 1,
          priority = 0,
        },
      })

      assert.is_false(checkout_called)
    end)

    it("logs error and skips plugin when checkout fails", function()
      local wez = require "wezterm"
      local apply_called = false
      wez.run_child_process = function()
        return false, "", "error: pathspec 'bad' did not match"
      end
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            apply_called = true
          end,
        }
      end
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/plugins/a" },
      }

      apply.run({}, {
        {
          name = "bad-pin",
          enabled = true,
          _resolved_url = "https://example.com/a",
          commit = "bad",
          _index = 1,
          priority = 0,
        },
      })

      assert.is_false(apply_called)
      assert.truthy(#wez._logs.error > 0)
      assert.truthy(wez._logs.error[1]:find "failed to checkout")
    end)

    it("warns when plugin_dir not found for pinned plugin", function()
      local wez = require "wezterm"
      local apply_called = false
      wez.plugin.require = function()
        return {
          apply_to_config = function()
            apply_called = true
          end,
        }
      end
      wez._plugin_list = {} -- no plugin_dir mapping

      apply.run({}, {
        {
          name = "no-dir",
          enabled = true,
          _resolved_url = "https://example.com/a",
          tag = "v1.0",
          _index = 1,
          priority = 0,
        },
      })

      -- Still applies (with warning), since plugin was loaded by require
      assert.is_true(apply_called)
      assert.truthy(#wez._logs.warn > 0)
      assert.truthy(wez._logs.warn[1]:find "plugin directory not found")
    end)

    it("commit takes precedence over tag over branch", function()
      local wez = require "wezterm"
      local checkout_ref
      wez.run_child_process = function(cmd)
        if cmd[4] == "checkout" then
          checkout_ref = cmd[5]
        end
        return true, "", ""
      end
      wez.plugin.require = function()
        return { apply_to_config = function() end }
      end
      wez._plugin_list = {
        { url = "https://example.com/a", plugin_dir = "/plugins/a" },
      }

      -- Even though validation should prevent this, apply resolves precedence
      apply.run({}, {
        {
          name = "multi-pin",
          enabled = true,
          _resolved_url = "https://example.com/a",
          commit = "sha123",
          tag = "v1.0",
          branch = "main",
          _index = 1,
          priority = 0,
        },
      })

      assert.equal("sha123", checkout_ref)
    end)
  end)
end)
