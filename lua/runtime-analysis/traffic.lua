---@module 'runtime-analysis.traffic'
--- `:RA traffic`: the request history read as a measurement, one row per
--- endpoint (method plus URL without query and fragment): how often it was
--- sent, how it answered, how long it took, how large and what shape the
--- last answer was.
---
--- Reads only what `runtime-analysis.history` recorded, so the same limits
--- hold: metadata and shapes, never content; and "recorded sends of this
--- project" is not "all traffic" — only what went through `:RA send` is in
--- it, capped at `history_max_entries`.

local shape = require("runtime-analysis.shape")

local M = {}

---@class RA.Traffic.Row
---@field method string
---@field endpoint string URL without query and fragment
---@field sends integer
---@field ok integer Answers with a status below 400
---@field errors integer Answers with a status of 400 or more
---@field failed integer Sends without an answer (transport error, cancelled)
---@field median_ms integer? Median duration of the sends that have one
---@field max_ms integer?
---@field last_status integer?
---@field last_bytes integer?
---@field last_shape RA.Shape?

---@internal
---@param url string
---@return string
local function endpoint_of(url)
  return (tostring(url or ""):gsub("[?#].*$", ""))
end

---@internal
---@param sorted integer[]
---@return integer?
local function median(sorted)
  local n = #sorted
  if n == 0 then
    return nil
  end
  if n % 2 == 1 then
    return sorted[(n + 1) / 2]
  end
  return math.floor((sorted[n / 2] + sorted[n / 2 + 1]) / 2 + 0.5)
end

---One row per endpoint, most-sent first (ties: by endpoint, then method).
---`entries` is `history.list()`'s own order, newest first, so the first
---entry seen for an endpoint is its latest.
---@param entries RA.History.Entry[]
---@return RA.Traffic.Row[]
function M.summarize(entries)
  local rows, by_key, durations = {}, {}, {}
  for _, raw in ipairs(entries or {}) do
    -- `history.list` hands on whatever table the file held; the cast is
    -- only taken after the type check, never instead of it.
    local e = type(raw) == "table" and raw --[[@as RA.History.Entry]] or nil
    if e and type(e.method) == "string" then
      local ep = endpoint_of(e.url)
      local key = e.method .. " " .. ep
      local row = by_key[key]
      if not row then
        row = {
          method = e.method,
          endpoint = ep,
          sends = 0,
          ok = 0,
          errors = 0,
          failed = 0,
          last_status = e.status,
          last_bytes = e.bytes,
          last_shape = e.shape,
        }
        by_key[key] = row
        durations[key] = {}
        rows[#rows + 1] = row
      end
      row.sends = row.sends + 1
      if type(e.status) ~= "number" then
        row.failed = row.failed + 1
      elseif e.status >= 400 then
        row.errors = row.errors + 1
      else
        row.ok = row.ok + 1
      end
      if type(e.duration_ms) == "number" and type(e.status) == "number" then
        local d = durations[key]
        d[#d + 1] = e.duration_ms
      end
    end
  end
  for key, row in pairs(by_key) do
    local d = durations[key]
    table.sort(d)
    row.median_ms = median(d)
    row.max_ms = d[#d]
  end
  table.sort(rows, function(a, b)
    if a.sends ~= b.sends then
      return a.sends > b.sends
    end
    if a.endpoint ~= b.endpoint then
      return a.endpoint < b.endpoint
    end
    return a.method < b.method
  end)
  return rows
end

---Human-readable byte count: `512 B`, `4.2 KB`, `1.3 MB`.
---@param n integer?
---@return string
function M.format_bytes(n)
  if type(n) ~= "number" then
    return "-"
  end
  if n < 1024 then
    return ("%d B"):format(n)
  elseif n < 1024 * 1024 then
    return ("%.1f KB"):format(n / 1024)
  end
  return ("%.1f MB"):format(n / (1024 * 1024))
end

---@param ms integer?
---@return string
function M.format_ms(ms)
  if type(ms) ~= "number" then
    return "-"
  end
  return ("%d ms"):format(ms)
end

---The lines `:RA traffic` shows.
---@param entries RA.History.Entry[]
---@return string[]
function M.lines(entries)
  local rows = M.summarize(entries)
  local out = {
    "Request traffic of this project (recorded :RA sends only; metadata and shapes, never content)",
    "",
  }
  if #rows == 0 then
    out[#out + 1] = "no recorded sends yet"
    return out
  end
  out[#out + 1] = ("%-6s %5s %4s %4s %4s %9s %9s %6s %9s  %-30s %s"):format(
    "METHOD",
    "SENDS",
    "OK",
    "ERR",
    "FAIL",
    "MEDIAN",
    "MAX",
    "LAST",
    "SIZE",
    "SHAPE",
    "ENDPOINT"
  )
  for _, r in ipairs(rows) do
    out[#out + 1] = ("%-6s %5d %4d %4d %4d %9s %9s %6s %9s  %-30s %s"):format(
      r.method,
      r.sends,
      r.ok,
      r.errors,
      r.failed,
      M.format_ms(r.median_ms),
      M.format_ms(r.max_ms),
      r.last_status and tostring(r.last_status) or "-",
      M.format_bytes(r.last_bytes),
      shape.summary(r.last_shape),
      r.endpoint
    )
  end
  return out
end

return M
