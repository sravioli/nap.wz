---Lightweight schema validation engine for nap.wz.
---
---Field descriptor shape:
---```lua
---{
---  type     = "string"|"number"|"boolean"|"table"|"function",
---  types    = { "boolean", "table" },  -- union: alternative to `type`
---  required = false,
---  default  = <value>,   -- scalar default applied by apply_defaults()
---  enum     = { "a", "b" }, -- allowed string values (for string fields)
---  min      = 0,         -- numeric lower bound (inclusive)
---  max      = 100,       -- numeric upper bound (inclusive)
---  fields   = { ... },   -- nested field schema (for table-typed fields)
---}
---```
---
---All user-facing nap opts should carry `default` on every leaf so that
---`apply_defaults({}, schema)` alone produces a fully-populated config.

local M = {}

---Deep-copy a value. Used to avoid sharing table references from defaults.
---@param t any
---@return any
local function deep_copy(t)
  if type(t) ~= "table" then
    return t
  end
  local clone = {}
  for k, v in pairs(t) do
    clone[k] = deep_copy(v)
  end
  return clone
end

---Apply schema defaults recursively to a value table.
---For every field in schema_def:
---  - If the field descriptor has nested `fields`, recurse into that sub-table.
---  - If the field value is nil and the descriptor has a non-nil `default`, use it.
---@param value  table|nil  input (nil or non-table is treated as an empty table)
---@param schema_def table  schema definition mapping field names to descriptors
---@return table  a new table with all defaults filled in
function M.apply_defaults(value, schema_def)
  if type(value) ~= "table" then
    value = {}
  end

  local result = {}
  for k, v in pairs(value) do
    result[k] = v
  end

  for field, descriptor in pairs(schema_def) do
    if type(descriptor.fields) == "table" then
      local nested = type(result[field]) == "table" and result[field] or nil
      result[field] = M.apply_defaults(nested, descriptor.fields)
    elseif result[field] == nil and descriptor.default ~= nil then
      result[field] = deep_copy(descriptor.default)
    end
  end

  return result
end

---Validate a value against a schema definition.
---Errors are collected and returned; this function never throws.
---Call after apply_defaults() so that missing-but-defaulted fields are present.
---@param value      table      value to validate
---@param schema_def table      schema definition
---@param path?      string     key-path prefix for error messages (default: "opts")
---@param errors?    string[]   accumulator for recursion; pass nil on the first call
---@return boolean ok           true when no errors were found
---@return string[] errors      list of human-readable error strings
function M.validate(value, schema_def, path, errors)
  path = path or "opts"
  errors = errors or {}

  if type(value) ~= "table" then
    errors[#errors + 1] = path .. " must be a table, got " .. type(value)
    return false, errors
  end

  for field, descriptor in pairs(schema_def) do
    local field_path = path .. "." .. field
    local field_value = value[field]

    if descriptor.required == true and field_value == nil then
      errors[#errors + 1] = field_path .. " is required"
    end

    if field_value ~= nil then
      -- type / types check (types wins over type when both present)
      local allowed = descriptor.types or (descriptor.type and { descriptor.type } or nil)
      if allowed then
        local matched = false
        for _, t in ipairs(allowed) do
          if type(field_value) == t then
            matched = true
            break
          end
        end
        if not matched then
          errors[#errors + 1] = ("%s must be %s, got %s"):format(
            field_path,
            table.concat(allowed, "|"),
            type(field_value)
          )
        end
      end

      -- enum check
      if descriptor.enum and type(field_value) == "string" then
        local valid = false
        for _, allowed_val in ipairs(descriptor.enum) do
          if field_value == allowed_val then
            valid = true
            break
          end
        end
        if not valid then
          errors[#errors + 1] = ("%s must be one of [%s], got '%s'"):format(
            field_path,
            table.concat(descriptor.enum, ", "),
            field_value
          )
        end
      end

      -- numeric range checks
      if type(field_value) == "number" then
        if descriptor.min ~= nil and field_value < descriptor.min then
          errors[#errors + 1] = ("%s must be >= %g, got %g"):format(
            field_path,
            descriptor.min,
            field_value
          )
        end
        if descriptor.max ~= nil and field_value > descriptor.max then
          errors[#errors + 1] = ("%s must be <= %g, got %g"):format(
            field_path,
            descriptor.max,
            field_value
          )
        end
      end

      -- recurse into nested table fields
      if descriptor.fields and type(field_value) == "table" then
        M.validate(field_value, descriptor.fields, field_path, errors)
      end
    end
  end

  return #errors == 0, errors
end

return M
