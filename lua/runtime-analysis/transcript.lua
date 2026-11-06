---@module 'runtime-analysis.transcript'
--- `:RA transcript on|off`: a Markdown protocol of the sends of this session, in a file that mdview
--- watches, so a browser page grows with every send.
---
--- Opt-in, and only what the history records: method, redacted URL, status or the reason of a failure,
--- plus the time. **No bodies and no headers**: they can hold secrets, which is why the history has none
--- either, and a file a browser reads is a worse place for them. The file lies in a temporary directory,
--- never in `stdpath("cache")`, and goes away with `off`.
---
--- Fed from `history.record`, the one place every send already passes through: success, failure and
--- cancellation. A problem here never reaches the send: `add` swallows it.

local notify = require("lib.nvim.notify").create("[runtime-analysis]")

local M = {}

---@type { path: string, lines: string[] }|nil
local active = nil

---@return boolean
function M.is_on()
  return active ~= nil
end

---@return string|nil path  The file, while the protocol is on.
function M.path()
  return active and active.path
end

---Show the protocol: live in the browser through mdview, else once in mdview's preview tab, else say
---where the file is. mdview missing is a hint, not an error.
---@param t { path: string, lines: string[] }
local function show(t)
  local browser = require("runtime-analysis.telemetry.renderers.mdview")
  if browser.available() then
    local opened, err = browser.open(t.lines, t.path)
    if opened then
      return
    end
    notify.warn("could not open the transcript in mdview: " .. tostring(err))
  else
    local tab = require("runtime-analysis.telemetry.renderers.preview_tab")
    if tab.available() and tab.open(t.lines, "RA transcript") then
      return
    end
  end
  notify.info("transcript without a live view (mdview.nvim is not available): " .. t.path)
end

---Start the protocol, or show it again when it is on.
---@return string|nil path
---@return string|nil err
function M.on()
  if active then
    show(active)
    return active.path
  end
  local dir = vim.fn.tempname()
  if vim.fn.mkdir(dir, "p") ~= 1 then
    return nil, "cannot create " .. dir
  end
  local t = {
    path = dir .. "/ra-transcript.md",
    lines = {
      "# Requests of this session",
      "",
      "Method, URL and result only: no headers, no bodies.",
      "",
    },
  }
  if vim.fn.writefile(t.lines, t.path) ~= 0 then
    return nil, "cannot write " .. t.path
  end
  active = t
  show(t)
  return t.path
end

---Stop the protocol and remove its file.
function M.off()
  if not active then
    return
  end
  vim.fn.delete(vim.fs.dirname(active.path), "rf")
  active = nil
end

---Add one send. Does nothing while the protocol is off.
---@param method string
---@param url string  Already redacted (`history.redact_url`).
---@param status integer?
---@param note string?  What went wrong, when there is no status.
function M.add(method, url, status, note)
  if not active then
    return
  end
  local result = status and tostring(status) or ("✗ " .. tostring(note or "no response"))
  -- One line each: a URL or a message with a line break must not open a new one.
  local line = ("- `%s` **%s** %s → %s")
    :format(os.date("%H:%M:%S"), method, url, result)
    :gsub("[\r\n]+", " ")
  active.lines[#active.lines + 1] = line
  pcall(vim.fn.writefile, active.lines, active.path)
end

return M
