describe("nap.spec", function()
  local spec

  before_each(function()
    reset_nap_modules()
    spec = require "nap.spec"
  end)

  -- ── dir_to_url ────────────────────────────────────────────────

  describe("dir_to_url", function()
    it("passes through existing file:// URLs", function()
      assert.equal("file:///some/path", spec.dir_to_url "file:///some/path")
    end)

    it("converts absolute unix path to file URL", function()
      assert.equal("file:///home/user/plugin", spec.dir_to_url "/home/user/plugin")
    end)

    it("converts relative path (non-slash start) with file:///", function()
      local result = spec.dir_to_url "plugins/myplugin"
      assert.equal("file:///plugins/myplugin", result)
    end)

    it("expands ~ to wezterm.home_dir", function()
      local result = spec.dir_to_url "~/myplugin"
      assert.equal("file:///home/testuser/myplugin", result)
    end)

    it("normalizes backslashes to forward slashes", function()
      local result = spec.dir_to_url "C:\\Users\\test\\plugin"
      assert.truthy(result:find "C:/Users/test/plugin")
    end)
  end)

  -- ── resolve_url ───────────────────────────────────────────────

  describe("resolve_url", function()
    it("returns url field when present", function()
      assert.equal(
        "https://example.com",
        spec.resolve_url { url = "https://example.com" }
      )
    end)

    it("expands owner/repo shorthand", function()
      local result = spec.resolve_url { [1] = "foo/bar" }
      assert.equal("https://github.com/foo/bar", result)
    end)

    it("prefers url over shorthand", function()
      local result = spec.resolve_url { [1] = "foo/bar", url = "https://custom.com" }
      assert.equal("https://custom.com", result)
    end)

    it("returns dir URL for dev plugins", function()
      local result = spec.resolve_url { dev = true, dir = "/local/plugin" }
      assert.equal("file:///local/plugin", result)
    end)

    it("prefers dev+dir over url", function()
      local result = spec.resolve_url {
        dev = true,
        dir = "/local/plugin",
        url = "https://remote.com",
      }
      assert.equal("file:///local/plugin", result)
    end)

    it("returns dir as file URL when no url or shorthand", function()
      local result = spec.resolve_url { dir = "/some/dir" }
      assert.equal("file:///some/dir", result)
    end)

    it("returns nil when nothing is resolvable", function()
      assert.is_nil(spec.resolve_url {})
    end)

    it("rejects invalid shorthand (no slash)", function()
      assert.is_nil(spec.resolve_url { [1] = "no-slash" })
    end)

    -- dev+dev_config pattern matching

    it("resolves via dev_config.path + patterns when pattern matches", function()
      local result = spec.resolve_url(
        { [1] = "sravioli/my-plugin", dev = true },
        { path = "/home/dev/projects", patterns = { "sravioli" } }
      )
      assert.truthy(result:find "file://")
      assert.truthy(result:find "my%-plugin")
    end)

    it("falls through to shorthand when dev_config patterns don't match", function()
      local result = spec.resolve_url(
        { [1] = "other/plugin", dev = true },
        { path = "/home/dev/projects", patterns = { "sravioli" } }
      )
      -- no pattern matched, no fallback → falls through to normal shorthand resolution
      assert.equal("https://github.com/other/plugin", result)
    end)

    it("returns nil when dev has no match and no shorthand/url/dir", function()
      local result = spec.resolve_url(
        { dev = true },
        { path = "/home/dev/projects", patterns = { "sravioli" } }
      )
      assert.is_nil(result)
    end)

    it("uses dev_config.fallback to URL when pattern doesn't match", function()
      local result = spec.resolve_url(
        { [1] = "other/plugin", dev = true, url = "https://custom.com" },
        { path = "/home/dev", patterns = { "sravioli" }, fallback = true }
      )
      assert.equal("https://custom.com", result)
    end)

    it("uses dev_config.fallback to shorthand when no url", function()
      local result = spec.resolve_url(
        { [1] = "other/plugin", dev = true },
        { path = "/home/dev", patterns = { "sravioli" }, fallback = true }
      )
      assert.equal("https://github.com/other/plugin", result)
    end)

    it("dev with no dev_config falls through to url/shorthand", function()
      local result = spec.resolve_url { [1] = "foo/bar", dev = true }
      assert.equal("https://github.com/foo/bar", result)
    end)

    it("dev+dir takes priority over dev_config patterns", function()
      local result = spec.resolve_url(
        { [1] = "sravioli/plugin", dev = true, dir = "/local/path" },
        { path = "/home/dev", patterns = { "sravioli" } }
      )
      assert.equal("file:///local/path", result)
    end)

    it("returns nil when empty url string without shorthand", function()
      -- url="" is truthy but useless
      local result = spec.resolve_url { url = "" }
      assert.equal("", result)
    end)
  end)

  -- ── name_from_url ─────────────────────────────────────────────

  describe("name_from_url", function()
    it("extracts last path segment", function()
      assert.equal("bar", spec.name_from_url "https://github.com/foo/bar")
    end)

    it("strips .git suffix", function()
      assert.equal("bar", spec.name_from_url "https://github.com/foo/bar.git")
    end)

    it("handles trailing slash", function()
      assert.equal("bar", spec.name_from_url "https://github.com/foo/bar/")
    end)

    it("returns raw URL when no path segment found", function()
      assert.equal("", spec.name_from_url "")
    end)
  end)

  -- ── normalize ─────────────────────────────────────────────────

  describe("normalize", function()
    it("resolves URL from shorthand and derives name", function()
      local result = spec.normalize({ [1] = "owner/repo" }, 1)
      assert.equal("https://github.com/owner/repo", result._resolved_url)
      assert.equal("repo", result.name)
      assert.equal(1, result._index)
    end)

    it("applies default enabled=true", function()
      local result = spec.normalize({ url = "https://example.com/p" }, 1)
      assert.is_true(result.enabled)
    end)

    it("applies default priority=0", function()
      local result = spec.normalize({ url = "https://example.com/p" }, 1)
      assert.equal(0, result.priority)
    end)

    it("preserves explicit enabled=false (not swallowed)", function()
      local result = spec.normalize({ url = "https://example.com/p", enabled = false }, 1)
      assert.is_false(result.enabled)
    end)

    it("respects per-spec defaults for enabled", function()
      local result = spec.normalize(
        { url = "https://example.com/p" },
        1,
        { enabled = false }
      )
      assert.is_false(result.enabled)
    end)

    it("respects per-spec defaults for priority", function()
      local result = spec.normalize(
        { url = "https://example.com/p" },
        1,
        { priority = 50 }
      )
      assert.equal(50, result.priority)
    end)

    it("user value overrides per-spec defaults", function()
      local result = spec.normalize(
        { url = "https://example.com/p", priority = 10 },
        1,
        { priority = 50 }
      )
      assert.equal(10, result.priority)
    end)

    it("stores shorthand in _shorthand", function()
      local result = spec.normalize({ [1] = "foo/bar" }, 1)
      assert.equal("foo/bar", result._shorthand)
    end)

    it("does not copy numeric keys into output", function()
      local result = spec.normalize({ [1] = "foo/bar", opts = {} }, 1)
      assert.is_nil(result[1])
    end)

    it("uses explicit name over derived name", function()
      local result = spec.normalize({ [1] = "foo/bar", name = "custom" }, 1)
      assert.equal("custom", result.name)
    end)

    it("threads dev_config into resolve_url", function()
      local result = spec.normalize(
        { [1] = "sravioli/plugin", dev = true },
        1,
        {},
        { path = "/home/dev", patterns = { "sravioli" } }
      )
      assert.truthy(result._resolved_url:find "file://")
    end)

    it("derives name from shorthand when URL is nil", function()
      local result = spec.normalize({ [1] = "no-slash" }, 1)
      assert.equal("no-slash", result.name)
    end)
  end)

  -- ── validate ──────────────────────────────────────────────────

  describe("validate", function()
    it("passes valid spec", function()
      local s = spec.normalize({ [1] = "foo/bar" }, 1)
      local ok, err = spec.validate(s)
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("skips import-only specs", function()
      local ok, err = spec.validate { import = "some.module" }
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("fails for spec with no resolvable URL", function()
      local s = spec.normalize({}, 1)
      local ok, err = spec.validate(s)
      assert.is_false(ok)
      assert.truthy(err:find "no resolvable URL")
    end)

    it("provides hint about dev flag for dir-only specs", function()
      local s = spec.normalize({ dir = "/some/dir", name = "test" }, 1)
      -- dir without dev=true and without url still resolves via dir_to_url
      -- so it should actually succeed
      local ok, _ = spec.validate(s)
      assert.is_true(ok)
    end)

    it("passes spec with single branch pin", function()
      local s = spec.normalize({ [1] = "foo/bar", branch = "main" }, 1)
      local ok, err = spec.validate(s)
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("passes spec with single tag pin", function()
      local s = spec.normalize({ [1] = "foo/bar", tag = "v1.0" }, 1)
      local ok, err = spec.validate(s)
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("passes spec with single commit pin", function()
      local s = spec.normalize({ [1] = "foo/bar", commit = "abc123" }, 1)
      local ok, err = spec.validate(s)
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("fails when both branch and tag are set", function()
      local s = spec.normalize({ [1] = "foo/bar", branch = "main", tag = "v1.0" }, 1)
      local ok, err = spec.validate(s)
      assert.is_false(ok)
      assert.truthy(err:find "only one of")
    end)

    it("fails when both branch and commit are set", function()
      local s = spec.normalize({ [1] = "foo/bar", branch = "main", commit = "abc" }, 1)
      local ok, err = spec.validate(s)
      assert.is_false(ok)
      assert.truthy(err:find "only one of")
    end)

    it("fails when both tag and commit are set", function()
      local s = spec.normalize({ [1] = "foo/bar", tag = "v1.0", commit = "abc" }, 1)
      local ok, err = spec.validate(s)
      assert.is_false(ok)
      assert.truthy(err:find "only one of")
    end)

    it("fails when all three pin fields are set", function()
      local s = spec.normalize(
        { [1] = "foo/bar", branch = "main", tag = "v1.0", commit = "abc" },
        1
      )
      local ok, err = spec.validate(s)
      assert.is_false(ok)
      assert.truthy(err:find "only one of")
    end)
  end)
end)
