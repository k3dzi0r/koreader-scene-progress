-- Real fork/pipe/kill/waitpid, using upstream ffi/util.lua. Only the UI event
-- loop and the unused filesystem helper are replaced for this headless test.
local upstream = assert(arg[1], "pass the KOReader source directory")
package.path = "sceneprogress.koplugin/?.lua;" .. upstream .. "/base/?.lua;" .. package.path
package.loaded["libs/libkoreader-lfs"] = {}
local ffi = require("ffi")
local ffiutil = require("ffi/util")
local tasks = {}
package.loaded["ui/uimanager"] = {
    scheduleIn=function(_, _, fn) tasks[#tasks+1]=fn end,
    unschedule=function(_, fn)
        for i=#tasks,1,-1 do if tasks[i]==fn then table.remove(tasks,i) end end
    end,
}
local Worker = require("sceneprogress/worker")
local function drain()
    local steps=0
    while #tasks>0 do
        steps=steps+1
        assert(steps<2000,"worker leaked event-loop tasks")
        local fn=table.remove(tasks,1)
        fn()
        ffi.C.usleep(1000)
    end
end
local received
Worker.start(function() return {value=42} end, function(value) received=value end)
drain();assert(received.value==42)
print("ok worker 1 - real fork and serialized result")
local large=string.rep("X",1000000)
Worker.start(function() return large end, function(value) received=value end)
drain();assert(received==large)
print("ok worker 2 - pipe result exceeds kernel buffer without blocking reader")
local error_name
Worker.start(function() error("intentional failure") end, function(value,err) received=value;error_name=err end)
drain();assert(not received and error_name=="scan")
print("ok worker 3 - scan failure is isolated")
local called=false
local job=Worker.start(function() ffi.C.usleep(5000000);return 1 end, function() called=true end)
-- Wait for runInSubProcess to establish its process group, as the UI does.
ffi.C.usleep(20000)
job:cancel();drain()
assert(not called and not job.fd and ffiutil.isSubProcessDone(job.pid))
print("ok worker 4 - cancel kills, closes and reaps without delivering stale result")
local limit
local timeout_job=Worker.start(function() ffi.C.usleep(5000000) end, function(_,err) limit=err end)
ffi.C.usleep(20000)
timeout_job.ticks=600
drain();assert(limit=="limit" and not timeout_job.fd)
print("ok worker 5 - timeout releases resources")
print("PASS: 5 worker tests against upstream POSIX implementation")
