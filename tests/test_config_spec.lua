--- Tests for lua/devbox/config.lua
--- Verifies default values, opts merging, and immutability.

local helper = require("helpers")

describe("devbox.config", function()
  ---@type devbox.Config
  local defaults_shallow

  before_each(function()
    helper.take_env_snapshot()
    -- fresh module each test
    package.loaded["devbox.config"] = nil
    defaults_shallow = {
      auto_activate = true,
      update_env = true,
      strategy = "async",
      silent = false,
      devbox_path = "devbox",
      lsp = { inject_env = true },
      exclude_env = {
        "^ATUIN_", "^BLE_", "_PREEXEC_", "^BASH_",
        "^SHELL", "^TERM", "^LS_COLORS", "^HIST", "^PROMPT",
      },
    }
  end)

  after_each(function()
    helper.restore_env()
  end)

  describe("defaults", function()
    it("contains auto_activate = true", function()
      local config = require("devbox.config")
      assert.is_true(config.defaults.auto_activate)
    end)

    it("contains strategy = 'async'", function()
      local config = require("devbox.config")
      assert.are.equal("async", config.defaults.strategy)
    end)

    it("contains lsp.inject_env = true", function()
      local config = require("devbox.config")
      assert.is_true(config.defaults.lsp.inject_env)
    end)

    it("contains the full exclude_env list", function()
      local config = require("devbox.config")
      assert.are.same(defaults_shallow.exclude_env, config.defaults.exclude_env)
    end)
  end)

  describe("setup()", function()
    it("returns options with defaults when called with nil", function()
      local config = require("devbox.config")
      config.setup(nil)
      assert.are.equal("async", config.options.strategy)
      assert.is_true(config.options.auto_activate)
    end)

    it("returns options with defaults when called with empty table", function()
      local config = require("devbox.config")
      config.setup({})
      assert.are.equal("async", config.options.strategy)
      assert.is_true(config.options.auto_activate)
    end)

    it("merges user opts, overriding defaults", function()
      local config = require("devbox.config")
      config.setup({ silent = true, auto_activate = false })
      assert.is_true(config.options.silent)
      assert.is_false(config.options.auto_activate)
      -- non-overridden field stays default
      assert.are.equal("async", config.options.strategy)
    end)

    it("merges nested lsp table", function()
      local config = require("devbox.config")
      config.setup({ lsp = { inject_env = false } })
      assert.is_false(config.options.lsp.inject_env)
    end)

    it("does not mutate the defaults table", function()
      local config = require("devbox.config")
      local orig_strategy = config.defaults.strategy
      config.setup({ strategy = "sync" })
      -- defaults unchanged
      assert.are.equal(orig_strategy, config.defaults.strategy)
      assert.are.equal("sync", config.options.strategy)
    end)

    it("accepts custom devbox_path", function()
      local config = require("devbox.config")
      config.setup({ devbox_path = "/custom/path/devbox" })
      assert.are.equal("/custom/path/devbox", config.options.devbox_path)
    end)

    it("replaces exclude_env when user provides custom patterns", function()
      local config = require("devbox.config")
      config.setup({ exclude_env = { "^CUSTOM_" } })
      assert.are.same({ "^CUSTOM_" }, config.options.exclude_env)
    end)
  end)
end)
