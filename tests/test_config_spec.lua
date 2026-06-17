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
      notify = "default",
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
      assert.is_true(config.options.auto_activate)
    end)

    it("returns options with defaults when called with empty table", function()
      local config = require("devbox.config")
      config.setup({})
      assert.is_true(config.options.auto_activate)
    end)

    it("merges user opts, overriding defaults", function()
      local config = require("devbox.config")
      config.setup({ notify = "statusline", auto_activate = false })
      assert.are.equal("statusline", config.options.notify)
      assert.is_false(config.options.auto_activate)
    end)

    it("merges nested lsp table", function()
      local config = require("devbox.config")
      config.setup({ lsp = { inject_env = false } })
      assert.is_false(config.options.lsp.inject_env)
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

    it("honours custom notify mode", function()
      local config = require("devbox.config")
      config.setup({ notify = "statusline" })
      assert.are.equal("statusline", config.options.notify)
    end)

    it("honours 'progress' notify mode", function()
      local config = require("devbox.config")
      config.setup({ notify = "progress" })
      assert.are.equal("progress", config.options.notify)
    end)

    it("honours 'silent' notify mode", function()
      local config = require("devbox.config")
      config.setup({ notify = "silent" })
      assert.are.equal("silent", config.options.notify)
    end)
  end)
end)
