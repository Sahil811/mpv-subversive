require 'utils.sequence'
local HTTPClient = require("http.client")
local mp = require 'mp'
local mpu = require 'mp.utils'

local jimaku = {
    BASE_URL = "https://jimaku.cc/api/",
}

function jimaku:get_scheduler()
    return HTTPClient:get_scheduler("jimaku.cc", 443)
end

---Extract all subtitles which are available for the given ID
---@param show_info table containing title, ep_number and anilist_data
---@return table containing all subtitles for the given show, with optional error field if something went wrong
function jimaku:query_subtitles(show_info)
    if not self.API_TOKEN or self.API_TOKEN == "" then
        return { error = "No API_TOKEN configured! Please add your Jimaku API key to mpv-subversive.conf" }
    end
    
    local anilist_id = show_info.anilist_data.id
    if self.show_notifications then
        mp.osd_message(("Finding subtitles for AniList ID: %s"):format(anilist_id), 3)
    end
    
    -- Initialize scheduler
    self:get_scheduler()
    
    local response = HTTPClient:sync_GET {
        url = self.BASE_URL .. "entries/search",
        params = { anilist_id = anilist_id },
        headers = { ["Authorization"] = self.API_TOKEN }
    }
    
    if response.status_code == 401 then
        return { error = "Invalid API token! Please check your Jimaku API key in mpv-subversive.conf" }
    elseif response.status_code == 404 then
        return { error = ("No subtitles found for AniList ID: %s"):format(anilist_id) }
    elseif response.status_code ~= 200 then
        return { error = ("Jimaku API error [%d]: %s"):format(response.status_code, response.data or "Unknown error") }
    end
    
    local entries, err = mpu.parse_json(response.data)
    if not entries then
        return { error = ("Failed to parse Jimaku response: %s"):format(err or "Invalid JSON") }
    end
    
    if #entries == 0 then
        return { error = ("No subtitle entries found for AniList ID: %s"):format(anilist_id) }
    end
    
    local util = require 'utils.utils'
    local cached_path = self:get_cached_path(show_info)
    util.mkdir_p(cached_path)

    local items = {}
    local total_files = 0
    
    for _, entry in ipairs(entries) do
        local files, file_err = self:get_files(entry.id)
        if files then
            for _, file in ipairs(files) do
                file.is_archive = self:is_supported_archive(file.name)
                file.matching_episode = self:is_matching_episode(show_info, file.name)
                file.absolute_path = cached_path .. '/' .. file.name
                file.entry_id = entry.id
                
                -- Parse last_modified timestamp
                -- Bug 25 fix: parse ISO 8601 datetime, flexible timezone handling
                local _, _, year, month, day, hour, minute, second =
                    string.find(file.last_modified or "", "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
                if year then
                    file.last_modified = os.time({
                        year = year,
                        month = month,
                        day = day,
                        hour = hour,
                        minute = minute,
                        second = second
                    })
                else
                    file.last_modified = 0
                end
                
                table.insert(items, file)
                total_files = total_files + 1
            end
        else
            print(("Warning: Failed to get files for entry %s: %s"):format(entry.id, file_err or "Unknown error"))
        end
    end

    -- Filter by preferred languages if configured
    if self.preferred_languages and #self.preferred_languages > 0 then
        local lang_codes = {}
        for code in self.preferred_languages:gmatch("([^,]+)") do
            table.insert(lang_codes, code:match("^%s*(.-)%s*$"):lower())
        end
        
        local preferred_items = {}
        for _, item in ipairs(items) do
            local name_lower = item.name:lower()
            for _, code in ipairs(lang_codes) do
                if name_lower:match("[%.%-%_%s%[]" .. code .. "[%.%-%_%s%]%)]") 
                   or name_lower:match("^" .. code .. "[%.%-%_%s]") then
                    table.insert(preferred_items, item)
                    break
                end
            end
        end
        
        -- Only filter if we found some matches; otherwise show everything
        if #preferred_items > 0 then
            items = preferred_items
            total_files = #items
            if self.show_notifications then
                mp.osd_message(("Filtered to %d subtitle(s) matching preferred language"):format(total_files), 2)
            end
        end
    end
    
    if total_files == 0 then
        return { error = "No subtitle files found in entries" }
    end
    
    if self.show_notifications then
        mp.osd_message(("Found %d subtitle file(s)"):format(total_files), 2)
    end
    
    return items
end

function jimaku:get_files(entry_id)
    local response = HTTPClient:sync_GET {
        url = self.BASE_URL .. ("entries/%s/files"):format(entry_id),
        headers = { ["Authorization"] = self.API_TOKEN }
    }
    
    if response.status_code ~= 200 then
        return nil, ("Failed to get files for entry %s: HTTP %d"):format(entry_id, response.status_code)
    end
    
    local result, err = mpu.parse_json(response.data)
    if not result then
        return nil, ("Failed to parse files response: %s"):format(err or "Invalid JSON")
    end
    
    return result
end

---@return Routine
function jimaku:download_subtitle(file_entry)
    return HTTPClient:async_GET {
        url = file_entry.url,
        headers = { ["Accept"] = "application/octet-stream" }
    }
end

return jimaku
