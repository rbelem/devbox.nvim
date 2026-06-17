--- Tests for lua/devbox/lsp.lua
--- Covers make_lsp_env() with various activation states.

local helper = require("helpers")

describe("devbox.lsp", function()
  local tmpdir

  before_each(function()
    helper.take_env_snapshot()
    tmpdir = helper.temp_project(true)
  end)

  after_each(function()
    helper.restore_jobstart()
    helper.restore_executable()
    helper.restore_env()
    helper.rmdir(tmpdir)
  end)

  --- Helper: activate devbox via mocked shellenv.
  --- Asserts activation completes.
  ---@param devbox_mod table
  local function activate_via_mock(devbox_mod)
    helper.mock_executable(true)
    helper.mock_jobstart({
      "export PATH=/devbox/bin:/usr/bin",
      "export JAVA_HOME=/opt/java",
    }, 0)

    local ok = devbox_mod.activate(tmpdir)
    if ok then
      -- cache hit
      assert.is_true(devbox_mod.is_active())
    else
      -- cache miss: wait for async load
      local waited = vim.wait(1000, function() return not devbox_mod.is_loading() end)
      assert.is_true(waited, "timeout waiting for async activation")
      assert.is_true(devbox_mod.is_active(), "devbox should be active after mock activation")
    end
  end

  describe("make_lsp_env()", function()
    it("returns nil when devbox is not active", function()
      local devbox = helper.reload_plugin({ notify = "silent" })

      -- Don't activate — state is inactive
      local lsp = require("devbox.lsp")
      local env = lsp.make_lsp_env()

      assert.is_nil(env)
    end)

    it("returns env table with devbox PATH when active", function()
      local devbox = helper.reload_plugin({ notify = "silent" })
      activate_via_mock(devbox)

      local lsp = require("devbox.lsp")
      local env = lsp.make_lsp_env()

      assert.is_not_nil(env)
      assert.is_not_nil(env.PATH)
      -- PATH should contain our devbox path
      assert.is_true(env.PATH:find("/devbox/bin", 1, true) ~= nil)
    end)

    it("includes DEVBOX_PROJECT_ROOT when active", function()
      local devbox = helper.reload_plugin({ notify = "silent" })
      activate_via_mock(devbox)

      local lsp = require("devbox.lsp")
      local env = lsp.make_lsp_env()

      assert.is_not_nil(env)
      assert.are.equal(tmpdir, env.DEVBOX_PROJECT_ROOT)
    end)

    it("returns a deep copy (mutating result doesn't affect vim.env)", function()
      local devbox = helper.reload_plugin({ notify = "silent" })
      activate_via_mock(devbox)

      local lsp = require("devbox.lsp")
      local env = lsp.make_lsp_env()

      local orig_path = env.PATH
      env.PATH = "/hacked"
      -- vim.env should be unchanged
      assert.is_not_nil(vim.env.PATH)
      assert.are.not_equal("/hacked", vim.env.PATH)
    end)
  end)
end)
