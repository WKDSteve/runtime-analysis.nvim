-- Test code: a nil here must crash and name itself, not be guarded away.
---@diagnostic disable: need-check-nil
-- TESTS/telemetry_timing_spec.lua — per-day timing and duration buckets
--
-- The aggregate used to keep one lifetime `total/min/max` per function, so a
-- re-measurement could not tell a fix that moved the mean from a few
-- outliers on one day. These specs pin the two additions that answer that:
-- `timing.buckets`/`bucket_ms` (a coarse histogram) and `timing.days`
-- (per-day `{ n, total_ms, max_ms }`), both additive to the existing JSON.

return function(H)
  local telemetry = require("runtime-analysis.telemetry")
  local store = require("runtime-analysis.telemetry.store")
  local report = require("runtime-analysis.telemetry.report")

  local seq = 0
  local function ns(name)
    seq = seq + 1
    return ("spec.timing.%s.%d"):format(name, seq)
  end

  local tmpdir = vim.fn.tempname() .. "-telemetry-timing"
  vim.fn.mkdir(tmpdir, "p")

  local function same(a, b, msg)
    H.ok(
      vim.deep_equal(a, b),
      ("%s (got %s)"):format(msg, vim.inspect(a, { newline = " ", indent = "" }))
    )
  end

  local function close(a, b, msg)
    H.ok(math.abs(a - b) < 1e-9, ("%s (got %s, want %s)"):format(msg, tostring(a), tostring(b)))
  end

  -- -------------------------------------------------------------------------
  -- bucket boundaries: the upper bound of each bucket is exclusive
  -- -------------------------------------------------------------------------
  H.eq(store.BUCKETS, 5, "five buckets")
  H.eq(store.bucket_of(0), 1, "0 ms is a free call")
  H.eq(store.bucket_of(0.999), 1, "just under 1 ms")
  H.eq(store.bucket_of(1), 2, "1 ms starts the second bucket")
  H.eq(store.bucket_of(9.99), 2, "just under 10 ms")
  H.eq(store.bucket_of(10), 3, "10 ms starts the third bucket")
  H.eq(store.bucket_of(999.9), 4, "just under 1 s")
  H.eq(store.bucket_of(1000), 5, "1 s is an outlier")
  H.eq(store.bucket_of(1e9), 5, "anything larger stays in the last bucket")
  H.eq(#report.BUCKET_LABELS, store.BUCKETS, "one label per bucket")

  -- -------------------------------------------------------------------------
  -- recording: buckets, bucket time and the day row of a timed call
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("record")
    local t = telemetry.new({ namespace = namespace, persist = true, dir = tmpdir })
    for _, dur in ipairs({ 0.002, 0.5, 4, 4, 50, 2000 }) do
      t._record("f", nil, dur, false)
    end
    t._record("counted", nil, nil, false)

    local today = store.today()
    H.ok(t.flush(), "flush succeeds")
    local data = store.load(namespace, { dir = tmpdir })
    local timing = data.functions.f.timing
    same(timing.buckets, { 2, 2, 1, 0, 1 }, "calls per bucket")
    close(timing.bucket_ms[5], 2000, "outlier time lands in the last bucket")
    close(timing.bucket_ms[2], 8, "time of the 1-10 ms bucket")
    H.eq(data.functions.counted.timing, nil, "an untimed key gets no timing")

    local day = timing.days[today]
    H.eq(day[1], 6, "day row counts the timed calls")
    close(day[2], 2058.502, "day row sums the time")
    close(day[3], 2000, "day row keeps the max")
    close(timing.bucket_ms[1], 0.502, "bucket time is rounded to a microsecond")
    H.eq(data.days[today].f, 6, "the call count per day is unchanged")

    -- A second process adds to the same file: buckets and day rows merge.
    local t2 = telemetry.new({ namespace = namespace, persist = true, dir = tmpdir })
    t2._record("f", nil, 3000, false)
    t2._record("f", nil, 0.1, false)
    H.ok(t2.flush(), "second flush succeeds")
    data = store.load(namespace, { dir = tmpdir })
    same(data.functions.f.timing.buckets, { 3, 2, 1, 0, 2 }, "buckets add up across processes")
    H.eq(data.functions.f.timing.days[today][1], 8, "day rows add up across processes")
    close(data.functions.f.timing.days[today][3], 3000, "day max is the max of both")

    -- The report built from it.
    local r = t2.report()
    local e
    for _, x in ipairs(r.entries) do
      if x.key == "f" then
        e = x
      end
    end
    H.eq(e.bucketed, 8, "all timed calls are bucketed")
    H.eq(e.timing_n, 8, "timed calls behind the mean")
    H.eq(e.outliers, 2, "two calls of 1 s or more")
    H.eq(e.median_bucket, 2, "the median call is in the 1-10 ms bucket")
    close(e.outlier_share, 5000 / 5058.602, "outlier share of the bucketed time")
    close(e.mean_ms_without_outliers, 58.602 / 6, "mean of the other six calls")
    H.eq(#e.days, 1, "one day row")
    H.eq(e.days[1].day, today, "named by its date")

    local md = table.concat(t2.markdown(), "\n")
    H.ok(
      md:find("| Function | Calls | Ø ms | Max ms | Median | ≥ 1 s | Errors |", 1, true) ~= nil,
      "distribution columns in the table"
    )
    H.ok(md:find("| < 10 ms | 2 (99 % of time) |", 1, true) ~= nil, "median and outlier cells")
    H.ok(
      md:find("### `f` — timing distribution", 1, true) ~= nil,
      "section for the function with outliers"
    )
    H.ok(md:find("Ø without calls ≥ 1 s: 9.77 ms", 1, true) ~= nil, "mean without outliers")
    H.ok(md:find("| " .. today .. " | 8 |", 1, true) ~= nil, "day row in the section")
    H.ok(md:find("### `counted`", 1, true) == nil, "no section for a function without outliers")
  end

  -- -------------------------------------------------------------------------
  -- backward compatibility: a file written before buckets and timing.days existed
  -- -------------------------------------------------------------------------
  do
    local namespace = ns("compat")
    local old = {
      version = store.VERSION,
      started_at = os.time(),
      sessions = 3,
      functions = {
        g = { calls = 10, timing = { n = 10, total_ms = 50, min_ms = 1, max_ms = 20 } },
      },
      days = { [store.today()] = { g = 10 } },
      reminded = {},
    }
    H.ok(store.save(namespace, old, { dir = tmpdir }), "old-shape file written")

    local t = telemetry.new({ namespace = namespace, persist = true, dir = tmpdir })
    local md = table.concat(t.markdown(), "\n")
    H.ok(
      md:find("| Function | Calls | Ø ms | Errors |", 1, true) ~= nil,
      "old data keeps the old table"
    )
    local e = t.report().entries[1]
    H.eq(e.buckets, nil, "no buckets reported for old data")
    H.eq(e.days, nil, "no day rows for old data")

    -- New calls on top: the buckets cover only them, and the section says so.
    t._record("g", nil, 1500, false)
    H.ok(t.flush(), "flush on top of old data")
    local data = store.load(namespace, { dir = tmpdir })
    H.eq(data.functions.g.timing.n, 11, "lifetime count keeps the old calls")
    same(data.functions.g.timing.buckets, { 0, 0, 0, 0, 1 }, "buckets start with the new calls")
    md = table.concat(t.markdown(), "\n")
    H.ok(
      md:find("_Buckets cover 1 of 11 timed calls (older data has none)._", 1, true) ~= nil,
      "partial coverage is stated"
    )
  end

  -- -------------------------------------------------------------------------
  -- retention: timing.days is pruned with days
  -- -------------------------------------------------------------------------
  do
    local data = store.empty()
    local old_day = os.date("%Y-%m-%d", os.time() - 40 * 86400)
    local today = store.today()
    data.days[old_day] = { f = 1 }
    data.days[today] = { f = 1 }
    data.functions.f = {
      calls = 2,
      timing = {
        n = 2,
        total_ms = 10,
        min_ms = 5,
        max_ms = 5,
        days = { [old_day] = { 1, 5, 5 }, [today] = { 1, 5, 5 } },
      },
    }
    data.functions.untimed = { calls = 1 }
    H.eq(store.prune(data, 30), 1, "one old call-count day dropped")
    H.eq(data.functions.f.timing.days[old_day], nil, "the old timing day is dropped too")
    H.ok(data.functions.f.timing.days[today] ~= nil, "today's timing stays")
  end

  vim.fn.delete(tmpdir, "rf")
end
