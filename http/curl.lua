local mp = require 'mp'
local scheduler = require("scheduler.scheduler")
local Routine = require("scheduler.routine")
local utils = require "utils.utils"

---@class CURL : HTTPClient curl-backed implementation
---@field schedulers table<string,Scheduler>
---@field default_headers table<string,string>
local CURL = {
    schedulers = {},
    default_headers = {
        ["Connection"] = "close",
        ["Accept"] = "application/json"
    }
}

-- Bug 23 fix: cache the curl binary name so we don't probe on every request
local _curl_cmd = nil
local function get_curl_cmd()
    if _curl_cmd then return _curl_cmd end
    local null_redirect = utils.is_windows() and ">nul 2>&1" or ">/dev/null 2>&1"
    local found = os.execute("curl.exe --version " .. null_redirect)
    if found == 0 or found == true then
        _curl_cmd = "curl.exe"
    else
        _curl_cmd = "curl"
    end
    return _curl_cmd
end

---@return Scheduler
function CURL:get_scheduler(host, port)
    local key = host .. ':' .. port
    if not self.schedulers[key] then
        self.schedulers[key] = scheduler.new {
            carrier = "curl",
            host = host,
            port = port,
            thread_count = 3,
        }
    end
    return self.schedulers[key]
end

---@param request Request
---@return string[]
function CURL:build_curl_cmd(request, method)
    local request_headers = { ["Host"] = request.host }
    for k, v in pairs(self.default_headers) do request_headers[k] = v end
    for k, v in pairs(request.headers) do request_headers[k] = v end
    local curl_args = {}
    local function add_args(...) for _, arg in ipairs({ ... }) do table.insert(curl_args, arg) end end
    local function add_header(k, v) add_args("--header", ("%s: %s"):format(k, v)) end

    add_args(get_curl_cmd(), "-i", "--http1.1", "--raw")
    add_args("-X", (assert(method, "Missing method! Expected GET or POST")))

    -- Apply configured timeout if available
    local timeout = OPTS and OPTS.http_timeout
    if timeout and tonumber(timeout) then
        add_args("--max-time", tostring(timeout))
    end

    if method == "POST" then
        add_args("--data", (assert(request.body, "Missing data for POST request")))
    end

    for k, v in pairs(request_headers) do add_header(k, v) end
    add_args(request.url)
    return curl_args
end

---@param request Request
---@return Response
function CURL:sync_GET(request)
    request = self:unpack_url(request)
    local result, error = mp.command_native({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        args = CURL:build_curl_cmd(request, "GET")
    })

    if not result then
        return { data = error or "Unknown error", headers = {}, status_code = 0, status_message = "Subprocess failed" }
    end

    if result.status ~= 0 then
        return { data = result.stderr or "curl command failed", headers = {}, status_code = 0,
            status_message = ("curl exit code: %d"):format(result.status) }
    end

    return self:parse_response(result.stdout)
end

---@param request Request
---@return Routine<Response>
function CURL:async_GET(request)
    request = self:unpack_url(request)
    local init_func = function(routine)
        -- Bug 24 fix: use pcall instead of assert inside the async callback to avoid crashing MPV
        mp.command_native_async({
            name = "subprocess",
            capture_stdout = true,
            capture_stderr = true,
            args = CURL:build_curl_cmd(request, "GET")
        }, function(success, result, error)
            if not success then
                routine.callback_result = { data = error or "Subprocess error", headers = {}, status_code = 0,
                    status_message = "async subprocess failed" }
            else
                local ok, parsed = pcall(function() return self:parse_response(result.stdout) end)
                routine.callback_result = ok and parsed or
                    { data = tostring(parsed), headers = {}, status_code = 0, status_message = "parse error" }
            end
            coroutine.resume(routine.co)
        end)
        coroutine.yield()
    end
    local routine = Routine:new {
        id = assert(request.id or request.path),
        polling_type = 'callback',
        create_coroutine_func = init_func,
    }
    return CURL:get_scheduler(request.host, request.port):schedule(routine)
end

---@param request Request
---@return Response
function CURL:POST(request)
    request = self:unpack_url(request)
    local result, error = mp.command_native({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        args = CURL:build_curl_cmd(request, "POST")
    })

    if not result then
        return { data = error or "Unknown error", headers = {}, status_code = 0, status_message = "Subprocess failed" }
    end

    if result.status ~= 0 then
        return { data = result.stderr or "curl command failed", headers = {}, status_code = 0,
            status_message = ("curl exit code: %d"):format(result.status) }
    end

    return self:parse_response(result.stdout)
end

return CURL
