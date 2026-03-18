describe("nap.util", function()
  local u, wez

  before_each(function()
    reset_nap_modules()
    wez = require "wezterm"
    u = require "nap.util"
  end)

  -- ── tbl.deep_copy ─────────────────────────────────────────────

  describe("tbl.deep_copy", function()
    it("copies scalars as-is", function()
      assert.equal(42, u.tbl.deep_copy(42))
      assert.equal("hi", u.tbl.deep_copy "hi")
      assert.is_true(u.tbl.deep_copy(true))
      assert.is_nil(u.tbl.deep_copy(nil))
    end)

    it("creates a new table with same values", function()
      local t = { a = 1, b = { c = 2 } }
      local c = u.tbl.deep_copy(t)
      assert.same(t, c)
      assert.are_not.equal(t, c)
      assert.are_not.equal(t.b, c.b)
    end)

    it("handles nested tables", function()
      local t = { x = { y = { z = "deep" } } }
      local c = u.tbl.deep_copy(t)
      c.x.y.z = "changed"
      assert.equal("deep", t.x.y.z)
    end)
  end)

  -- ── tbl.is_list ───────────────────────────────────────────────

  describe("tbl.is_list", function()
    it("recognizes sequential integer-keyed tables", function()
      assert.is_true(u.tbl.is_list { "a", "b", "c" })
    end)

    it("returns false for dict tables", function()
      assert.is_false(u.tbl.is_list { x = 1, y = 2 })
    end)

    it("returns false for mixed tables", function()
      assert.is_false(u.tbl.is_list { "a", x = 1 })
    end)

    it("returns true for empty table", function()
      assert.is_true(u.tbl.is_list {})
    end)

    it("returns false for non-table", function()
      assert.is_false(u.tbl.is_list "string")
      assert.is_false(u.tbl.is_list(42))
    end)
  end)

  -- ── tbl.deep_merge ────────────────────────────────────────────

  describe("tbl.deep_merge", function()
    it("overrides scalars from second table", function()
      local result = u.tbl.deep_merge({ a = 1 }, { a = 2 })
      assert.equal(2, result.a)
    end)

    it("adds new keys from override", function()
      local result = u.tbl.deep_merge({ a = 1 }, { b = 2 })
      assert.equal(1, result.a)
      assert.equal(2, result.b)
    end)

    it("recursively merges nested dicts", function()
      local base = { ui = { width = 80, fuzzy = true } }
      local over = { ui = { width = 120 } }
      local result = u.tbl.deep_merge(base, over)
      assert.equal(120, result.ui.width)
      assert.is_true(result.ui.fuzzy)
    end)

    it("replaces lists instead of merging", function()
      local base = { items = { "a", "b" } }
      local over = { items = { "c" } }
      local result = u.tbl.deep_merge(base, over)
      assert.same({ "c" }, result.items)
    end)

    it("does not mutate either input", function()
      local base = { a = 1, nested = { x = 1 } }
      local over = { b = 2, nested = { y = 2 } }
      local base_copy = { a = 1, nested = { x = 1 } }
      u.tbl.deep_merge(base, over)
      assert.same(base_copy, base)
    end)
  end)

  -- ── tbl.dedupe ────────────────────────────────────────────────

  describe("tbl.dedupe", function()
    it("removes duplicates preserving order", function()
      assert.same({ "a", "b", "c" }, u.tbl.dedupe { "a", "b", "a", "c", "b" })
    end)

    it("returns empty for empty list", function()
      assert.same({}, u.tbl.dedupe {})
    end)

    it("preserves single-element list", function()
      assert.same({ "x" }, u.tbl.dedupe { "x" })
    end)
  end)

  -- ── log ───────────────────────────────────────────────────────

  describe("log", function()
    it("suppresses info at default warn level", function()
      u.log.info "test info"
      assert.equal(0, #wez._logs.info)
    end)

    it("emits warn at default warn level", function()
      u.log.warn "test warn"
      assert.equal(1, #wez._logs.warn)
      assert.truthy(wez._logs.warn[1]:find "test warn")
    end)

    it("always emits errors", function()
      u.log.error "test error"
      assert.equal(1, #wez._logs.error)
    end)

    it("respects set_level to info", function()
      u.log.set_level "info"
      u.log.info "now visible"
      assert.equal(1, #wez._logs.info)
    end)

    it("suppresses warn at error level", function()
      u.log.set_level "error"
      u.log.warn "should be hidden"
      assert.equal(0, #wez._logs.warn)
    end)

    it("includes [nap.wz] prefix", function()
      u.log.error "check prefix"
      assert.truthy(wez._logs.error[1]:find "%[nap%.wz%]")
    end)

    it("ignores invalid log levels", function()
      u.log.set_level "info"
      u.log.set_level "nonexistent"
      u.log.info "still info level"
      assert.equal(1, #wez._logs.info)
    end)

    it("formats with zero varargs (plain string)", function()
      u.log.error "plain message"
      assert.truthy(wez._logs.error[1]:find "plain message")
    end)

    it("formats with one vararg", function()
      u.log.error("count: %d", 42)
      assert.truthy(wez._logs.error[1]:find "count: 42")
    end)

    it("formats with multiple varargs", function()
      u.log.error("a=%s b=%d", "hello", 99)
      assert.truthy(wez._logs.error[1]:find "a=hello b=99")
    end)

    it("warn formats varargs when level allows", function()
      u.log.set_level "warn"
      u.log.warn("x=%s", "val")
      assert.truthy(wez._logs.warn[1]:find "x=val")
    end)

    it("info formats varargs when level allows", function()
      u.log.set_level "info"
      u.log.info("n=%d", 7)
      assert.truthy(wez._logs.info[1]:find "n=7")
    end)

    it("suppressed log does not call string.format", function()
      -- At default warn level, info is suppressed
      -- If format were called with bad args, it would error
      u.log.info "this has %d but no args"
      assert.equal(0, #wez._logs.info)
    end)
  end)

  -- ── is_windows ────────────────────────────────────────────────

  describe("is_windows", function()
    it("returns a boolean", function()
      local result = u.is_windows()
      assert.is_boolean(result)
    end)

    it("matches package.config separator", function()
      local expected = package.config:sub(1, 1) == "\\"
      assert.equal(expected, u.is_windows())
    end)
  end)

  -- ── find_plugin_dir ───────────────────────────────────────────

  describe("find_plugin_dir", function()
    it("returns plugin_dir for matching URL", function()
      wez._plugin_list = {
        { url = "https://github.com/foo/bar", plugin_dir = "/path/to/bar" },
      }
      assert.equal("/path/to/bar", u.find_plugin_dir "https://github.com/foo/bar")
    end)

    it("returns nil for unknown URL", function()
      wez._plugin_list = {}
      assert.is_nil(u.find_plugin_dir "https://github.com/unknown")
    end)

    it("returns first match when multiple plugins listed", function()
      wez._plugin_list = {
        { url = "https://github.com/a/a", plugin_dir = "/path/a" },
        { url = "https://github.com/b/b", plugin_dir = "/path/b" },
      }
      assert.equal("/path/b", u.find_plugin_dir "https://github.com/b/b")
    end)
  end)

  -- ── get_cache ─────────────────────────────────────────────────

  describe("get_cache", function()
    it("returns a table", function()
      local cache = u.get_cache()
      assert.is_table(cache)
    end)

    it("lazily initializes GLOBAL.__nap", function()
      wez.GLOBAL = {}
      assert.is_nil(wez.GLOBAL.__nap)
      u.get_cache()
      assert.is_table(wez.GLOBAL.__nap)
    end)

    it("returns the same table on repeated calls", function()
      wez.GLOBAL = {}
      local c1 = u.get_cache()
      c1.my_key = "hello"
      local c2 = u.get_cache()
      assert.equal("hello", c2.my_key)
      assert.equal(c1, c2)
    end)

    it("preserves existing GLOBAL.__nap data", function()
      wez.GLOBAL = { __nap = { existing = true } }
      local cache = u.get_cache()
      assert.is_true(cache.existing)
    end)
  end)

  -- ── tbl.dedupe edge cases ─────────────────────────────────────

  describe("tbl.dedupe (additional)", function()
    it("dedupes numeric values", function()
      assert.same({ 1, 2, 3 }, u.tbl.dedupe { 1, 2, 1, 3, 2 })
    end)
  end)

  -- ── tbl.is_list edge cases ────────────────────────────────────

  describe("tbl.is_list (additional)", function()
    it("returns false for sparse arrays", function()
      local t = { [1] = "a", [3] = "c" }
      assert.is_false(u.tbl.is_list(t))
    end)
  end)
end)
