---@module 'runtime-analysis.diagnostics'
--- `:RA diagnose`: the state of the plugin in one plain-text file to attach to a bug report, in the
--- shape of `:MDView diagnose` (`mdview.diagnostics`), so a report of both plugins reads the same.
---
--- Read-only except for writing that file: nothing is started, stopped or flushed.
---
--- What stays out, because the file is meant to be passed on: request headers and bodies, the URLs of
--- the history (it reports the number of entries), the values of environments (names only), and any
--- option whose name looks like a secret (`mask`).

local uv = vim.uv or vim.loop

local M = {}

---The plugins this one works with, all optional. `probe` is a module of the plugin that is cheap to
---load; `health.lua` shows the same list (`M.siblings`), so there is one to keep up to date.
---@type { name: string, probe: string }[]
M.SIBLINGS = {
  { name = "lib.nvim", probe = "lib.nvim.net.curl" },
  { name = "ui.nvim", probe = "ui.kit" },
  { name = "mdview.nvim", probe = "mdview" },
  { name = "pdfport.nvim", probe = "pdfport" },
  { name = "docmap.nvim", probe = "docmap" },
}

---A directory is not walked further than this many entries: a report must not hang on a huge cache.
local MAX_WALKED = 5000

---@param path string
---@return string|nil
local function read_line(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local line = f:read("*l")
  f:close()
  return line
end

---The short commit a plugin folder is on, read from its files: no process for a report that is
---asked for when something is already wrong. `nil` outside a git checkout.
---@param root string
---@return string|nil
function M.commit_of(root)
  local git_dir = root .. "/.git"
  local pointer = uv.fs_stat(git_dir)
  if not pointer then
    return nil
  end
  if pointer.type == "file" then
    -- A worktree: `.git` is a file naming the real folder.
    local target = (read_line(git_dir) or ""):match("^gitdir:%s*(.+)$")
    if not target then
      return nil
    end
    git_dir = target
  end
  local head = read_line(git_dir .. "/HEAD")
  if not head then
    return nil
  end
  local ref = head:match("^ref:%s*(.+)$")
  if not ref then
    return head:sub(1, 7)
  end
  -- A worktree keeps its refs in the common folder.
  local common = read_line(git_dir .. "/commondir")
  local base = common and (git_dir .. "/" .. common) or git_dir
  local sha = read_line(base .. "/" .. ref) or read_line(git_dir .. "/" .. ref)
  if sha then
    return sha:sub(1, 7)
  end
  local packed = io.open(base .. "/packed-refs", "r")
  if not packed then
    return nil
  end
  for line in packed:lines() do
    local found, name = line:match("^(%x+) (.+)$")
    if name == ref then
      packed:close()
      return found:sub(1, 7)
    end
  end
  packed:close()
  return nil
end

---The folder of the plugin holding module `mod`, or `nil`.
---@param mod string
---@return string|nil
local function plugin_root(mod)
  local rel = "lua/" .. mod:gsub("%.", "/")
  local hit = vim.api.nvim_get_runtime_file(rel .. ".lua", false)[1]
    or vim.api.nvim_get_runtime_file(rel .. "/init.lua", false)[1]
  if not hit then
    return nil
  end
  return (hit:gsub("\\", "/"):match("^(.*)/lua/"))
end

---@class RuntimeAnalysis.Sibling
---@field name string
---@field found boolean  It is on the runtimepath.
---@field root? string  Its folder.
---@field commit? string  Its commit, where the folder is a git checkout.
---@field error? string  It is there, and loading it failed.

---Where the plugins this one works with are. A sibling that fails to load is a row saying so, never
---an error here: this list is read when something is already broken.
---@param list? { name: string, probe: string }[]  Default `M.SIBLINGS`.
---@return RuntimeAnalysis.Sibling[]
function M.siblings(list)
  local rows = {}
  for _, sib in ipairs(list or M.SIBLINGS) do
    local root = plugin_root(sib.probe)
    local row = { name = sib.name, found = root ~= nil, root = root }
    if root then
      row.commit = M.commit_of(root)
      local ok, err = pcall(require, sib.probe)
      if not ok then
        row.error = tostring(err):match("^[^\n]*")
      end
    end
    rows[#rows + 1] = row
  end
  return rows
end

---Does an option of this name hold a secret?
---@param key any
---@return boolean
local function secret_name(key)
  local name = tostring(key):lower()
  for _, word in ipairs({
    "token",
    "secret",
    "password",
    "passwd",
    "key",
    "auth",
    "header",
    "cookie",
  }) do
    if name:find(word, 1, true) then
      return true
    end
  end
  return false
end

---A copy of `value` with the value of every option named like a secret replaced by `<hidden>`.
---@param value any
---@param depth? integer
---@return any
function M.mask(value, depth)
  depth = depth or 0
  if type(value) ~= "table" or depth > 16 then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = secret_name(k) and "<hidden>" or M.mask(v, depth + 1)
  end
  return out
end

---Size of a folder in bytes, and whether the walk stopped at `MAX_WALKED`.
---@param dir string
---@return integer bytes
---@return boolean cut
local function folder_size(dir)
  local bytes, seen = 0, 0
  local pending = { dir }
  while #pending > 0 do
    local here = table.remove(pending)
    local handle = uv.fs_scandir(here)
    while handle do
      local name, kind = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      seen = seen + 1
      if seen > MAX_WALKED then
        return bytes, true
      end
      local path = here .. "/" .. name
      if kind == "directory" then
        pending[#pending + 1] = path
      else
        local st = uv.fs_lstat(path)
        bytes = bytes + (st and st.size or 0)
      end
    end
  end
  return bytes, false
end

---Build the report.
---@return string[] lines
function M.collect()
  local lines = {}
  local function section(title)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== " .. title .. " =="
  end
  local function kv(key, value)
    lines[#lines + 1] = ("  %-22s %s"):format(key .. ":", tostring(value))
  end

  lines[#lines + 1] = "runtime-analysis.nvim diagnostics — " .. os.date("%Y-%m-%d %H:%M:%S")

  section("Environment")
  kv("nvim version", tostring(vim.version()))
  local uname = uv.os_uname() or {}
  kv("os", (uname.sysname or "?") .. " " .. (uname.machine or "?"))

  section("Plugin")
  local own_root = plugin_root("runtime-analysis")
  kv("folder", own_root or "(not on the runtimepath)")
  kv("commit", own_root and M.commit_of(own_root) or "unknown")

  section("Config (resolved)")
  local ok_ra, ra = pcall(require, "runtime-analysis")
  if ok_ra and type(ra.opts) == "table" then
    local masked = M.mask(ra.opts)
    local keys = vim.tbl_keys(masked)
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)
    for _, key in ipairs(keys) do
      kv(tostring(key), vim.inspect(masked[key], { newline = " ", indent = "" }))
    end
  else
    kv("config", "FAILED to load: " .. tostring(ra))
  end

  section("Telemetry")
  local ok_tel, telemetry = pcall(require, "runtime-analysis.telemetry")
  if ok_tel then
    local live = telemetry.instances()
    if #live == 0 then
      kv("live instances", "none")
    end
    for _, inst in ipairs(live) do
      kv(inst.namespace, inst.is_running() and "running" or "stopped")
    end
    local off = telemetry.disabled() or {}
    kv("disabled for good", #off > 0 and table.concat(off, ", ") or "none")
  else
    kv("telemetry", "FAILED to load: " .. tostring(telemetry))
  end

  section("Cache")
  local cache = vim.fn.stdpath("cache")
  for _, sub in ipairs({ "/runtime-analysis", "/lib.nvim/cache" }) do
    local dir = cache .. sub
    if vim.fn.isdirectory(dir) == 1 then
      local bytes, cut = folder_size(dir)
      kv(dir, ("%d bytes%s"):format(bytes, cut and " or more (walk stopped)" or ""))
    else
      kv(dir, "does not exist")
    end
  end

  section("Request history")
  local ok_hist, history = pcall(require, "runtime-analysis.history")
  local ok_list, entries, list_err = false, nil, nil
  if ok_hist then
    ok_list, entries, list_err = pcall(history.list)
  end
  -- The number only: the URLs of a history are the user's, however redacted.
  kv("entries of this project", ok_list and #entries or "could not be read")
  if list_err then
    kv("history file", "could not be read as JSON")
  end

  section("Environments (names only)")
  local ok_env, env = pcall(require, "runtime-analysis.env")
  local ok_names, names = false, nil
  if ok_env then
    ok_names, names = pcall(env.list_names)
  end
  kv(
    "defined",
    ok_names and (#names > 0 and table.concat(names, ", ") or "none") or "could not be read"
  )
  if ok_env then
    kv("active", env.current() or "none")
  end

  section("Siblings")
  for _, row in ipairs(M.siblings()) do
    if not row.found then
      kv(row.name, "not installed")
    else
      kv(
        row.name,
        ("%s (%s)%s"):format(
          row.root,
          row.commit or "no git checkout",
          row.error and (" FAILS TO LOAD: " .. row.error) or ""
        )
      )
    end
  end

  return lines
end

---Write the report to a new file in a temporary directory. A file that could not be written is an
---error, not a path: the report is the hand-off.
---@return string|nil path
---@return string|nil err
function M.run()
  local dir = vim.fn.tempname()
  if vim.fn.mkdir(dir, "p") ~= 1 then
    return nil, "cannot create " .. dir
  end
  local path = dir .. "/runtime-analysis-diagnostics.txt"
  if vim.fn.writefile(M.collect(), path) ~= 0 then
    return nil, "cannot write " .. path
  end
  return path
end

return M
