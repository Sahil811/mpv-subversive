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
    if not show_info.ep_number or show_info.ep_number <= 0 then
        return true
    end
    
    local sanitized_filename = self.sanitize(filename)
    local ep_num = show_info.ep_number
    
    -- Build patterns. Use episodes count only when it's actually available.
    local total_episodes = (show_info.anilist_data and show_info.anilist_data.episodes) or nil
    local pad_width = total_episodes and #tostring(total_episodes) or 2
    local patterns = {
        -- Zero-padded based on total episodes (e.g. 01, 001)
        string.format("%0" .. pad_width .. "d", ep_num),
        -- Common patterns: E01, EP01, Episode 01, etc.
        "[Ee][Pp]?%s*0*" .. ep_num,
        -- Dash or space followed by number: - 01, -01
        "[%s%-]0*" .. ep_num,
        -- Just the number with word boundaries
        "[^%d]0*" .. ep_num .. "[^%d]",
        -- At start or end
        "^0*" .. ep_num .. "[^%d]",
        "[^%d]0*" .. ep_num .. "$",
    }
    
    for _, pattern in ipairs(patterns) do
        if sanitized_filename:match(pattern) then
            return true
        end
    end
    
    return false
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
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json"
        },
        body = body_json
    }
    
    if response.status_code ~= 200 then
        if self.show_notifications then
            mp.osd_message(("AniList API error: HTTP %d"):format(response.status_code), 3)
        end
        print(("AniList API error [%d]: %s"):format(response.status_code, response.data or "Unknown error"))
        return {}
    end
    
    local parsed, err = mpu.parse_json(response.data)
    if not parsed then
        print(("Failed to parse AniList response: %s"):format(err or "Invalid JSON"))
        return {}
    end
    
    if not parsed.data or not parsed.data.Page or not parsed.data.Page.media then
        print("Unexpected AniList response structure")
        return {}
    end
    
    return parsed.data.Page.media
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
        if not parser then
            print(("[mpv-subversive] Skipping invalid archive: %s"):format(path_to_archive))
            return
        end
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

    -- Copy the original file to tmp_path using Lua IO for cross-platform reliability
    util.open_file(file, 'rb', function(fin)
        local data = fin:read("*a")
        local _, fname = require('mp.utils').split_path(file)
        util.open_file(tmp_path .. '/' .. fname, 'wb', function(fout)
            fout:write(data)
        end)
    end)

    print(string.format("Extracting matches to: %q", tmp_path))
    local inner_files = mpu.readdir(tmp_path) or {}
    for _, f in ipairs(inner_files) do
        local full_path = tmp_path .. '/' .. f
        if self:is_supported_archive(f) then
            local parser = archive:new(full_path)
            if parser and parser:check_valid() then
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

    -- Bug 15 fix: cross-platform move using Lua IO instead of os.execute with %q
    if util.is_windows() then
        os.execute(string.format('mkdir "%s" >nul 2>&1', cached_path:gsub("/", "\\")))
    else
        os.execute(string.format("mkdir -p %q", cached_path))
    end
    -- Copy each file individually using Lua IO for reliability
    for _, f in ipairs(final_files) do
        local src = tmp_path .. '/' .. f
        local dst = cached_path .. '/' .. f
        util.open_file(src, 'rb', function(fin)
            local data = fin:read("*a")
            util.open_file(dst, 'wb', function(fout)
                fout:write(data)
            end)
        end)
    end
    -- Clean up temp directory
    if util.is_windows() then
        os.execute(string.format('rd /S /Q "%s" >nul 2>&1', tmp_path:gsub("/", "\\")))
    else
        os.execute(string.format("rm -rf %q", tmp_path))
    end
    return cached_path, files
end

function backend:get_cached_path(show_info)
    return ("%s/%s/"):format(self.cache_directory, show_info.anilist_data.id)
end

function backend.sanitize(text)
    local sub_patterns = {
        "%.[%a]+$", -- extension
        "%[[^%]]+%]", -- [] bracket - remove these
        "%{[^%}]+%}", -- {} bracket - remove these
        "720[pP]", "480[pP]", "1080[pP]", "2160[pP]", "4[kK]",
        "[xXhH]26[45]", "[xXhH]265", "HEVC", "AVC",
        "[bB]lu[-]?[rR]ay", "[bB][dD][rR]ip", "[dD][vV][dD][rR]ip",
        "[wW][eE][bB][-]?[rR]ip", "[wW][eE][bB][-]?[dD][lL]",
        "10[bB]it", "8[bB]it", "Hi10P?",
        "FLAC", "AAC", "MP3", "DTS", "AC3",
        "[mM]ulti", "[dD]ual",
        "1920x1080", "1280x720", "[0-9]+x[0-9]+",
    }
    local result = text
    for _, sub_pattern in ipairs(sub_patterns) do
        result = result:gsub(sub_pattern, " ")
    end
    -- Replace () parentheses with spaces but keep the content
    result = result:gsub("[%(%)]" , " ")
    -- Replace underscores and dots with spaces AFTER removing brackets
    result = result:gsub("_", " "):gsub("%.", " ")
    -- Collapse multiple spaces and trim
    result = result:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return result
end

---@return string,number|nil: show's title and episode number
function backend.extract_title_and_number(text)
    local matchers = Sequence {
        Regex("^([%a%s%p]+)[%s]+(%d+)$", "\1\2"),  -- "Title 077" at end
        Regex("^([%a%s%p]+)[%s]+(%d+)[%s]+", "\1\2"),  -- "Title 077 " with trailing space
        Regex("^([%a%s%p%d]+)[Ss][%d]+[Ee]?([%d]+)", "\1\2"),  -- S01E05
        Regex("^([%a%s%p%d]+)%-[%s]-([%d]+)[%s%p]*[^%a]*", "\1\2"),  -- Title - 05
        Regex("^([%a%s%p%d]+)[Ee][Pp]?[%s]*(%d+)", "\1\2"),  -- EP05 or E05
        Regex("^([%d]+)[%s]*(.+)$", "\2\1")  -- 05 Title (reversed)
    }
    local _, re = matchers:find_first(function(re) return re:match(text) end)
    if re then
        local title, ep_number = re:groups()
        return title:gsub("%s+$", ""):gsub("^%s+", ""), tonumber(ep_number)
    end
    return text
end

function backend:parse_current_file(filename)
    print(string.format("[mpv-subversive] Original filename: '%s'", filename))
    local sanitized_filename = self.sanitize(filename)
    print(string.format("[mpv-subversive] Sanitized filename: '%s'", sanitized_filename))
    local title, ep = self.extract_title_and_number(sanitized_filename)
    print(string.format("[mpv-subversive] Extracted - Title: '%s', Episode: %s", title, ep or "nil"))
    return title, ep
end

return backend
