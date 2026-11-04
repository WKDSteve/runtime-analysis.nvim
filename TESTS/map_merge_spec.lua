-- TESTS/map_merge_spec.lua — the generated map gives way in a pull.
--
-- CI commits the regenerated map on main and a session regenerates it in the shared working tree, so
-- `git pull --rebase --autostash` would leave conflict markers. docmap.nvim's map_merge_spec.lua plays the
-- pull through; here it is the attribute this repository has to carry for that.

return function(H)
  local file = assert(io.open(".gitattributes", "rb"))
  local text = file:read("*a"):gsub("\r\n", "\n")
  file:close()
  for _, rel in ipairs({ "docs/map/index.html", "docs/map/module_map.json", "docs/map/overview.md" }) do
    local found
    for line in text:gmatch("[^\n]+") do
      if vim.startswith(line, rel .. " ") then
        found = line
      end
    end
    H.ok(found ~= nil, "`.gitattributes` names " .. rel)
    H.ok(vim.endswith(found or "", " merge=ours"), "the map is merged as generated: " .. rel)
  end
end
