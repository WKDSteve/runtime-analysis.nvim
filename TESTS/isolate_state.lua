-- TESTS/isolate_state.lua — points stdpath("state") and stdpath("cache") at a
-- throwaway directory for the rest of this editor process.
--
-- The runner-free fallback `nvim --headless -u NONE -l TESTS/run.lua` runs the
-- specs with the user's real stdpaths: everything a spec writes through
-- `:RATelemetry` or `telemetry.snapshot()` without a `dir` would land in the
-- real telemetry store under stdpath("state") (which, unlike the old cache
-- location, nothing ever cleans). testing.nvim's child editors already get a
-- sandbox of their own; this gives the legacy runner the same.
--
-- `stdpath()` reads $XDG_STATE_HOME / $XDG_CACHE_HOME on every call, so setting
-- them here (before any plugin module computes a path) is enough. The folder
-- sits below `tempname()`, i.e. in this editor's own temp directory, which
-- Neovim removes when it exits.

---@class RA.Tests.Isolated
---@field state string the new stdpath("state")
---@field cache string the new stdpath("cache")
---@field state_before string stdpath("state") before the redirect
---@field cache_before string stdpath("cache") before the redirect

---@return RA.Tests.Isolated
return function()
  local before = { state = vim.fn.stdpath("state"), cache = vim.fn.stdpath("cache") }
  local base = vim.fs.normalize(vim.fn.tempname()) .. "-runtime-analysis-tests"
  vim.fn.mkdir(base .. "/state", "p")
  vim.fn.mkdir(base .. "/cache", "p")
  vim.env.XDG_STATE_HOME = base .. "/state"
  vim.env.XDG_CACHE_HOME = base .. "/cache"
  return {
    state = vim.fn.stdpath("state") --[[@as string]],
    cache = vim.fn.stdpath("cache") --[[@as string]],
    state_before = before.state --[[@as string]],
    cache_before = before.cache --[[@as string]],
  }
end
