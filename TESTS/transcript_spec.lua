-- TESTS/transcript_spec.lua — `:RA transcript`: off by default, grows per send, holds a failure and a
-- cancellation, no secret, and mdview missing is a hint, not an error.

return function(H)
  local eq, ok = H.eq, H.ok
  local transcript = require("runtime-analysis.transcript")
  local history = require("runtime-analysis.history")

  local RENDERERS = {
    "runtime-analysis.telemetry.renderers.mdview",
    "runtime-analysis.telemetry.renderers.preview_tab",
  }
  local saved = {}
  for _, name in ipairs(RENDERERS) do
    saved[name] = package.loaded[name]
  end
  local opened = {}
  package.loaded[RENDERERS[1]] = {
    available = function()
      return false
    end,
  }
  package.loaded[RENDERERS[2]] = {
    available = function()
      return false, "no mdview"
    end,
  }

  local dir = vim.fn.tempname()
  local function text()
    return table.concat(vim.fn.readfile(transcript.path()), "\n")
  end

  local ran, err = pcall(function()
    eq(transcript.is_on(), false, "off by default")
    history.record("GET", "https://example.com/a", 200, nil, { dir = dir })
    eq(transcript.path(), nil, "and a send leaves no file")

    -- mdview missing: a hint, and the protocol still runs.
    local path, on_err = transcript.on()
    ok(path, tostring(on_err))
    eq(transcript.is_on(), true, "on")
    ok(not path:find(vim.fn.stdpath("cache"), 1, true), "not in the cache folder")
    local before = #vim.fn.readfile(path)

    history.record("GET", "https://example.com/a?token=s3cret", 200, nil, { dir = dir })
    eq(#vim.fn.readfile(path), before + 1, "a send adds a line")
    ok(text():find("**GET**", 1, true) and text():find("→ 200", 1, true), "method and status")
    ok(not text():find("s3cret", 1, true), "through the redacted URL: " .. text())

    history.record("POST", "https://example.com/b", nil, "connection refused", { dir = dir })
    ok(text():find("connection refused", 1, true), "a failure shows")
    history.record("GET", "https://example.com/c", nil, "cancelled", { dir = dir })
    ok(text():find("cancelled", 1, true), "a cancellation shows")

    transcript.add("GET", "https://example.com/d\nforged", 200)
    ok(not text():find("\nforged", 1, true), "a line break does not open a new line")

    -- With mdview: the browser path gets the file.
    transcript.off()
    package.loaded[RENDERERS[1]] = {
      available = function()
        return true
      end,
      open = function(lines, target)
        opened[#opened + 1] = { lines = lines, path = target }
        return true
      end,
    }
    local again = transcript.on()
    eq(opened[1] and opened[1].path, again, "mdview watches the protocol's file")
    eq(transcript.on(), again, "on again keeps the file")
    eq(#opened, 2, "and shows it again")

    -- A failing view is a message; the protocol stays on.
    package.loaded[RENDERERS[1]].open = function()
      return false, "no relay"
    end
    transcript.on()
    eq(transcript.is_on(), true, "a view that fails does not stop it")

    local file = transcript.path()
    transcript.off()
    eq(vim.fn.filereadable(file), 0, "off removes the file")
    transcript.off()
    transcript.add("GET", "https://example.com/e", 200)
    eq(transcript.is_on(), false, "and stays off")
  end)

  transcript.off()
  vim.fn.delete(dir, "rf")
  for _, name in ipairs(RENDERERS) do
    package.loaded[name] = saved[name]
  end
  if not ran then
    error(err, 0)
  end
end
