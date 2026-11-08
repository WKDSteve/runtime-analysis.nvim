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
  _G.served = {}
  _G.held = {}
  local server = assert(uv.new_tcp())
  assert(server:bind("127.0.0.1", 0))
  _G.port = server:getsockname().port
  server:listen(128, function()
    local client = assert(uv.new_tcp())
    server:accept(client)
    client:read_start(function(_, chunk)
      if not chunk then
        return
      end
      local first = chunk:match("^[^\r\n]*") or ""
      _G.served[#_G.served + 1] = first
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
