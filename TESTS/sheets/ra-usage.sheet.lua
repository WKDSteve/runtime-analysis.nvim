-- Feature sheet: :RA usage counts which of the user's own keymaps and typed commands are pressed.
-- Automated: before start, start (and a refused second start), a mapping of the user pressed, the report, stop.
return {
  id = "runtime-analysis.usage",
  feature = "runtime-analysis.usage",
  title = ":RA usage start, report and stop over a pressed keymap of the user",
  sizes = { { rows = 40, cols = 120 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()
      vim.keymap.set("n", "<Space>x", function() _G.pressed = (_G.pressed or 0) + 1 end, { desc = "my own map" })]],
      note = "a session with one mapping of the user's own",
    },
    { keys = ":RA usage<CR>" },
    { expect = [[_G.noted("usage tracking is not running")]], note = ":RA usage before start" },
    { lua = [[_G.forget()]] },
    { keys = ":RA usage start<CR>" },
    { expect = [[_G.noted("usage tracking started")]], note = ":RA usage start" },
    { keys = ":RA usage start<CR>" },
    { expect = [[_G.noted("already running")]], note = "and a second start is refused" },
    { keys = " x" },
    { keys = " x" },
    { expect = [[_G.pressed == 2]], note = "the mapping ran twice" },
    { lua = [[_G.forget()]] },
    { keys = ":RA usage<CR>" },
    { expect = [[#_G.notes > 0 and not _G.noted("not running")]], note = ":RA usage reports" },
    { lua = [[_G.forget()]] },
    { keys = ":RA usage stop<CR>" },
    { expect = [[_G.noted("usage tracking stopped")]], note = ":RA usage stop" },
  },
  judge = { "the usage report reads well and names the pressed mapping" },
  manual = {},
}
