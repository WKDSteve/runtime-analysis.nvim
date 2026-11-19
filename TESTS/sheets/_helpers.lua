-- TESTS/sheets/_helpers.lua -- what every runtime-analysis test sheet needs in its child editor. Not a sheet
-- (`testing.sheet` only reads *.sheet.lua); a sheet's first step runs it with `dofile`, the child's cwd is
-- the project root. The directory is in the spec's @cache-inputs, so a change here re-runs the sheets.
--
-- The plugin runs for real. The HTTP runner talks to a tiny server this editor itself listens on
-- (127.0.0.1, a free port): GET /ok answers 200 with a JSON body, /slow never answers (for :RA cancel).

vim.o.swapfile = false
vim.opt.shortmess:append("I")

_G.notes = {}
vim.notify = function(msg)
  _G.notes[#_G.notes + 1] = tostring(msg)
end

---Whether a notification so far holds `text` (plain).
---@param text string
---@return boolean
function _G.noted(text)
  for _, n in ipairs(_G.notes) do
    if n:find(text, 1, true) then
      return true
    end
  end
  return false
end

---Forget the notifications and the recorded requests.
function _G.forget()
  _G.notes = {}
  _G.served = {}
  _G.raw = {}
end

---Whether a request the server received holds `text` (plain): head and body as sent.
---@param text string
---@return boolean
function _G.received(text)
  for _, r in ipairs(_G.raw or {}) do
    if r:find(text, 1, true) then
      return true
    end
  end
  return false
end

---The text of every floating window, joined.
---@return string
function _G.floattext()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
      out[#out + 1] = table.concat(lines, "\n")
    end
  end
  return table.concat(out, "\n")
end

---The text of every window's buffer (floats and splits), joined.
---@return string
function _G.screentext()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
    out[#out + 1] = table.concat(lines, "\n")
  end
  return table.concat(out, "\n")
end

---Whether `text` (plain) was shown: a report float, or the message area it falls back to without ui.kit.
---@param text string
---@return boolean
function _G.seen(text)
  return _G.noted(text) or _G.screentext():find(text, 1, true) ~= nil
end

---The text of the response window (the buffer `runtime-analysis://response`), "" before the first one.
---@return string
function _G.response()
  local b = vim.fn.bufnr("runtime-analysis://response")
  if b == -1 then
    return ""
  end
  return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
end

---Answer the next `vim.ui.select` with the item for which `pick(item)` is true; records the prompt.
---@param pick fun(item: any): boolean
function _G.choose(pick)
  _G.prompt = nil
  vim.ui.select = function(items, opts, on_choice)
    _G.prompt = opts and opts.prompt
    for _, item in ipairs(items) do
      if pick(item) then
        on_choice(item)
        return
      end
    end
    on_choice(nil)
  end
end

local uv = vim.uv or vim.loop

---Start the server, write a project with two environments, cd into it and set the plugin up.
function _G.boot()
  _G.root = _G.root or vim.fn.getcwd()
  _G.served = {}
  _G.raw = {}
  _G.held = {}
  local server = assert(uv.new_tcp())
  assert(server:bind("127.0.0.1", 0))
  _G.port = server:getsockname().port
  server:listen(128, function()
    local client = assert(uv.new_tcp())
    server:accept(client)
    local buf, answered = "", false
    client:read_start(function(_, chunk)
      if not chunk or answered then
        return
      end
      -- the whole request (head and Content-Length bytes of body), however curl splits it
      buf = buf .. chunk
      local head_end = buf:find("\r\n\r\n", 1, true)
      if not head_end then
        return
      end
      local length = tonumber(buf:sub(1, head_end):lower():match("content%-length:%s*(%d+)")) or 0
      if #buf < head_end + 3 + length then
        return
      end
      answered = true
      local first = buf:match("^[^\r\n]*") or ""
      _G.served[#_G.served + 1] = first
      _G.raw[#_G.raw + 1] = buf
      if first:find("/slow", 1, true) then
        _G.held[#_G.held + 1] = client
        return
      end
      client:write(table.concat({
        "HTTP/1.1 200 OK",
        "Content-Type: application/json",
        "Connection: close",
        "",
        '{"ok":true}',
      }, "\r\n"))
      client:shutdown(function()
        client:close()
      end)
    end)
  end)
  _G.server = server

  _G.proj = vim.fn.tempname()
  vim.fn.mkdir(_G.proj .. "/.git", "p")
  local base = ("http://127.0.0.1:%d"):format(_G.port)
  vim.fn.writefile({
    vim.json.encode({ dev = { baseUrl = base }, prod = { baseUrl = "http://127.0.0.1:1" } }),
  }, _G.proj .. "/http-client.env.json")
  vim.cmd("cd " .. vim.fn.fnameescape(_G.proj))
  require("runtime-analysis").setup({ deps_popup = false })
  _G.forget()
end

---The system openers `lib.nvim.cross.open_default` can start: explorer (Windows), open (macOS), xdg-open (Linux),
---explorer.exe / rundll32.exe (WSL). A sheet that opens a report lists them as its `fakes`; this reads every call.
_G.OPENERS = { "explorer", "open", "xdg-open", "explorer.exe", "rundll32.exe" }

---On Windows a `.cmd` stand-in catches only the bare name, so the `.exe` is stripped for the openers
---(fixtures/windows_stand_in_argv.lua). Loaded as a chunk without a file name: to `testing perf` it is runtime,
---the plugin's own line stays the caller of the start. Call it before the first open.
function _G.catch_openers()
  if vim.fn.has("win32") == 1 then
    local path = vim.fn.getcwd() .. "/TESTS/sheets/fixtures/windows_stand_in_argv.lua"
    assert(load(table.concat(vim.fn.readfile(path), "\n"), "=windows stand-in argv"))(_G.OPENERS)
  end
end

---Every recorded call of an opener stand-in, in order: `{ program, argv, cwd }`.
---@return table[]
function _G.opened()
  local ok, fakes = pcall(require, "testing.fake_programs")
  if not ok or not vim.env.TESTING_FAKES then
    return {}
  end
  local out = {}
  for _, name in ipairs(_G.OPENERS) do
    vim.list_extend(out, fakes.read(vim.env.TESTING_FAKES, name) or {})
  end
  return out
end

---The last argument the last opener got ("" before any).
---@return string
function _G.opened_last()
  local calls = _G.opened()
  local last = calls[#calls]
  return last and (last.argv[#last.argv] or "") or ""
end

---A small module `demo.calc` and a telemetry instance for it (namespace "demo", stored in the child's own state
---directory), the way a plugin author wires one up. Not started: the sheet starts it like a user does.
---@return table instance
function _G.demo()
  package.loaded["demo.calc"] = {
    add = function(a, b)
      return a + b
    end,
    mul = function(a, b)
      return a * b
    end,
    unused = function() end,
  }
  local t = require("runtime-analysis.telemetry").new({ namespace = "demo", flush_interval_ms = 0 })
  t.wrap(package.loaded["demo.calc"], "calc")
  _G.tdemo = t
  return t
end

---Call the demo module the way its plugin would, `n` times.
---@param n integer
function _G.use_demo(n)
  local calc = package.loaded["demo.calc"]
  for i = 1, n do
    calc.add(i, 1)
    if i % 2 == 0 then
      calc.mul(i, 2)
    end
  end
end
