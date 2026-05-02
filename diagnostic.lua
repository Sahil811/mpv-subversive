-- mpv-subversive Diagnostic Tool
-- Run this in MPV console to check your setup
-- Usage: script-message-to mpv_subversive_diag run

local mp = require 'mp'
local mpu = require 'mp.utils'

local function get_null_redirect()
    return (package.config:sub(1,1) == "\\") and " >nul 2>&1" or " >/dev/null 2>&1"
end

local function check_curl()
    local result = os.execute("curl --version" .. get_null_redirect())
    if result == 0 or result == true then
        return "✓ curl found"
    end
    result = os.execute("curl.exe --version" .. get_null_redirect())
    if result == 0 or result == true then
        return "✓ curl.exe found"
    end
    return "✗ curl not found - install curl"
end

local function check_extractors()
    local tools = {"unzip", "unrar", "7z"}
    local results = {}
    for _, tool in ipairs(tools) do
        local cmd = tool .. " --version" .. get_null_redirect()
        local result = os.execute(cmd)
        if result == 0 or result == true then
            table.insert(results, "✓ " .. tool)
        else
            table.insert(results, "✗ " .. tool .. " not found")
        end
    end
    return table.concat(results, "\n")
end

local function check_config()
    local config_path = mp.command_native({"expand-path", "~~/script-opts/mpv-subversive.conf"})
    local f = io.open(config_path, "r")
    if f then
        f:close()
        return "✓ Config file exists: " .. config_path
    end
    return "✗ Config file not found: " .. config_path
end

local function check_api_token()
    -- Try to read config
    local config_path = mp.command_native({"expand-path", "~~/script-opts/mpv-subversive.conf"})
    local f = io.open(config_path, "r")
    if not f then
        return "✗ Cannot check - config file not found"
    end
    
    local has_token = false
    for line in f:lines() do
        if line:match("^API_TOKEN=.+") and not line:match("^API_TOKEN=%s*$") then
            has_token = true
            break
        end
    end
    f:close()
    
    if has_token then
        return "✓ API_TOKEN is set"
    else
        return "✗ API_TOKEN not set - get one from https://jimaku.cc/account"
    end
end

local function check_cache_dir()
    local util = require 'utils.utils'
    local cache_dir = util.is_windows() and "C:\\temp\\subloader" or "/tmp/subloader"
    
    -- Try to create it
    if util.is_windows() then
        os.execute(string.format('mkdir "%s" >nul 2>&1', cache_dir:gsub("/", "\\")))
    else
        os.execute(string.format("mkdir -p %q", cache_dir))
    end
    
    -- Check if writable
    local test_file = cache_dir .. (util.is_windows() and "\\test" or "/test")
    local f = io.open(test_file, "w")
    if f then
        f:write("test")
        f:close()
        os.remove(test_file)
        return "✓ Cache directory writable: " .. cache_dir
    else
        return "✗ Cache directory not writable: " .. cache_dir
    end
end

local function test_filename_parsing()
    local backend = require("backend.backend")
    local test_files = {
        "[CBT] Gintama 077 [DVDrip 760x576 x264 FLAC].mkv",
        "Show Name - 01.mkv",
        "Show Name S01E05.mkv",
        "[Group] Show Name EP12 [1080p].mkv",
    }
    
    local results = {}
    for _, filename in ipairs(test_files) do
        local title, ep = backend.extract_title_and_number(backend.sanitize(filename))
        table.insert(results, string.format("  %s\n    → Title: '%s', Episode: %s", 
            filename, title, ep or "NOT DETECTED"))
    end
    
    return "Filename parsing test:\n" .. table.concat(results, "\n")
end

local function run_diagnostics()
    local report = {
        "=== mpv-subversive Diagnostic Report ===",
        "",
        "System Checks:",
        check_curl(),
        check_extractors(),
        "",
        "Configuration:",
        check_config(),
        check_api_token(),
        check_cache_dir(),
        "",
        test_filename_parsing(),
        "",
        "=== End of Report ===",
        "",
        "If you see ✗ marks, fix those issues first.",
        "Check the console for detailed error messages when using the plugin.",
    }
    
    local report_text = table.concat(report, "\n")
    print(report_text)
    mp.osd_message("Diagnostic report printed to console", 3)
end

mp.register_script_message("run", run_diagnostics)

-- Auto-run on load
mp.add_timeout(0.1, function()
    print("[mpv_subversive_diag] Diagnostic tool loaded. Run with: script-message-to mpv_subversive_diag run")
end)
