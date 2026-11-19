-- Feature sheet: :RA transcript on keeps a Markdown protocol of the sends (method, URL, status; no headers, no
-- bodies). mdview.nvim is not in the test editor, so the protocol is shown in the preview tab or named as a path.
-- Automated: on, one send through curl to the local server, the line in the file without the header value, off
-- removes the file.
return {
  id = "runtime-analysis.request-transcript",
  task = "runtime-analysis.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  feature = "runtime-analysis.request-transcript",
  title = ":RA transcript on and off around a send",
  sizes = { { rows = 40, cols = 120 } },
  requires = {
    { lua = [[vim.fn.executable("curl") == 1]], reason = "curl is not installed" },
  },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":RA transcript on<CR>" },
    {
      expect = [[require("runtime-analysis.transcript").is_on() and vim.fn.filereadable(require("runtime-analysis.transcript").path()) == 1]],
      note = "the protocol is on and its file exists",
    },
    { lua = [[_G.tpath = require("runtime-analysis.transcript").path()]] },
    { keys = ":RA request<CR>" },
    { keys = ":RA env dev<CR>" },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "GET {{baseUrl}}/ok", "X-Secret: hunter2" }); _G.forget()]],
    },
    { keys = ":RA send<CR>" },
    {
      wait = [[_G.response():find("200 OK", 1, true) ~= nil]],
      timeout = 15000,
      note = "the send is answered",
    },
    {
      wait = [[table.concat(vim.fn.readfile(_G.tpath), "\n"):find("/ok", 1, true) ~= nil]],
      timeout = 5000,
      note = "the protocol has a line for the send",
    },
    {
      expect = [[table.concat(vim.fn.readfile(_G.tpath), "\n"):find("200", 1, true) ~= nil and table.concat(vim.fn.readfile(_G.tpath), "\n"):find("hunter2", 1, true) == nil]],
      note = "with the status and without the header value",
    },
    { keys = ":RA transcript off<CR>" },
    {
      expect = [[not require("runtime-analysis.transcript").is_on() and vim.fn.filereadable(_G.tpath) == 0]],
      note = "off ends it and removes the file",
    },
  },
  judge = {},
  manual = { "`:RA transcript on` with mdview.nvim: the browser page grows with every send" },
}
