local util = require "nap.util"

local M = {}

---Expand top-level import specs in a list.
---Nested imports inside imported modules are skipped with a warning.
---@param spec_list table[]
---@return table[]
function M.expand(spec_list)
  local expanded = {}
  for _, raw in ipairs(spec_list) do
    if raw.import then
      local ok, result = pcall(require, raw.import)
      if not ok then
        util.error(
          ("failed to import '%s': %s"):format(raw.import, result)
        )
      elseif type(result) ~= "table" then
        util.error(
          ("import '%s' did not return a table"):format(raw.import)
        )
      else
        local count = 0
        for _, imported in ipairs(result) do
          if imported.import then
            util.warn(
              ("nested import '%s' in '%s' is not supported in v1; skipping")
                :format(imported.import, raw.import)
            )
          else
            expanded[#expanded + 1] = imported
            count = count + 1
          end
        end
        util.info(
          ("imported %d specs from '%s'"):format(count, raw.import)
        )
      end
    else
      expanded[#expanded + 1] = raw
    end
  end
  return expanded
end

return M
