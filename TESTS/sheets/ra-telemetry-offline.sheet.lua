-- Feature sheet: a namespace read straight off disk with no live instance. A session records `demo` and quits; the
-- next session (same state directory, no instance of its own) reads it through `telemetry.load`, lists it in
-- :RATelemetry status, and the headless CLI `nvim --headless -l scripts/telemetry.lua report demo` prints it.
-- The CLI is started by the sheet itself (it is the cron job / CI side of the feature, never a start of the editor).
return {
  id = "runtime-analysis.telemetry-offline",
  feature = "runtime-analysis.telemetry-offline",
  title = "A recorded namespace read off disk by a later session and by the headless CLI",
  sizes = { { rows = 40, cols = 120 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()
      _G.demo(); _G.tdemo.start(); _G.use_demo(6); _G.tdemo.stop()]],
      note = "a session records demo and stops it (written to disk)",
    },
    { restart = true },
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    {
      expect = [[require("runtime-analysis.telemetry").get("demo") == nil]],
      note = "the new session has no instance for demo",
    },
    {
      expect = [[(function()
        local data = require("runtime-analysis.telemetry").load("demo")
        return type(data) == "table" and vim.inspect(data):find("add", 1, true) ~= nil
      end)()]],
      note = "telemetry.load reads what the earlier session recorded",
    },
    { keys = ":RATelemetry status<CR>" },
    {
      wait = [[_G.seen("demo")]],
      timeout = 5000,
      note = ":RATelemetry status lists the namespace from disk",
    },
    { keys = "<Esc>" },
    {
      lua = [[local r = vim.system({ vim.v.progpath, "--headless", "-l", "scripts/telemetry.lua", "report", "demo" },
        { text = true, cwd = _G.root }):wait(30000)
      _G.cli = (r.stdout or "") .. (r.stderr or "")
      _G.cli_code = r.code]],
      timeout = 35000,
      note = "the headless CLI reports the namespace (no editor session)",
    },
    {
      expect = [[_G.cli_code == 0 and _G.cli:find("add", 1, true) ~= nil]],
      note = "it exits 0 and names the counted function",
    },
  },
  judge = {},
  manual = {},
}
