-- TESTS/lazy_spec.lua — runtime-analysis.telemetry.lazy
--
-- The one plugin-manager adapter this module ships. Since real lazy.nvim is
-- not on this test run's runtime path, `lazy.core.config`/`lazy.core.loader`
-- are stubbed here rather than faked as real lazy.nvim internals -- this
-- exercises the adapter's own logic (catch-up scan, the ongoing autocmd,
-- per-plugin policy dispatch, dedup), not lazy.nvim's.

return function(H)
  local lazy_adapter = require("runtime-analysis.telemetry.lazy")

  -- Nothing stubbed yet -- setup() must be a safe no-op, not an error, when
  -- lazy.nvim genuinely is not the caller's plugin manager.
  do
    local ok = pcall(lazy_adapter.setup, { plugins = {} })
    H.eq(ok, true, "setup() does not error when lazy.core.config is unavailable")
  end

  local seq = 0
  local function ns(name)
    seq = seq + 1
    return ("spec.lazy.%s.%d"):format(name, seq)
  end

  -- Two fake plugins: "early" is already loaded (simulating a lazy=false
  -- dependency whose LazyLoad fired before this adapter's own setup() could
  -- run), "late" is not loaded yet, "unwanted" is loaded but never opted
  -- into `opts.plugins` at all.
  package.loaded["fakelazy_early"] = { f = function() end }

  local plugin_early = { "someorg/early.nvim" }
  local plugin_late = { "someorg/late.nvim" }
  local plugin_unwanted = { "someorg/unwanted.nvim" }

  package.loaded["lazy.core.config"] = {
    plugins = {
      early = plugin_early,
      late = plugin_late,
      unwanted = plugin_unwanted,
    },
  }
  package.loaded["lazy.core.loader"] = {
    get_main = function(plugin)
      if plugin == plugin_early then
        return "fakelazy_early"
      elseif plugin == plugin_late then
        return "fakelazy_late"
      end
      return nil
    end,
  }

  local ns_early = ns("early")
  local ns_late = ns("late")

  lazy_adapter.setup({
    plugins = {
      ["someorg/early.nvim"] = { namespace = ns_early, persist = false },
      ["someorg/late.nvim"] = { namespace = ns_late, persist = false },
    },
    lib_nvim = false,
  })

  local telemetry = require("runtime-analysis.telemetry")
  H.ok(telemetry.get(ns_early) ~= nil, "catch-up scan wraps a plugin already loaded")
  H.eq(telemetry.get(ns_late), nil, "a not-yet-loaded plugin is NOT wrapped by the catch-up scan")

  -- "late" now actually loads; fire the event the catch-up scan could not
  -- have seen yet.
  package.loaded["fakelazy_late"] = { g = function() end }
  vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "late" })
  H.ok(telemetry.get(ns_late) ~= nil, "the autocmd wraps a plugin once it actually loads")

  -- Re-firing the same event must not create a second live instance for the
  -- same namespace -- exactly the "two instances, one cache file" trap the
  -- original hand-rolled version guarded against with its own dedup set.
  local before = #telemetry.instances()
  vim.api.nvim_exec_autocmds("User", { pattern = "LazyLoad", data = "late" })
  H.eq(
    #telemetry.instances(),
    before,
    "re-firing LazyLoad for an already-started plugin is a no-op"
  )

  -- An unrecognized plugin_name (not in opts.plugins) loading is simply
  -- ignored, not an error.
  local ok_unwanted =
    pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "LazyLoad", data = "unwanted" })
  H.eq(ok_unwanted, true, "a plugin never opted into `plugins` does not error")
  H.eq(telemetry.get("someorg/unwanted.nvim"), nil, "...and gets no instance")

  -- lib_nvim: soft dependency, must not error whether or not lib.nvim's
  -- lib.strategies.telemetry_wrap is actually reachable from this repo's
  -- test run.
  do
    local ok = pcall(lazy_adapter.setup, {
      plugins = {},
      lib_nvim = { profile_args = false, persist = false },
    })
    H.eq(ok, true, "lib_nvim wiring does not error regardless of lib.nvim's presence")
  end

  for _, inst in ipairs(telemetry.instances()) do
    if inst.namespace == ns_early or inst.namespace == ns_late then
      inst.stop()
      inst.unwrap()
    end
  end
  for _, name in ipairs({ "fakelazy_early", "fakelazy_late" }) do
    package.loaded[name] = nil
  end

  -- A plugin whose real code loads after its own LazyLoad (lsp.nvim: only its pack is there when
  -- the event fires, the other 120 modules come during startup). Without another look those
  -- modules stay unwrapped for the whole session.
  do
    local function calls_of(inst, key)
      for _, row in ipairs(inst.report().entries) do
        if row.key == key then
          return row.calls
        end
      end
      return 0
    end

    local plugin_deep = { "someorg/deep.nvim" }
    local plugin_flat = { "someorg/flat.nvim" }
    package.loaded["lazy.core.config"] = { plugins = { deep = plugin_deep, flat = plugin_flat } }
    package.loaded["lazy.core.loader"] = {
      get_main = function(plugin)
        return plugin == plugin_deep and "fakelazy_deep" or "fakelazy_flat"
      end,
    }
    package.loaded["fakelazy_deep"] = { root = function() end }
    package.loaded["fakelazy_flat"] = { root = function() end }

    local ns_deep, ns_flat = ns("deep"), ns("flat")
    lazy_adapter.setup({
      plugins = {
        ["someorg/deep.nvim"] = {
          namespace = ns_deep,
          persist = false,
          deep = true,
          profile_args = true,
        },
        ["someorg/flat.nvim"] = { namespace = ns_flat, persist = false, deep = false },
      },
      lib_nvim = false,
    })
    local deep, flat = assert(telemetry.get(ns_deep)), assert(telemetry.get(ns_flat))
    H.eq(#deep.wrapped_keys(), 1, "only what is loaded at the event is wrapped")

    -- The first look comes after startup, behind what the config defers itself.
    local later = { work = function(_) end }
    package.loaded["fakelazy_deep.later"] = later
    package.loaded["fakelazy_flat.later"] = { work = function() end }
    if vim.v.vim_did_enter == 0 then
      vim.api.nvim_exec_autocmds("VimEnter", {})
    end
    H.ok(
      vim.wait(1000, function()
        return #deep.wrapped_keys() == 2
      end),
      "a module loaded during startup is wrapped after VimEnter"
    )
    later.work("a")
    H.eq(calls_of(deep, "later.work"), 1, "and its calls are counted, on the running instance")
    H.ok(deep.report().modes.args, "with the settings of the plugin")
    H.eq(#flat.wrapped_keys(), 1, "a plugin that asked for its facade only stays at its facade")

    -- A module first required on a key press: the next idle moment finds it.
    local on_key = { work = function() end }
    package.loaded["fakelazy_deep.on_key"] = on_key
    vim.api.nvim_exec_autocmds("CursorHold", {})
    H.eq(#deep.wrapped_keys(), 3, "an idle moment wraps what was required since")

    -- Idle moments come often: at most one of them in a while does the work.
    package.loaded["fakelazy_deep.soon"] = { work = function() end }
    vim.api.nvim_exec_autocmds("CursorHold", {})
    H.eq(#deep.wrapped_keys(), 3, "the next idle moment right after it does nothing")
    lazy_adapter.rescan()
    H.eq(#deep.wrapped_keys(), 4, "rescan() looks at once")

    local instances = #telemetry.instances()
    local real_start, starts = deep.start, 0
    deep.start = function(...)
      starts = starts + 1
      return real_start(...)
    end
    lazy_adapter.rescan()
    H.eq(#deep.wrapped_keys(), 4, "looking again wraps nothing twice")
    H.eq(#telemetry.instances(), instances, "and creates no instance")
    H.eq(starts, 0, "and does not restart the flush timer of the instance")
    deep.start = real_start

    -- A namespace that was stopped on purpose is not started again by a look.
    deep.stop()
    package.loaded["fakelazy_deep.stopped"] = { work = function() end }
    lazy_adapter.rescan()
    H.eq(deep.is_running(), false, "a stopped namespace stays stopped")
    H.eq(#deep.wrapped_keys(), 4, "and nothing is added to it")

    flat.stop()
    deep.unwrap()
    flat.unwrap()
    for name in pairs(package.loaded) do
      if name:match("^fakelazy_") then
        package.loaded[name] = nil
      end
    end
  end

  -- What a report of 0 calls can mean (mdview.nvim: 223 functions, no call). A command that
  -- reaches its function through the module is counted however early it was bound; only a
  -- function saved before the wrap is out of sight.
  do
    local module = { show = function() end, kept = function() end }
    package.loaded["fakelazy_cmd"] = module
    local through_the_module = function()
      module.show()
    end
    local saved = module.kept

    local inst = assert(telemetry.auto({
      namespace = ns("cmd"),
      main = "fakelazy_cmd",
      deep = true,
      persist = false,
    }))
    through_the_module()
    saved()

    local counted = {}
    for _, row in ipairs(inst.report().entries) do
      counted[row.key] = row.calls
    end
    H.eq(counted.show, 1, "a command bound before the wrap is counted through the module")
    H.eq(counted.kept, nil, "a function saved before the wrap is not")

    inst.stop()
    inst.unwrap()
    package.loaded["fakelazy_cmd"] = nil
  end

  package.loaded["lazy.core.config"] = nil
  package.loaded["lazy.core.loader"] = nil
end
