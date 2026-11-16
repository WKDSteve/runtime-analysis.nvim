---@module 'runtime-analysis.runner'
--- Executes a parsed request via `lib.nvim.net.curl` and formats the result
--- into plain lines for `view.lua` to display.
---
--- Two entry points over one formatter (`format_response`, so the two can
--- never drift): `M.run` blocks via `fetch_raw_blocking`; `M.run_async` is
--- the non-blocking twin `:RA send` uses, with its callback guaranteed to
--- run outside Neovim's fast event context. Pending-request tracking and
--- `:RA cancel` live in `bindings/usrcmds.lua`, not here — this module has
--- no request state machine of its own.
---
--- A transport failure (unreachable host, timeout) comes back as an error
--- string; a real-but-unwelcome HTTP status (404, 500, …) is not an error
--- at all and renders as an ordinary response.

local curl = require("lib.nvim.net.curl")
local json_encode = require("lib.lua.json.encode")
local shape = require("runtime-analysis.shape")
local uv = vim.uv or vim.loop

local M = {}

---@internal
---@param body string
---@return string[]
local function body_lines(body)
  return vim.split(body, "\n", { plain = true })
end

---Whether `headers` name this response's body as JSON — a substring match
---on `Content-Type`'s value (`application/json`, `application/json;
---charset=utf-8`, `application/vnd.api+json`, …) rather than an exact
---match, since real APIs vary the parameters and the `+json` suffix
---convention (RFC 6839) is common enough to be worth catching.
---@internal
---@param headers table<string, string>
---@return boolean
local function is_json_response(headers)
  for name, value in pairs(headers) do
    if name:lower() == "content-type" and value:lower():find("json", 1, true) then
      return true
    end
  end
  return false
end

---Pretty-print `body` if it decodes as JSON, or `nil` to fall back to the
---raw text verbatim. `vim.json.encode(value, { indent = N })` was tried
---first and rejected: verified against a real call on this Neovim version,
---it does not indent at all — it inserts the literal text of `N` (`"2"`,
---unindented) before each key instead of two spaces. `lib.lua.json.encode`
---is a real, correct, pure-Lua encoder with a genuine `.pretty` mode, which
---is what makes this safe to do automatically now where it was not before.
---
---Both `vim.json.decode` and `encode.pretty` are wrapped defensively: a
---`Content-Type: application/json` header is a claim, not a guarantee — a
---misconfigured server can send that header over a body that is not
---actually valid JSON, and showing the reader the real (if compact)
---response is strictly better than an error where a response used to be.
---@internal
---@param body string
---@return string[]? pretty_lines
---@return any decoded The decoded value, for `shape.of`; set only with `pretty_lines`
local function try_pretty_json(body)
  local ok_decode, decoded = pcall(vim.json.decode, body)
  if not ok_decode then
    return nil
  end
  local pretty = json_encode.pretty(decoded)
  if not pretty then
    return nil
  end
  return body_lines(pretty), decoded
end

---@class RA.Runner.Meta
---@field status integer? HTTP status; `nil` when curl itself failed
---@field body_start integer? First body line, for `view.lua`
---@field is_json boolean? Whether the body is shown pretty-printed as JSON
---@field duration_ms integer Wall time from handing the request to curl until curl answered
---@field bytes integer? Size of the response body in bytes; `nil` when curl failed
---@field shape RA.Shape? Shape of the answer (never its content), see `runtime-analysis.shape`

---Milliseconds since `start` (an `uv.hrtime()` reading), rounded.
---@internal
---@param start number
---@return integer
local function elapsed_ms(start)
  return math.floor((uv.hrtime() - start) / 1e6 + 0.5)
end

---Turn a raw `Lib.Net.Curl.RawResponse` into lines ready for `view.lua`,
---shared by the blocking and async paths below so neither can drift from
---the other's formatting.
---@internal
---@param resp Lib.Net.Curl.RawResponse
---@param duration_ms integer
---@return string[] lines
---@return RA.Runner.Meta meta
---`body_start`/`is_json` are `view.lua`'s (folding/syntax, "yank just the
---body"); `status`, `duration_ms`, `bytes` and `shape` are
---`bindings/usrcmds.lua`'s own, for a request history entry, so a caller
---never has to re-parse anything back out of `lines`.
local function format_response(resp, duration_ms)
  local lines = { ("%d %s"):format(resp.status, resp.status_text) }
  local header_names = vim.tbl_keys(resp.headers)
  table.sort(header_names)
  for _, name in ipairs(header_names) do
    lines[#lines + 1] = ("%s: %s"):format(name, resp.headers[name])
  end
  lines[#lines + 1] = ""

  local body_start = #lines + 1
  local is_json = false
  local decoded

  if resp.body and resp.body ~= "" then
    local pretty_lines
    if is_json_response(resp.headers) then
      pretty_lines, decoded = try_pretty_json(resp.body)
      is_json = pretty_lines ~= nil
    end
    vim.list_extend(lines, pretty_lines or body_lines(resp.body))
  end

  return lines,
    {
      status = resp.status,
      body_start = body_start,
      is_json = is_json,
      duration_ms = duration_ms,
      bytes = type(resp.body) == "string" and #resp.body or 0,
      shape = shape.of(resp.headers, is_json, decoded),
    }
end

---Run `request` and return response lines ready for `view.lua`, or an error
---string when curl itself failed (unreachable host, timeout) — a different
---failure shape from a real-but-unwelcome HTTP status, which is not an
---error at all: a 404 is a real answer, and is rendered as one.
---@param request { method: string, url: string, headers: table<string, string>, body: string? }
---@return string[]? lines
---@return string? err
---@return RA.Runner.Meta meta Always set: on a curl failure it carries `duration_ms` only
function M.run(request)
  local start = uv.hrtime()
  local ok, resp = curl.fetch_raw_blocking(request.url, {
    method = request.method,
    headers = request.headers,
    body = request.body,
  })

  if not ok then
    -- `resp` is the error string in this branch — `fetch_raw_blocking`'s
    -- own contract, the same one `fetch_json_blocking` already has. The cast
    -- is that contract, stated where the reader is instead of only in prose.
    ---@cast resp string
    return nil, resp, { duration_ms = elapsed_ms(start) }
  end

  ---@cast resp Lib.Net.Curl.RawResponse
  local lines, meta = format_response(resp, elapsed_ms(start))
  return lines, nil, meta
end

---The non-blocking twin of `M.run`. `cb` always runs
---through `vim.schedule` — `lib.nvim.net.curl.fetch_raw`'s own completion
---callback fires in a **fast event context** (verified: a bare
---`nvim_create_buf` call inside it raises `E5560`), so every caller of this
---function would otherwise have to remember to schedule its own callback
---before touching any buffer/window/`vim.notify` API. Guaranteeing that
---here, once, is cheaper than documenting it as a caller's own
---responsibility and hoping nobody forgets.
---
---No cancellation lives here — see `bindings/usrcmds.lua`'s own pending-
---request tracking for what `:RA cancel` actually does and why it is a
---*logical* cancel (the in-flight `curl` process keeps running to
---completion; only its eventual result is discarded) rather than a real
---process kill: `fetch_raw` does not hand back the `vim.SystemObj` a hard
---kill would need, and extending `lib.nvim.net.curl` for that is real,
---separate work in a different repository, not attempted here.
---@param request { method: string, url: string, headers: table<string, string>, body: string? }
---
---`meta.duration_ms` is taken in curl's own completion callback, before the
---hop through `vim.schedule`, so a busy editor loop does not count as
---network time.
---@param cb fun(lines: string[]?, err: string?, meta: RA.Runner.Meta)
function M.run_async(request, cb)
  local start = uv.hrtime()
  curl.fetch_raw(request.url, {
    method = request.method,
    headers = request.headers,
    body = request.body,
  }, function(ok, resp)
    local duration_ms = elapsed_ms(start)
    vim.schedule(function()
      if not ok then
        -- `resp` is the error string in this branch too, same contract
        -- `fetch_raw_blocking` documents.
        ---@cast resp string
        cb(nil, resp, { duration_ms = duration_ms })
        return
      end
      ---@cast resp Lib.Net.Curl.RawResponse
      local lines, meta = format_response(resp, duration_ms)
      cb(lines, nil, meta)
    end)
  end)
end

return M
