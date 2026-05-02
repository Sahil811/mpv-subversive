local mp = require 'mp'
local mpu = require 'mp.utils'
local options = require 'mp.options'
local loader = require('subloader')
local util = require 'utils.utils'

local function default_cache_dir()
    if util.is_windows() then
        local temp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\temp"
        return temp .. "\\subloader"
    end
    return "/tmp/subloader"
end

OPTS = {
    enabled = true,
    -- the selected subtitle file is stored in the directory below. Leave it blank to skip this step
    -- If the path is relative, this is interpreted as relative to the currently playing file
    chosen_sub_dir = './subs',
    cache_directory = default_cache_dir(),
    -- When looking up the show for any given file, the result of that lookup is stored in the cache
    -- That same result is then used for all other files in the directory of that file.
    enable_lookup_caching = true,
    -- Exclude some directories from being considered for lookup caching.
    -- you can add multiple directories, separated by semicolons (;)
    media_blacklist_dir = "",
    subtitle_backend = 'jimaku', -- can be either 'jimaku' or 'offline'
    subtitle_mapping = string.format("%s/mapping.csv", mp.get_script_directory()),
    API_TOKEN = "",
    -- Auto-load best matching subtitle on file load (requires episode detection and cached .anilist.id)
    auto_load_subs = false,
    -- Preferred subtitle language codes (comma-separated, e.g., "ja,jp,jpn")
    preferred_languages = "ja,jp,jpn",
    -- Show OSD notifications for operations
    show_notifications = true,
    -- Retry failed downloads (number of attempts)
    download_retry_count = 3,
    -- Timeout for HTTP requests in seconds
    http_timeout = 30,
    keybinding = "q",
}
options.read_options(OPTS, 'mpv-subversive')

local backend
local initialized = false

-- Initialize backend and keybindings ONCE (not on every file load)
local function init()
    if initialized then return end
    initialized = true
    backend = require("backend.backend"):new(OPTS)
    mp.add_key_binding(OPTS.keybinding, "find_sub", function() loader:run(backend) end)
end

local function on_file_loaded()
    init()

    if OPTS.auto_load_subs then
        local function try_auto_load()
            local path = mp.get_property("path")
            if not path or path:match("^%a+://") then return end -- Skip URLs

            local dir, _ = mpu.split_path(path)
            local saved_id = util.open_file(dir .. '/' .. loader.ID_FILE, 'r', function(f) return f:read("*l") end)

            if saved_id then
                if OPTS.show_notifications then
                    mp.osd_message("Auto-loading subtitles...", 2)
                end
                loader:auto_load(backend, saved_id)
            end
        end

        mp.add_timeout(1, try_auto_load)
    end
end

if OPTS.enabled then
    mp.register_event("file-loaded", on_file_loaded)
    mp.register_event("shutdown", function()
        if not backend then return end
        if backend.scheduler then
            backend.scheduler:quit()
        end
        for anilist_id, cache_table in pairs(backend.cache or {}) do
            local cache_path = backend.cache_directory .. '/' .. anilist_id .. '/' .. 'cache.json'
            util.write_file_atomic(cache_path, mpu.format_json(util.copy_table(cache_table)))
        end
    end)
end
