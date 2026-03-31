describe("nap.updates", function()
  local updates, wez

  before_each(function()
    reset_nap_modules()
    wez = require "wezterm"
    updates = require "nap.updates"
  end)

  -- ── check_updates_async ───────────────────────────────────────

  describe("check_updates_async", function()
    it("does nothing when config is nil", function()
      -- Should not throw
      updates.check_updates_async({}, nil)
      assert.equal(0, #wez._logs.error)
    end)

    it("does nothing when config.enabled is false", function()
      updates.check_updates_async({}, { enabled = false })
      assert.equal(0, #wez._logs.error)
    end)

    it("warns for non-table specs", function()
      updates.check_updates_async("bad", { enabled = true })
      assert.equal(1, #wez._logs.warn)
      assert.truthy(wez._logs.warn[1]:find "invalid specs")
    end)

    it("emits nap-updates-checked event for valid specs", function()
      local emitted = {}
      wez.emit = function(event, payload)
        emitted[event] = payload
      end

      updates.check_updates_async(
        { { name = "test", _resolved_url = "https://example.com" } },
        { enabled = true, timeout_ms = 100 }
      )
      assert.is_table(emitted["nap-updates-checked"])
      assert.equal(0, emitted["nap-updates-checked"].update_count)
    end)

    it("skips plugins without _resolved_url", function()
      local emitted = {}
      wez.emit = function(event, payload)
        emitted[event] = payload
      end

      updates.check_updates_async({ { name = "no-url" } }, { enabled = true })
      assert.equal(0, emitted["nap-updates-checked"].update_count)
    end)

    it("skips plugins without name", function()
      local emitted = {}
      wez.emit = function(event, payload)
        emitted[event] = payload
      end

      updates.check_updates_async({ { _resolved_url = "https://example.com" } }, { enabled = true })
      assert.equal(0, emitted["nap-updates-checked"].update_count)
    end)

    it("records timestamps in GLOBAL cache", function()
      wez.GLOBAL = {}

      updates.check_updates_async(
        { { name = "test", _resolved_url = "https://example.com" } },
        { enabled = true }
      )

      assert.is_table(wez.GLOBAL.__nap)
      assert.is_table(wez.GLOBAL.__nap.update_timestamps)
      assert.is_number(wez.GLOBAL.__nap.update_timestamps["test"])
    end)

    it("skips plugin within cooldown window", function()
      wez.GLOBAL = {
        __nap = {
          update_timestamps = {
            test = os.time(), -- just checked
          },
        },
      }

      local emitted = {}
      wez.emit = function(event, payload)
        emitted[event] = payload
      end

      -- Set log level to info to capture the skip message
      local u = require "nap.util"
      u.log.set_level "info"

      updates.check_updates_async(
        { { name = "test", _resolved_url = "https://example.com" } },
        { enabled = true, cooldown_s = 3600 } -- 1 hour cooldown
      )

      assert.truthy(#wez._logs.info > 0)
      assert.truthy(wez._logs.info[1]:find "cooldown")
    end)

    it("checks plugin past cooldown window", function()
      wez.GLOBAL = {
        __nap = {
          update_timestamps = {
            test = os.time() - 7200, -- checked 2 hours ago
          },
        },
      }

      local emitted = {}
      wez.emit = function(event, payload)
        emitted[event] = payload
      end

      updates.check_updates_async(
        { { name = "test", _resolved_url = "https://example.com" } },
        { enabled = true, cooldown_s = 3600 } -- 1 hour cooldown, 2 hours elapsed
      )

      -- Should have updated the timestamp
      assert.is_number(wez.GLOBAL.__nap.update_timestamps["test"])
      -- New timestamp should be recent
      assert.truthy(os.time() - wez.GLOBAL.__nap.update_timestamps["test"] < 5)
    end)

    it("checks all plugins when cooldown_s=0", function()
      wez.GLOBAL = {
        __nap = {
          update_timestamps = {
            test = os.time(), -- just checked, but cooldown is 0
          },
        },
      }

      local emitted = {}
      wez.emit = function(event, payload)
        emitted[event] = payload
      end

      updates.check_updates_async(
        { { name = "test", _resolved_url = "https://example.com" } },
        { enabled = true, cooldown_s = 0 }
      )

      assert.is_table(emitted["nap-updates-checked"])
    end)

    it("handles background_task pcall error gracefully", function()
      wez.background_task = function(fn)
        -- Simulate the fn being called; the internal pcall should handle errors
        fn()
      end

      -- This should not throw even if something goes wrong internally
      updates.check_updates_async(
        { { name = "test", _resolved_url = "https://example.com" } },
        { enabled = true }
      )
      assert.equal(0, #wez._logs.error)
    end)
  end)

  -- ── check_updates_sync ────────────────────────────────────────

  describe("check_updates_sync", function()
    it("returns empty list (has_update always returns false)", function()
      local result = updates.check_updates_sync(
        { { name = "test", _resolved_url = "https://example.com" } },
        { timeout_ms = 100 }
      )
      assert.same({}, result)
    end)

    it("skips specs without _resolved_url", function()
      local result = updates.check_updates_sync({ { name = "test" } }, {})
      assert.same({}, result)
    end)

    it("skips specs without name", function()
      local result = updates.check_updates_sync({ { _resolved_url = "https://example.com" } }, {})
      assert.same({}, result)
    end)

    it("handles empty specs list", function()
      local result = updates.check_updates_sync({}, {})
      assert.same({}, result)
    end)
  end)

  -- ── update_plugin ─────────────────────────────────────────────

  describe("update_plugin", function()
    it("fetches and fast-forward merges unpinned plugin", function()
      wez._plugin_list = {
        { url = "https://github.com/owner/a", plugin_dir = "/plugins/a" },
      }

      local cmds = {}
      wez.run_child_process = function(cmd)
        cmds[#cmds + 1] = table.concat(cmd, " ")
        local subcmd = cmd[4]
        if subcmd == "rev-parse" then
          return true, "abc123\n", ""
        elseif subcmd == "fetch" then
          return true, "", ""
        elseif subcmd == "merge" then
          return true, "", ""
        end
        return true, "", ""
      end

      local spec = { name = "a", _resolved_url = "https://github.com/owner/a" }
      local ok, err = updates.update_plugin(spec)
      assert.is_true(ok)
      assert.is_nil(err)

      -- Should have called fetch and merge
      local has_fetch, has_merge = false, false
      for _, c in ipairs(cmds) do
        if c:find "fetch" then
          has_fetch = true
        end
        if c:find "merge" then
          has_merge = true
        end
      end
      assert.is_true(has_fetch)
      assert.is_true(has_merge)
    end)

    it("fetches and checks out pinned ref for tagged plugin", function()
      wez._plugin_list = {
        { url = "https://github.com/owner/a", plugin_dir = "/plugins/a" },
      }

      local cmds = {}
      wez.run_child_process = function(cmd)
        cmds[#cmds + 1] = table.concat(cmd, " ")
        local subcmd = cmd[4]
        if subcmd == "rev-parse" then
          return true, "abc123\n", ""
        elseif subcmd == "fetch" then
          return true, "", ""
        elseif subcmd == "checkout" then
          return true, "", ""
        end
        return true, "", ""
      end

      local spec = { name = "a", _resolved_url = "https://github.com/owner/a", tag = "v1.0" }
      local ok, err = updates.update_plugin(spec)
      assert.is_true(ok)

      -- Should have called checkout, not merge
      local has_checkout = false
      for _, c in ipairs(cmds) do
        if c:find "checkout" then
          has_checkout = true
        end
      end
      assert.is_true(has_checkout)
    end)

    it("returns error when no resolved URL", function()
      local ok, err = updates.update_plugin { name = "bad" }
      assert.is_false(ok)
      assert.truthy(err:find "no resolved URL")
    end)

    it("returns error when plugin_dir not found", function()
      wez._plugin_list = {}
      local ok, err =
        updates.update_plugin { name = "a", _resolved_url = "https://github.com/owner/a" }
      assert.is_false(ok)
      assert.truthy(err:find "not found")
    end)

    it("returns error when fetch fails", function()
      wez._plugin_list = {
        { url = "https://github.com/owner/a", plugin_dir = "/plugins/a" },
      }
      wez.run_child_process = function(cmd)
        if cmd[4] == "fetch" then
          return false, "", "network error"
        end
        return true, "sha\n", ""
      end

      local ok, err =
        updates.update_plugin { name = "a", _resolved_url = "https://github.com/owner/a" }
      assert.is_false(ok)
      assert.truthy(err:find "fetch failed")
    end)

    it("returns error when merge fails", function()
      wez._plugin_list = {
        { url = "https://github.com/owner/a", plugin_dir = "/plugins/a" },
      }
      wez.run_child_process = function(cmd)
        if cmd[4] == "merge" then
          return false, "", "conflict"
        end
        return true, "sha\n", ""
      end

      local ok, err =
        updates.update_plugin { name = "a", _resolved_url = "https://github.com/owner/a" }
      assert.is_false(ok)
      assert.truthy(err:find "merge failed")
    end)
  end)
end)
