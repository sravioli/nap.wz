local util = require "nap.util"

local M = {}

---Fields that are overridden (not merged) by later specs.
local SCALAR_FIELDS = {
  "url",
  "dev",
  "dir",
  "enabled",
  "priority",
  "config",
  "_shorthand",
  "_resolved_url",
}

---Merge a list of normalized specs by name.
---Later specs override scalar fields; opts are deep-merged; groups are
---concatenated and deduped.
---@param specs table[]
---@return table[]
function M.merge(specs)
  local registry = {} -- name -> merged spec
  local order = {} -- list preserving first-seen order (name or unnamed spec)
  local seen = {} -- name -> true

  for _, s in ipairs(specs) do
    local name = s.name
    if not name then
      -- Unnamed specs cannot be merged; keep as-is
      order[#order + 1] = s
    elseif not seen[name] then
      seen[name] = true
      registry[name] = s
      order[#order + 1] = name
    else
      -- Merge into existing spec
      local existing = registry[name]

      -- Deep-merge opts
      if s.opts and existing.opts then
        existing.opts = util.deep_merge(existing.opts, s.opts)
      elseif s.opts then
        existing.opts = s.opts
      end

      -- Concatenate and dedupe groups
      if s.groups then
        existing.groups = existing.groups or {}
        for _, g in ipairs(s.groups) do
          existing.groups[#existing.groups + 1] = g
        end
        existing.groups = util.dedupe(existing.groups)
      end

      -- Override scalar fields
      for _, field in ipairs(SCALAR_FIELDS) do
        if s[field] ~= nil then
          existing[field] = s[field]
        end
      end
    end
  end

  -- Rebuild list in declaration order
  local result = {}
  for _, entry in ipairs(order) do
    if type(entry) == "string" then
      result[#result + 1] = registry[entry]
    else
      result[#result + 1] = entry
    end
  end

  return result
end

return M
