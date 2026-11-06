-- TESTS/diagnostics_spec.lua — `:RA diagnose`: what the report holds, what stays out of it, and that a
-- missing or broken sibling is a row, never an error.

return function(H)
  local eq, ok = H.eq, H.ok
  local diagnostics = require("runtime-analysis.diagnostics")

  -- ── siblings ───────────────────────────────────────────────────────────
  do
    local rows = diagnostics.siblings({ { name = "gone.nvim", probe = "ra_no_such_module" } })
    eq(rows[1].found, false, "a sibling that is not there is a row")
    eq(rows[1].error, nil, "and not an error")

    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/lua/ra_broken_probe", "p")
    vim.fn.writefile({ 'error("broken on purpose")' }, tmp .. "/lua/ra_broken_probe/init.lua")
    vim.opt.rtp:prepend(tmp)
    local ran, broken =
      pcall(diagnostics.siblings, { { name = "broken", probe = "ra_broken_probe" } })
    vim.opt.rtp:remove(tmp)
    package.loaded["ra_broken_probe"] = nil
    vim.fn.delete(tmp, "rf")
    ok(ran, "a sibling that fails to load does not raise: " .. tostring(broken))
    eq(broken[1].found, true, "it is found")
    ok(tostring(broken[1].error):find("broken on purpose", 1, true), "and the reason is named")
  end

  -- ── the commit, read from the files ────────────────────────────────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.git/refs/heads", "p")
    eq(diagnostics.commit_of(root), nil, "no HEAD, no commit")
    vim.fn.writefile({ "ref: refs/heads/main" }, root .. "/.git/HEAD")
    vim.fn.writefile({ "abcdef0123456789" }, root .. "/.git/refs/heads/main")
    eq(diagnostics.commit_of(root), "abcdef0", "a loose ref")
    vim.fn.delete(root .. "/.git/refs/heads/main")
    vim.fn.writefile({ "# pack-refs", "1234567890ab refs/heads/main" }, root .. "/.git/packed-refs")
    eq(diagnostics.commit_of(root), "1234567", "a packed ref")
    vim.fn.writefile({ "fedcba9876543210" }, root .. "/.git/HEAD")
    eq(diagnostics.commit_of(root), "fedcba9", "a detached HEAD")
    vim.fn.delete(root, "rf")
    eq(diagnostics.commit_of(root), nil, "no checkout, no commit")
  end

  -- ── mask ───────────────────────────────────────────────────────────────
  do
    local input =
      { split = "vsplit", api_token = "s3cret", nested = { Authorization = "s3cret", n = 1 } }
    local masked = diagnostics.mask(input)
    eq(masked.split, "vsplit", "an ordinary option stays")
    eq(masked.api_token, "<hidden>", "a token does not")
    eq(masked.nested.Authorization, "<hidden>", "at any depth, in any case")
    eq(masked.nested.n, 1, "next to it the rest stays")
    eq(input.api_token, "s3cret", "the input is not changed")
  end

  -- ── the report ─────────────────────────────────────────────────────────
  local names = {
    "runtime-analysis",
    "runtime-analysis.history",
    "runtime-analysis.env",
    "runtime-analysis.telemetry",
  }
  local saved = {}
  for _, name in ipairs(names) do
    saved[name] = package.loaded[name]
  end
  local started = false
  package.loaded["runtime-analysis"] = { opts = { split = "vsplit", token = "s3cret-option" } }
  package.loaded["runtime-analysis.history"] = {
    list = function()
      return { { url = "https://s3cret-url.example/x" }, { url = "https://s3cret-url.example/y" } }
    end,
  }
  package.loaded["runtime-analysis.env"] = {
    list_names = function()
      return { "dev", "prod" }
    end,
    current = function()
      return "dev"
    end,
    load_all = function()
      error("the report must not read the values of an environment")
    end,
  }
  package.loaded["runtime-analysis.telemetry"] = {
    instances = function()
      return {
        {
          namespace = "my.ns",
          is_running = function()
            return true
          end,
          start = function()
            started = true
          end,
          flush = function()
            started = true
          end,
        },
      }
    end,
    disabled = function()
      return { "off.ns" }
    end,
  }
  local ran, path, err = pcall(diagnostics.run)
  for _, name in ipairs(names) do
    package.loaded[name] = saved[name]
  end
  ok(ran, "the report builds: " .. tostring(path))
  ok(path, "and is written: " .. tostring(err))
  local text = table.concat(vim.fn.readfile(path), "\n")
  vim.fn.delete(vim.fs.dirname(path), "rf")

  for _, section in ipairs({
    "Environment",
    "Plugin",
    "Config",
    "Telemetry",
    "Cache",
    "Environments",
    "Siblings",
  }) do
    ok(text:find("== " .. section, 1, true), "section " .. section)
  end
  ok(text:find("my.ns", 1, true) and text:find("running", 1, true), "an instance with its state")
  ok(text:find("off.ns", 1, true), "a namespace disabled for good")
  ok(text:find("dev, prod", 1, true), "the names of the environments")
  ok(text:find("lib.nvim", 1, true), "the siblings")
  ok(text:find("entries of this project:%s+2"), "the size of the history")
  ok(not text:find("s3cret", 1, true), "no URL of the history and no secret option: " .. text)
  eq(started, false, "nothing is started or flushed")
end
