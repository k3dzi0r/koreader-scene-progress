-- KOReader's POSIX worker API also works on Android. Drain the pipe in bounded
-- nonblocking chunks; unlike Trapper, this does not intercept reading gestures.
local ffi = require("ffi")
local ffiutil = require("ffi/util")
local buffer = require("string.buffer")
local UIManager = require("ui/uimanager")
local Worker = {}

local function reap(pid)
    if not ffiutil.isSubProcessDone(pid) then
        UIManager:scheduleIn(1, function() reap(pid) end)
    end
end

function Worker.start(task, callback)
    local pid, fd = ffiutil.runInSubProcess(function(_, output)
        local ok, result = pcall(task)
        local data = buffer.encode(ok and { ok = true, result = result } or { ok = false })
        local ptr, offset = ffi.cast("const char *", data), 0
        while offset < #data do
            local count = tonumber(ffi.C.write(output, ptr + offset, #data - offset))
            if count <= 0 then break end
            offset = offset + count
        end
        ffi.C.close(output)
    end, true)
    if not pid then callback(nil, "worker"); return end
    local job = { pid = pid, fd = fd, chunks = {}, bytes = 0, ticks = 0 }
    local function release(kill)
        if kill then ffiutil.terminateSubProcess(pid) end
        ffi.C.close(fd)
        job.fd = nil
        job.chunks = nil
        reap(pid)
    end
    function job:cancel()
        if not self.fd then return end
        UIManager:unschedule(self.poll)
        release(true)
    end
    job.poll = function()
        if not job.fd then return end
        job.ticks = job.ticks + 1
        local available = ffiutil.getNonBlockingReadSize(fd)
        if available == nil or job.ticks > 600 or job.bytes > 4 * 1024 * 1024 then
            release(true)
            callback(nil, "limit")
            return
        end
        if available > 0 then
            local size = math.min(available, 65536)
            local chunk = ffi.new("char[?]", size)
            local read = tonumber(ffi.C.read(fd, chunk, size))
            if read > 0 then
                job.chunks[#job.chunks + 1] = ffi.string(chunk, read)
                job.bytes = job.bytes + read
            end
        end
        if ffiutil.isSubProcessDone(pid) and ffiutil.getNonBlockingReadSize(fd) == 0 then
            local data = table.concat(job.chunks)
            release(false)
            local ok, payload = pcall(buffer.decode, data)
            if ok and type(payload) == "table" and payload.ok then
                callback(payload.result)
            else
                callback(nil, "scan")
            end
        else
            UIManager:scheduleIn(0.1, job.poll)
        end
    end
    UIManager:scheduleIn(0.1, job.poll)
    return job
end

return Worker
