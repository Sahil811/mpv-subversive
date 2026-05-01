local utils = require 'utils.utils'  -- fixed: was 'utils/utils' (slash-style fails on some platforms)
local mpu = require 'mp.utils'

---@class Offline : Backend
---@field subtitle_mapping string
local offline = {}

function offline:get_scheduler()
    -- offline backend doesn't use async downloads
    return { poll = function() return {} end, has_remaining = function() return false end, quit = function() end }
end

function offline:query_subtitles(show_info)
    print(("[mpv-subversive] offline: found ID: %s, looking for matches in %q"):format(show_info.anilist_data.id, self.subtitle_mapping))
    if not utils.path_exists(self.subtitle_mapping) then
        return { error = (("Could not find mapping file '%s'"):format(self.subtitle_mapping)) }
    end
    local mapping_dir, _ = mpu.split_path(self.subtitle_mapping)
    local subtitles = {}
    utils.open_file(self.subtitle_mapping, 'r', function(f)
        for entry in f:lines("*l") do
            local id, path = entry:match("^([%d]+),\"(.+)\"$")
            if tonumber(id) == show_info.anilist_data.id then
                if path:sub(1, 1) ~= '/' and path:sub(2, 2) ~= ':' then
                    -- relative path — prepend mapping_dir
                    path = mapping_dir .. path
                end
                assert(utils.path_exists(path), ("Path in mapping was invalid: '%s'"):format(path))
                -- Cross-platform directory listing using mp.utils.readdir
                local files = mpu.readdir(path, "files") or {}
                for _, file in ipairs(files) do
                    if self:is_supported_archive(file) then
                        local _, files_in_archive = self:extract_archive(path .. '/' .. file, show_info)
                        for _, ff in ipairs(files_in_archive) do
                            ff.last_modified = 1
                            table.insert(subtitles, ff)
                        end
                    else
                        table.insert(subtitles, {
                            name = file,
                            matching_episode = self:is_matching_episode(show_info, file),
                            absolute_path = path .. '/' .. file,
                            is_downloaded = true,
                            last_modified = 1
                        })
                    end
                end
            end
        end
    end)
    return subtitles
end

return offline
