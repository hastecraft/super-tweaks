-- Serializes saved variables for tools/install.py (through lupa), to check copied settings value for value.
local function key(k)
    if type(k) == "string" then return "[" .. string.format("%q", k) .. "]" end
    return "[" .. tostring(k) .. "]"
end

local function scalar(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "number" then
        if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
        return string.format("%.17g", v)
    end
    return tostring(v)
end

local function write(out, value, depth)
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    out[#out + 1] = "{\n"
    for _, k in ipairs(keys) do
        local v = value[k]
        out[#out + 1] = string.rep("\t", depth + 1) .. key(k) .. " = "
        if type(v) == "table" then write(out, v, depth + 1) else out[#out + 1] = scalar(v) end
        out[#out + 1] = ",\n"
    end
    out[#out + 1] = string.rep("\t", depth) .. "}"
end

-- Returns Lua source that assigns `value` to the global `name`, like a SavedVariables file.
function HST_Serialize(name, value)
    local out = { name, " = " }
    write(out, value, 0)
    out[#out + 1] = "\n"
    return table.concat(out)
end
