---@module 'runtime-analysis.telemetry.paths'
--- Where telemetry keeps its persisted data, and the one-time move out of the
--- places it used to live.
---
--- The store lives under `stdpath("state")`, NOT `stdpath("cache")`. On
--- Windows `stdpath("cache")` is `%TEMP%\nvim`, which Windows' own storage
--- sense and every temp cleaner empty without asking: the counters are an
--- accumulated history (weeks of "which function was called how often"), and
--- a before/after comparison across a few days needs them still to be there.
--- Nothing in them can be rebuilt from anything else, so "cache" (deletable
--- at any time, by definition) was the wrong class. `state` rather than
--- `data`: XDG describes `state` as history-like data that should persist
--- across restarts but is not worth carrying to another machine -- exactly
--- what usage counters are. (On Windows both resolve to `nvim-data`.)
---
--- Regenerable outputs (rendered `.md`/`.html` reports, ad-hoc exports) stay
--- under `stdpath("cache")`: losing those costs nothing.
---
--- Kept free of other requires on purpose: `health.lua` reads `M.DIR` and
--- must not pull in the telemetry module to do it.

local uv = vim.uv or vim.loop

local M = {}

---The store root, passed to `lib.nvim.cache.disk` as `opts.dir`; aggregates
---land at `<DIR>/telemetry/<namespace>.json`.
M.DIR = vim.fn.stdpath("state") .. "/runtime-analysis.nvim"

---Roots that held `telemetry/` before, newest first. A file present in more
---than one keeps the first one moved; later ones stay where they are.
---  - `stdpath("cache")/runtime-analysis.nvim/cache`: this plugin's own
---    default until the store moved to `stdpath("state")`.
---  - `stdpath("cache")/lib.nvim/cache`: `lib.nvim.cache.disk`'s default,
---    where telemetry wrote while it was still part of lib.nvim.
M.LEGACY_DIRS = {
  vim.fn.stdpath("cache") .. "/runtime-analysis.nvim/cache",
  vim.fn.stdpath("cache") .. "/lib.nvim/cache",
}

---@internal
---@param path string
---@return string|nil kind "file"|"directory"|...
local function kind_of(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type or nil
end

---Move `src` to `dst` without overwriting anything. Directories that exist
---on both sides are merged entry by entry; a file that exists on both sides
---is left alone in `src` (and reported), so no data is ever replaced.
---@internal
---@param src string
---@param dst string
---@param kept string[] collects every `src` path left behind
---@return integer moved number of entries that ended up in `dst`
local function move(src, dst, kept)
  local src_kind = kind_of(src)
  if not src_kind then
    -- Gone in the meantime (another instance migrating at the same moment).
    return 0
  end
  local dst_kind = kind_of(dst)

  if not dst_kind and uv.fs_rename(src, dst) then
    return 1
  end

  if src_kind == "directory" and (dst_kind == nil or dst_kind == "directory") then
    if not dst_kind then
      -- rename failed (another volume): rebuild the tree by copying.
      vim.fn.mkdir(dst, "p")
    end
    local moved = 0
    local handle = uv.fs_scandir(src)
    while handle do
      local name = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      moved = moved + move(src .. "/" .. name, dst .. "/" .. name, kept)
    end
    -- Fails while anything was kept inside, which is what should happen.
    uv.fs_rmdir(src)
    return moved
  end

  if src_kind == "file" and not dst_kind and uv.fs_copyfile(src, dst) then
    uv.fs_unlink(src)
    return 1
  end

  kept[#kept + 1] = src
  return 0
end

---Move every `<legacy>/telemetry` entry into `<root>/telemetry`. Never
---overwrites: an entry already present under `root` wins, the legacy one
---stays where it is and is listed in `kept`.
---@param legacy_dirs string[]
---@param root string
---@return integer moved
---@return string[] kept
function M.migrate(legacy_dirs, root)
  local moved, kept = 0, {}
  local target = root .. "/telemetry"
  for _, legacy in ipairs(legacy_dirs) do
    local source = legacy .. "/telemetry"
    if source ~= target and kind_of(source) == "directory" then
      vim.fn.mkdir(root, "p")
      moved = moved + move(source, target, kept)
    end
  end
  return moved, kept
end

local migrated = false

---The store root for every real caller (no explicit `opts.dir`). The first
---call per process moves data out of `M.LEGACY_DIRS` (one `fs_stat` each
---once nothing is left there).
---@return string
function M.dir()
  if not migrated then
    migrated = true
    pcall(M.migrate, M.LEGACY_DIRS, M.DIR)
  end
  return M.DIR
end

return M
