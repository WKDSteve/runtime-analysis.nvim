---@module 'runtime-analysis.shape'
--- The shape of an HTTP response: what `:RA send` records next to the
--- status, so a later reader can say "this route is documented as an object
--- and answered with an array" without anyone ever storing the answer.
---
--- **Shape, never content** (SEC-11, SEC-13): the top-level JSON type, the
--- key names one level deep with the *type* of each value (only keys that
--- look like field names, see `M.MAX_KEY_LEN`; the rest is counted), and the media
--- type of the `Content-Type` header. No values, no other headers, no body.
--- A response that is not JSON (or claims to be and does not decode)
--- carries the media type only.
---
--- Every part is capped (SEC-32), for the same reason the telemetry
--- fingerprints are: the history file is committed-adjacent data whose
--- size must follow how much it is used, not how wide one API's answer
--- happens to be. `M.sanitize` re-applies the same caps on the read side,
--- because a history file on disk is untrusted input (SEC-33).

local M = {}

---At most this many keys of a top-level object are kept (sorted, so the
---same answer keeps the same keys); the rest is only counted in `more`.
---Guards against a map-shaped answer (`{ "<id>": {...}, ... }`) turning one
---history entry into a copy of its key set.
M.MAX_KEYS = 32

---Media types longer than this are cut (a header value is not ours to keep
---in full).
M.MAX_NAME = 64

---A key name is stored only when it looks like a field name: at most this
---long, starting with a letter, `_`, `@` or `$`, made of letters, digits and
---`_ - . $ @`, with at most `MAX_KEY_DIGITS` digits and, when it mixes
---cases, not more than a third upper-case letters. Every other key is only
---counted in `opaque`, its name never stored.
---
---A whitelist (SEC-40) rather than a length cap: a map-shaped answer
---(`{ "<token>": {...}, "user_123456": {...} }`) uses data as its keys, and
---most tokens and IDs are far shorter than any cap that still fits real
---field names, so a cap alone kept up to `MAX_KEYS` of them in clear. Hex,
---base64 and numeric IDs carry digits; real field names rarely carry more
---than a few (`address2`, `v1_url`). The price: a field name with many
---digits is counted instead of named, and a random key with few digits can
---still pass (unlikely, not impossible).
M.MAX_KEY_LEN = 40
M.MAX_KEY_DIGITS = 3

---Whether `k` may be stored as a key name (see `MAX_KEY_LEN`).
---@param k any
---@return boolean
function M.is_field_name(k)
  if type(k) ~= "string" or #k > M.MAX_KEY_LEN then
    return false
  end
  if not k:match("^[%a_@$][%w_%-%.$@]*$") then
    return false
  end
  local _, digits = k:gsub("%d", "")
  if digits > M.MAX_KEY_DIGITS then
    return false
  end
  -- Base64 mixes cases at random (`eyJhbGciOiJ...`, often with few digits);
  -- a camelCase field name has few humps. More than a third upper-case
  -- letters (and at least three) next to lower-case ones reads as data.
  -- All upper-case (`HTTP_STATUS`) stays a name.
  local _, upper = k:gsub("%u", "")
  if upper >= 3 and k:find("%l") and upper * 3 > #k then
    return false
  end
  return true
end

---A non-negative finite count from `v`, else 0. `1e999` in a file decodes
---to `inf`, which `vim.json.encode` refuses, and the next history write
---would fail.
---@internal
---@param v any
---@return integer
local function finite_count(v)
  if type(v) == "number" and v >= 1 and v < math.huge then
    return math.floor(v)
  end
  return 0
end

---The type tags a shape may use.
---@type table<string, true>
local TYPES = {
  object = true,
  array = true,
  string = true,
  number = true,
  boolean = true,
  null = true,
  mixed = true,
}

---The metatable `vim.json.decode` puts on an empty object (`{}`), taken
---once rather than per value.
local EMPTY_DICT_MT = getmetatable(vim.empty_dict())

---@internal
---@param s string
---@return string
local function cap(s)
  if #s > M.MAX_NAME then
    return s:sub(1, M.MAX_NAME)
  end
  return s
end

---The JSON type of one decoded value. `vim.json.decode` keeps the two empty
---containers apart: `[]` is a list, `{}` carries `vim.empty_dict()`'s
---metatable.
---@internal
---@param v any
---@return string
local function type_of(v)
  if v == vim.NIL or v == nil then
    return "null"
  end
  local t = type(v)
  if t == "table" then
    if EMPTY_DICT_MT ~= nil and getmetatable(v) == EMPTY_DICT_MT then
      return "object"
    end
    return vim.islist(v) and "array" or "object"
  end
  if t == "string" or t == "number" or t == "boolean" then
    return t
  end
  return "null"
end

---The type every element of `list` shares, `"mixed"` when they differ, or
---`nil` for an empty list.
---@internal
---@param list any[]
---@return string?
local function items_of(list)
  local items
  for _, v in ipairs(list) do
    local t = type_of(v)
    if items == nil then
      items = t
    elseif items ~= t then
      return "mixed"
    end
  end
  return items
end

---The media type of `headers`' `Content-Type`, lower-cased, without its
---parameters (`; charset=...`), capped.
---@param headers table<string, string>?
---@return string?
function M.content_type(headers)
  for name, value in pairs(headers or {}) do
    if type(name) == "string" and name:lower() == "content-type" and type(value) == "string" then
      local media = vim.trim((value:match("^[^;]*") or ""):lower())
      if media ~= "" then
        return cap(media)
      end
    end
  end
  return nil
end

---@class RA.Shape
---@field content_type string? Media type of the `Content-Type` header, without parameters
---@field type string? Top-level JSON type: object, array, string, number, boolean or null; absent when the body is not JSON
---@field keys table<string, string>? For an object: key name -> type of its value, at most `MAX_KEYS` of them
---@field more integer? For an object: how many field-name keys were left out of `keys` (past `MAX_KEYS`)
---@field opaque integer? For an object: how many keys did not look like a field name and were only counted
---@field items string? For a non-empty array: the type all elements share, or `"mixed"`

---Split `names` into the field names kept in `keys` (sorted, at most
---`MAX_KEYS`, each with `type_for(name)`) and two counts: field names past
---the cap (`more`) and keys that are no field name at all (`opaque`).
---@internal
---@param names string[]
---@param type_for fun(name: string): string
---@return table<string, string> keys
---@return integer more
---@return integer opaque
local function split_keys(names, type_for)
  local fields, opaque = {}, 0
  for _, k in ipairs(names) do
    if M.is_field_name(k) then
      fields[#fields + 1] = k
    else
      opaque = opaque + 1
    end
  end
  table.sort(fields)
  local keys = {}
  for i = 1, math.min(#fields, M.MAX_KEYS) do
    keys[fields[i]] = type_for(fields[i])
  end
  return keys, math.max(#fields - M.MAX_KEYS, 0), opaque
end

---The shape of one response. `is_json` is the runner's own finding (header
---says JSON *and* the body decoded); `decoded` is the value it decoded, so
---the body is parsed once. `nil` when there is nothing to say (no
---`Content-Type` and no JSON).
---@param headers table<string, string>?
---@param is_json boolean
---@param decoded any The decoded body when `is_json`
---@return RA.Shape?
function M.of(headers, is_json, decoded)
  local shape = { content_type = M.content_type(headers) }
  if is_json then
    local t = type_of(decoded)
    shape.type = t
    if t == "object" then
      local names = {}
      for k in pairs(decoded) do
        names[#names + 1] = tostring(k)
      end
      local keys, more, opaque = split_keys(names, function(name)
        return type_of(decoded[name])
      end)
      shape.keys = keys
      shape.more = more > 0 and more or nil
      shape.opaque = opaque > 0 and opaque or nil
    elseif t == "array" then
      shape.items = items_of(decoded)
    end
  end
  if next(shape) == nil then
    return nil
  end
  return shape
end

---A shape read back from disk, re-validated field by field (SEC-33):
---unknown fields and type tags are dropped, strings and the key set are
---capped again. `nil` when nothing valid is left.
---@param raw any
---@return RA.Shape?
function M.sanitize(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local out = {}
  if type(raw.content_type) == "string" and raw.content_type ~= "" then
    out.content_type = cap(raw.content_type)
  end
  if type(raw.type) == "string" and TYPES[raw.type] and raw.type ~= "mixed" then
    out.type = raw.type
  end
  if out.type == "object" and type(raw.keys) == "table" then
    local names = {}
    for k, v in pairs(raw.keys) do
      if type(k) == "string" and type(v) == "string" and TYPES[v] and v ~= "mixed" then
        names[#names + 1] = k
      end
    end
    -- A file written before the field-name whitelist existed may still hold
    -- data-shaped keys: they become `opaque` here, never shown or handed on.
    local keys, more, opaque = split_keys(names, function(name)
      return raw.keys[name]
    end)
    out.keys = keys
    more = more + finite_count(raw.more)
    opaque = opaque + finite_count(raw.opaque)
    out.more = more > 0 and more or nil
    out.opaque = opaque > 0 and opaque or nil
  end
  if out.type == "array" and type(raw.items) == "string" and TYPES[raw.items] then
    out.items = raw.items
  end
  if next(out) == nil then
    return nil
  end
  return out
end

---One short line for a shape: `object{id,name,+3,+5 opaque}`,
---`array<object>`, `text/html`. For pickers and the traffic view.
---@param shape RA.Shape?
---@return string
function M.summary(shape)
  if type(shape) ~= "table" then
    return "-"
  end
  if shape.type == "object" then
    local names = vim.tbl_keys(shape.keys or {})
    table.sort(names)
    if shape.more then
      names[#names + 1] = "+" .. shape.more
    end
    if shape.opaque then
      names[#names + 1] = "+" .. shape.opaque .. " opaque"
    end
    return "object{" .. table.concat(names, ",") .. "}"
  elseif shape.type == "array" then
    return "array<" .. (shape.items or "empty") .. ">"
  elseif shape.type then
    return shape.type
  end
  return shape.content_type or "-"
end

return M
