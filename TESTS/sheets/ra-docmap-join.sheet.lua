-- Feature sheet: docmap.nvim hands a route over as a request buffer (`require("runtime-analysis").open_request`, the
-- call docmap's `gs` makes in :DocBrowse Endpoints) and the reader completes and sends it. Automated: the buffer
-- holds the method and the relative path, not sent; the reader fills in the base URL and :RA send reaches the local
-- server through curl. Invalid input from the other plugin is refused with a message.
return {
  id = "runtime-analysis.docmap-join",
  feature = "runtime-analysis.docmap-join",
  title = "A route from docmap.nvim becomes a request buffer the reader completes and sends",
  sizes = { { rows = 40, cols = 120 } },
  requires = {
    { lua = [[vim.fn.executable("curl") == 1]], reason = "curl is not installed" },
  },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    {
      lua = [[require("runtime-analysis").open_request({ "GET /ok", "" })]],
      note = "docmap.nvim calls open_request for a route it found",
    },
    {
      expect = [[vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "GET /ok" and vim.bo.filetype == "http"]],
      note = "a request buffer with the method and the path",
    },
    { expect = [[#_G.served == 0]], note = "nothing was sent yet" },
    { keys = ":RA env dev<CR>" },
    { keys = "0wi{{baseUrl}}<Esc>", note = "the reader puts the base URL in front of the path" },
    {
      expect = [[vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "GET {{baseUrl}}/ok"]],
      note = "the line is complete",
    },
    { keys = ":RA send<CR>" },
    {
      wait = [[_G.response():find("200 OK", 1, true) ~= nil and _G.served[1] == "GET /ok HTTP/1.1"]],
      timeout = 15000,
      note = "the completed route is sent and answered",
    },
    { lua = [[require("runtime-analysis").open_request({ 42 })]] },
    {
      expect = [[vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "GET https://"]],
      note = "a malformed hand-over opens the empty template, never its contents",
    },
  },
  judge = {},
  manual = {
    "Once with docmap.nvim installed: `gs` on a route in :DocBrowse Endpoints opens the request buffer",
  },
}
