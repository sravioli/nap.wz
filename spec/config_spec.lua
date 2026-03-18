describe("nap.config", function()
  local config_mod, wez

  before_each(function()
    reset_nap_modules()
    wez = require "wezterm"
    config_mod = require "nap.config"
  end)

  -- ── defaults ──────────────────────────────────────────────────

  describe("defaults", function()
    it("returns a fully-populated config", function()
      local d = config_mod.defaults()
      assert.is_string(d.log_level)
      assert.is_table(d.integrations)
      assert.is_table(d.updates)
      assert.is_table(d.ui)
      assert.is_table(d.specs)
    end)

    it("has expected default log_level", function()
      assert.equal("warn", config_mod.defaults().log_level)
    end)

    it("has expected default update settings", function()
      local u = config_mod.defaults().updates
      assert.is_false(u.enabled)
      assert.equal(24, u.interval_hours)
      assert.equal(1000, u.startup_delay_ms)
    end)

    it("has expected default ui settings", function()
      local ui = config_mod.defaults().ui
      assert.is_true(ui.fuzzy)
      assert.is_true(ui.icons)
      assert.is_true(ui.show_url)
    end)

    it("has expected default spec settings", function()
      local specs = config_mod.defaults().specs
      assert.is_true(specs.defaults.enabled)
      assert.equal(0, specs.defaults.priority)
    end)

    it("returns independent copies each call", function()
      local d1 = config_mod.defaults()
      local d2 = config_mod.defaults()
      d1.log_level = "error"
      assert.equal("warn", d2.log_level)
    end)
  end)

  -- ── schema ────────────────────────────────────────────────────

  describe("schema", function()
    it("returns a table describing config fields", function()
      local s = config_mod.schema()
      assert.is_table(s)
      assert.is_table(s.log_level)
      assert.is_table(s.updates)
    end)
  end)

  -- ── normalize ─────────────────────────────────────────────────

  describe("normalize", function()
    it("returns all defaults for nil input", function()
      local result = config_mod.normalize(nil)
      assert.same(config_mod.defaults(), result)
    end)

    it("returns all defaults for empty table", function()
      local result = config_mod.normalize {}
      assert.same(config_mod.defaults(), result)
    end)

    it("applies user overrides", function()
      local result = config_mod.normalize { log_level = "info" }
      assert.equal("info", result.log_level)
    end)

    it("applies nested user overrides", function()
      local result = config_mod.normalize {
        updates = { enabled = true },
      }
      assert.is_true(result.updates.enabled)
      -- other defaults still present
      assert.equal(24, result.updates.interval_hours)
    end)

    it("logs error for non-table input and returns defaults", function()
      local result = config_mod.normalize "bad"
      assert.same(config_mod.defaults(), result)
      assert.equal(1, #wez._logs.error)
      assert.truthy(wez._logs.error[1]:find "must be a table")
    end)

    it("logs error and ignores bad-typed field", function()
      local result = config_mod.normalize { log_level = 42 }
      assert.equal("warn", result.log_level)
      assert.truthy(#wez._logs.error > 0)
    end)

    it("does not mutate caller's table", function()
      local input = { log_level = "info" }
      config_mod.normalize(input)
      -- input should NOT have gained new keys
      assert.is_nil(input.updates)
      assert.is_nil(input.ui)
    end)

    it("validates and logs bad enum value", function()
      local result = config_mod.normalize { log_level = "trace" }
      -- apply_defaults won't overwrite "trace" since it's not nil
      -- but validation should catch it
      assert.truthy(#wez._logs.error > 0)
    end)

    it("validates and logs out-of-range number", function()
      config_mod.normalize {
        updates = { interval_hours = 0 },
      }
      assert.truthy(#wez._logs.error > 0)
    end)

    it("preserves keymaps=false (boolean union type)", function()
      local result = config_mod.normalize { keymaps = false }
      assert.is_false(result.keymaps)
    end)

    it("preserves keymaps as table (boolean union type)", function()
      local result = config_mod.normalize { keymaps = { leader = "C-p" } }
      assert.is_table(result.keymaps)
      assert.equal("C-p", result.keymaps.leader)
    end)

    -- dev block

    it("returns default dev settings when not provided", function()
      local result = config_mod.normalize {}
      assert.is_table(result.dev)
      assert.equal("~/projects", result.dev.path)
      assert.same({}, result.dev.patterns)
      assert.is_false(result.dev.fallback)
    end)

    it("applies user dev overrides", function()
      local result = config_mod.normalize {
        dev = { path = "/custom", patterns = { "sravioli" }, fallback = true },
      }
      assert.equal("/custom", result.dev.path)
      assert.same({ "sravioli" }, result.dev.patterns)
      assert.is_true(result.dev.fallback)
    end)

    it("merges partial dev overrides with defaults", function()
      local result = config_mod.normalize {
        dev = { path = "/custom" },
      }
      assert.equal("/custom", result.dev.path)
      assert.same({}, result.dev.patterns) -- default
      assert.is_false(result.dev.fallback) -- default
    end)

    -- install block

    it("returns default install.missing=true", function()
      local result = config_mod.normalize {}
      assert.is_table(result.install)
      assert.is_true(result.install.missing)
    end)

    it("applies install.missing=false", function()
      local result = config_mod.normalize {
        install = { missing = false },
      }
      assert.is_false(result.install.missing)
    end)

    -- updates: cooldown_s, concurrency

    it("returns default cooldown_s=0", function()
      local result = config_mod.normalize {}
      assert.equal(0, result.updates.cooldown_s)
    end)

    it("applies cooldown_s override", function()
      local result = config_mod.normalize {
        updates = { cooldown_s = 3600 },
      }
      assert.equal(3600, result.updates.cooldown_s)
    end)

    it("validates cooldown_s minimum", function()
      config_mod.normalize {
        updates = { cooldown_s = -1 },
      }
      assert.truthy(#wez._logs.error > 0)
    end)

    it("returns default concurrency=nil", function()
      local result = config_mod.normalize {}
      assert.is_nil(result.updates.concurrency)
    end)

    it("applies concurrency override", function()
      local result = config_mod.normalize {
        updates = { concurrency = 4 },
      }
      assert.equal(4, result.updates.concurrency)
    end)

    -- icons (boolean|table union type)

    it("preserves icons=true (default)", function()
      local result = config_mod.normalize {}
      assert.is_true(result.ui.icons)
    end)

    it("preserves icons=false", function()
      local result = config_mod.normalize {
        ui = { icons = false },
      }
      assert.is_false(result.ui.icons)
    end)

    it("preserves icons as table", function()
      local result = config_mod.normalize {
        ui = { icons = { plugin_enabled = "●" } },
      }
      assert.is_table(result.ui.icons)
      assert.equal("●", result.ui.icons.plugin_enabled)
    end)

    it("rejects icons as non-boolean/table", function()
      config_mod.normalize {
        ui = { icons = 42 },
      }
      assert.truthy(#wez._logs.error > 0)
    end)

    -- integrations.command_palette

    it("defaults command_palette to false", function()
      local result = config_mod.normalize {}
      assert.is_false(result.integrations.command_palette)
    end)

    it("applies command_palette=true", function()
      local result = config_mod.normalize {
        integrations = { command_palette = true },
      }
      assert.is_true(result.integrations.command_palette)
    end)

    -- multiple validation errors

    it("accumulates multiple validation errors", function()
      config_mod.normalize {
        log_level = 42,
        updates = { interval_hours = -5 },
      }
      -- at least 2 errors (bad log_level type + bad interval_hours)
      assert.truthy(#wez._logs.error >= 2)
    end)
  end)
end)
