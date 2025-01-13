local asrEnum = require "autosizer_pk/autosizer_enums"

local asrHelper = {}

function asrHelper.tprint(tbl, indent)
    if type(tbl) ~= 'table' then return print(tbl) end
    if not indent then indent = 0 end
    for k, v in pairs(tbl) do
      local formatting = string.rep("  ", indent) .. k .. ": "
      if type(v) == "table" then
        print(formatting)
        asrHelper.tprint(v, indent + 1)
      elseif type(v) == 'boolean' then
        print(formatting .. tostring(v))
      else
        print(formatting .. tostring(v))
      end
    end
  end

function asrHelper.getSortOrder(array, field)

  local keysTable = {}
  local counter = 0
  for key in pairs(array) do
      table.insert(keysTable, { key = key, index = counter} )
      counter = counter + 1
  end
  table.sort(keysTable, function(a,b)
      return string.lower(array[a.key][field]) < string.lower(array[b.key][field])
  end)

  local sortOrder = {}
  for i, val in ipairs(keysTable) do
      table.insert(sortOrder, val.index)
  end
  return sortOrder
end

function asrHelper.getFirstSortedKey(array, field)

  if array and type(array) == "table" then 
    local keysTable = {}
    for key in pairs(array) do
        table.insert(keysTable, key )
    end
    table.sort(keysTable, function(a,b)
        return string.lower(array[a][field]) < string.lower(array[b][field])
    end)

    return keysTable[1]
  end
end

function asrHelper.filterOutInvalid(array)

  if array and type(array) == "table" then 
    local filteredTable = {}
    for key, value in pairs(array) do
        if value[asrEnum.line.STATUS] ~= "Invalid" then
            filteredTable[key] = value
        end
    end

    return filteredTable
  end
end

function asrHelper.filterTable(array, property, matchString)

  if array and type(array) == "table" then 
    local filteredTable = {}
    for key, value in pairs(array) do
      if string.find(string.lower(tostring(value[property])), string.lower(matchString)) then
          filteredTable[key] = value
        end
    end
    return filteredTable
  end
end


function asrHelper.inTable(table, value)
  if table == nil then
    return false
  end
  for _, v in ipairs(table) do
    if v == value then 
      return true
    end
  end
  return false
end

function asrHelper.tablesAreIdentical(table1, table2)

    if type(table1) ~= "table" or type(table2) ~= "table" then
        return false
    end

    -- Check if tables have the same keys and values
    for key, value in pairs(table1) do
        if type(value) == "table" and type(table2[key]) == "table" then
            if not asrHelper.tablesAreIdentical(value, table2[key]) then
                return false
            end
        elseif value ~= table2[key] then
            return false
        end
    end

    -- Ensure t2 has no extra keys
    for key in pairs(table2) do
        if table1[key] == nil then
            return false
        end
    end

    return true
end

function asrHelper.getTableLength(table)

  if type(table) ~= "table" then return nil end
  local length = 0
  for _ in pairs(table) do
    length = length + 1
  end
  return length
end

function asrHelper.getUniqueTimestamp()

  math.randomseed(os.time())
  return tostring(os.time()) .. "." .. tostring(math.random(10000))
end

function asrHelper.average(table)

  if not table then return 0 end 
  local total = 0
  for _, value in pairs(table) do
      total = total + value
  end
  return total/#table
end

function asrHelper.max(table)

  if not table then return 0 end 
  local max = 0
  for _, value in pairs(table) do
      if value > max then max = value end
  end
  return max
end

function asrHelper.tableCreate(size)

  local table = {}
  for i = 1, size do
    table[i] = false
  end

  return table
end

return asrHelper
