-- Feature sheet: the request bodies beyond plain JSON, sent through curl to the local server (_helpers.lua), which
-- records each request as it arrived. Automated: a GraphQL body (query + variables become one JSON payload, the
-- X-Request-Type directive is not sent), a multipart body with a real local file (`< ./data.bin`), the `Auth: Basic`
-- shorthand (base64 on the wire) and an `@expect status` that holds.
return {
  id = "runtime-analysis.request-bodies",
  task = "runtime-analysis.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  feature = "runtime-analysis.request-bodies",
  title = "GraphQL, multipart with a local file, Auth: Basic and @expect status, as the server sees them",
  sizes = { { rows = 40, cols = 120 } },
  requires = {
    { lua = [[vim.fn.executable("curl") == 1]], reason = "curl is not installed" },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()
      vim.fn.writefile({ "FILEBYTES-42" }, _G.proj .. "/data.bin")]],
      note = "a project with a local file to upload",
    },
    { keys = ":RA request<CR>" },
    { keys = ":RA env dev<CR>" },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        "POST {{baseUrl}}/graphql",
        "X-Request-Type: GraphQL",
        "Content-Type: application/json",
        "",
        "query GetUser($id: ID!) {",
        "  user(id: $id) { name }",
        "}",
        "",
        '{"id": "42"}',
      }); _G.forget()]],
      note = "a GraphQL request",
    },
    { keys = ":RA send<CR>" },
    {
      wait = [[_G.response():find("200 OK", 1, true) ~= nil and #_G.raw == 1]],
      timeout = 15000,
      note = "the GraphQL request is answered",
    },
    {
      expect = [[_G.received('"query"') and _G.received('"variables"') and _G.received("GetUser") and not _G.received("X-Request-Type")]],
      note = "the server got query and variables as JSON, without the directive header",
    },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        "POST {{baseUrl}}/upload",
        "Content-Type: multipart/form-data; boundary=XYZBOUNDARY",
        "",
        "--XYZBOUNDARY",
        'Content-Disposition: form-data; name="title"',
        "",
        "My title",
        "--XYZBOUNDARY",
        'Content-Disposition: form-data; name="file"; filename="data.bin"',
        "Content-Type: application/octet-stream",
        "",
        "< ./data.bin",
        "--XYZBOUNDARY--",
      }); _G.forget()]],
      note = "a multipart upload of a local file",
    },
    { keys = ":RA send<CR>" },
    {
      wait = [[_G.response():find("200 OK", 1, true) ~= nil and #_G.raw == 1]],
      timeout = 15000,
      note = "the upload is answered",
    },
    {
      expect = [[_G.received("FILEBYTES-42") and _G.received('name="title"') and not _G.received("< ./data.bin")]],
      note = "the server got the file's bytes in place of the < line",
    },
    {
      lua = [[vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        "# @expect status 200",
        "GET {{baseUrl}}/ok",
        "Auth: Basic alice:s3cret",
      }); _G.forget()]],
      note = "the Auth: Basic shorthand and an @expect line",
    },
    { keys = ":RA send<CR>" },
    {
      wait = [[_G.response():find("200 OK", 1, true) ~= nil and #_G.raw == 1]],
      timeout = 15000,
      note = "the request is answered",
    },
    {
      expect = [[_G.received("Authorization: Basic YWxpY2U6czNjcmV0") and not _G.received("Auth: Basic alice")]],
      note = "the server got the base64 Authorization header",
    },
    { expect = [[_G.noted("expect status 200")]], note = "the @expect status 200 held" },
  },
  judge = {},
  manual = {},
}
