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

--- Parse structured episode/season metadata from a raw filename.
--- Extracts data BEFORE sanitization to preserve context.
---@param raw_filename string the filename (basename, no directory)
---@return table info with fields: ep_number, season_number, ep_end (range), version, is_special, special_type, year
function backend.parse_episode_info(raw_filename)
    local info = {
        ep_number = nil,
        season_number = nil,
        ep_end = nil,       -- end of range if multi-episode (e.g., 01-03 → ep_end=3)
        version = nil,
        is_special = false,
        special_type = nil,
        year = nil,
    }

    -- Remove extension first
    local name = raw_filename:gsub("%.[%a]+$", "")
    -- Strip bracket contents but capture them for CRC/group detection
    local bracket_contents = {}
    for content in name:gmatch("%[([^%]]+)%]") do
        bracket_contents[#bracket_contents + 1] = content
    end
    name = name:gsub("%[[^%]]+%]", " ")
    name = name:gsub("%{[^%}]+%}", " ")

    -- Detect year in parentheses: (2007), (2017-2023)
    local paren_year = name:match("%((%d%d%d%d)%)")
    if paren_year then
        local y = tonumber(paren_year)
        if y and y >= 1900 and y <= 2099 then
            info.year = y
        end
    end
    -- Remove parentheses content
    name = name:gsub("%(([^%)]+)%)", function(content)
        -- Keep the content but remove the parens
        return " " .. content .. " "
    end)

    -- Normalize separators: underscores and dots → spaces
    name = name:gsub("_", " "):gsub("%.", " ")

    -- Detect version suffix anywhere: v2, v3
    local ver = name:match("[Vv](%d+)")
    if ver and tonumber(ver) <= 9 then
        info.version = tonumber(ver)
    end

    -- 1. S01E10 with optional range S01E01-E03 or S01E01-03
    local s, e = name:match("[Ss](%d+)[%s]*[Ee](%d+)")
    if s and e then
        info.season_number = tonumber(s)
        info.ep_number = tonumber(e)
        -- Check for range: S01E01-E03 or S01E01-03
        local range_end = name:match("[Ss]%d+[%s]*[Ee]%d+%-[Ee]?(%d+)")
        if range_end then
            info.ep_end = tonumber(range_end)
        end
        return info
    end

    -- 2. 2x10 season notation
    local sx, ex = name:match("(%d+)[xX](%d+)")
    if sx and ex then
        local sn = tonumber(sx)
        if sn and sn <= 99 then  -- reasonable season number
            info.season_number = sn
            info.ep_number = tonumber(ex)
            return info
        end
    end

    -- 3. SP/Special/OVA/OAD numbered
    local sp_type, sp_num = name:match("([Ss][Pp])(%d+)")
    if not sp_type then
        sp_type, sp_num = name:match("([Ss]pecial)[%s%-]*(%d+)")
    end
    if not sp_type then
        sp_type, sp_num = name:match("([Oo][Vv][Aa])[%s%-]*(%d+)")
    end
    if not sp_type then
        sp_type, sp_num = name:match("([Oo][Aa][Dd])[%s%-]*(%d+)")
    end
    if sp_type and sp_num then
        info.is_special = true
        info.special_type = sp_type:upper()
        info.ep_number = tonumber(sp_num)
        return info
    end

    -- 4. EP/Ep./ep prefix: EP100, Ep.100, ep 100
    local ep_prefixed = name:match("[Ee][Pp]%.?[%s]*(%d+)")
    if ep_prefixed then
        info.ep_number = tonumber(ep_prefixed)
        -- Check version right after: EP10v2
        local range_end = name:match("[Ee][Pp]%.?[%s]*%d+%-(%d+)")
        if range_end then info.ep_end = tonumber(range_end) end
        return info
    end

    -- 5. E prefix (but NOT part of HEVC, AVC, etc.)
    -- Match E followed by digits, but preceded by space/dash/start
    local e_prefixed = name:match("[%s%-]E(%d+)")
    if not e_prefixed then
        e_prefixed = name:match("^E(%d+)")
    end
    if e_prefixed then
        info.ep_number = tonumber(e_prefixed)
        return info
    end

    -- 6. "Season X" in filename — extract season, continue to find episode
    local season_in_name = name:match("[Ss]eason[%s]*(%d+)")
    if season_in_name then
        info.season_number = tonumber(season_in_name)
        -- Remove the "Season X" part and continue parsing for episode
        local rest = name:gsub("[Ss]eason[%s]*%d+", " ")
        -- Try to find episode in the remaining text
        local ep_after_season = rest:match("[Ee]pisode[%s%.%-]*(%d+)")
        if not ep_after_season then
            ep_after_season = rest:match("[Ee][Pp]%.?[%s]*(%d+)")
        end
        if not ep_after_season then
            -- Try bare number after stripping known metadata
            ep_after_season = backend._extract_bare_number(rest, info)
        end
        if ep_after_season then
            info.ep_number = tonumber(ep_after_season)
            return info
        end
    end

    -- 7. "Episode" / "Episode." spelled out (without Season prefix)
    local episode_spelled = name:match("[Ee]pisode[%s%.%-]*(%d+)")
    if episode_spelled then
        info.ep_number = tonumber(episode_spelled)
        return info
    end

    -- 8. Hash prefix: #100
    local hash_ep = name:match("#(%d+)")
    if hash_ep then
        info.ep_number = tonumber(hash_ep)
        return info
    end

    -- 9. Dash/separator + number: "Title - 100", "Title - 100v2", "Title - 01-03"
    local dash_ep = name:match("[%s]%-[%s]-(%d+)")
    if dash_ep then
        info.ep_number = tonumber(dash_ep)
        -- Check for range: - 01-03
        local range_end = name:match("[%s]%-[%s]-%d+%-(%d+)")
        if range_end then info.ep_end = tonumber(range_end) end
        return info
    end

    -- 10. Bare trailing number (last resort) — with year/metadata exclusion
    local bare = backend._extract_bare_number(name, info)
    if bare then
        info.ep_number = tonumber(bare)
    end

    return info
end

--- Helper: extract a bare number from text, excluding years and metadata numbers.
---@param text string sanitized text to search
---@param info table parsed info so far (for year exclusion)
---@return string|nil the episode number string, or nil
function backend._extract_bare_number(text, info)
    -- Strip known metadata that might leave residual numbers
    local clean = text
    clean = clean:gsub("[Vv]%d+", " ")              -- version
    clean = clean:gsub("%d+[xX]%d+", " ")           -- resolution like 1920x1080
    clean = clean:gsub("%d+[pPkK]", " ")             -- 720p, 1080p, 4K
    clean = clean:gsub("[xXhH]26[45]", " ")          -- codec
    clean = clean:gsub("HEVC", " "):gsub("AVC", " ")
    clean = clean:gsub("10[bB]it", " "):gsub("8[bB]it", " ")
    clean = clean:gsub("FLAC", " "):gsub("AAC", " "):gsub("MP3", " ")
    clean = clean:gsub("DTS", " "):gsub("AC3", " ")
    clean = clean:gsub("[Cc][Dd]%d+", " ")           -- CD1, CD2
    clean = clean:gsub("[Pp]art[%s]*%d+", " ")       -- Part 1
    clean = clean:gsub("%d+%.%d+[Cc][Hh]?", " ")    -- 5.1ch, 2.0
    clean = clean:gsub("[Bb]atch", " ")
    clean = clean:gsub("[Cc]ommentary", " ")
    clean = clean:gsub("[Ss]eason[%s]*%d+", " ")
    clean = clean:gsub("[Vv]ol%.?[%s]*%d+", " ")

    -- Collapse spaces
    clean = clean:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

    -- Find all number tokens (space-bounded)
    local candidates = {}
    for num in clean:gmatch("(%d+)") do
        local n = tonumber(num)
        -- Exclude years
        if not (n >= 1900 and n <= 2099) then
            -- Exclude if it matches the known year
            if not (info and info.year and n == info.year) then
                candidates[#candidates + 1] = num
            end
        end
    end

    -- Prefer the LAST numeric candidate (most likely episode in "Title 100" format)
    if #candidates > 0 then
        return candidates[#candidates]
    end
    return nil
end

--- Extract season number from an archive-relative folder path.
---@param relative_path string e.g., "Season 1/Episode 10.srt"
---@return number|nil season number from folder path
function backend.parse_season_from_path(relative_path)
    if not relative_path then return nil end
    -- Match "Season X" or "S01" in the directory portion
    local dir = relative_path:match("^(.+)/[^/]+$") or ""
    local season = dir:match("[Ss]eason[%s]*(%d+)")
    if not season then
        season = dir:match("[Ss](%d+)")
    end
    if season then return tonumber(season) end
    return nil
end

function backend:is_matching_episode(show_info, filename, relative_path)
    if not show_info.ep_number or show_info.ep_number <= 0 then
        return true
    end

    local target_ep = show_info.ep_number
    local target_season = show_info.season_number  -- may be nil

    -- Parse episode info from the subtitle filename
    local sub_info = self.parse_episode_info(filename)

    -- Also try to get season from archive folder path
    if not sub_info.season_number and relative_path then
        sub_info.season_number = self.parse_season_from_path(relative_path)
    end

    -- No episode number found in subtitle → can't match, include it (conservative)
    if not sub_info.ep_number then
        return true
    end

    -- Check episode match
    local ep_matches = false

    if sub_info.ep_end then
        -- Range match: target must be within [ep_number, ep_end]
        ep_matches = (target_ep >= sub_info.ep_number and target_ep <= sub_info.ep_end)
    else
        -- Exact match
        ep_matches = (target_ep == sub_info.ep_number)
    end

    if not ep_matches then
        return false
    end

    -- If both sides have season info, require season match
    if target_season and sub_info.season_number then
        return target_season == sub_info.season_number
    end

    -- If subtitle is marked as special but we're looking for a regular episode, don't match
    if sub_info.is_special and not show_info.is_special then
        return false
    end

    return true
end

--- Calculate a match quality score for ranking subtitle matches.
--- Higher score = better match.
---@param show_info table with ep_number, season_number
---@param filename string subtitle filename
---@param relative_path string|nil archive-relative path
---@return number score (0 = no match, 1-4 = match quality)
function backend:match_score(show_info, filename, relative_path)
    if not self:is_matching_episode(show_info, filename, relative_path) then
        return 0
    end

    local sub_info = self.parse_episode_info(filename)
    if not sub_info.ep_number then
        return 1  -- no episode parsed, included conservatively
    end

    local score = 2  -- base: episode matches

    -- Bonus: season also matches
    if show_info.season_number and sub_info.season_number
       and show_info.season_number == sub_info.season_number then
        score = score + 1
    end

    -- Bonus: exact single episode (not a range)
    if not sub_info.ep_end then
        score = score + 1
    end

    -- Prefer higher version
    if sub_info.version then
        score = score + 0.1 * sub_info.version
    end

    return score
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

---Async version of query_shows. Calls callback(results) when done.
---Uses mp.command_native_async to avoid blocking the UI.
---@param show_info table containing parsed_title
---@param callback function called with results table (list of media)
function backend:query_shows_async(show_info, callback)
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
        variables = { search = show_info.parsed_title }
    })

    local curl_cmd = util.is_windows() and "curl.exe" or "curl"

    mp.command_native_async({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        args = {curl_cmd, "-s", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-H", "Accept: application/json",
            "--data", body_json,
            "https://graphql.anilist.co"}
    }, function(success, result, err)
        if not success or not result or result.status ~= 0 then
            print(("[mpv-subversive] AniList async error: %s"):format(
                err or (result and result.stderr) or "subprocess failed"))
            callback({})
            return
        end

        local ok, parsed = pcall(mpu.parse_json, result.stdout)
        if not ok or not parsed then
            print(("[mpv-subversive] AniList parse error: %s"):format(tostring(parsed)))
            callback({})
            return
        end

        if not parsed.data or not parsed.data.Page or not parsed.data.Page.media then
            print("[mpv-subversive] Unexpected AniList response structure")
            callback({})
            return
        end

        callback(parsed.data.Page.media)
    end)
end

---Extract all subtitles which are available for the given ID
---@param show_info table containing parsed_title, ep_number and anilist_data
---@return Subtitle[] list of subs for the given show
function backend:query_subtitles(show_info)
    assert(false, "This should be implemented in a specific backend!")
end


--- Recursively list all files under a directory, returning relative paths.
---@param base_path string the root directory
---@param prefix string current relative path prefix (empty for root)
---@return table list of {relative_path, full_path} pairs
local function list_files_recursive(base_path, prefix)
    prefix = prefix or ""
    local results = {}
    local entries = mpu.readdir(base_path) or {}
    for _, entry in ipairs(entries) do
        local full = base_path .. '/' .. entry
        local rel = prefix == "" and entry or (prefix .. '/' .. entry)
        if util.path_exists(full) then
            -- Check if it's a directory by trying to readdir it
            local sub_entries = mpu.readdir(full)
            if sub_entries then
                -- It's a directory, recurse
                local sub_files = list_files_recursive(full, rel)
                for _, sf in ipairs(sub_files) do
                    results[#results + 1] = sf
                end
            else
                -- It's a file
                results[#results + 1] = { relative_path = rel, full_path = full, name = entry }
            end
        end
    end
    return results
end

--- Extract all subtitle files in the given archive and store them in predefined cache directory.
--- Preserves directory structure for season/folder disambiguation.
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
    -- First pass: extract any inner archives (now in subdirectories too)
    local all_extracted = list_files_recursive(tmp_path)
    for _, entry in ipairs(all_extracted) do
        if self:is_supported_archive(entry.name) then
            local parser = archive:new(entry.full_path)
            if parser and parser:check_valid() then
                -- Extract inner archive to a subdirectory to preserve structure
                local inner_dir = entry.full_path:gsub("%.[^%.]+$", "")
                util.mkdir_p(inner_dir)
                for sub_f in parser:list_files {} do
                    print(("Listing file from %s: %s"):format(entry.full_path, sub_f))
                    parser:extract { filter = { sub_f }, target_path = inner_dir }
                end
            end
            os.remove(entry.full_path)
        end
    end

    local cached_path = self:get_cached_path(show_info)
    local files = {}

    -- Collect all files recursively, handling duplicate basenames
    local final_files = list_files_recursive(tmp_path)
    local seen_names = {}

    for _, entry in ipairs(final_files) do
        -- Skip non-subtitle files (fonts, NFO, etc.)
        local ext = (util.get_extension(entry.name) or ""):lower()
        local sub_extensions = { srt=1, ass=1, ssa=1, sub=1, vtt=1, idx=1 }
        if sub_extensions[ext] then
            local display_name = entry.name
            -- Handle duplicate basenames by prefixing with folder context
            if seen_names[display_name] then
                -- Extract folder context for disambiguation
                local dir_part = entry.relative_path:match("^(.+)/[^/]+$")
                if dir_part then
                    -- Use season folder or parent folder as prefix
                    local season = dir_part:match("[Ss]eason[%s_%-]*(%d+)")
                    if season then
                        display_name = string.format("S%02d_%s", tonumber(season), entry.name)
                    else
                        -- Use last folder component
                        local folder = dir_part:match("([^/]+)$") or dir_part
                        display_name = folder .. "_" .. entry.name
                    end
                end
            end
            seen_names[display_name] = true

            table.insert(files, {
                name = display_name,
                relative_path = entry.relative_path,
                absolute_path = cached_path .. '/' .. display_name,
                matching_episode = self:is_matching_episode(show_info, entry.name, entry.relative_path),
                is_downloaded = true
            })
        end
    end

    -- Copy files to cache
    util.mkdir_p(cached_path)
    for _, entry in ipairs(final_files) do
        local ext = (util.get_extension(entry.name) or ""):lower()
        local sub_extensions = { srt=1, ass=1, ssa=1, sub=1, vtt=1, idx=1 }
        if sub_extensions[ext] then
            -- Find the corresponding display_name from files table
            local dst_name = nil
            for _, f in ipairs(files) do
                if f.relative_path == entry.relative_path then
                    dst_name = f.name
                    break
                end
            end
            if dst_name then
                local dst = cached_path .. '/' .. dst_name
                util.open_file(entry.full_path, 'rb', function(fin)
                    local data = fin:read("*a")
                    util.open_file(dst, 'wb', function(fout)
                        fout:write(data)
                    end)
                end)
            end
        end
    end
    -- Clean up temp directory
    util.rmdir(tmp_path)
    return cached_path, files
end

function backend:get_cached_path(show_info)
    return ("%s/%s/"):format(self.cache_directory, show_info.anilist_data.id)
end

--- Sanitize for AniList search: aggressive, removes all metadata but preserves title.
function backend.sanitize_for_search(text)
    local sub_patterns = {
        "%.[%a]+$",             -- extension
        "%[[^%]]+%]",           -- [] bracket contents
        "%{[^%}]+%}",           -- {} bracket contents
        "720[pP]", "480[pP]", "1080[pP]", "2160[pP]", "4[kK]",
        "[xXhH]26[45]", "[xXhH]265", "HEVC", "AVC",
        "[bB]lu[-]?[rR]ay", "[bB][dD][rR]ip", "[dD][vV][dD][rR]ip",
        "[wW][eE][bB][-]?[rR]ip", "[wW][eE][bB][-]?[dD][lL]",
        "10[bB]it", "8[bB]it", "Hi10P?",
        "FLAC", "AAC", "MP3", "DTS", "AC3",
        "[mM]ulti", "[dD]ual",
        "1920x1080", "1280x720", "[0-9]+x[0-9]+",
        "[Ss]eason%s*%d+",
        "[Vv]ol%.?%s*%d+",
        "[Bb]atch",
        "[Cc]ommentary",
        "[Nn][Cc][Oo][Pp]",
        "[Nn][Cc][Ee][Dd]",
        "[Ss]pecials?",
        "[Oo][Vv][Aa]",
        "[Oo][Nn][Aa]",
        "[Oo][Aa][Dd]",
        "[Vv]%d+",              -- version markers
        "END",
        "FINAL",
    }
    local result = text
    for _, sub_pattern in ipairs(sub_patterns) do
        result = result:gsub(sub_pattern, " ")
    end
    result = result:gsub("[%(%)]" , " ")
    result = result:gsub("_", " "):gsub("%.", " ")
    result = result:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return result
end

--- Sanitize for matching: lighter touch, preserves Season/Special/OVA markers
--- since parse_episode_info() needs them.
function backend.sanitize(text)
    local sub_patterns = {
        "%.[%a]+$",             -- extension
        "%[[^%]]+%]",           -- [] bracket contents
        "%{[^%}]+%}",           -- {} bracket contents
        "720[pP]", "480[pP]", "1080[pP]", "2160[pP]", "4[kK]",
        "[xXhH]26[45]", "[xXhH]265", "HEVC", "AVC",
        "[bB]lu[-]?[rR]ay", "[bB][dD][rR]ip", "[dD][vV][dD][rR]ip",
        "[wW][eE][bB][-]?[rR]ip", "[wW][eE][bB][-]?[dD][lL]",
        "10[bB]it", "8[bB]it", "Hi10P?",
        "FLAC", "AAC", "MP3", "DTS", "AC3",
        "[mM]ulti", "[dD]ual",
        "1920x1080", "1280x720", "[0-9]+x[0-9]+",
        "[Vv]ol%.?%s*%d+",
        "[Bb]atch",
        "[Cc]ommentary",
        "[Nn][Cc][Oo][Pp]",
        "[Nn][Cc][Ee][Dd]",
    }
    local result = text
    for _, sub_pattern in ipairs(sub_patterns) do
        result = result:gsub(sub_pattern, " ")
    end
    result = result:gsub("[%(%)]" , " ")
    result = result:gsub("_", " "):gsub("%.", " ")
    result = result:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return result
end

---@return string,number|nil,number|nil: show's title, episode number, and season number
function backend.extract_title_and_number(text)
    -- First try structured parsing on the raw text
    local info = backend.parse_episode_info(text)

    -- If we found structured episode info, extract the title portion
    if info.ep_number then
        -- Build removal patterns for the episode marker
        local title = text
        -- Remove extension
        title = title:gsub("%.[%a]+$", "")
        -- Remove bracket contents
        title = title:gsub("%[[^%]]+%]", " ")
        title = title:gsub("%{[^%}]+%}", " ")
        -- Remove parenthesized years
        title = title:gsub("%((%d%d%d%d)%)", " ")
        -- Remove the episode marker patterns
        title = title:gsub("[Ss]%d+[%s]*[Ee]%d+[%-]?[Ee]?%d*", " ")    -- S01E10, S01E01-E03
        title = title:gsub("%d+[xX]%d+", " ")                           -- 2x10
        title = title:gsub("[Ee][Pp]%.?[%s]*%d+", " ")                  -- EP100, Ep.100
        title = title:gsub("[Ss]eason[%s]*%d+", " ")                    -- Season 10
        title = title:gsub("[Ee]pisode[%s%.%-]*%d+", " ")               -- Episode 100
        title = title:gsub("[Ss][Pp]%d+", " ")                          -- SP01
        title = title:gsub("[Oo][Vv][Aa][%s%-]*%d+", " ")              -- OVA 1
        title = title:gsub("[Oo][Aa][Dd][%s%-]*%d+", " ")              -- OAD 1
        title = title:gsub("#%d+", " ")                                  -- #100
        title = title:gsub("[Vv]%d+", " ")                               -- v2
        title = title:gsub("END", " "):gsub("FINAL", " ")
        -- Remove the bare episode number (last number in the string, cautiously)
        -- Only if it matches what we parsed
        local ep_str = tostring(info.ep_number)
        -- Remove zero-padded variants of the episode number
        title = title:gsub("(%s)0*" .. ep_str .. "(%D)", "%1%2")
        title = title:gsub("(%s)0*" .. ep_str .. "$", "%1")
        -- Normalize
        title = title:gsub("_", " "):gsub("%.", " ")
        title = title:gsub("[%(%)]", " ")
        -- Strip trailing punctuation (dashes, underscores, dots)
        title = title:gsub("[%s%-_%.]+$", "")
        title = title:gsub("^[%s%-_%.]+", "")
        title = title:gsub("%s+", " ")
        title = title:gsub("^%s+", ""):gsub("%s+$", "")

        if #title > 0 then
            return title, info.ep_number, info.season_number
        end
    end

    -- Fallback: legacy matchers for unusual formats
    local matchers = Sequence {
        Regex("^([%a%s%p]+)[%s]+(%d+)$", "\1\2"),            -- "Title 077" at end
        Regex("^([%a%s%p]+)[%s]+(%d+)[%s]+", "\1\2"),        -- "Title 077 " with trailing
        Regex("^([%a%s%p%d]+)[Ss]%d+[%s]*[Ee](%d+)", "\1\2"),-- S01E05
        Regex("^([%a%s%p%d]+)%-[%s]-([%d]+)[%s%p]*[^%a]*", "\1\2"), -- Title - 05
        Regex("^([%a%s%p%d]+)[Ee][Pp]?[%s]*(%d+)", "\1\2"),  -- EP05 or E05
        Regex("^([%d]+)[%s]*(.+)$", "\2\1")                   -- 05 Title (reversed)
    }
    local _, re = matchers:find_first(function(re) return re:match(text) end)
    if re then
        local title, ep_number = re:groups()
        title = title:gsub("[%s%-_%.]+$", ""):gsub("^[%s%-_%.]+", "")
        return title, tonumber(ep_number)
    end
    return text
end

function backend:parse_current_file(filename)
    print(string.format("[mpv-subversive] Original filename: '%s'", filename))
    local sanitized_filename = self.sanitize_for_search(filename)
    print(string.format("[mpv-subversive] Sanitized filename: '%s'", sanitized_filename))
    local title, ep, season = self.extract_title_and_number(filename)
    print(string.format("[mpv-subversive] Extracted - Title: '%s', Episode: %s, Season: %s",
        title, ep or "nil", season or "nil"))
    return title, ep, season
end

return backend
