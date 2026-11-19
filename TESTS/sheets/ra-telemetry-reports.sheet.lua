-- Feature sheet: the reports on recorded telemetry. A namespace `demo` records some calls (_helpers.lua), then:
-- compare over time windows, two named snapshots and their diff, export as Markdown, the startup attribution and
-- cost, the HTML dashboard (report_style "html") and the startup flamegraph. Both of the last two hand their file to
-- the system opener (lib.nvim.cross.open_default): the openers are recording stand-ins (`fakes`; on Windows the
-- `.exe` is stripped by fixtures/windows_stand_in_argv.lua), so no browser opens.
return {
  id = "runtime-analysis.telemetry-reports",
  feature = "runtime-analysis.telemetry-reports",
  title = ":RATelemetry compare, snapshots, export, startup, cost, the HTML dashboard and the flamegraph",
  sizes = { { rows = 40, cols = 120 } },
  fakes = { "explorer", "open", "xdg-open", "explorer.exe", "rundll32.exe" },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.catch_openers(); _G.boot()
      local startup = require("runtime-analysis.telemetry.startup")
      startup.reset(); startup.start()
      package.loaded["runtime-analysis.bench"] = nil; require("runtime-analysis.bench")
      package.loaded["runtime-analysis.graphql"] = nil; require("runtime-analysis.graphql")
      startup.stop()
      _G.demo(); _G.tdemo.start(); _G.use_demo(10); _G.tdemo.flush()]],
      note = "startup attribution saw two modules load; demo recorded calls",
    },
    { keys = ":RATelemetry compare demo<CR>" },
    {
      wait = [[_G.seen("demo") and _G.seen("add")]],
      timeout = 5000,
      note = ":RATelemetry compare demo shows this window against the one before",
    },
    { keys = "<Esc>" },
    { lua = [[_G.forget()]] },
    { keys = ":RATelemetry snapshot demo before<CR>" },
    { expect = [[_G.noted('saved snapshot "before" for demo')]], note = "a named snapshot" },
    { lua = [[_G.use_demo(4); _G.forget()]] },
    { keys = ":RATelemetry snapshot demo after<CR>" },
    { expect = [[_G.noted('saved snapshot "after" for demo')]], note = "and a second one later" },
    { keys = ":RATelemetry snapshots demo<CR>" },
    {
      wait = [[_G.seen("before") and _G.seen("after")]],
      timeout = 5000,
      note = ":RATelemetry snapshots demo lists both",
    },
    { keys = "<Esc>" },
    { keys = ":RATelemetry snapshot-compare demo before after<CR>" },
    {
      wait = [[_G.seen("add")]],
      timeout = 5000,
      note = ":RATelemetry snapshot-compare diffs the call counts",
    },
    { keys = "<Esc>" },
    { lua = [[_G.forget(); _G.md = vim.fn.tempname() .. ".md"]] },
    {
      lua = [[vim.cmd("RATelemetry export " .. vim.fn.fnameescape(_G.md))]],
      note = ":RATelemetry export <file>.md",
    },
    {
      wait = [[vim.fn.filereadable(_G.md) == 1 and table.concat(vim.fn.readfile(_G.md), "\n"):find("demo", 1, true) ~= nil]],
      timeout = 5000,
      note = "the Markdown report is written and names the namespace",
    },
    { keys = ":RATelemetry startup<CR>" },
    {
      wait = [[_G.seen("runtime-analysis.bench")]],
      timeout = 5000,
      note = ":RATelemetry startup names the modules that loaded",
    },
    { keys = "<Esc>" },
    { lua = [[_G.forget()]] },
    { keys = ":RATelemetry cost<CR>" },
    {
      wait = [[_G.seen("demo")]],
      timeout = 5000,
      note = ":RATelemetry cost weighs the namespace's startup cost against its calls",
    },
    { keys = "<Esc>" },
    {
      lua = [[_G.forget(); require("runtime-analysis.telemetry").setup({ report_style = "html" })]],
    },
    { keys = ":RATelemetry open demo<CR>" },
    {
      wait = [[#_G.opened() == 1]],
      timeout = 10000,
      note = "report_style html: :RATelemetry open demo hands the dashboard to the system opener",
    },
    {
      expect = [[_G.opened_last():match("%.html$") ~= nil]],
      note = "the opener got the written HTML file",
    },
    { expect = [[_G.noted("wrote and opened")]], note = "and the user is told" },
    { lua = [[_G.forget()]] },
    { keys = ":RATelemetry flamegraph<CR>" },
    {
      wait = [[#_G.opened() == 2]],
      timeout = 10000,
      note = ":RATelemetry flamegraph (no images.nvim) hands the SVG to the system opener",
    },
    { expect = [[_G.opened_last():match("%.svg$") ~= nil]], note = "the opener got the SVG" },
    { expect = [[_G.noted("wrote and opened")]], note = "and the user is told" },
  },
  judge = { "the compare, snapshot and startup floats read well" },
  manual = {
    "Once in the real editor: `:RATelemetry open` with report_style html opens the dashboard in the browser, and `:RATelemetry flamegraph` shows the SVG (images.nvim or the system viewer)",
  },
}
