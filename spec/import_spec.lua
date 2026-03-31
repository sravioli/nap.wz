describe("nap.import", function()
  local imports, wez

  before_each(function()
    reset_nap_modules()
    wez = require "wezterm"
    imports = require "nap.import"
  end)

  it("passes through non-import specs", function()
    local specs = {
      { [1] = "foo/bar", opts = {} },
      { url = "https://example.com" },
    }
    local result = imports.expand(specs)
    assert.equal(2, #result)
  end)

  it("expands import specs from require'd modules", function()
    -- Inject a fake module
    package.loaded["test_plugins.core"] = {
      { [1] = "owner/plugin-a" },
      { [1] = "owner/plugin-b" },
    }
    local specs = {
      { import = "test_plugins.core" },
    }
    local result = imports.expand(specs)
    assert.equal(2, #result)
    assert.equal("owner/plugin-a", result[1][1])
    assert.equal("owner/plugin-b", result[2][1])
    package.loaded["test_plugins.core"] = nil
  end)

  it("logs error when import module not found", function()
    local specs = {
      { import = "nonexistent.module.xyz" },
    }
    local result = imports.expand(specs)
    assert.equal(0, #result)
    assert.equal(1, #wez._logs.error)
    assert.truthy(wez._logs.error[1]:find "nonexistent.module.xyz")
  end)

  it("logs error when import returns non-table", function()
    package.loaded["bad_module"] = "not a table"
    local specs = {
      { import = "bad_module" },
    }
    local result = imports.expand(specs)
    assert.equal(0, #result)
    assert.equal(1, #wez._logs.error)
    assert.truthy(wez._logs.error[1]:find "did not return a table")
    package.loaded["bad_module"] = nil
  end)

  it("warns on nested imports and skips them", function()
    package.loaded["nested_test"] = {
      { [1] = "foo/bar" },
      { import = "should.be.skipped" },
    }
    local specs = { { import = "nested_test" } }
    local result = imports.expand(specs)
    assert.equal(1, #result)
    assert.equal("foo/bar", result[1][1])
    assert.equal(1, #wez._logs.warn)
    assert.truthy(wez._logs.warn[1]:find "nested import")
    package.loaded["nested_test"] = nil
  end)

  it("mixes import and non-import specs", function()
    package.loaded["mixed_mod"] = {
      { [1] = "from/import" },
    }
    local specs = {
      { [1] = "direct/spec" },
      { import = "mixed_mod" },
      { url = "https://example.com" },
    }
    local result = imports.expand(specs)
    assert.equal(3, #result)
    assert.equal("direct/spec", result[1][1])
    assert.equal("from/import", result[2][1])
    assert.equal("https://example.com", result[3].url)
    package.loaded["mixed_mod"] = nil
  end)
end)
