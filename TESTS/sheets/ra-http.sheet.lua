-- Live check: the HTTP request runner of `:RA` against a small server the child editor listens on (task
-- runtime-analysis.nvim/testblatt-bindings-checkliste; the runtime-analysis sections of
-- BINDINGS-RUNTIME-CHECKLIST.md). Automated: request, send (+ the aliases), yank, env, history, cancel,
-- export, import and diagnose, with an `@expect status` that holds and one that does not.
-- Not here: transcript (needs mdview), the look of the response window.
return {
  id = "runtime-analysis.http",
  title = ":RA request, send, yank, env, history, cancel, export and import",
  task = "runtime-analysis.nvim/testblatt-bindings-checkliste",
  sizes = { { rows = 40, cols = 120 } },
  requires = {
    { lua = [[vim.fn.executable("curl") == 1]], reason = "curl is not installed" },
  },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":RA request<CR>" },
    {
      expect = [[vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "GET https://" and vim.bo.filetype == "http"]],
      note = ":RA request opens the template buffer",
    },
    { keys = ":RARequest<CR>" },
    {
      expect = [[vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "GET https://"]],
      note = "and so does the alias :RARequest",
    },
    { keys = ":RA env nope<CR>" },
    { expect = [[_G.noted("nope")]], note = ":RA env with an unknown name is refused" },
    { lua = [[_G.forget()]] },
    { keys = ":RA env dev<CR>" },
    { expect = [[_G.noted("environment set to dev")]], note = ":RA env dev selects it" },
    { lua = [[_G.choose(function(n) return n == "prod" end)]] },
    { keys = ":RA env<CR>" },
    {
      expect = [[_G.prompt:find("current: dev", 1, true) ~= nil and _G.noted("environment set to prod")]],
      note = "bare :RA env offers the names and takes the picked one",
    },
    { keys = ":RA env dev<CR>" },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# @expect status 200", "GET {{baseUrl}}/ok", "Accept: application/json" }); _G.forget()]],
    },
    { keys = ":RA send<CR>" },
    {
      wait = [[_G.response():find("200 OK", 1, true) ~= nil]],
      timeout = 15000,
      note = ":RA send shows the real status",
    },
    {
      expect = [[_G.response():find('"ok": true', 1, true) ~= nil and _G.served[1] == "GET /ok HTTP/1.1"]],
      note = "the pretty-printed body, and the server saw {{baseUrl}} resolved",
    },
    { expect = [[_G.noted("expect status 200")]], note = "the @expect status 200 held" },
    { keys = ":RA yank<CR>" },
    {
      expect = [[vim.fn.getreg('"') == '{\n  "ok": true\n}' and _G.noted("yanked 3 line(s)")]],
      note = ":RA yank puts just the body into the unnamed register",
    },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# @expect status 404", "GET {{baseUrl}}/ok" }); _G.forget()]],
    },
    { keys = ":RASend<CR>" },
    {
      wait = [[#vim.fn.getqflist() == 1]],
      timeout = 15000,
      note = "the alias :RASend; a wrong @expect lands in quickfix",
    },
    {
      expect = [[vim.fn.getqflist()[1].text == "expected status 404, got 200"]],
      note = "with the expected and the real status",
    },
    { keys = ":RA export<CR>" },
    {
      expect = [[vim.fn.getreg('"'):find("curl '{{baseUrl}}/ok'", 1, true) ~= nil and vim.fn.getreg('"'):find("expect", 1, true) == nil]],
      note = ":RA export yanks a curl line, the placeholder unresolved and without the @expect line",
    },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, { [=[curl -X POST http://127.0.0.1:9/x -H 'Content-Type: application/json' -d '{"a":1}']=] }); _G.forget()]],
    },
    { keys = ":1RA import<CR>" },
    {
      expect = [[vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "POST http://127.0.0.1:9/x" and vim.api.nvim_buf_get_lines(0, 1, 2, false)[1] == "Content-Type: application/json"]],
      note = ":RA import turns the selected curl line into a request buffer",
    },
    { lua = [[_G.forget()]] },
    { keys = ":RA cancel<CR>" },
    {
      expect = [[_G.noted("no request in flight")]],
      note = ":RA cancel with nothing in flight says so",
    },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "GET {{baseUrl}}/slow" }); _G.forget()]],
    },
    { keys = ":RA send<CR>" },
    {
      wait = [[_G.response():find("sending", 1, true) ~= nil and #_G.served == 1]],
      timeout = 15000,
      note = "the slow request is out and unanswered",
    },
    { keys = ":RA cancel<CR>" },
    {
      expect = [[_G.response():find("cancelled", 1, true) ~= nil]],
      note = ":RA cancel replaces the placeholder",
    },
    { lua = [[_G.choose(function() return true end)]] },
    { keys = ":RA history<CR>" },
    {
      expect = [[_G.prompt:find("request history", 1, true) ~= nil and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find("{{baseUrl}}/slow", 1, true) ~= nil]],
      note = ":RA history lists the sends, newest first, and reopens the picked one",
    },
    { lua = [[_G.forget()]] },
    { keys = ":RA history clear<CR>" },
    { expect = [[_G.noted("request history cleared")]], note = ":RA history clear" },
    { lua = [[_G.forget()]] },
    { keys = ":RA history<CR>" },
    { expect = [[_G.noted("no request history")]], note = "and the history is empty afterwards" },
    { lua = [[_G.forget()]] },
    { keys = ":RA diagnose<CR>" },
    {
      expect = [[(function() for _, n in ipairs(_G.notes) do local p = n:match("diagnostics written to (.+)$"); if p and vim.fn.filereadable(p) == 1 then return true end end return false end)()]],
      note = ":RA diagnose writes its report file",
    },
  },
  judge = { "the response window reads well (status line, headers, the pretty-printed body)" },
  manual = {
    "`:RA transcript on` / `off` (needs mdview)",
    "`:RA env` and `:RA history` through the real picker (ui.kit, telescope, fzf-lua)",
  },
}
