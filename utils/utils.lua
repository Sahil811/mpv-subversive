local utils = {}

math.randomseed(os.time() + os.clock() * 1000)

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
        -- Use os.tmpname() for a unique name instead of unseeded math.random
        local tmpname = os.tmpname()
        os.remove(tmpname)
        local dirname = tmpname:match("([^/\\]+)$") or ("sub-tmp-" .. os.time())
        local path = string.format("%s\\%s", temp, dirname)
        utils.mkdir_p(path)
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

-- Cross-platform directory creation using mp.command_native
function utils.mkdir_p(path)
    if not path or #path == 0 then return false end
    local mp = require 'mp'
    if utils.is_windows() then
        local win_path = path:gsub("/", "\\")
        local result = mp.command_native({
            name = "subprocess",
            capture_stdout = true,
            capture_stderr = true,
            args = {"cmd", "/C", "mkdir", win_path}
        })
        return result and (result.status == 0 or result.status == 1)  -- status 1 = already exists
    else
        local result = mp.command_native({
            name = "subprocess",
            capture_stdout = true,
            capture_stderr = true,
            args = {"mkdir", "-p", path}
        })
        return result and result.status == 0
    end
end

-- Cross-platform directory removal
function utils.rmdir(path)
    if not path or #path == 0 then return false end
    local mp = require 'mp'
    if utils.is_windows() then
        local win_path = path:gsub("/", "\\")
        local result = mp.command_native({
            name = "subprocess",
            capture_stdout = true,
            capture_stderr = true,
            args = {"cmd", "/C", "rd", "/S", "/Q", win_path}
        })
        return result and result.status == 0
    else
        local result = mp.command_native({
            name = "subprocess",
            capture_stdout = true,
            capture_stderr = true,
            args = {"rm", "-rf", path}
        })
        return result and result.status == 0
    end
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
    if not f then
        print(("[mpv-subversive] Warning: Failed to run command: %s"):format(cmd))
        return {}
    end
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
    else
        print(("[mpv-subversive] Warning: Failed to run command: %s"):format(cmd))
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
