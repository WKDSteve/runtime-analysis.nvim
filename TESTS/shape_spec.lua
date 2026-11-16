-- TESTS/shape_spec.lua — runtime-analysis.shape: the shape of an answer,
-- never its content.

return function(H)
  local eq, ok = H.eq, H.ok
  ---Deep equality (`H.eq` compares tables by reference).
  local function same(a, b, msg)
    H.ok(
      vim.deep_equal(a, b),
      ("%s: expected %s, got %s"):format(msg, vim.inspect(b), vim.inspect(a))
    )
  end
  local shape = require("runtime-analysis.shape")
  local JSON = { ["Content-Type"] = "application/json; charset=utf-8" }

  ---@param body string
  ---@return RA.Shape?
  local function of_json(body)
    return shape.of(JSON, true, vim.json.decode(body))
  end

  -- Object: key names with the type of each value, one level deep.
  do
    local s = assert(of_json('{"id":1,"name":"x","ok":true,"tags":[],"meta":{"a":1},"gone":null}'))
    eq(s.type, "object", "shape: an object is an object")
    same(s.keys, {
      id = "number",
      name = "string",
      ok = "boolean",
      tags = "array",
      meta = "object",
      gone = "null",
    }, "shape: ... with every key and the type of its value")
    eq(s.more, nil, "shape: ... and nothing left out")
    eq(s.content_type, "application/json", "shape: the media type, without its parameters")
    ok(not vim.inspect(s):find('"x"', 1, true), "shape: no value is kept")
  end

  -- Nested: only one level deep; the inner object is a type tag, not keys.
  do
    local s = assert(of_json('{"user":{"id":1,"address":{"city":"Graz"}}}'))
    same(s.keys, { user = "object" }, "shape: nested objects stay a type tag")
    ok(not vim.inspect(s):find("city", 1, true), "shape: ... their keys are not recorded")
  end

  -- Arrays: the shared element type, or `mixed`.
  do
    eq(of_json('[{"a":1},{"b":2}]').items, "object", "shape: an array of objects")
    eq(of_json('[1,"a"]').items, "mixed", "shape: an array of different types is mixed")
    eq(of_json("[1,2]").type, "array", "shape: an array is an array")
  end

  -- Empty: `{}` and `[]` stay apart, and neither invents keys or items.
  do
    local obj = assert(of_json("{}"))
    eq(obj.type, "object", "shape: {} is an empty object, not an array")
    same(obj.keys, {}, "shape: ... with no keys")
    local arr = assert(of_json("[]"))
    eq(arr.type, "array", "shape: [] is an empty array")
    eq(arr.items, nil, "shape: ... with no element type")
  end

  -- Scalars and null at the top level.
  do
    eq(of_json('"hi"').type, "string", "shape: a top-level string")
    eq(of_json("3").type, "number", "shape: a top-level number")
    eq(of_json("null").type, "null", "shape: a top-level null")
  end

  -- A very wide object: capped at MAX_KEYS, sorted, the rest counted.
  do
    local parts = {}
    for i = 1, shape.MAX_KEYS + 10 do
      parts[#parts + 1] = ('"k%03d":%d'):format(i, i)
    end
    local s = assert(of_json("{" .. table.concat(parts, ",") .. "}"))
    eq(vim.tbl_count(s.keys), shape.MAX_KEYS, "shape: a wide object keeps MAX_KEYS keys")
    eq(s.more, 10, "shape: ... and counts the rest")
    eq(s.keys.k001, "number", "shape: ... the first keys in sorted order")
    eq(s.keys["k" .. ("%03d"):format(shape.MAX_KEYS + 1)], nil, "shape: ... not the later ones")
  end

  -- A key that is itself long data is cut.
  do
    local long = ("x"):rep(500)
    local s = assert(of_json(('{"%s":1}'):format(long)))
    local name = next(s.keys)
    eq(#name, shape.MAX_NAME, "shape: a long key name is capped")
  end

  -- Not JSON: the media type only.
  do
    local s = shape.of({ ["content-type"] = "text/html; charset=utf-8" }, false, nil)
    same(s, { content_type = "text/html" }, "shape: a non-JSON answer carries its media type only")
    eq(shape.of({}, false, nil), nil, "shape: no Content-Type and no JSON: nothing to record")
  end

  -- An error answer is shaped like any other answer.
  do
    local s = assert(of_json('{"error":"not found","code":404}'))
    same(s.keys, { error = "string", code = "number" }, "shape: an error body has a shape too")
  end

  -- Read side (SEC-33): a hand-edited shape is re-validated.
  do
    eq(shape.sanitize("object"), nil, "sanitize: a non-table is dropped")
    eq(shape.sanitize({ type = "evil" }), nil, "sanitize: an unknown type tag is dropped")
    local keys = { good = "string", bad = "value-not-a-type", [1] = "number" }
    for i = 1, shape.MAX_KEYS + 5 do
      keys[("z%03d"):format(i)] = "number"
    end
    local s = assert(shape.sanitize({ type = "object", keys = keys, extra = "x", more = 2 }))
    eq(rawget(s, "extra"), nil, "sanitize: unknown fields are dropped")
    eq(s.keys.bad, nil, "sanitize: a key whose type is not a type tag is dropped")
    eq(s.keys.good, "string", "sanitize: a valid key stays")
    eq(vim.tbl_count(s.keys), shape.MAX_KEYS, "sanitize: the key cap holds on read too")
    eq(s.more, 2 + 6, "sanitize: ... and the dropped keys are counted")
    local html = { content_type = "text/html" }
    same(shape.sanitize(html), html, "sanitize: a valid shape comes back equal")
  end

  -- Summary lines.
  do
    eq(shape.summary(of_json('{"b":1,"a":2}')), "object{a,b}", "summary: object keys")
    eq(shape.summary(of_json("[1]")), "array<number>", "summary: array element type")
    eq(shape.summary(of_json("[]")), "array<empty>", "summary: empty array")
    eq(shape.summary({ content_type = "text/plain" }), "text/plain", "summary: media type")
    eq(shape.summary(nil), "-", "summary: nothing")
  end
end
