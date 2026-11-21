---@module 'scripts.gen_map'
--- CLI entry point for this repository's own module map, adopted per
--- docmap.nvim's own reuse guide
--- (https://github.com/WKDSteve/docmap.nvim/blob/main/docs/REUSE.md)
--- — the housekeeping section, `scripts/gen_map.lua` +
--- docmap.nvim as a dev dependency.
---
---   nvim --headless -l scripts/gen_map.lua                    # regenerate
---   nvim --headless -l scripts/gen_map.lua --check            # verify, write nothing
---   nvim --headless -l scripts/gen_map.lua --check --lenient  # fail on staleness only
---   nvim --headless -l scripts/gen_map.lua --full             # + LuaLS enrichment
---   nvim --headless -l scripts/gen_map.lua --siblings         # citations into sibling checkouts, writes nothing
---
--- Everything above the options table at the bottom is generic, copied
--- verbatim from docmap.nvim's own copy of this file — see docs/REUSE.md
--- for what changing it would cost future updates. `layers` and a
--- self-rendered `docs/BINDINGS.md` (both present in docmap.nvim's own
--- copy) are deliberately not carried over here: `layers` encodes that
--- repository's own core/editor architecture boundary, which this plugin has
--- no equivalent of, and this repository's `docs/BINDINGS.md` is explicitly
--- hand-maintained (see that file's own header) rather than generated.

local root = vim.uv.cwd():gsub("\\", "/"):gsub("/+$", "")
vim.opt.runtimepath:prepend(root)

--- Put a dependency on the runtimepath, if it is not already reachable.
---
--- A headless `nvim -l` run starts with no plugin manager, so nothing beyond
--- `root` is on the rtp — `docmap` and `lib.nvim` both have to be found
--- by hand. Three candidates, in descending order of explicitness: an
--- environment variable (what CI sets), a `.deps/` checkout (what CI clones
--- into), and a sibling checkout (what a local development tree looks like).
---@param modname string A module the dependency provides, used as the probe.
---@param dirname string Repository directory name.
local function ensure(modname, dirname)
  if pcall(require, modname) then
    return
  end
  -- Built with explicit indices, not a `{a, b, c}` literal fed to `ipairs`:
  -- the environment-variable candidate is `nil` whenever it is unset — the
  -- normal case for CI, which relies on the `.deps/<dirname>` candidate
  -- below instead — and a table literal with `nil` in its first slot makes
  -- `ipairs` stop immediately without ever inspecting the slots after it,
  -- silently skipping every other candidate regardless of whether the
  -- directory actually exists.
  local candidates = {}
  local env_dir = vim.env[dirname:upper():gsub("[.-]", "_") .. "_DIR"]
  if env_dir and env_dir ~= "" then
    candidates[#candidates + 1] = env_dir
  end
  candidates[#candidates + 1] = root .. "/.deps/" .. dirname
  candidates[#candidates + 1] = vim.fs.dirname(root) .. "/" .. dirname
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir) == 1 then
      vim.opt.runtimepath:prepend(dir)
      if pcall(require, modname) then
        return
      end
    end
  end
  io.stderr:write(("gen_map: %s not found (probed require('%s')).\n"):format(dirname, modname))
  io.stderr:write(
    ("  Set %s_DIR, clone it to .deps/%s, or check it out beside this repo.\n"):format(
      dirname:upper():gsub("[.-]", "_"),
      dirname
    )
  )
  os.exit(1)
end

ensure("lib.nvim.fs.read", "lib.nvim")
ensure("docmap.core.cli", "docmap.nvim")

-- `--siblings` is this script's own flag, not docmap's: it is taken out of the
-- argv before docmap sees the rest.
local siblings_mode = false
local argv = {}
for _, a in ipairs(_G.arg or {}) do
  if a == "--siblings" then
    siblings_mode = true
  else
    argv[#argv + 1] = a
  end
end

-- The sibling repositories this tree links to or cites. `name` is the
-- repository *directory* name a doc citation uses, which is not the module
-- prefix the entry is keyed by: `docmap.nvim` against a `docmap` key.
--
-- **No `local_path` in the committed map.** A declared checkout changes the
-- artifact itself (the link shape `a.lua` against `a/init.lua`, and the
-- `sibling-reference-missing` findings in the drift section), so the map a
-- machine with siblings wrote differed from the one a worktree without them
-- wrote, and `--check` was red on one of the two whatever was committed
-- (docmap.nvim's core/external_repos.lua header). Without `local_path` the map
-- is the same bytes everywhere, and `--check` can be a pipeline step.
local siblings = {
  ["lib.nvim"] = { repo = "WKDSteve/lib.nvim", name = "lib.nvim" },
  docmap = { repo = "WKDSteve/docmap.nvim", name = "docmap.nvim" },
  mdview = { repo = "WKDSteve/mdview.nvim", name = "mdview.nvim" },
  ["docmap-desktop"] = { repo = "WKDSteve/docmap-desktop", name = "docmap-desktop" },
}

-- `--siblings`: the citations into sibling repositories, checked against their
-- checkouts (`<NAME>_DIR`, else `../<name>`). This repository is the reason the
-- check exists -- it carried nine dead `docs/ECOSYSTEM.md` citations, a path
-- that only exists in docmap.nvim. Writes nothing.
local env_var = require("docmap.core.external_repos").env_var
if siblings_mode then
  for _, entry in pairs(siblings) do
    local named = os.getenv(env_var(entry))
    entry.local_path = (named and named ~= "") and named or ("../" .. entry.name)
  end
end

local opts = require("docmap.config").build(root, {
  source = "lua/runtime-analysis",
  title = "runtime-analysis.nvim",
  out_dir = "docs/map",
  repo_url = "https://github.com/WKDSteve/runtime-analysis.nvim",
  branch = "main",
  external_repos = siblings,
})

if not siblings_mode then
  vim.cmd("cq " .. require("docmap.core.cli").run(opts, argv))
  return
end

local names = vim.tbl_keys(siblings)
table.sort(names)
for _, key in ipairs(names) do
  local entry = siblings[key]
  local path = entry.local_path:gsub("\\", "/")
  local dir = (path:match("^%a:/") or path:sub(1, 1) == "/") and path or (root .. "/" .. path)
  if vim.fn.isdirectory(dir) == 0 then
    io.stdout:write(
      ("n/a  %s: no checkout at %s (set %s)\n"):format(entry.name, entry.local_path, env_var(entry))
    )
  end
end
local _, findings = require("docmap").scan_full(opts)
local missing = 0
for _, f in ipairs(findings) do
  if f.check == "sibling-reference-missing" then
    missing = missing + 1
    io.stdout:write(
      ("%s: %s does not exist in the %s checkout\n"):format(
        f.params.file,
        f.params.target,
        f.params.repo
      )
    )
  end
end
io.stdout:write(("gen_map --siblings: %d missing sibling reference(s)\n"):format(missing))
vim.cmd("cq " .. (missing > 0 and 1 or 0))
