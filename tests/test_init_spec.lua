--- Tests for lua/devbox/init.lua
--- Covers: find_root, available, _is_excluded, _parse_shellenv,
---         activate, _apply_env, _inject_path, clear_cache.

local helper = require("helpers")

-- ── Helpers ──

--- Reload plugin and return the module.
---@param opts? table
---@return table
local function fresh(opts)
  return helper.reload_plugin(opts)
end

-- ═══════════════════════════════════════════════════════════════
-- find_root
-- ═══════════════════════════════════════════════════════════════

describe("Devbox.find_root", function()
  local tmpdir_with, tmpdir_without

  before_each(function()
    helper.take_env_snapshot()
    fresh()
    tmpdir_with = helper.temp_project(true)
    tmpdir_without = helper.temp_project(false)
  end)

  after_each(function()
    helper.rmdir(tmpdir_with)
    helper.rmdir(tmpdir_without)
    helper.restore_env()
  end)

  it("returns the project root when devbox.json exists", function()
    local devbox = require("devbox")
    local root = devbox.find_root(tmpdir_with)
    assert.is_not_nil(root)
    -- should normalize to absolute path
    assert.are.equal(tmpdir_with, root)
  end)

  it("returns nil when no devbox.json in tree", function()
    local devbox = require("devbox")
    local root = devbox.find_root(tmpdir_without)
    assert.is_nil(root)
  end)

  it("finds root from a subdirectory", function()
    -- Create a/b/c/ under tmpdir_with, call find_root from c/
    local sub = tmpdir_with .. "/a/b/c"
    vim.fn.mkdir(sub, "p")
    local devbox = require("devbox")
    local root = devbox.find_root(sub)
    assert.are.equal(tmpdir_with, root)
  end)

  it("returns nil from a directory outside any project", function()
    local devbox = require("devbox")
    -- /tmp is unlikely to have devbox.json
    local root = devbox.find_root("/tmp")
    assert.is_nil(root)
  end)
end)

-- ═══════════════════════════════════════════════════════════════
-- available
-- ═══════════════════════════════════════════════════════════════

describe("Devbox.available", function()
  before_each(function()
    helper.take_env_snapshot()
    fresh()
  end)

  after_each(function()
    helper.restore_executable()
    helper.restore_env()
  end)

  it("returns true when devbox binary exists", function()
    helper.mock_executable(true)
    local devbox = require("devbox")
    assert.is_true(devbox.available())
  end)

  it("returns false when devbox binary not found", function()
    helper.mock_executable(false)
    local devbox = require("devbox")
    assert.is_false(devbox.available())
  end)

  it("caches the result after first call", function()
    helper.mock_executable(true)
    local devbox = require("devbox")
    devbox.available()
    -- change mock after first call
    helper.mock_executable(false)
    -- should still return the cached true
    assert.is_true(devbox.available())
  end)
end)

-- ═══════════════════════════════════════════════════════════════
-- _is_excluded
-- ═══════════════════════════════════════════════════════════════

describe("Devbox._is_excluded", function()
  before_each(function()
    helper.take_env_snapshot()
    fresh()
  end)

  after_each(function()
    helper.restore_env()
  end)

  it("excludes BASH_ vars by default", function()
    local devbox = require("devbox")
    assert.is_true(devbox._is_excluded("BASH_FUNC_foo"))
  end)

  it("excludes SHELL vars by default", function()
    local devbox = require("devbox")
    assert.is_true(devbox._is_excluded("SHELL"))
  end)

  it("excludes HIST vars by default", function()
    local devbox = require("devbox")
    assert.is_true(devbox._is_excluded("HISTSIZE"))
  end)

  it("excludes PROMPT vars by default", function()
    local devbox = require("devbox")
    assert.is_true(devbox._is_excluded("PROMPT_COMMAND"))
  end)

  it("excludes TERM by default", function()
    local devbox = require("devbox")
    assert.is_true(devbox._is_excluded("TERM"))
  end)

  it("allows PATH through", function()
    local devbox = require("devbox")
    assert.is_false(devbox._is_excluded("PATH"))
  end)

  it("allows arbitrary project vars through", function()
    local devbox = require("devbox")
    assert.is_false(devbox._is_excluded("JAVA_HOME"))
    assert.is_false(devbox._is_excluded("GOPATH"))
    assert.is_false(devbox._is_excluded("NODE_ENV"))
  end)

  it("respects custom exclude_env patterns", function()
    fresh({ exclude_env = { "^MYAPP_" } })
    local devbox = require("devbox")
    assert.is_true(devbox._is_excluded("MYAPP_SECRET"))
    -- default patterns are gone when user overrides
    assert.is_false(devbox._is_excluded("BASH_FUNC_foo"))
  end)
end)

-- ═══════════════════════════════════════════════════════════════
-- _parse_shellenv
-- ═══════════════════════════════════════════════════════════════

describe("Devbox._parse_shellenv", function()
  before_each(function()
    helper.take_env_snapshot()
    fresh()
  end)

  after_each(function()
    helper.restore_env()
  end)

  it("parses a single export line", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv('export FOO=bar\n')
    assert.are.equal("bar", result.vars["FOO"])
  end)

  it("parses multiple export lines", function()
    local devbox = require("devbox")
    local raw = 'export FOO=bar\nexport BAZ=qux\nexport HELLO=world\n'
    local result = devbox._parse_shellenv(raw)
    assert.are.equal("bar", result.vars["FOO"])
    assert.are.equal("qux", result.vars["BAZ"])
    assert.are.equal("world", result.vars["HELLO"])
  end)

  it("parses values with equals signs", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv('export PGPASS=host=localhost port=5432\n')
    -- Current parser is naive — first '=' splits key/value
    assert.are.equal("host=localhost port=5432", result.vars["PGPASS"])
  end)

  it("handles quoted values", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv('export FOO="some value"\n')
    assert.are.equal("some value", result.vars["FOO"])
  end)

  it("handles empty values", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv('export FOO=\n')
    assert.is_not_nil(result.vars["FOO"])
    assert.are.equal("", result.vars["FOO"])
  end)

  it("filters excluded vars", function()
    local devbox = require("devbox")
    local raw = 'export PATH=/usr/bin\nexport BASH_FUNC_foo=()\nexport JAVA_HOME=/opt/java\n'
    local result = devbox._parse_shellenv(raw)
    -- PATH and JAVA_HOME survive
    assert.are.equal("/usr/bin", result.vars["PATH"])
    assert.are.equal("/opt/java", result.vars["JAVA_HOME"])
    -- BASH_FUNC_foo is excluded
    assert.is_nil(result.vars["BASH_FUNC_foo"])
  end)

  it("replaces escaped quotes", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv('export FOO="he\\"llo"\n')
    assert.are.equal('he"llo', result.vars["FOO"])
  end)

  it("handles special characters in values", function()
    local devbox = require("devbox")
    local raw = 'export PATH=/usr/bin:/custom/path\nexport PS1="\\\\w \\\\$ "\n'
    local result = devbox._parse_shellenv(raw)
    assert.are.equal("/usr/bin:/custom/path", result.vars["PATH"])
    -- PS1 is NOT excluded (no default pattern matches "PS"), but verify value parsed
    assert.are.equal("\\w \\$ ", result.vars["PS1"])
  end)

  it("handles PATH with trailing colons", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv('export PATH=/devbox/bin:/usr/bin:\n')
    -- verify colons survive
    assert.are.equal("/devbox/bin:/usr/bin:", result.vars["PATH"])
  end)

  it("handles values with semicolons", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv('export FOO="a;b;c"\n')
    assert.are.equal("a;b;c", result.vars["FOO"])
  end)

  it("handles values that contain 'export' substring", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv('export FOO="some export value"\n')
    assert.are.equal("some export value", result.vars["FOO"])
  end)

  it("returns empty vars for empty input", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv("")
    assert.are.same({}, result.vars)
  end)

  it("returns empty vars for input with only excluded lines", function()
    local devbox = require("devbox")
    local result = devbox._parse_shellenv("export BASH_FUNC_foo=()\nexport HISTFILE=/dev/null\n")
    assert.are.same({}, result.vars)
  end)
end)

-- ═══════════════════════════════════════════════════════════════
-- _apply_env
-- ═══════════════════════════════════════════════════════════════

describe("Devbox._apply_env", function()
  before_each(function()
    helper.take_env_snapshot()
    fresh()
  end)

  after_each(function()
    helper.restore_env()
  end)

  it("sets vars from parsed env into vim.env", function()
    local devbox = require("devbox")
    local env = {
      vars = { PATH = "/devbox/bin:/usr/bin", JAVA_HOME = "/opt/java" },
      project_root = "/tmp/test_project",
      path = "/devbox/bin:/usr/bin",
    }
    devbox._apply_env(env)
    assert.are.equal("/devbox/bin:/usr/bin", vim.env.PATH)
    assert.are.equal("/opt/java", vim.env.JAVA_HOME)
  end)

end)

-- ═══════════════════════════════════════════════════════════════
-- activate
-- ═══════════════════════════════════════════════════════════════

describe("Devbox.activate", function()
  local tmpdir

  --- Activate into tmpdir with mocked devbox shellenv output.
  --- Handles both cache-miss (first activate) and cache-hit (re-activate).
  ---@param devbox table
  ---@param extra_vars? table additional vars to inject into mock output
  local function activate_mocked(devbox, extra_vars)
    local lines = {
      "export PATH=/devbox/test/bin:/usr/bin",
      "export JAVA_HOME=/opt/java",
    }
    if extra_vars then
      for k, v in pairs(extra_vars) do
        table.insert(lines, "export " .. k .. "=" .. v)
      end
    end
    helper.mock_jobstart(lines, 0)
    local ok = devbox.activate(tmpdir)
    if ok then
      -- cache hit: active immediately
      assert.is_true(devbox.is_active())
    else
      -- cache miss: wait for async load
      vim.wait(500, function() return not devbox.is_loading() end)
      assert.is_true(devbox.is_active())
    end
  end

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

  it("returns false when devbox binary is missing", function()
    helper.mock_executable(false)
    helper.mock_jobstart({}, 0)
    local devbox = fresh()
    local ok = devbox.activate(tmpdir)
    assert.is_false(ok)
  end)

  it("returns false when no devbox.json found", function()
    helper.mock_executable(true)
    local devbox = fresh()
    local ok = devbox.activate("/nonexistent")
    assert.is_false(ok)
  end)

  it("returns false on cache miss, then becomes active after async load", function()
    helper.mock_executable(true)
    local devbox = fresh()
    helper.mock_jobstart({
      "export PATH=/devbox/test/bin:/usr/bin",
      "export FOO=bar",
    }, 0)

    local ok = devbox.activate(tmpdir)
    -- Cache miss → returns false immediately
    assert.is_false(ok)
    assert.is_true(devbox.is_loading())

    -- Wait for mocked jobstart to fire on_exit
    vim.wait(500, function() return not devbox.is_loading() end)

    assert.is_true(devbox.is_active())
    assert.are.equal(tmpdir, devbox.get_active_root())
    assert.are.equal("/devbox/test/bin:/usr/bin", vim.env.PATH)
    assert.are.equal("bar", vim.env.FOO)
  end)

  it("returns true on disk cache hit (instant activation)", function()
    helper.mock_executable(true)
    -- prime the disk cache via a first activation
    local devbox1 = fresh()
    activate_mocked(devbox1)

    -- fresh module — no in-memory cache, but disk cache exists
    -- mock jobstart again so background refresh doesn't call the real one
    helper.mock_jobstart({ "export PATH=/devbox/test/bin:/usr/bin" }, 0)
    local devbox2 = fresh()
    local ok = devbox2.activate(tmpdir)
    -- Should return true (disk cache hit)
    assert.is_true(ok)
    assert.is_true(devbox2.is_active())
    assert.are.equal(tmpdir, devbox2.get_active_root())
    -- PATH should be applied from cache
    assert.is_true(vim.env.PATH:find("/devbox/test/bin", 1, true) ~= nil)
  end)

  it("activation from a subdir finds root with devbox.json", function()
    helper.mock_executable(true)
    local sub = tmpdir .. "/inner/sub"
    vim.fn.mkdir(sub, "p")
    local devbox = fresh()
    helper.mock_jobstart({
      "export PATH=/devbox/sub/bin:/usr/bin",
    }, 0)
    devbox.activate(sub)
    vim.wait(500, function() return not devbox.is_loading() end)
    assert.is_true(devbox.is_active())
    assert.are.equal(tmpdir, devbox.get_active_root())
  end)

  it("two overlapping activations resolve _loading correctly", function()
    helper.mock_executable(true)
    local devbox = fresh()

    -- First call: cache miss → starts async load (gen=1)
    helper.mock_jobstart({ "export PATH=/devbox/test/bin:/usr/bin" }, 0)
    local ok1 = devbox.activate(tmpdir)
    assert.is_false(ok1) -- cache miss
    assert.is_true(devbox.is_loading())

    -- Clear cache so second activate also misses
    devbox.clear_cache(tmpdir)

    -- Second call: cache miss → starts second async load (gen=2)
    helper.mock_jobstart({ "export PATH=/devbox/test/bin:/usr/bin" }, 0)
    local ok2 = devbox.activate(tmpdir)
    assert.is_false(ok2)
    assert.is_true(devbox.is_loading())

    -- Both on_exit callbacks are scheduled; wait for loading to finish
    vim.wait(500, function() return not devbox.is_loading() end)

    -- _loading must be false after all callbacks fire
    assert.is_false(devbox.is_loading())
    assert.is_true(devbox.is_active())
    assert.are.equal(tmpdir, devbox.get_active_root())
  end)
end)

-- ═══════════════════════════════════════════════════════════════
-- _inject_path (LSP integration)
-- ═══════════════════════════════════════════════════════════════

describe("Devbox._inject_path", function()
  local tmpdir

  local function activate_mocked(devbox)
    helper.mock_jobstart({
      "export PATH=/devbox/bin:/usr/bin",
    }, 0)
    devbox.activate(tmpdir)
    vim.wait(500, function() return not devbox.is_loading() end)
  end

  before_each(function()
    helper.take_env_snapshot()
    helper.mock_executable(true)
    tmpdir = helper.temp_project(true)
  end)

  after_each(function()
    helper.restore_jobstart()
    helper.restore_executable()
    helper.restore_env()
    helper.rmdir(tmpdir)
  end)

  it("prepends devbox PATH to client.cmd_env when active", function()
    local devbox = fresh()
    activate_mocked(devbox)

    -- Client with a clean PATH (no devbox) — triggers injection
    local client = { config = { cmd_env = { PATH = "/original/bin" } } }
    devbox._inject_path(client)

    assert.is_not_nil(client.config.cmd_env)
    assert.is_true(
      client.config.cmd_env.PATH:find("/devbox/bin", 1, true) ~= nil,
      "expected devbox PATH in client.cmd_env.PATH"
    )
    -- Original PATH preserved after devbox portion
    assert.is_true(
      client.config.cmd_env.PATH:find("/original/bin", 1, true) ~= nil,
      "expected original PATH preserved"
    )
  end)

  it("is a noop when devbox is not active", function()
    local devbox = fresh()
    -- No activation

    local client = { config = {} }
    devbox._inject_path(client)
    -- no active root → get_path() returns "" → no injection
    assert.is_nil(client.config.cmd_env)
  end)

  it("does not duplicate devbox PATH if already present", function()
    local devbox = fresh()
    activate_mocked(devbox)

    local client = {
      config = {
        cmd_env = { PATH = "/devbox/bin:/usr/bin" },
      },
    }
    devbox._inject_path(client)
    -- Should still be just once
    local count = 0
    for _ in client.config.cmd_env.PATH:gmatch("/devbox/bin") do
      count = count + 1
    end
    assert.are.equal(1, count)
  end)

  it("handles nil client gracefully", function()
    local devbox = require("devbox")
    devbox._inject_path(nil)
    assert.is_true(true)
  end)

  it("handles client with nil config gracefully", function()
    local devbox = require("devbox")
    devbox._inject_path({})
    assert.is_true(true)
  end)
end)

-- ═══════════════════════════════════════════════════════════════
-- clear_cache
-- ═══════════════════════════════════════════════════════════════

describe("Devbox.clear_cache", function()
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

  it("clearing cache then activating triggers an async reload (cache miss)", function()
    helper.mock_executable(true)
    helper.mock_jobstart({
      "export PATH=/devbox/bin:/usr/bin",
    }, 0)

    local devbox = fresh()
    -- activate to populate cache
    devbox.activate(tmpdir)
    vim.wait(500, function() return not devbox.is_loading() end)
    assert.is_true(devbox.is_active())

    -- clear just this project's cache
    devbox.clear_cache(tmpdir)

    -- suppress the in-memory cache by using a fresh module
    -- (clear_cache cleared disk cache too, so fresh module will miss)
    local devbox2 = fresh()
    helper.mock_executable(true)
    helper.mock_jobstart({
      "export PATH=/devbox/bin:/usr/bin",
    }, 0)

    local ok = devbox2.activate(tmpdir)
    -- Returning false = cache miss (async load started)
    assert.is_false(ok)
  end)

  it("does not error when clearing non-existent project", function()
    local devbox = require("devbox")
    devbox.clear_cache("/nonexistent/project")
    assert.is_true(true)
  end)

  it("clearing all cache does not affect active state", function()
    local devbox = require("devbox")
    -- no activation, just verify the API works
    devbox.clear_cache()
    assert.is_false(devbox.is_active())
  end)
end)

-- ═══════════════════════════════════════════════════════════════
-- _notify — notification routing
-- ═══════════════════════════════════════════════════════════════

describe("Devbox._notify", function()
  before_each(function()
    helper.take_env_snapshot()
    helper.mock_notify()
  end)

  after_each(function()
    helper.restore_notify()
    helper.restore_env()
  end)

  it("default mode calls vim.notify", function()
    local devbox = helper.reload_plugin({ notify = "default" })
    devbox._notify("hello", vim.log.levels.INFO)
    assert.are.equal(1, #helper._notify_calls)
    assert.are.equal("hello", helper._notify_calls[1].msg)
    assert.is_nil(helper._notify_calls[1].once)
  end)

  it("default mode with once calls vim.notify_once", function()
    local devbox = helper.reload_plugin({ notify = "default" })
    devbox._notify("once msg", vim.log.levels.INFO, { once = true })
    assert.are.equal(1, #helper._notify_calls)
    assert.are.equal("once msg", helper._notify_calls[1].msg)
    assert.is_true(helper._notify_calls[1].once)
  end)

  it("silent mode does nothing", function()
    local devbox = helper.reload_plugin({ notify = "silent" })
    devbox._notify("should not appear", vim.log.levels.WARN)
    devbox._notify("nor this", vim.log.levels.INFO)
    assert.are.equal(0, #helper._notify_calls)
    assert.are.equal(0, #helper._echo_calls)
  end)

  it("statusline mode suppresses non-forced calls", function()
    local devbox = helper.reload_plugin({ notify = "statusline" })
    devbox._notify("background noise", vim.log.levels.INFO)
    assert.are.equal(0, #helper._notify_calls)
    assert.are.equal(0, #helper._echo_calls)
  end)

  it("statusline mode allows forced calls (user commands)", function()
    local devbox = helper.reload_plugin({ notify = "statusline" })
    devbox._notify("devbox status", vim.log.levels.INFO, { force = true })
    assert.are.equal(1, #helper._notify_calls)
    assert.are.equal("devbox status", helper._notify_calls[1].msg)
  end)

  it("progress mode calls nvim_echo", function()
    local devbox = helper.reload_plugin({ notify = "progress" })
    devbox._notify("loading...", vim.log.levels.INFO)
    assert.are.equal(0, #helper._notify_calls)
    assert.are.equal(1, #helper._echo_calls)
    assert.matches("loading", helper._echo_calls[1].chunks[1][1] or "")
  end)

  it("progress mode uses WarningMsg for WARN level", function()
    local devbox = helper.reload_plugin({ notify = "progress" })
    devbox._notify("oops", vim.log.levels.WARN)
    assert.are.equal(1, #helper._echo_calls)
    assert.are.equal("WarningMsg", helper._echo_calls[1].chunks[1][2])
  end)

  it("progress mode uses MoreMsg for INFO level", function()
    local devbox = helper.reload_plugin({ notify = "progress" })
    devbox._notify("info", vim.log.levels.INFO)
    assert.are.equal(1, #helper._echo_calls)
    assert.are.equal("MoreMsg", helper._echo_calls[1].chunks[1][2])
  end)
end)

-- ═══════════════════════════════════════════════════════════════
-- is_active / is_loading / get_active_root / get_path
-- ═══════════════════════════════════════════════════════════════

describe("Devbox state accessors", function()
  before_each(function()
    helper.take_env_snapshot()
    fresh()
  end)

  after_each(function()
    helper.restore_env()
  end)

  it("is_active returns false initially", function()
    local devbox = require("devbox")
    assert.is_false(devbox.is_active())
  end)

  it("is_loading returns false initially", function()
    local devbox = require("devbox")
    assert.is_false(devbox.is_loading())
  end)

  it("get_active_root returns nil initially", function()
    local devbox = require("devbox")
    assert.is_nil(devbox.get_active_root())
  end)

  it("get_path returns empty string initially", function()
    local devbox = require("devbox")
    assert.are.equal("", devbox.get_path())
  end)
end)

-- ═══════════════════════════════════════════════════════════════
-- auto_enable integration
-- ═══════════════════════════════════════════════════════════════

describe("Devbox auto_enable", function()
  local tmpdir

  before_each(function()
    helper.take_env_snapshot()
    helper.mock_lspconfig()  -- make pcall(require, "lspconfig") succeed
    tmpdir = helper.temp_project(true)
  end)

  after_each(function()
    helper.restore_jobstart()
    helper.restore_executable()
    helper.restore_lspconfig()
    helper.restore_env()
    helper.rmdir(tmpdir)
  end)

  it("does not enable servers when auto_enable is false (default)", function()
    helper.mock_executable(true)
    local devbox = fresh({ lsp = { auto_enable = false, inject_env = true } })

    helper.mock_jobstart({
      "export PATH=/devbox/bin:/usr/bin",
    }, 0)
    devbox.activate(tmpdir)
    vim.wait(500, function() return not devbox.is_loading() end)

    -- No servers should have been enabled
    assert.is_false(vim.lsp.is_enabled("lua_ls"))
  end)

  it("enables detected servers when auto_enable is true", function()
    helper.mock_executable({
      ["lua-language-server"] = true,
      ["typescript-language-server"] = false,
    })
    local devbox = fresh({ lsp = { auto_enable = true, inject_env = true } })

    -- Register a mapping so detect() finds something
    local servers = require("devbox.lsp.servers")
    servers._generated_map = {}
    servers.add_mapping("lua-language-server", "lua_ls")
    servers.add_mapping("typescript-language-server", "ts_ls")

    -- Use cache-hit path: prime the cache via first activation, then re-activate
    -- to exercise the sync path which calls _apply_env inline
    helper.mock_jobstart({
      "export PATH=/devbox/bin:/usr/bin",
    }, 0)
    devbox.activate(tmpdir)

    -- Manually call _apply_env to simulate the activation applying env
    local test_env = {
      vars = { PATH = "/devbox/bin:/usr/bin" },
      project_root = tmpdir,
      path = "/devbox/bin:/usr/bin",
    }
    devbox._apply_env(test_env)

    assert.is_true(vim.lsp.is_enabled("lua_ls"), "lua_ls should be enabled")
    assert.is_false(vim.lsp.is_enabled("ts_ls"), "ts_ls should NOT be enabled")
  end)

  it("respects auto_enable_filter", function()
    helper.mock_executable({
      ["lua-language-server"] = true,
      ["typescript-language-server"] = true,
    })
    local devbox = fresh({
      lsp = {
        auto_enable = true,
        auto_enable_filter = { "lua_ls" },
        inject_env = true,
      },
    })

    local servers = require("devbox.lsp.servers")
    servers._generated_map = {}
    servers.add_mapping("lua-language-server", "lua_ls")
    servers.add_mapping("typescript-language-server", "ts_ls")

    local test_env = {
      vars = { PATH = "/devbox/bin:/usr/bin" },
      project_root = tmpdir,
      path = "/devbox/bin:/usr/bin",
    }
    devbox._apply_env(test_env)

    assert.is_true(vim.lsp.is_enabled("lua_ls"), "lua_ls should be enabled")
    assert.is_false(vim.lsp.is_enabled("ts_ls"), "ts_ls should be filtered out")
  end)

  it("does not error when nvim-lspconfig is not installed", function()
    -- Remove our mock so pcall(require, "lspconfig") fails
    package.loaded["lspconfig"] = nil

    helper.mock_executable(true)
    local devbox = fresh({ lsp = { auto_enable = true, inject_env = true } })

    helper.mock_jobstart({
      "export PATH=/devbox/bin:/usr/bin",
    }, 0)
    devbox.activate(tmpdir)
    vim.wait(500, function() return not devbox.is_loading() end)

    -- No errors should occur; just disabled
    assert.is_true(true)
  end)

  it("calling _maybe_auto_enable directly enables servers", function()
    helper.mock_executable({ ["lua-language-server"] = true })
    local devbox = fresh({ lsp = { auto_enable = true, inject_env = true } })

    local servers = require("devbox.lsp.servers")
    servers.add_mapping("lua-language-server", "lua_ls")

    -- Manually call the auto-enable function (simulates what activation does)
    local count = devbox._maybe_auto_enable()
    assert.are.equal(1, count, "should detect 1 server")

    -- Check via vim.lsp.is_enabled
    assert.is_true(vim.lsp.is_enabled("lua_ls"), "lua_ls should be enabled")
  end)

  it("triggers auto-enable on cache hit path", function()
    helper.mock_executable({ ["lua-language-server"] = true })
    local devbox = fresh({ lsp = { auto_enable = true, inject_env = true } })

    local servers = require("devbox.lsp.servers")
    servers._generated_map = {}
    servers.add_mapping("lua-language-server", "lua_ls")

    -- Simulate a cache-hit activation: call _apply_env directly
    -- (this is what activate() does on the cache-hit path)
    local test_env = {
      vars = { PATH = "/devbox/bin:/usr/bin" },
      project_root = tmpdir,
      path = "/devbox/bin:/usr/bin",
    }
    devbox._apply_env(test_env)

    assert.is_true(vim.lsp.is_enabled("lua_ls"), "lua_ls should be enabled after _apply_env")
  end)
end)
