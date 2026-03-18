describe("nap.schema", function()
  local schema

  before_each(function()
    reset_nap_modules()
    schema = require "nap.schema"
  end)

  -- ── apply_defaults ──────────────────────────────────────────────

  describe("apply_defaults", function()
    it("returns empty table for empty schema", function()
      local result = schema.apply_defaults({}, {})
      assert.same({}, result)
    end)

    it("fills scalar defaults when value is nil", function()
      local s = {
        name = { type = "string", default = "hello" },
        count = { type = "number", default = 42 },
      }
      local result = schema.apply_defaults({}, s)
      assert.equal("hello", result.name)
      assert.equal(42, result.count)
    end)

    it("preserves user-supplied values over defaults", function()
      local s = {
        name = { type = "string", default = "hello" },
      }
      local result = schema.apply_defaults({ name = "world" }, s)
      assert.equal("world", result.name)
    end)

    it("preserves false (does not treat as nil)", function()
      local s = {
        enabled = { type = "boolean", default = true },
      }
      local result = schema.apply_defaults({ enabled = false }, s)
      assert.is_false(result.enabled)
    end)

    it("handles nested table fields", function()
      local s = {
        ui = {
          type = "table",
          fields = {
            fuzzy = { type = "boolean", default = true },
            width = { type = "number", default = 80 },
          },
        },
      }
      local result = schema.apply_defaults({}, s)
      assert.is_table(result.ui)
      assert.is_true(result.ui.fuzzy)
      assert.equal(80, result.ui.width)
    end)

    it("merges user values into nested tables", function()
      local s = {
        ui = {
          type = "table",
          fields = {
            fuzzy = { type = "boolean", default = true },
            width = { type = "number", default = 80 },
          },
        },
      }
      local result = schema.apply_defaults({ ui = { width = 120 } }, s)
      assert.is_true(result.ui.fuzzy)
      assert.equal(120, result.ui.width)
    end)

    it("deep-copies table defaults to prevent shared references", function()
      local s = {
        tags = { type = "table", default = { "a", "b" } },
      }
      local r1 = schema.apply_defaults({}, s)
      local r2 = schema.apply_defaults({}, s)
      r1.tags[1] = "changed"
      assert.equal("a", r2.tags[1])
    end)

    it("treats non-table input as empty table", function()
      local s = {
        x = { type = "number", default = 1 },
      }
      local result = schema.apply_defaults(nil, s)
      assert.equal(1, result.x)

      result = schema.apply_defaults("bad", s)
      assert.equal(1, result.x)
    end)

    it("does not mutate the input table", function()
      local s = {
        x = { type = "number", default = 1 },
        y = { type = "number", default = 2 },
      }
      local input = { x = 10 }
      schema.apply_defaults(input, s)
      assert.is_nil(input.y)
    end)

    it("ignores extra fields not in schema", function()
      local s = {
        x = { type = "number", default = 1 },
      }
      local result = schema.apply_defaults({ x = 5, extra = "hi" }, s)
      assert.equal(5, result.x)
      assert.equal("hi", result.extra)
    end)
  end)

  -- ── validate ────────────────────────────────────────────────────

  describe("validate", function()
    it("passes for valid simple values", function()
      local s = {
        name = { type = "string", default = "x" },
        count = { type = "number", default = 0 },
      }
      local ok, errors = schema.validate({ name = "hello", count = 5 }, s)
      assert.is_true(ok)
      assert.same({}, errors)
    end)

    it("detects type mismatch", function()
      local s = {
        name = { type = "string" },
      }
      local ok, errors = schema.validate({ name = 123 }, s)
      assert.is_false(ok)
      assert.equal(1, #errors)
      assert.truthy(errors[1]:find "must be string")
    end)

    it("detects required missing field", function()
      local s = {
        name = { type = "string", required = true },
      }
      local ok, errors = schema.validate({}, s)
      assert.is_false(ok)
      assert.truthy(errors[1]:find "required")
    end)

    it("validates enum values", function()
      local s = {
        level = { type = "string", enum = { "info", "warn", "error" } },
      }
      local ok, _ = schema.validate({ level = "info" }, s)
      assert.is_true(ok)

      local ok2, errors = schema.validate({ level = "bad" }, s)
      assert.is_false(ok2)
      assert.truthy(errors[1]:find "must be one of")
    end)

    it("validates numeric min", function()
      local s = {
        count = { type = "number", min = 0 },
      }
      local ok, _ = schema.validate({ count = 0 }, s)
      assert.is_true(ok)

      local ok2, errors = schema.validate({ count = -1 }, s)
      assert.is_false(ok2)
      assert.truthy(errors[1]:find ">= 0")
    end)

    it("validates numeric max", function()
      local s = {
        count = { type = "number", max = 100 },
      }
      local ok, _ = schema.validate({ count = 100 }, s)
      assert.is_true(ok)

      local ok2, errors = schema.validate({ count = 101 }, s)
      assert.is_false(ok2)
      assert.truthy(errors[1]:find "<= 100")
    end)

    it("supports union types via 'types'", function()
      local s = {
        keymaps = { types = { "boolean", "table" } },
      }
      local ok1, _ = schema.validate({ keymaps = false }, s)
      assert.is_true(ok1)

      local ok2, _ = schema.validate({ keymaps = {} }, s)
      assert.is_true(ok2)

      local ok3, errors = schema.validate({ keymaps = 42 }, s)
      assert.is_false(ok3)
      assert.truthy(errors[1]:find "boolean|table")
    end)

    it("recurses into nested table fields", function()
      local s = {
        ui = {
          type = "table",
          fields = {
            width = { type = "number", min = 40 },
          },
        },
      }
      local ok, errors = schema.validate({ ui = { width = 10 } }, s)
      assert.is_false(ok)
      assert.truthy(errors[1]:find "ui.width")
      assert.truthy(errors[1]:find ">= 40")
    end)

    it("collects multiple errors", function()
      local s = {
        a = { type = "string", required = true },
        b = { type = "number", min = 0 },
      }
      local ok, errors = schema.validate({ b = -5 }, s)
      assert.is_false(ok)
      assert.equal(2, #errors)
    end)

    it("uses custom path prefix", function()
      local s = {
        x = { type = "string" },
      }
      local _, errors = schema.validate({ x = 42 }, s, "myconfig")
      assert.truthy(errors[1]:find "^myconfig%.x")
    end)

    it("rejects non-table root value", function()
      local s = { x = { type = "string" } }
      local ok, errors = schema.validate("oops", s)
      assert.is_false(ok)
      assert.truthy(errors[1]:find "must be a table")
    end)

    it("skips nil optional fields without error", function()
      local s = {
        x = { type = "string" },
      }
      local ok, errors = schema.validate({}, s)
      assert.is_true(ok)
      assert.same({}, errors)
    end)

    it("validates 3-level nested structure", function()
      local s = {
        a = {
          type = "table",
          fields = {
            b = {
              type = "table",
              fields = {
                c = { type = "number", min = 0 },
              },
            },
          },
        },
      }
      local ok, errors = schema.validate({ a = { b = { c = -1 } } }, s)
      assert.is_false(ok)
      assert.truthy(errors[1]:find "a.b.c")
      assert.truthy(errors[1]:find ">= 0")
    end)

    it("skips enum check for non-string values", function()
      local s = {
        level = { type = "string", enum = { "a", "b" } },
      }
      -- Pass a number: type check fails, enum check should not run
      local ok, errors = schema.validate({ level = 123 }, s)
      assert.is_false(ok)
      assert.equal(1, #errors)
      assert.truthy(errors[1]:find "must be string")
    end)

    it("skips range check for non-numeric values", function()
      local s = {
        count = { type = "number", min = 0 },
      }
      -- Pass a string: type check fails, range check should not run
      local ok, errors = schema.validate({ count = "hi" }, s)
      assert.is_false(ok)
      assert.equal(1, #errors)
      assert.truthy(errors[1]:find "must be number")
    end)

    it("validates union types at nested level", function()
      local s = {
        ui = {
          type = "table",
          fields = {
            icons = { types = { "boolean", "table" } },
          },
        },
      }
      local ok1, _ = schema.validate({ ui = { icons = false } }, s)
      assert.is_true(ok1)

      local ok2, _ = schema.validate({ ui = { icons = {} } }, s)
      assert.is_true(ok2)

      local ok3, errors = schema.validate({ ui = { icons = "bad" } }, s)
      assert.is_false(ok3)
      assert.truthy(errors[1]:find "boolean|table")
    end)

    it("detects both required-missing and type-mismatch in same validation", function()
      local s = {
        a = { type = "string", required = true },
        b = { type = "number", min = 0 },
      }
      local ok, errors = schema.validate({ b = "wrong" }, s)
      assert.is_false(ok)
      assert.equal(2, #errors) -- required + type mismatch
    end)
  end)
end)
