-- Feature sheet: what package.loaded holds, with named snapshots a later session still reads.
-- Automated: :RA loaded snapshot saves one, :RA loaded snapshots lists it, and after a restart of the editor (same
-- state directory) the snapshot is still there.
return {
  id = "runtime-analysis.loaded",
  feature = "runtime-analysis.loaded",
  title = ":RA loaded snapshot and snapshots, kept across a restart",
  sizes = { { rows = 40, cols = 120 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":RA loaded snapshot runtime-analysis snapone<CR>" },
    { expect = [[_G.noted('loaded snapshot "snapone" saved')]], note = "loaded snapshot saves it" },
    { lua = [[_G.forget()]] },
    { keys = ":RA loaded snapshots runtime-analysis<CR>" },
    {
      expect = [[_G.noted("1 snapshot(s)") and _G.noted("snapone")]],
      note = "loaded snapshots lists it",
    },
    { restart = true },
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":RA loaded snapshots runtime-analysis<CR>" },
    {
      expect = [[_G.noted("1 snapshot(s)") and _G.noted("snapone")]],
      note = "a later session still reads the snapshot",
    },
  },
  judge = { "the snapshot list reads well" },
  manual = {},
}
