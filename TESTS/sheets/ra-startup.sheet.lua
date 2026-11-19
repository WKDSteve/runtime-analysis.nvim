-- Feature sheet: stall detection and startup attribution. Automated: :RA startup probe (the --cmd line), start,
-- report (the stall timeline), watch, and :RA startup profile 1, which starts a real child editor
-- (`nvim --startuptime`, startup/profile.lua) once and reports its cost per file; an absurd run count is refused.
return {
  id = "runtime-analysis.startup",
  task = "runtime-analysis.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  feature = "runtime-analysis.startup",
  title = ":RA startup probe, start, watch, report and profile",
  sizes = { { rows = 40, cols = 120 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":RA startup probe<CR>" },
    {
      expect = [[_G.noted("measure a startup with:") and vim.fn.getreg('"'):find("--cmd", 1, true) ~= nil]],
      note = ":RA startup probe prints and yanks the --cmd line",
    },
    { lua = [[_G.forget()]] },
    { keys = ":RA startup start<CR>" },
    { expect = [[_G.noted("watching for main-loop stalls")]], note = ":RA startup start" },
    { keys = ":RA startup report<CR>" },
    {
      wait = [[_G.floattext():find("stall", 1, true) ~= nil or _G.noted("stall")]],
      timeout = 8000,
      note = ":RA startup report shows the timeline",
    },
    { keys = "<Esc>" },
    { lua = [[_G.forget()]] },
    { keys = ":RA startup watch<CR>" },
    { expect = [[_G.noted("watching until")]], note = ":RA startup watch" },
    { keys = ":RA startup report<CR>" },
    { keys = "<Esc>" },
    { lua = [[_G.forget()]] },
    { keys = ":RA startup profile 1<CR>" },
    {
      wait = [[_G.noted("median startup over 1 run(s)") or _G.screentext():find("median startup over 1 run(s)", 1, true) ~= nil]],
      timeout = 60000,
      note = ":RA startup profile 1 starts an editor once and reports the cost",
    },
    {
      expect = [[_G.noted("MEDIAN") or _G.screentext():find("MEDIAN", 1, true) ~= nil]],
      note = "with the per-file table",
    },
    { keys = "<Esc>" },
    { lua = [[_G.forget()]] },
    { keys = ":RA startup profile 500<CR>" },
    {
      expect = [[_G.noted("runs must be between 1 and 50")]],
      note = "an absurd run count is refused",
    },
  },
  judge = { "the startup profile and stall floats read well" },
  manual = {
    "`:RA startup profile` against the real configuration names the slow files of the real startup",
  },
}
