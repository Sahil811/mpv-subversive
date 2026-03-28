require 'utils.sequence'
require 'utils.regex'
local mpu = require 'mp.utils'
local util = require 'utils.utils'
local archive = require 'utils.archive'
local HTTPClient = require 'http.client'

---@class Subtitle
---@field is_downloaded boolean indicates if this was downloaded already, always true for offline backend
---@field is_archive boolean indicates if this is an archive file, to be downloaded extracted
---@field matching_episode boolean indicates if this sub is for the currently playing file
---@field name string name of the subtitle
---@field absolute_path string path in the cache where the sub is stored
---@field last_modified number seconds since UNIX epoch, not used for offline backend

---@class Backend
local backend = {
    archive_extensions = { ["RAR"] = 1, ["ZIP"] = 1, ["7Z"] = 1 },
}

function backend:new(options)
    local backend_impl = require("backend." .. string.lower(options.subtitle_backend))
    options.media_blacklist = {}
    if options.enable_lookup_caching and #options.media_blacklist_dir > 0 then
        for dir in options.media_blacklist_dir:gmatch("([^;]+)") do
            options.media_blacklist[#options.media_blacklist+1] = dir
        end
        print("Skipping lookup caching for the following directories: ", table.concat(options.media_blacklist, ", "))
    end
    return setmetatable(options, {
        __index = function(t, k)
            return backend_impl[k] or self[k] or rawget(t, k)
        end
    })
end

function backend:is_supported_archive(filename)
    local ext = string.upper(util.get_extension(filename))
    return self.archive_extensions[ext:upper()]
end

function backend:is_matching_episode(show_info, filename)
    if not show_info.ep_number then
        return true
    end
    local sanitized_filename = self.sanitize(filename)
    local zero_padded_ep_number = ("%%0%dd"):format(#tostring(show_info.anilist_data.episodes or "00")):format(show_info.ep_number)
    local match = sanitized_filename:match(zero_padded_ep_number)
    return match ~= nil
end

---Use AniList's search API to query the show name (parsed from the filename)
---@param show_info table containing parsed_title, ep_number (anilist_data is not filled in at this point)
---@return table containing all shows which match the title
function backend:query_shows(show_info)
    local graphql_query = [[
        query ($id: Int, $page: Int=1, $search: String) {
            Page (page: $page) {
                media (id: $id, search: $search, type: ANIME) {
                    id
                    episodes
                    format
                    startDate { year }
                    endDate { year }
                    title {
                        english
                        romaji
                        native
                    }
                }
            }
        }
    ]]
    local body_json = mpu.format_json({
        query = graphql_query,
        variables = {
            search = show_info.parsed_title
        }
    })
    local response = HTTPClient:POST {
        url = "https://graphql.anilist.co",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = body_json
    }
    return assert(mpu.parse_json(response.data), ("Could not parse anilist response: %s"):format(response.data)).data.Page.media
end

---Extract all subtitles which are available for the given ID
---@param show_info table containing parsed_title, ep_number and anilist_data
---@return Subtitle[] list of subs for the given show
function backend:query_subtitles(show_info)
    assert(false, "This should be implemented in a specific backend!")
end


--- Extract all subtitle files in the given archive and store them in predefined cache directory
---@param file string: filename which is a archive containing subtitles
---@param show_info table containing title, ep_number and anilist_data
---@return string path,table files extracted cache path and table with the actual files
function backend:extract_archive(file, show_info)
    local tmp_path = util.get_temporary_path()

    local function extract_inner_archive(path_to_archive)
        print(string.format("Looking for archive files in: %q", path_to_archive))
        local parser = archive:new(path_to_archive)
        if not parser:check_valid() then
            print(string.format("Archive was invalid! skipping..\n"))
            return
        end
        local archive_filter = { "*.zip", "*.rar", "*.7z" }
        for arch in parser:list_files { filter = archive_filter } do
            parser:extract { filter = { arch }, target_path = tmp_path }
            -- lookup in archive can have full path, so strip it
            local a_path = string.format("%s/%s", tmp_path, util.strip_path(arch))
            extract_inner_archive(a_path)
        end
    end
    extract_inner_archive(file)

    -- Copy the original file to tmp_path as well if it's an archive we can extract from
    -- On Windows we can use mp.command_native or just Lua's io.open/write for small files, but here we'll use a system command
    local cp_cmd = util.is_windows() and "copy" or "cp"
    os.execute(string.format("%s %q %q >nul 2>&1", cp_cmd, file, tmp_path))

    print(string.format("Extracting matches to: %q", tmp_path))
    local inner_files = mpu.readdir(tmp_path) or {}
    for _, f in ipairs(inner_files) do
        local full_path = tmp_path .. '/' .. f
        if self:is_supported_archive(f) then
            local parser = archive:new(full_path)
            if parser:check_valid() then
                for sub_f in parser:list_files {} do
                    print(("Listing file from %s: %s"):format(full_path, sub_f))
                    parser:extract { filter = { sub_f }, target_path = tmp_path }
                end
            end
            os.remove(full_path)
        end
    end

    local cached_path = self:get_cached_path(show_info)
    local files = {}
    local final_files = mpu.readdir(tmp_path) or {}
    for _, f in ipairs(final_files) do
        if util.path_exists(tmp_path .. '/' .. f) then
            table.insert(files, {
                name = f,
                absolute_path = cached_path .. '/' .. f,
                matching_episode = self:is_matching_episode(show_info, f),
                is_downloaded = true
            })
        end
    end

    if util.is_windows() then
        os.execute(string.format("mkdir %q >nul 2>&1", cached_path))
        os.execute(string.format("xcopy /Y /Q %q %q >nul 2>&1", tmp_path .. "\\*", cached_path))
        os.execute(string.format("rd /S /Q %q >nul 2>&1", tmp_path))
    else
        os.execute(string.format("mkdir -p %q", cached_path))
        os.execute(("cp %q/* %q"):format(tmp_path, cached_path))
        os.execute(("rm -r %q"):format(tmp_path))
    end
    return cached_path, files
end

function backend:get_cached_path(show_info)
    return ("%s/%s/"):format(self.cache_directory, show_info.anilist_data.id)
end

function backend.sanitize(text)
    local sub_patterns = {
        "%.[%a]+$", -- extension
        "_", "%.",
        "%[[^%]]+%]", -- [] bracket
        "%([^%)]+%)", -- () bracket
        "720[pP]", "480[pP]", "1080[pP]", "[xX]26[45]", "[bB]lu[-]?[rR]ay", "^[%s]*", "[%s]*$",
        "1920x1080", "1920X1080", "Hi10P", "FLAC", "AAC"
    }
    local result = text
    for _,sub_pattern in ipairs(sub_patterns) do
        local new = result:gsub(sub_pattern, "")
        if #new > 0 then result = new end
    end
    return result
end

---@return string,number|nil: show's title and episode number
function backend.extract_title_and_number(text)
    local matchers = Sequence {
        Regex("^([%a%s%p%d]+)[Ss][%d]+[Ee]?([%d]+)", "\1\2"),
        Regex("^([%a%s%p%d]+)%-[%s]-([%d]+)[%s%p]*[^%a]*", "\1\2"),
        Regex("^([%a%s%p]+)[%s]+(%d+)$", "\1\2"),
        Regex("^([%a%s%p]+)[%s]+(%d+)[%s]*.*$", "\1\2"),
        Regex("^([%a%s%p%d]+)[Ee]?[Pp]?[%s]+(%d+)$", "\1\2"),
        Regex("^([%a%s%p%d]+)[%s](%d+).*$", "\1\2"),
        Regex("^([%d]+)[%s]*(.+)$", "\2\1") }
    local _, re = matchers:find_first(function(re) return re:match(text) end)
    if re then
        local title, ep_number = re:groups()
        return title:gsub("%s+$", ""):gsub("^%s+", ""), tonumber(ep_number)
    end
    return text
end

function backend:parse_current_file(filename)
    local sanitized_filename = self.sanitize(filename)
    print(string.format("Sanitized filename: '%s'", sanitized_filename))
    return self.extract_title_and_number(sanitized_filename)
end

return backend
