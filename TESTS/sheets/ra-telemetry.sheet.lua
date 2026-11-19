-- Feature sheet: opt-in call counting for a Lua plugin (a small module `demo.calc` with its own instance, wired up
-- the way a plugin author does it, _helpers.lua). Automated: :RATelemetry start <ns>, calls counted, the report of
-- the namespace, flush, status, stop (naming the file), and the fleet commands StartAll / StopAll.
-- Not here: SetupAll / SetupAllFull / ResetAll against a real configuration (manual).
return {
  id = "runtime-analysis.telemetry",
  task = "runtime-analysis.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  feature = "runtime-analysis.telemetry",
  title = ":RATelemetry start, report, flush, status and stop of a namespace, StartAll and StopAll",
  sizes = { { rows = 40, cols = 120 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot(); _G.demo()]] },
    { keys = ":RATelemetry start demo<CR>" },
    { expect = [[_G.noted("started demo")]], note = ":RATelemetry start demo" },
    { lua = [[_G.use_demo(10)]], note = "the plugin is used: add 10 times, mul 5 times" },
    { keys = ":RATelemetry demo<CR>" },
    {
      wait = [[_G.seen("add") and _G.seen("10")]],
      timeout = 5000,
      note = ":RATelemetry demo shows the counted functions",
    },
    { keys = "<Esc>" },
    { lua = [[_G.forget()]] },
    { keys = ":RATelemetry flush demo<CR>" },
    { expect = [[#_G.notes > 0]], note = ":RATelemetry flush demo answers" },
    { lua = [[_G.forget()]] },
    { keys = ":RATelemetry status<CR>" },
    {
      wait = [[_G.seen("demo") and _G.seen("NAMESPACE")]],
      timeout = 5000,
      note = ":RATelemetry status has a row for demo",
    },
    { keys = "<Esc>" },
    { lua = [[_G.forget()]] },
    { keys = ":RATelemetry stop demo<CR>" },
    {
      expect = [[_G.noted("stopped demo") and _G.noted("written to")]],
      note = ":RATelemetry stop demo names the file it wrote",
    },
    {
      expect = [[vim.fn.filereadable(_G.tdemo.data_path()) == 1]],
      note = "and the file is there",
    },
    { lua = [[_G.forget()]] },
    { keys = ":RATelemetryStartAll<CR>" },
    {
      expect = [[_G.noted("started ") and _G.noted("instance(s)")]],
      note = ":RATelemetryStartAll reports how many instances it started",
    },
    { lua = [[_G.forget()]] },
    { keys = ":RATelemetryStopAll<CR>" },
    {
      expect = [[_G.noted("stopped ") and _G.noted("instance(s)")]],
      note = ":RATelemetryStopAll reports how many it stopped",
    },
  },
  judge = { "the report and the status table read well" },
  manual = {
    "`:RATelemetrySetupAll`, `ResetAll`, `NvimConfig` and `NvimConfigFull` against a real configuration",
  },
}
