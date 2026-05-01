local loader = {
    ID_FILE = ".anilist.id"
}
require 'utils.sequence'
require 'utils.regex'
local mp = require 'mp'
local mpu = require 'mp.utils'
local mpi = require 'mp.input'
local menu = require 'menu'
local util = require 'utils.utils'

local function build_menu_entry(anilist_media)
    local start, end_ = anilist_media.startDate.year, anilist_media.endDate.year
    local year_string = start == end_ and start or ("%s-%s"):format(start, end_ or '...')
    return ("[%s]  %s  (%s)"):format(anilist_media.format, anilist_media.title.romaji, year_string)
end

local show_selector = menu:new { pos_x = 50, pos_y = 50 }
local sub_selector = menu:new { pos_x = 50, pos_y = 50 }

function show_selector:build_manual_episode_console()
    mpi.get {
        prompt = "Please type the correct episode number: ",
        submit = function(episode_text)
            local ep_number = tonumber(episode_text)
            if ep_number then
                mpi.terminate()
                self.show_info.ep_number = ep_number
                self:display()
            end
        end,
        edited = function(episode_text)
            if not tonumber(episode_text) then
                mpi.log("This isn't a valid number!")
            end
        end,
    }
end

function show_selector:build_manual_lookup_console()
    local search_results = {}
    local search_menu = menu:new { pos_x = 50, pos_y = 50 }
    local current_search = ""
    local search_timer = nil
    local is_searching = false

    search_menu:set_header("Search Results")
    search_menu.selected = 1

    local function do_search(query)
        if #query < 3 then return end

        is_searching = true
        if self.backend.show_notifications then
            mp.osd_message(("Searching for: %s..."):format(query), 1)
        end

        local results = self.backend:query_shows { parsed_title = query }
        search_results = results or {}

        search_menu.choices = {}
        search_menu.selected = 1

        if #search_results == 0 then
            search_menu:set_header(("No results for: %s"):format(query))
            if self.backend.show_notifications then
                mp.osd_message("No results found", 2)
            end
        else
            search_menu:set_header(("Found %d results for: %s (Use ↑↓ to select, Enter to choose)"):format(#search_results, query))

            for _, anime in ipairs(search_results) do
                local entry_text = build_menu_entry(anime)
                entry_text = entry_text .. string.format(" [ID:%d, Eps:%s]",
                    anime.id, anime.episodes or "?")

                local menu_item = search_menu:new_item {
                    display_text = entry_text,
                    on_chosen_cb = function(item)
                        search_menu:close()

                        print(("[mpv-subversive] Selected: %s (ID: %d)"):format(
                            item.anime_data.title.romaji, item.anime_data.id))

                        self.show_info.anilist_data = item.anime_data
                        self.show_info.parsed_title = item.anime_data.title.romaji
                        self:cache_lookup(item.anime_data)

                        mpi.get {
                            prompt = string.format("Episode number for %s: ", item.anime_data.title.romaji),
                            opened = function()
                                mpi.log("Enter episode number and press ENTER")
                                if item.anime_data.episodes then
                                    mpi.log(("Total episodes: %d"):format(item.anime_data.episodes))
                                end
                            end,
                            submit = function(ep_text)
                                if not ep_text or #ep_text == 0 then
                                    mpi.log_error("No episode number entered!")
                                    return
                                end

                                local ep_num = tonumber(ep_text)
                                if ep_num and ep_num > 0 then
                                    mpi.terminate()
                                    self.show_info.ep_number = ep_num

                                    if self.backend.show_notifications then
                                        mp.osd_message(("Loading %s Episode %d..."):format(
                                            item.anime_data.title.romaji, ep_num), 2)
                                    end

                                    if not sub_selector.backend then
                                        sub_selector:init(self.backend)
                                    end

                                    sub_selector:query(self.show_info)
                                else
                                    mpi.log_error("Invalid episode number! Please enter a positive number.")
                                end
                            end
                        }
                    end
                }
                menu_item.anime_data = anime
                search_menu:add(menu_item)
            end

            search_menu:open()
        end

        is_searching = false
    end

    mpi.get {
        prompt = "Search anime: ",
        opened = function()
            mpi.log("Type anime name (3+ characters) and press ENTER to search")
            mpi.log("Example: gintama, conan, naruto, etc.")
        end,
        submit = function(query)
            if query and #query >= 3 then
                current_search = query
                mpi.terminate()
                print(("[mpv-subversive] Searching for: %s"):format(query))
                do_search(query)
            else
                mpi.log_error("Please enter at least 3 characters")
            end
        end,
        edited = function(text)
            if text and #text >= 3 and text ~= current_search then
                current_search = text
                if search_timer then search_timer:kill() end
                search_timer = mp.add_timeout(1.0, function()
                    if not is_searching then
                        mpi.log(("Type complete and press ENTER to search: %s"):format(text))
                    end
                end)
            end
        end
    }
end

function show_selector:build_manual_episode_console_then_query()
    local self_ref = self

    mpi.get {
        prompt = "Enter episode number: ",
        opened = function()
            mpi.log(("Selected: %s"):format(self_ref.show_info.parsed_title))
            mpi.log("Now enter the episode number you want to watch.")
            mpi.log("Press ENTER when done.")
        end,
        submit = function(episode_text)
            if not episode_text or #episode_text == 0 then
                mpi.log_error("No episode number entered!")
                return
            end

            local ep_number = tonumber(episode_text)

            if ep_number and ep_number > 0 then
                mpi.terminate()
                self_ref.show_info.ep_number = ep_number

                if self_ref.backend.show_notifications then
                    mp.osd_message(("Loading subtitles for %s Episode %d..."):format(self_ref.show_info.parsed_title, ep_number), 2)
                end

                if not sub_selector.backend then
                    sub_selector:init(self_ref.backend)
                end

                local success, err = pcall(function()
                    sub_selector:query(self_ref.show_info)
                end)

                if not success then
                    print(("[mpv-subversive] Error querying subtitles: %s"):format(err))
                    mp.osd_message(("Error: %s"):format(err), 5)
                end
            else
                mpi.log_error("Invalid episode number! Please enter a positive number.")
            end
        end,
        edited = function(episode_text)
            if episode_text and #episode_text > 0 then
                if not tonumber(episode_text) then
                    mpi.log("Please enter a valid number")
                end
            end
        end,
    }
end

function show_selector:init(backend, show_info)
    self.backend = backend
    self.show_info = show_info
    self.modify_show_item = self.modify_show_item or self:add_option {
        display_text = " >>>   Text-based lookup",
        on_chosen_cb = function() self:build_manual_lookup_console() end
    }
    -- Bug 7 fix: the original :format() call had no placeholders in the string
    self.modify_episode_item = self.modify_episode_item or self:add_option {
        display_text = " >>>   Modify episode number",
        on_chosen_cb = nil -- set in display()
    }
    self.initialized = true
end

function show_selector:cache_lookup(anilist_data)
    if not self.backend.enable_lookup_caching then return end
    -- Bug 3/16 fix: normalize-path is not a real MPV command; use split_path result directly
    local dir, _ = mpu.split_path(mp.get_property("path"))
    for _, media_blacklist_dir in pairs(self.backend.media_blacklist) do
        if dir == media_blacklist_dir then return end
    end

    local file_path = ("%s/%s"):format(dir, loader.ID_FILE)
    util.open_file(file_path, "w", function(f)
        print(("Caching show '%s', storing %s in %s"):format(anilist_data.title.romaji, anilist_data.id, file_path))
        f:write(anilist_data.id)
    end)
end

function show_selector:display(show_list)
    -- only show at most 10 entries; if more, the show name was probably parsed wrong
    self.show_list = show_list and show_list or util.table_slice(self.backend:query_shows(self.show_info), 1, 11)
    self:clear_choices()
    self:set_header(([[Looking for: %s, episode: %s]]):format(self.show_info.parsed_title,
        self.show_info.ep_number or 'N/A'))
    self.modify_episode_item.on_chosen_cb = function() self:build_manual_episode_console() end

    if #self.show_list == 0 then
        self:set_header(("No shows found for: %s"):format(self.show_info.parsed_title))
    end

    for _, s in ipairs(self.show_list) do
        local entry_text = build_menu_entry(s) .. string.format(" [ID:%d]", s.id)
        self:add_item {
            display_text = entry_text,
            on_chosen_cb = function(item)
                print(("[mpv-subversive] Selected show: %s (ID: %d)"):format(
                    item.anilist_data.title.romaji, item.anilist_data.id))
                self.show_info.anilist_data = item.anilist_data
                self:cache_lookup(item.anilist_data)
                sub_selector:query(self.show_info)
            end
        }
        self.choices[#self.choices].anilist_data = s
    end
    self:open()
end

function sub_selector:init(backend)
    self.backend = backend
    self.showing_all_choices = false
    self.go_back_option = self.go_back_option or self:add_option {
        display_text = " >>>   Return to show selection",
        on_chosen_cb = function()
            self:close()
            self.showing_all_choices = false
            show_selector:display(show_selector.show_list)
        end
    }
    self.show_all_toggle = self.show_all_toggle or self:add_option {
        display_text = " >>>   Toggle showing all files",
        on_chosen_cb = function()
            self.showing_all_choices = not self.showing_all_choices
            self:display()
        end
    }
    self.download_timer = function()
        local finished_results = self.backend:get_scheduler():poll()
        if #finished_results > 0 then
            self:draw()
        end
    end
end

function sub_selector:query(show_info)
    print(("[mpv-subversive] sub_selector:query called for show ID: %s, episode: %s"):format(
        show_info.anilist_data and show_info.anilist_data.id or "nil",
        show_info.ep_number or "nil"))

    self.subtitles = {}
    self.show_info = show_info

    local function extract_archive(path_to_archive)
        local _, files_in_archive = self.backend:extract_archive(path_to_archive, show_info)
        for _, f in ipairs(files_in_archive) do
            table.insert(self.subtitles, f)
        end
        return files_in_archive
    end

    local archive_cnt, completed_archive_cnt = 0, 0

    if self.backend.show_notifications then
        mp.osd_message("Fetching subtitles...", 5)
    end

    local queried_subtitles = self.backend:query_subtitles(show_info)
    local err = queried_subtitles['error']

    if err then
        print(("[mpv-subversive] Error querying subtitles: %s"):format(err))
        if self.backend.show_notifications then
            mp.osd_message(("Error: %s"):format(err), 5)
        end
        return
    end

    print(("[mpv-subversive] Found %d subtitle entries"):format(#queried_subtitles))

    if #queried_subtitles == 0 then
        if self.backend.show_notifications then
            mp.osd_message("No subtitles found", 3)
        end
        return
    end

    for _, sub in ipairs(queried_subtitles) do
        if self:is_cached(sub) then sub.is_downloaded = true end

        if sub.is_archive then
            local archive_name = self.backend:get_cached_path(show_info) .. sub.name
            if sub.is_downloaded then
                local cached_files = self:get_cache().archives[sub.name]
                if cached_files then
                    for _, s in ipairs(util.copy_table(cached_files)) do
                        s.matching_episode = self.backend:is_matching_episode(show_info, s.name)
                        table.insert(self.subtitles, s)
                    end
                end
            else
                archive_cnt = archive_cnt + 1
                self.backend:download_subtitle(sub):on_complete(function(result)
                    if not result or result.status_code ~= 200 then
                        print(("Failed to download archive: %s"):format(sub.name))
                        return false
                    end

                    completed_archive_cnt = completed_archive_cnt + 1
                    if self.backend.show_notifications then
                        mp.osd_message(("Extracted archive %d/%d: %s"):format(completed_archive_cnt, archive_cnt, sub.name), 2)
                    end

                    util.open_file(archive_name, 'wb', function(f) f:write(result.data) end)
                    self:cache_archive(sub, extract_archive(archive_name))
                    return true
                end)
            end
        else
            table.insert(self.subtitles, sub)
        end
    end

    local function display_sorted_subs()
        table.sort(self.subtitles, function(a, b)
            if a.matching_episode ~= b.matching_episode then
                return a.matching_episode
            end
            return a.name < b.name
        end)
        self:display()
    end

    if archive_cnt == 0 then
        return display_sorted_subs()
    end

    if self.backend.show_notifications then
        mp.osd_message(("Extracting %d archive(s)..."):format(archive_cnt), 3)
    end

    -- Bug 8 fix: kill stale archive_timer before creating a new one
    if self.archive_timer then
        self.archive_timer:kill()
        self.archive_timer = nil
    end
    self.archive_timer = mp.add_periodic_timer(0.2, function()
        self.backend:get_scheduler():poll()
        if not self.backend:get_scheduler():has_remaining() then
            self.archive_timer:kill()
            display_sorted_subs()
        end
    end)
end

function sub_selector:get_cache()
    if not self.backend.cache then
        self.backend.cache = {}
    end
    local show_id = self.show_info.anilist_data.id
    if not self.backend.cache[show_id] then
        local cache_path = self.backend:get_cached_path(self.show_info) .. 'cache.json'
        print(("Checking cache for id %s in path %q"):format(show_id, cache_path))
        self.backend.cache[show_id] = util.open_file(cache_path, 'r', function(f)
            local c, parse_err = mpu.parse_json(f:read("*a"))
            if not c then
                print(("Could not parse stored JSON %q: %s"):format(cache_path, parse_err))
            end
            return c
        end) or { subs = {}, archives = {} }
    end
    return self.backend.cache[show_id]
end

function sub_selector:is_cached(sub)
    local last_modified = self:get_cache().subs[sub.name]
    return last_modified and last_modified >= sub.last_modified
end

function sub_selector:cache_subtitle(sub)
    self:get_cache().subs[sub.name] = sub.last_modified
end

function sub_selector:cache_archive(archive_entry, files_in_archive)
    files_in_archive = util.copy_table(files_in_archive)
    self:cache_subtitle(archive_entry)
    for _, f in ipairs(files_in_archive) do
        f.matching_episode = nil
    end
    self:get_cache().archives[archive_entry.name] = files_in_archive
end

function sub_selector:select_item(menu_item)
    if not menu_item.subtitle.is_downloaded then
        if self.backend.show_notifications then
            mp.osd_message("Subtitle not downloaded yet, please wait...", 2)
        end
        return
    end

    if menu_item.parent.last_selected then
        mp.commandv("sub_remove", menu_item.parent.last_selected)
    end

    mp.commandv("sub_add", menu_item.subtitle.absolute_path, 'cached')
    menu_item.parent.last_selected = mp.get_property('sid')

    if menu_item.parent.last_selected then
        mp.commandv("set", "sid", menu_item.parent.last_selected)
        if self.backend.show_notifications then
            mp.osd_message(("Loaded: %s"):format(menu_item.subtitle.name), 3)
        end
    end
end

function sub_selector:choose_item(menu_item)
    if not menu_item.subtitle.is_downloaded then
        if self.backend.show_notifications then
            mp.osd_message("Subtitle not downloaded yet, please wait...", 2)
        end
        return
    end

    if self.backend.show_notifications then
        mp.osd_message(string.format("Selected: %s", menu_item.subtitle.name), 2)
    end

    if self.backend.chosen_sub_dir and #self.backend.chosen_sub_dir > 0 then
        local dir, fn = mpu.split_path(mp.get_property("path"))
        local sub_path = self.backend.chosen_sub_dir

        if sub_path:sub(1, 1) == '.' then
            sub_path = dir .. '/' .. sub_path .. '/'
        end

        if util.is_windows() then
            os.execute(string.format("mkdir %q >nul 2>&1", sub_path))
        else
            os.execute(("mkdir -p %q"):format(sub_path))
        end

        local sub_fn = table.concat({ sub_path, fn:gsub("[^.]+$", ""), util.get_extension(menu_item.subtitle.name) })
        local cp_cmd = util.is_windows() and "copy" or "cp"
        local result = os.execute(string.format("%s %q %q >nul 2>&1", cp_cmd, menu_item.subtitle.absolute_path, sub_fn))

        if result == 0 or result == true then
            if self.backend.show_notifications then
                mp.osd_message(("Subtitle saved to: %s"):format(sub_path), 3)
            end
        else
            if self.backend.show_notifications then
                mp.osd_message("Failed to save subtitle file", 3)
            end
        end
    end
end

function sub_selector:display()
    if #self.subtitles == 0 then
        if self.backend.show_notifications then
            mp.osd_message("No matching subtitles found", 3)
        end
        return
    end

    self:clear_choices()
    local start_dl = false
    self.last_selected = nil
    local matching_subs_count = 0

    for _, sub in ipairs(self.subtitles) do
        local text = sub.name
        local prefix = ""

        if sub.matching_episode then
            matching_subs_count = matching_subs_count + 1
            prefix = "[MATCH] "
        end

        local menu_entry = self:new_item {
            display_text = prefix .. text,
            is_visible = self.showing_all_choices and true or sub.matching_episode,
            font_size = 17,
            on_selected_cb = function(item) self:select_item(item) end,
            on_chosen_cb = function(item) self:choose_item(item) end
        }

        menu_entry.subtitle = sub

        if menu_entry.is_visible then
            if not sub.is_downloaded then
                start_dl = true
                menu_entry.display_text = '[DOWNLOADING] ' .. prefix .. text
                self:download(menu_entry)
            end
        end

        self:add(menu_entry)
    end

    local header_text = ("Found %d subtitle(s)"):format(#self.subtitles)
    if matching_subs_count > 0 then
        header_text = header_text .. (" (%d matching episode)"):format(matching_subs_count)
    end
    if not self.showing_all_choices and #self.subtitles > matching_subs_count then
        header_text = header_text .. (" | Toggle to see all %d"):format(#self.subtitles)
    end

    self:set_header(header_text)
    self:open()

    if start_dl then
        -- Bug 9 fix: kill stale timer and reset callbacks before re-assigning
        if self.timer then self.timer:kill() end
        self.on_close_callbacks = {}
        self.timer = mp.add_periodic_timer(0.2, self.download_timer)
        self:on_close(function()
            if self.timer then self.timer:kill() end
        end)
    end
end

function sub_selector:download(menu_item)
    if menu_item.subtitle.is_downloaded then
        menu_item.display_text = menu_item.subtitle.name
        return
    end

    local sub = menu_item.subtitle
    local max_retries = (self.backend.download_retry_count or 3)
    local attempt = 0

    local function do_download()
        attempt = attempt + 1
        self.backend:download_subtitle(sub):on_complete(function(response)
            if not response or response.status_code ~= 200 then
                if attempt < max_retries then
                    menu_item.display_text = ('[RETRY %d/%d] %s'):format(attempt, max_retries, sub.name)
                    mp.add_timeout(1.0, do_download)
                else
                    menu_item.display_text = '[FAILED] ' .. sub.name
                    if self.backend.show_notifications then
                        mp.osd_message(("Failed after %d attempts: %s"):format(max_retries, sub.name), 4)
                    end
                end
                return false
            end

            local success = util.open_file(sub.absolute_path, 'wb', function(f)
                f:write(response.data)
                return true
            end)

            if success then
                self:cache_subtitle(sub)
                menu_item.subtitle.is_downloaded = true
                menu_item.display_text = sub.name
                if self.backend.show_notifications then
                    mp.osd_message(("Downloaded: %s"):format(sub.name), 2)
                end
            else
                menu_item.display_text = '[SAVE FAILED] ' .. sub.name
                if self.backend.show_notifications then
                    mp.osd_message(("Could not save: %s"):format(sub.name), 3)
                end
            end

            return success ~= nil and success or false
        end):on_incomplete(function(response)
            local content_length = response.headers and response.headers['content-length']
            if not content_length then return end
            local data_downloaded = response.data and #response.data or 0
            local percent = math.floor(100 * data_downloaded / tonumber(content_length))
            menu_item.display_text = ('[%d%%] %s'):format(percent, sub.name)
            self:draw()
        end)
    end

    do_download()
end

function loader:run(backend)
    if backend.show_notifications then
        mp.osd_message("Loading mpv-subversive...", 1)
    end

    local dir, fn = mpu.split_path(mp.get_property("path"))
    -- Bug 3/16 fix: normalize-path is not a standard MPV command; use split_path result directly
    local show_name, episode = backend:parse_current_file(fn)

    local initial_show_info = {
        parsed_title = show_name,
        ep_number = episode and tonumber(episode),
    }

    -- Bug 5 fix: episode can be nil — use %s/tostring instead of %d
    print(("[mpv-subversive] show title: '%s', episode number: '%s'"):format(show_name, tostring(episode or 'N/A')))

    show_selector:init(backend, initial_show_info)
    sub_selector:init(backend)

    -- look for .anilist.id file to skip the show selection menu
    local saved_id = util.open_file(dir .. '/' .. self.ID_FILE, 'r', function(f) return f:read("*l") end)
    if saved_id then
        print(("[mpv-subversive] Found cached AniList ID: %s"):format(saved_id))
        initial_show_info.anilist_data = { id = tonumber(saved_id) }

        if backend.show_notifications then
            mp.osd_message("Found cached show, fetching subtitles...", 2)
        end
        sub_selector:query(initial_show_info)
        return
    end

    if backend.show_notifications then
        mp.osd_message("Searching for show...", 3)
    end
    print("[mpv-subversive] No cached ID found, showing show selection menu")
    show_selector:display()
end

function loader:auto_load(backend, anilist_id)
    local _, fn = mpu.split_path(mp.get_property("path"))
    local show_name, episode = backend:parse_current_file(fn)

    if not episode or episode <= 0 then
        print("[mpv-subversive] Cannot auto-load: episode number not detected")
        return
    end

    local show_info = {
        parsed_title = show_name,
        ep_number = tonumber(episode),
        anilist_data = { id = tonumber(anilist_id) }
    }

    sub_selector:init(backend)
    -- Bug 12 fix: set show_info before calling is_cached (which accesses show_info.anilist_data.id)
    sub_selector.show_info = show_info

    local queried_subtitles = backend:query_subtitles(show_info)

    if queried_subtitles.error then
        print(("[mpv-subversive] Auto-load failed: %s"):format(queried_subtitles.error))
        return
    end

    local best_match = nil
    for _, sub in ipairs(queried_subtitles) do
        if not sub.is_archive and backend:is_matching_episode(show_info, sub.name) then
            if sub_selector:is_cached(sub) then
                local cached_path = backend:get_cached_path(show_info) .. sub.name
                if util.path_exists(cached_path) then
                    best_match = cached_path
                    break
                end
            end
        end
    end

    if best_match then
        mp.commandv("sub_add", best_match, 'cached')
        if backend.show_notifications then
            mp.osd_message("Auto-loaded subtitle", 2)
        end
        print(("[mpv-subversive] Auto-loaded: %s"):format(best_match))
    else
        print("[mpv-subversive] Auto-load: no cached matching subtitle found")
    end
end

return loader
