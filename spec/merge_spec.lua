describe("nap.merge", function()
  local merge

  before_each(function()
    reset_nap_modules()
    merge = require "nap.merge"
  end)

  it("keeps unnamed specs as-is", function()
    local specs = {
      { _resolved_url = "url1", priority = 1 },
      { _resolved_url = "url2", priority = 2 },
    }
    local result = merge.merge(specs)
    assert.equal(2, #result)
  end)

  it("merges specs with the same name", function()
    local specs = {
      { name = "foo", opts = { a = 1 }, priority = 0, _resolved_url = "u1" },
      { name = "foo", opts = { b = 2 }, priority = 5 },
    }
    local result = merge.merge(specs)
    assert.equal(1, #result)
    assert.equal("foo", result[1].name)
  end)

  it("deep-merges opts from duplicate specs", function()
    local specs = {
      { name = "foo", opts = { a = 1, nested = { x = 1 } } },
      { name = "foo", opts = { b = 2, nested = { y = 2 } } },
    }
    local result = merge.merge(specs)
    assert.equal(1, result[1].opts.a)
    assert.equal(2, result[1].opts.b)
    assert.equal(1, result[1].opts.nested.x)
    assert.equal(2, result[1].opts.nested.y)
  end)

  it("later spec overrides scalar fields", function()
    local specs = {
      { name = "foo", priority = 0, enabled = true, _resolved_url = "old" },
      { name = "foo", priority = 10, enabled = false, _resolved_url = "new" },
    }
    local result = merge.merge(specs)
    assert.equal(10, result[1].priority)
    assert.is_false(result[1].enabled)
    assert.equal("new", result[1]._resolved_url)
  end)

  it("concatenates and dedupes groups", function()
    local specs = {
      { name = "foo", groups = { "core", "ui" } },
      { name = "foo", groups = { "ui", "extra" } },
    }
    local result = merge.merge(specs)
    assert.same({ "core", "ui", "extra" }, result[1].groups)
  end)

  it("preserves declaration order", function()
    local specs = {
      { name = "alpha" },
      { name = "beta" },
      { name = "alpha", priority = 5 },
    }
    local result = merge.merge(specs)
    assert.equal(2, #result)
    assert.equal("alpha", result[1].name)
    assert.equal("beta", result[2].name)
  end)

  it("sets opts from later spec when first has no opts", function()
    local specs = {
      { name = "foo" },
      { name = "foo", opts = { a = 1 } },
    }
    local result = merge.merge(specs)
    assert.same({ a = 1 }, result[1].opts)
  end)

  it("handles empty spec list", function()
    assert.same({}, merge.merge({}))
  end)

  it("handles single unnamed spec", function()
    local specs = { { _resolved_url = "u1" } }
    local result = merge.merge(specs)
    assert.equal(1, #result)
  end)
end)
