-- Live check: asking the running session (task runtime-analysis.nvim/testblatt-bindings-checkliste).
-- Automated: :RA provenance names the function it looked at, :RA inspect walks a loaded module.
-- loaded, usage, startup and the :RATelemetry basics have sheets of their own (ra-loaded, ra-usage, ra-startup,
-- ra-telemetry).
return {
  id = "runtime-analysis.analysis",
  feature = "runtime-analysis.inspect",
  title = ":RA provenance and :RA inspect in a running session",
  task = "runtime-analysis.nvim/testblatt-bindings-checkliste",
  sizes = { { rows = 40, cols = 120 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":RA provenance vim.notify<CR>" },
    {
      expect = [[#_G.notes > 0 and _G.noted("vim.notify")]],
      note = ":RA provenance names the function it looked at",
    },
    { lua = [[_G.forget()]] },
    { keys = ":RA inspect runtime-analysis.parse<CR>" },
    {
      expect = [[#_G.notes > 0 and _G.noted("parse")]],
      note = ":RA inspect walks a loaded module",
    },
  },
  judge = { "the inspect and provenance output reads well" },
  manual = {
    "the Session marks keys (`<C-e>`, `<M-1>`..`<M-9>`, `<M-S>`) and the slot bar belong to the session plugin, not to this one",
  },
}
