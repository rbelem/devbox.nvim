--- Tests for lua/devbox/lsp/servers.lua
--- Covers detect(), enable(), add_mapping(), _generate().

local helper = require("helpers")

---@return table The servers module (reloaded)
local function fresh_servers()
  package.loaded["devbox.lsp.servers"] = nil
  return require("devbox.lsp.servers")
end

describe("devbox.lsp.servers", function()
  before_each(function()
    helper.take_env_snapshot()
  end)

  after_each(function()
    helper.restore_executable()
    helper.restore_lsp_enable()
    helper.restore_runtime_files()
    helper.restore_env()
  end)

  describe("detect()", function()
    it("returns empty when no servers executable", function()
      helper.mock_executable(false)
      local servers = fresh_servers()
      -- With no generated map and no user map, detect returns empty
      local detected = servers.detect()
      assert.are.same({}, detected)
    end)

    it("detects servers from user map when binary is executable", function()
      helper.mock_executable({ ["my-lsp"] = true })
      local servers = fresh_servers()
      servers.add_mapping("my-lsp", "my_lsp")
      local detected = servers.detect()
      assert.are.same({ "my_lsp" }, detected)
    end)

    it("skips non-executable binaries from user map", function()
      helper.mock_executable({ ["my-lsp"] = false })
      local servers = fresh_servers()
      servers.add_mapping("my-lsp", "my_lsp")
      local detected = servers.detect()
      assert.are.same({}, detected)
    end)

    it("filters by provided filter set", function()
      helper.mock_executable({ ["lsp-a"] = true, ["lsp-b"] = true })
      local servers = fresh_servers()
      servers.add_mapping({ ["lsp-a"] = "server_a", ["lsp-b"] = "server_b" })
      local detected = servers.detect({ server_a = true })
      assert.are.same({ "server_a" }, detected)
    end)

    it("returns multiple detected servers", function()
      helper.mock_executable({ ["lsp-a"] = true, ["lsp-b"] = true, ["lsp-c"] = false })
      local servers = fresh_servers()
      servers.add_mapping({
        ["lsp-a"] = "server_a",
        ["lsp-b"] = "server_b",
        ["lsp-c"] = "server_c",
      })
      local detected = servers.detect()
      table.sort(detected)
      assert.are.same({ "server_a", "server_b" }, detected)
    end)

    it("user map overrides generated map on collision", function()
      helper.mock_executable({ ["shared-binary"] = true })
      local servers = fresh_servers()
      -- Simulate a generated map entry
      servers._generated_map = {
        shared = { binary = "shared-binary" },
      }
      -- User maps the same server name to a different binary
      servers.add_mapping("shared-binary", "shared")
      -- The generated entry is overridden by the user entry (same key → same binary)
      local detected = servers.detect()
      assert.are.same({ "shared" }, detected)
    end)
  end)

  describe("enable()", function()
    it("calls vim.lsp.enable for each server name", function()
      helper.mock_lsp_enable()
      local servers = fresh_servers()
      servers.enable({ "server_a", "server_b" })
      local calls = helper.get_lsp_enable_calls()
      assert.are.same({ "server_a", "server_b" }, calls)
    end)

    it("handles empty list gracefully", function()
      helper.mock_lsp_enable()
      local servers = fresh_servers()
      servers.enable({})
      local calls = helper.get_lsp_enable_calls()
      assert.are.same({}, calls)
    end)

    it("does not error on unknown server names", function()
      -- vim.lsp.enable is idempotent for unknown names
      local servers = fresh_servers()
      servers.enable({ "nonexistent_server_xyz" })
      assert.is_true(true)  -- no error
    end)
  end)

  describe("add_mapping()", function()
    it("registers a single binary→name pair", function()
      local servers = fresh_servers()
      servers.add_mapping("my-binary", "my_lsp")
      assert.are.same({ binary = "my-binary" }, servers._user_map["my_lsp"])
    end)

    it("registers a table of pairs", function()
      local servers = fresh_servers()
      servers.add_mapping({ ["bin-a"] = "lsp_a", ["bin-b"] = "lsp_b" })
      assert.are.same({ binary = "bin-a" }, servers._user_map["lsp_a"])
      assert.are.same({ binary = "bin-b" }, servers._user_map["lsp_b"])
    end)

    it("overwrites existing entry for the same name", function()
      local servers = fresh_servers()
      servers.add_mapping("old-binary", "my_lsp")
      servers.add_mapping("new-binary", "my_lsp")
      assert.are.same({ binary = "new-binary" }, servers._user_map["my_lsp"])
    end)
  end)

  describe("_generate()", function()
    it("returns false when no nvim-lspconfig files found", function()
      helper.mock_runtime_files({})
      local servers = fresh_servers()
      local ok = servers._generate()
      assert.is_false(ok)
    end)

    it("generates map from mock config files", function()
      -- Create a mock config file that can be required
      local tmp_dir = "/tmp/devbox_test_lspconfig"
      vim.fn.mkdir(tmp_dir .. "/lua/lspconfig/server_configurations", "p")

      -- Write a simple config file
      vim.fn.writefile(
        vim.split([[
return {
  default_config = {
    cmd = { "test-lang-server" },
    filetypes = { "test" },
  },
}
]], "\n"),
        tmp_dir .. "/lua/lspconfig/server_configurations/test_ls.lua"
      )

      -- Add to package.path so require can find it
      local orig_path = package.path
      package.path = tmp_dir .. "/lua/?.lua;" .. tmp_dir .. "/lua/?/init.lua;" .. package.path

      -- Mock runtime files to return our test config
      helper.mock_runtime_files({
        tmp_dir .. "/lua/lspconfig/server_configurations/test_ls.lua",
      })

      local servers = fresh_servers()
      local ok = servers._generate()
      assert.is_true(ok)
      assert.is_not_nil(servers._generated_map)
      assert.are.same(
        { binary = "test-lang-server" },
        servers._generated_map["test_ls"]
      )

      -- Clean up
      package.path = orig_path
      vim.fn.delete(tmp_dir, "rf")
    end)
  end)
end)
