-- TESTS/isolate_state_spec.lua — no spec run touches the user's real
-- telemetry store under stdpath("state").
--
-- Two ways run the specs: testing.nvim (a child editor per file with its own
-- stdpaths) and the runner-free fallback TESTS/run.lua. The first is checked
-- in this very editor, the second by starting run.lua the way a person would
-- (no XDG_* variables of a sandbox) and reading where it says its stdpaths are.

return function(H)
  local root = vim.fs.normalize(vim.fn.getcwd())

  -- this editor: its state folder is a redirected one, not the default
  do
    local xdg = vim.env.XDG_STATE_HOME
    H.ok(xdg ~= nil and xdg ~= "", "XDG_STATE_HOME is set for the spec editor")
    local state = vim.fs.normalize(vim.fn.stdpath("state"))
    H.eq(
      state:sub(1, #vim.fs.normalize(xdg)),
      vim.fs.normalize(xdg),
      "stdpath('state') lies below XDG_STATE_HOME"
    )
  end

  -- TESTS/run.lua started without a sandbox: it moves state and cache away
  do
    local env = {}
    for k, v in pairs(vim.fn.environ()) do
      local up = k:upper()
      if up ~= "XDG_STATE_HOME" and up ~= "XDG_CACHE_HOME" then
        env[k] = v
      end
    end
    env.RA_RUN_SPECS = "parse_spec.lua"
    local res = vim
      .system(
        { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", "TESTS/run.lua" },
        { cwd = root, env = env, clear_env = true, text = true }
      )
      :wait(60000)
    local out = (res.stdout or "") .. (res.stderr or "")
    H.eq(res.code, 0, "run.lua with one spec passes: " .. out)
    local state, before = out:match("stdpath%('state'%): (.-) %(was (.-)%)\n")
    H.ok(state, "run.lua reports where its state folder is: " .. out)
    H.ok(state ~= before, "run.lua does not use the default state folder " .. tostring(before))
    H.ok(
      vim.fs.normalize(state):find("-runtime-analysis-tests/state", 1, true),
      "state folder is the throwaway one: " .. state
    )
    local cache, cache_before = out:match("stdpath%('cache'%): (.-) %(was (.-)%)\n")
    H.ok(cache and cache ~= cache_before, "run.lua does not use the default cache folder: " .. out)
    H.ok(out:find("ok    parse_spec.lua", 1, true), "RA_RUN_SPECS limited the run: " .. out)
    H.ok(not out:find("runner_spec.lua", 1, true), "no other spec ran: " .. out)
  end

  -- RA_RUN_SPECS naming a file that is not in the manifest is refused
  do
    local res = vim
      .system(
        { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", "TESTS/run.lua" },
        { cwd = root, env = { RA_RUN_SPECS = "nope_spec.lua" }, text = true }
      )
      :wait(60000)
    H.eq(res.code, 2, "unknown spec name -> exit 2")
    H.ok(
      (res.stderr or ""):find("nope_spec.lua", 1, true),
      "names the unknown spec: " .. (res.stderr or "")
    )
  end
end
