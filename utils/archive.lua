local archive = {}
local archive_mt = { __index = archive }
local ZIP = setmetatable({}, archive_mt)
local RAR = setmetatable({}, archive_mt)
local _7Z = setmetatable({}, archive_mt)
local mapper = { CBZ = ZIP, ZIP = ZIP, RAR = RAR, ['7Z'] = _7Z }

local utils = require 'utils.utils'

-- execute command and return exit code
local function execute(cmd)
    if utils.is_windows() then
        cmd = cmd:gsub("^7z ", "7z.exe ")
    end
    local res = os.execute(cmd)
    if res == true or res == 0 then return 0 end
    if type(res) == "number" then return res end
    return 1
end

local function get_null_redirect()
    return utils.is_windows() and " >nul 2>&1" or " >/dev/null 2>&1"
end

-- Bug 26 fix: create a proper instance, not modifying the class table
function archive:new(file_path)
    if not utils.path_exists(file_path) then
        print(("[mpv-subversive] Warning: Archive path does not exist: %s"):format(file_path))
        return nil, ("Archive path does not exist: %s"):format(file_path)
    end
    local ext = utils.get_extension(file_path) or ""
    local path = file_path
    local instance = { ext = ext, path = path }
    return setmetatable(instance, { __index = mapper[ext:upper()] or archive })
end

function archive:build_filter(filters)
    if filters == nil then return "*" end
    local str_builder = ""
    for _, f in pairs(filters) do
        str_builder = str_builder .. string.format(" %q ", f)
    end
    return str_builder
end

function _7Z:build_filter(filters)
    if filters == nil then return "'-i!*'" end
    local str_builder = {}
    for _, filter in ipairs(filters) do
        table.insert(str_builder, ("'-i!%s'"):format(filter))
    end
    return table.concat(str_builder, " ")
end

function ZIP:list_files(args)
    if utils.is_windows() then
        return _7Z.list_files(self, args)
    end
    local cmd_str = 'unzip -Z -1 %q %s 2>/dev/null'
    local cmd = cmd_str:format(self.path, args.filter and self:build_filter(args.filter) or '')
    return utils.iterate_cmd(cmd)
end

function RAR:list_files(args)
    if utils.is_windows() then
        return _7Z.list_files(self, args)
    end
    local cmd_str = 'unrar lb %q %s 2>/dev/null'
    local cmd = cmd_str:format(self.path, args.filter and self:build_filter(args.filter) or '')
    return utils.iterate_cmd(cmd)
end

function _7Z:list_files(args)
    local redirect = utils.is_windows() and "" or " 2>/dev/null"
    local z7_cmd = utils.is_windows() and "7z.exe" or "7z"
    local cmd_str = [[%s l -slt %q %s]] .. redirect
    local cmd = cmd_str:format(z7_cmd, self.path, self:build_filter(args.filter))
    local files = {}
    for _, c in ipairs(utils.run_cmd(cmd)) do
        local _, _, path = c:find("^Path = (.+)$")
        if path then
            table.insert(files, path)
        else
            local _, _, size = c:find("^Size = (%d+)")
            if size and size == '0' then -- this is a directory
                table.remove(files, #files)
            end
        end
    end
    return function()
        -- first entry is the 7z file itself
        return table.remove(files, 2)
    end
end

function ZIP:check_valid()
    local redirect = get_null_redirect()
    if utils.is_windows() then
        return execute(("7z t %q"):format(self.path) .. redirect) == 0
    end
    return execute(("unzip -t %q"):format(self.path) .. redirect) == 0
end

function RAR:check_valid()
    local redirect = get_null_redirect()
    if utils.is_windows() then
        return execute(("7z t %q"):format(self.path) .. redirect) == 0
    end
    return execute(("unrar t %q"):format(self.path) .. redirect) == 0
end

function _7Z:check_valid()
    return execute(("7z t %q"):format(self.path) .. get_null_redirect()) == 0
end

-- [] are expanded as pattern in unzip command, to 'escape' them '[' is replaced with '[[]'
function ZIP:replace_left_brackets(filter)
    if filter == nil then return nil end
    local replaced = {}
    for _, v in ipairs(filter) do
        local v_replaced, _ = string.gsub(v, "%[", "[[]")
        replaced[#replaced + 1] = v_replaced
    end
    return replaced
end

function ZIP:extract(args)
    if utils.is_windows() then
        return _7Z.extract(self, args)
    end
    -- Use -o (preserve paths) instead of -jo (junk paths) to keep folder structure
    local cmd = ('unzip -o %q %s -d %q 2>/dev/null'):format(self.path,
        self:build_filter(self:replace_left_brackets(args.filter)), args.target_path or ".")
    return utils.iterate_cmd(cmd)
end

function RAR:extract(args)
    if utils.is_windows() then
        return _7Z.extract(self, args)
    end
    local cmd = ('unrar e -y -o+ %q %s %q 2>/dev/null'):format(self.path, args.filter and self:build_filter(args.filter) or '',
        args.target_path or ".")
    return utils.iterate_cmd(cmd)
end

function _7Z:extract(args)
    local redirect = utils.is_windows() and "" or " 2>/dev/null"
    local z7_cmd = utils.is_windows() and "7z.exe" or "7z"
    -- Use 'x' instead of 'e' to preserve directory structure
    local cmd = ('%s x -y %q %s -o%q'):format(z7_cmd, self.path, self:build_filter(args.filter), args.target_path or ".") .. redirect
    return utils.iterate_cmd(cmd)
end

return archive
