-- TESTS/run.lua — headless test runner for runtime-analysis.nvim.
--
-- Run from the repo root:
--   nvim -n -i NONE --headless -u NONE -l TESTS/run.lua
--
-- Loads every *_spec.lua listed below, runs it against the shared harness,
-- prints a per-spec result, and exits non-zero on the first failing spec.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

-- Before anything computes a path: state and cache go to a throwaway folder,
-- so no spec writes into the user's real telemetry store (TESTS/isolate_state.lua).
local isolated = dofile(here .. "isolate_state.lua")()
io.stdout:write(("stdpath('state'): %s (was %s)\n"):format(isolated.state, isolated.state_before))
io.stdout:write(("stdpath('cache'): %s (was %s)\n"):format(isolated.cache, isolated.cache_before))

-- Make the repo importable whether invoked via -l (cwd) or luafile.
vim.opt.rtp:append(vim.fn.getcwd())

-- lib.nvim is a runtime dependency (net.curl), so the specs cannot run
-- without it on the rtp. Three ways it can be found, in descending order of
-- explicitness — CI uses the first, a local checkout the second, an
-- installed plugin manager the third (already on the rtp, so nothing to
-- do). Candidates built with explicit indices, not a `{a, b, c}` literal fed
-- to `ipairs`: `LIB_NVIM_DIR` is `nil` whenever unset (the normal case for
-- CI), and a `nil` in a table literal's first slot makes `ipairs` stop
-- immediately without inspecting the slots after it — a real bug, found
-- and fixed this same way in docmap.nvim's own copy of this file
-- (see that repo's FEATURES.md), not repeated here.
local function add_lib_nvim()
  if pcall(require, "lib.nvim.net.curl") then
    return
  end
  local candidates = {}
  if vim.env.LIB_NVIM_DIR and vim.env.LIB_NVIM_DIR ~= "" then
    candidates[#candidates + 1] = vim.env.LIB_NVIM_DIR
  end
  candidates[#candidates + 1] = vim.fn.getcwd() .. "/.deps/lib.nvim"
  candidates[#candidates + 1] = vim.fs.dirname(vim.fn.getcwd()) .. "/lib.nvim"
  for _, dir in ipairs(candidates) do
    if dir and vim.fn.isdirectory(dir) == 1 then
      vim.opt.rtp:append(dir)
      if pcall(require, "lib.nvim.net.curl") then
        return
      end
    end
  end
  io.stderr:write("TESTS/run.lua: lib.nvim not found.\n")
  io.stderr:write("  Set LIB_NVIM_DIR, or clone it to .deps/lib.nvim, or beside this repo.\n")
  os.exit(1)
end

add_lib_nvim()

local H = dofile(here .. "harness.lua")

local specs = {
  "parse_spec.lua",
  "runner_spec.lua",
  "view_spec.lua",
  "init_spec.lua",
  "usrcmds_spec.lua",
  "diagnostics_spec.lua",
  "transcript_spec.lua",
  "pattern_tables_spec.lua",
  "env_choice_spec.lua",
  "usrcmds_help_spec.lua",
  "history_spec.lua",
  "env_spec.lua",
  "curl_spec.lua",
  "assertions_spec.lua",
  "telemetry_spec.lua",
  "registry_spec.lua",
  "map_merge_spec.lua",
  "startup_spec.lua",
  "startup_stall_spec.lua",
  "startup_profile_spec.lua",
  "float_spec.lua",
  "flamegraph_spec.lua",
  "cost_vs_use_spec.lua",
  "provenance_spec.lua",
  "usage_spec.lua",
  "loaded_spec.lua",
  "bench_spec.lua",
  "inspect_spec.lua",
  "graphql_spec.lua",
  "multipart_spec.lua",
  "telemetry_html_spec.lua",
  "telemetry_flush_spec.lua",
  "lazy_spec.lua",
  "setup_all_spec.lua",
  "config_validate_spec.lua",
  "statusline_spec.lua",
  "columns_spec.lua",
  "isolate_state_spec.lua",
}

-- RA_RUN_SPECS=a_spec.lua,b_spec.lua runs only those (in manifest order); a
-- name that is not in the manifest above is refused with exit 2.
local only = vim.env.RA_RUN_SPECS
if only and only ~= "" then
  local wanted, known = {}, {}
  for _, name in ipairs(specs) do
    known[name] = true
  end
  for name in only:gmatch("[^,%s]+") do
    if not known[name] then
      io.stderr:write(
        ("TESTS/run.lua: RA_RUN_SPECS names %s, which is not in the manifest\n"):format(name)
      )
      os.exit(2)
    end
    wanted[name] = true
  end
  specs = vim.tbl_filter(function(name)
    return wanted[name] == true
  end, specs)
end

--- Straight to stdout rather than through `print` — the same reason
--- docmap.nvim's own runner gives: `print` in a headless Neovim goes
--- through the message area, and a spec that opens a window (`view_spec`
--- opens a real split) forces a redraw that swallows the pending newline.
---@param s string
local function say(s)
  io.stdout:write(s, "\n")
end

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(here .. name)
  local ok, err = pcall(run, H)
  if ok then
    say(("ok    %s"):format(name))
  else
    failed = failed + 1
    say(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  say(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

say("\nRUNTIME_ANALYSIS_TESTS_OK")
