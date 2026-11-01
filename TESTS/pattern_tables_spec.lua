-- Test code: when something here comes back nil this file must crash and name it.
---@diagnostic disable: need-check-nil
-- TESTS/pattern_tables_spec.lua — two dispatch tables that replaced hand-written chains:
--   * telemetry/command.lua: REPORT_STYLES (one entry per `report_style`)
--   * bindings/usrcmds.lua: one `pick_one` adapter (ui.kit chooser, else vim.ui.select)

return function(H)
  local eq, ok = H.eq, H.ok

  require("runtime-analysis").setup({})

  -- Every style the resolver can return has a handler ------------------------------------
  local command = require("runtime-analysis.telemetry.command")
  local names = command.report_styles()
  eq(table.concat(names, ","), "file,html,kit,mdview,preview-tab", "report styles with a handler")

  -- :RA env picks through ui.kit when present ---------------------------------------------
  local env = require("runtime-analysis.env")
  local orig_list, orig_set = env.list_names, env.set_current
  local orig_kit, orig_select = package.loaded["ui.kit"], vim.ui.select
  local orig_preload = package.preload["ui.kit"]

  env.list_names = function()
    return { "dev", "prod" }
  end
  local chosen
  env.set_current = function(name)
    chosen = name
    return true
  end

  local good, err = pcall(function()
    -- With the kit: its chooser gets the items, the title and respect_override.
    local seen
    package.loaded["ui.kit"] = {
      select = function(opts)
        seen = opts
        opts.on_select("prod")
      end,
    }
    vim.cmd("RA env")
    ok(seen ~= nil, "ui.kit.select is used when installed")
    eq(table.concat(seen.selection, ","), "dev,prod", "kit receives the names")
    eq(seen.respect_override, true, "kit defers to a configured picker")
    ok(seen.title:find("select environment", 1, true) ~= nil, "kit gets the prompt as its title")
    eq(chosen, "prod", "the choice is applied")

    -- Without the kit: vim.ui.select gets the same prompt and items.
    package.loaded["ui.kit"] = nil
    package.preload["ui.kit"] = function()
      error("ui.kit not installed")
    end
    local sel
    vim.ui.select = function(items, opts, cb)
      sel = { items = items, prompt = opts.prompt }
      cb("dev")
    end
    chosen = nil
    vim.cmd("RA env")
    ok(sel ~= nil, "vim.ui.select is the fallback")
    eq(table.concat(sel.items, ","), "dev,prod", "fallback receives the names")
    ok(sel.prompt:find("select environment", 1, true) ~= nil, "fallback gets the prompt")
    eq(chosen, "dev", "the fallback choice is applied")
  end)

  env.list_names, env.set_current = orig_list, orig_set
  package.loaded["ui.kit"], vim.ui.select, package.preload["ui.kit"] =
    orig_kit, orig_select, orig_preload
  ok(good, "pickers run without error: " .. tostring(err))

  -- The chains are gone ------------------------------------------------------------------
  local function src(rel)
    local path = vim.api.nvim_get_runtime_file("lua/runtime-analysis/" .. rel, false)[1]
    return table.concat(vim.fn.readfile(path), "\n")
  end
  ok(
    src("telemetry/command.lua"):find('if style == "mdview" then', 1, true) == nil,
    "no style if chain"
  )
  local _, kit_requires = src("bindings/usrcmds.lua"):gsub('pcall%(require, "ui.kit"%)', "")
  ok(
    kit_requires <= 3,
    "the select fallback lives in one place (kit requires: " .. kit_requires .. ")"
  )
end
