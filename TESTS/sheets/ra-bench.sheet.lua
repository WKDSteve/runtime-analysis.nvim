-- Feature sheet: time candidate functions against each other (`runtime-analysis.bench`, a Lua API: there is no
-- command). Automated: two implementations of the same sum, one clearly slower, compared in the running editor; the
-- result names the faster one and `bench.lines` renders a table with both names.
return {
  id = "runtime-analysis.bench",
  task = "runtime-analysis.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  feature = "runtime-analysis.bench",
  title = "bench.compare times two candidate functions and names the faster one",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    {
      lua = [[local bench = require("runtime-analysis.bench")
      local function fast() local s = 0 for i = 1, 10 do s = s + i end return s end
      local function slow() local s = 0 for i = 1, 2000 do s = s + i end return s end
      _G.result = bench.compare({ { name = "fast", fn = fast }, { name = "slow", fn = slow } }, { iterations = 2000 })
      _G.lines = table.concat(bench.lines(_G.result), "\n")]],
      timeout = 20000,
      note = "compare a cheap and an expensive candidate",
    },
    { expect = [[_G.result.fastest == "fast"]], note = "the cheap one is the fastest" },
    {
      expect = [[_G.lines:find("fast", 1, true) ~= nil and _G.lines:find("slow", 1, true) ~= nil]],
      note = "the rendered lines name both candidates",
    },
  },
  judge = {},
  manual = {},
}
