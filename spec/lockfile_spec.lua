describe("nap.lockfile", function()
  local lockfile, wez, git

  before_each(function()
    reset_nap_modules()
    wez = require "wezterm"
    lockfile = require "nap.lockfile"
    git = require "nap.git"
  end)

  -- ── snapshot ──────────────────────────────────────────────────

  describe("snapshot", function()
    it("records commit and branch for each resolved spec", function()
      wez._plugin_list = {
        { url = "https://github.com/owner/a", plugin_dir = "/plugins/a" },
        { url = "https://github.com/owner/b", plugin_dir = "/plugins/b" },
      }

      local call_log = {}
      wez.run_child_process = function(cmd)
        local subcmd = cmd[4]
        local dir = cmd[3]
        call_log[#call_log + 1] = { dir = dir, subcmd = subcmd }
        if subcmd == "rev-parse" then
          if dir == "/plugins/a" then
            return true, "aaa111\n", ""
          else
            return true, "bbb222\n", ""
          end
        elseif subcmd == "rev-parse" or subcmd == "symbolic-ref" then
          return true, "main\n", ""
        end
        -- symbolic-ref for branch
        if cmd[5] == "--short" then
          if dir == "/plugins/a" then
            return true, "main\n", ""
          else
            return true, "develop\n", ""
          end
        end
        return true, "", ""
      end

      local specs = {
        { name = "a", _resolved_url = "https://github.com/owner/a" },
        { name = "b", _resolved_url = "https://github.com/owner/b" },
      }

      local snap = lockfile.snapshot(specs)
      assert.is_not_nil(snap.a)
      assert.is_not_nil(snap.b)
      assert.equal("https://github.com/owner/a", snap.a.url)
      assert.equal("aaa111", snap.a.commit)
      assert.equal("https://github.com/owner/b", snap.b.url)
      assert.equal("bbb222", snap.b.commit)
    end)

    it("skips specs without _resolved_url", function()
      local specs = {
        { name = "orphan" },
      }
      local snap = lockfile.snapshot(specs)
      assert.is_nil(snap.orphan)
    end)

    it("skips specs whose plugin_dir is not found", function()
      wez._plugin_list = {} -- empty
      local specs = {
        { name = "missing", _resolved_url = "https://github.com/owner/missing" },
      }
      local snap = lockfile.snapshot(specs)
      assert.is_nil(snap.missing)
    end)

    it("skips specs when git rev-parse fails", function()
      wez._plugin_list = {
        { url = "https://github.com/owner/fail", plugin_dir = "/plugins/fail" },
      }
      wez.run_child_process = function(cmd)
        return false, "", "fatal: not a git repository"
      end
      local specs = {
        { name = "fail", _resolved_url = "https://github.com/owner/fail" },
      }
      local snap = lockfile.snapshot(specs)
      assert.is_nil(snap.fail)
    end)
  end)

  -- ── serialize ─────────────────────────────────────────────────

  describe("serialize", function()
    it("produces valid Lua source with sorted keys", function()
      local data = {
        zebra = { url = "https://github.com/z/z", commit = "zzz999" },
        alpha = { url = "https://github.com/a/a", commit = "aaa111", branch = "main" },
      }
      local source = lockfile.serialize(data)

      -- alpha should come before zebra
      local alpha_pos = source:find "alpha"
      local zebra_pos = source:find "zebra"
      assert.is_true(alpha_pos < zebra_pos)

      -- Should be valid Lua that returns a table
      local fn = load(source)
      assert.is_not_nil(fn)
      local result = fn()
      assert.same(data, result)
    end)

    it("omits branch when nil", function()
      local data = {
        plugin1 = { url = "https://github.com/o/p", commit = "abc123" },
      }
      local source = lockfile.serialize(data)
      assert.is_nil(source:find "branch")
    end)

    it("handles empty data", function()
      local source = lockfile.serialize {}
      local fn = load(source)
      local result = fn()
      assert.same({}, result)
    end)
  end)

  -- ── write / read roundtrip ────────────────────────────────────

  describe("write and read", function()
    local tmpfile

    before_each(function()
      tmpfile = os.tmpname()
    end)

    after_each(function()
      os.remove(tmpfile)
    end)

    it("roundtrips data through the filesystem", function()
      local data = {
        myplugin = {
          url = "https://github.com/me/plugin",
          commit = "deadbeef",
          branch = "main",
        },
        other = { url = "https://github.com/me/other", commit = "cafebabe" },
      }

      local ok, err = lockfile.write(tmpfile, data)
      assert.is_true(ok)
      assert.is_nil(err)

      local read_data, read_err = lockfile.read(tmpfile)
      assert.is_nil(read_err)
      assert.same(data, read_data)
    end)

    it("returns error for non-existent read path", function()
      local data, err = lockfile.read "/nonexistent/path/lockfile.lua"
      assert.is_nil(data)
      assert.is_truthy(err:find "not found")
    end)

    it("returns error for invalid Lua content", function()
      local f = io.open(tmpfile, "w")
      f:write "this is not valid lua {{{"
      f:close()

      local data, err = lockfile.read(tmpfile)
      assert.is_nil(data)
      assert.is_truthy(err:find "failed to parse")
    end)

    it("returns error when lockfile does not return a table", function()
      local f = io.open(tmpfile, "w")
      f:write 'return "not a table"'
      f:close()

      local data, err = lockfile.read(tmpfile)
      assert.is_nil(data)
      assert.is_truthy(err:find "did not return a table")
    end)
  end)

  -- ── restore ───────────────────────────────────────────────────

  describe("restore", function()
    it("restores plugins to lockfile commits", function()
      wez._plugin_list = {
        { url = "https://github.com/owner/a", plugin_dir = "/plugins/a" },
      }

      local cmds = {}
      wez.run_child_process = function(cmd)
        cmds[#cmds + 1] = table.concat(cmd, " ")
        local subcmd = cmd[4]
        if subcmd == "rev-parse" then
          return true, "current_sha\n", ""
        elseif subcmd == "fetch" then
          return true, "", ""
        elseif subcmd == "checkout" then
          return true, "", ""
        end
        return true, "", ""
      end

      local specs = {
        { name = "a", _resolved_url = "https://github.com/owner/a" },
      }
      local lf_data = {
        a = { url = "https://github.com/owner/a", commit = "target_sha" },
      }

      local results = lockfile.restore(specs, lf_data)
      assert.is_true(results.a.ok)
    end)

    it("skips lockfile entries without matching spec", function()
      local specs = {}
      local lf_data = {
        missing = { url = "https://github.com/owner/missing", commit = "abc" },
      }

      local results = lockfile.restore(specs, lf_data)
      assert.is_false(results.missing.ok)
      assert.equal("no matching spec", results.missing.reason)
    end)

    it("skips specs with no resolved URL", function()
      local specs = {
        { name = "a" },
      }
      local lf_data = {
        a = { url = "https://github.com/owner/a", commit = "abc" },
      }

      local results = lockfile.restore(specs, lf_data)
      assert.is_false(results.a.ok)
      assert.equal("no resolved URL", results.a.reason)
    end)

    it("skips specs whose plugin_dir is not found", function()
      wez._plugin_list = {} -- empty
      local specs = {
        { name = "a", _resolved_url = "https://github.com/owner/a" },
      }
      local lf_data = {
        a = { url = "https://github.com/owner/a", commit = "abc" },
      }

      local results = lockfile.restore(specs, lf_data)
      assert.is_false(results.a.ok)
      assert.equal("plugin_dir not found", results.a.reason)
    end)

    it("reports failure when checkout fails", function()
      wez._plugin_list = {
        { url = "https://github.com/owner/a", plugin_dir = "/plugins/a" },
      }
      wez.run_child_process = function(cmd)
        local subcmd = cmd[4]
        if subcmd == "checkout" then
          return false, "", "error: pathspec 'bad' did not match"
        end
        return true, "", ""
      end

      local specs = {
        { name = "a", _resolved_url = "https://github.com/owner/a" },
      }
      local lf_data = {
        a = { url = "https://github.com/owner/a", commit = "bad" },
      }

      local results = lockfile.restore(specs, lf_data)
      assert.is_false(results.a.ok)
      assert.is_truthy(results.a.reason)
    end)

    it("still attempts checkout when fetch fails", function()
      wez._plugin_list = {
        { url = "https://github.com/owner/a", plugin_dir = "/plugins/a" },
      }

      local checkout_called = false
      wez.run_child_process = function(cmd)
        local subcmd = cmd[4]
        if subcmd == "fetch" then
          return false, "", "network error"
        elseif subcmd == "checkout" then
          checkout_called = true
          return true, "", ""
        end
        return true, "", ""
      end

      local specs = {
        { name = "a", _resolved_url = "https://github.com/owner/a" },
      }
      local lf_data = {
        a = { url = "https://github.com/owner/a", commit = "abc123" },
      }

      local results = lockfile.restore(specs, lf_data)
      assert.is_true(checkout_called)
      assert.is_true(results.a.ok)
    end)
  end)
end)
