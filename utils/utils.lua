local utils = {}

function utils.is_windows()
    return package.config:sub(1, 1) == "\\"
end

function utils.get_extension(filename)
    return filename:match("%.([%d%a]+)$")
end

function utils.read_file(filename, line_parser)
    local fn_not_found = "ERROR: file %q was not found!"
    line_parser = line_parser or function(x) return x end
    local f, data = io.open(filename, 'r'), {}
    assert(f, fn_not_found:format(filename))
    for line in f:lines("*l") do
        table.insert(data, line_parser(line))
    end
    return data
end

function utils.open_file(filename, mode, callback)
    local f = io.open(filename, mode)
    if not f then
        return
    end
    local res = callback(f)
    f:close()
    return res
end

function utils.get_temporary_path()
    if utils.is_windows() then
        local temp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\temp"
        local path = string.format("%s\\sub-tmp-%d", temp, math.random(1000, 9999))
        os.execute(string.format('mkdir "%s" >nul 2>&1', path))
        return path
    else
        local f = io.popen("mktemp -d")
        if f then
            local res = f:lines("*l")()
            f:close()
            return res
        end
    end
end

function utils.split(input, sep, is_regex)
    local splits, last_idx, plain = {}, 1, true
    local function add_substring(from, to)
        local split = input:sub(from, to)
        if #split > 0 then
            splits[#splits + 1] = split
        end
    end
    if is_regex == true then
        plain = false
    end

    while true do
        local s, e = input:find(sep, last_idx, plain)
        if s == nil then
            break
        end
        add_substring(last_idx, s - 1)
        last_idx = e + 1
    end
    add_substring(last_idx, #input)
    return splits
end

function utils.defaultdict(func)
    local f = type(func) == 'function' and func or function() return func end
    local mt = { __index = function(t, idx) return rawget(t, idx) or rawset(t, idx, f())[idx] end }
    return setmetatable({}, mt)
end

function utils.table_to_set(t, in_place)
    local t_ = (in_place or true) and t or {}
    for i, v in ipairs(t) do
        assert(utils.is_numeric(v) == false, "Table t should not contain numeric values!")
        t_[v] = i
    end
    return t_
end

function utils.path_exists(path)
    local f = io.open(path, 'r')
    if f then
        f:close()
        return true
    end
    return false
end

function utils.run_cmd(cmd)
    local output = {}
    local f = io.popen(cmd, 'r')
    if not f then return {} end
    for line in f:lines("*l") do
        table.insert(output, line)
    end
    f:close()
    return output
end

function utils.iterate_cmd(cmd)
    local output = {}
    local f = io.popen(cmd, 'r')
    if f then
        for line in f:lines("*l") do
            table.insert(output, line)
        end
        f:close()
    end
    return function()
        return table.remove(output, 1)
    end
end

function utils.strip_path(path)
    local stripped = string.match(path, "[/\\]([^/\\]+)$")
    return stripped or path
end

function utils.dir_name(path)
    local dir = string.match(path, "^(.*)[/\\]")
    return dir or "."
end


function utils.is_numeric_int(s)
    return string.match(s, "^%d+$") ~= nil
end

function utils.is_numeric(str)
    return string.match(str, "^-?[%d%.]+$")
end

function utils.table_slice(t, from, to)
    local new = {}
    for i,v in ipairs(t) do
        if i > to then
            return new
        elseif i >= from then
            table.insert(new, v)
        end
    end
    return new
end

function utils.copy_table(t)
    local copy = {}
    for _,v in ipairs(t) do table.insert(copy, type(v) == "table" and utils.copy_table(v) or v) end
    for k,v in pairs(t) do copy[k] = type(v) == "table" and utils.copy_table(v) or v end
    return copy
end

return utils
