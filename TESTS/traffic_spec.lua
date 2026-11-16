-- TESTS/traffic_spec.lua — runtime-analysis.traffic: the history read as a
-- measurement, one row per endpoint.

return function(H)
  local eq, ok = H.eq, H.ok
  ---Deep equality (`H.eq` compares tables by reference).
  local function same(a, b, msg)
    H.ok(
      vim.deep_equal(a, b),
      ("%s: expected %s, got %s"):format(msg, vim.inspect(b), vim.inspect(a))
    )
  end
  local traffic = require("runtime-analysis.traffic")

  -- `history.list` order: newest first.
  local entries = {
    {
      method = "GET",
      url = "https://a.io/items?page=2",
      status = 200,
      duration_ms = 30,
      bytes = 2048,
      at = 5,
    },
    {
      method = "GET",
      url = "https://a.io/items?page=1",
      status = 500,
      duration_ms = 10,
      bytes = 10,
      at = 4,
    },
    { method = "GET", url = "https://a.io/items", status = nil, note = "cancelled", at = 3 },
    { method = "GET", url = "https://a.io/items#x", status = 200, duration_ms = 20, at = 2 },
    {
      method = "POST",
      url = "https://a.io/items",
      status = nil,
      note = "timeout",
      duration_ms = 9000,
      at = 1,
    },
    "not a table",
  }

  local rows = traffic.summarize(entries)
  eq(#rows, 2, "traffic: one row per method and endpoint, query and fragment ignored")
  local get = rows[1]
  eq(get.method .. " " .. get.endpoint, "GET https://a.io/items", "traffic: most-sent first")
  eq(get.sends, 4, "traffic: every send counts")
  same(
    { get.ok, get.errors, get.failed },
    { 2, 1, 1 },
    "traffic: ok, error answers and failed sends apart"
  )
  eq(get.median_ms, 20, "traffic: median of the answered sends' durations")
  eq(get.max_ms, 30, "traffic: max duration")
  eq(get.last_status, 200, "traffic: the newest send's status")
  eq(get.last_bytes, 2048, "traffic: the newest send's size")

  local post = rows[2]
  eq(post.failed, 1, "traffic: a transport failure is a failed send")
  eq(post.median_ms, nil, "traffic: a failed send's wait is not an answer time")

  eq(traffic.format_bytes(512), "512 B", "format_bytes: bytes")
  eq(traffic.format_bytes(4300), "4.2 KB", "format_bytes: kilobytes")
  eq(traffic.format_bytes(nil), "-", "format_bytes: unknown")
  eq(traffic.format_ms(12), "12 ms", "format_ms")

  local lines = traffic.lines(entries)
  ok(lines[1]:find("never content", 1, true) ~= nil, "lines: the header names the limit")
  ok(table.concat(lines, "\n"):find("page=", 1, true) == nil, "lines: no query is shown")
  eq(traffic.lines({})[3], "no recorded sends yet", "lines: an empty history says so")
end
