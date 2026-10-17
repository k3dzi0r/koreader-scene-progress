-- Run the real plugin against explicit KOReader UI/worker test doubles.
package.path = "sceneprogress.koplugin/?.lua;" .. package.path
local buffer = require("string.buffer")
local Config = require("sceneprogress/config")
local scheduled, jobs, events = {}, {}, {}
local function store()
    return {
        readSetting = function(self, key, default) local v=rawget(self,key); if v==nil then return default end; return v end,
        saveSetting = function(self, key, value) self[key]=value end,
    }
end
G_reader_settings = store()
local Widget = {}
function Widget:extend(value) return setmetatable(value, {__index=self}) end
function Widget:new(value) local v=self:extend(value or {}); if v.init then v:init() end; return v end
package.loaded["ui/widget/container/widgetcontainer"] = Widget
package.loaded["ui/widget/infomessage"] = Widget
package.loaded["ui/widget/inputdialog"] = Widget
package.loaded["ui/uimanager"] = {
    scheduleIn=function(_, _, fn) scheduled[fn]=true end,
    unschedule=function(_, fn) scheduled[fn]=nil end,
    show=function() end, close=function() end,
}
package.loaded["ui/event"] = { new=function(_, name) return {name=name} end }
package.loaded["libs/libkoreader-lfs"] = {attributes=function() return {size=100,modification=10,change=10} end}
package.loaded["util"] = {htmlEntitiesToUtf8=function(s) return s end}
package.loaded["sceneprogress/i18n"] = function(s) return s end
package.loaded["sceneprogress/worker"] = {start=function(task, callback)
    local job={task=task, callback=callback, cancel=function(self) self.cancelled=true end}
    jobs[#jobs+1]=job
    return job
end}
local Plugin = dofile("sceneprogress.koplugin/main.lua")
local function create()
    local footer={ callbacks={}, settings={} }
    function footer:addAdditionalFooterContent(fn) self.callbacks[#self.callbacks+1]=fn end
    function footer:removeAdditionalFooterContent(fn)
        for i,value in ipairs(self.callbacks) do if fn==value then table.remove(self.callbacks,i); return end end
    end
    local ui={
        menu={registerToMainMenu=function(self, plugin) self.plugin=plugin end},
        view={footer=footer}, rolling={}, doc_settings=store(),
        document={file="sample.epub", hash=1, page=1, delayed=false,
            getDocumentFormat=function() return "EPUB" end,
            getDocumentRenderingHash=function(self) return self.hash end,
            getCurrentPage=function(self) return self.page end,
            getHTMLFromXPointer=function() end, getNormalizedXPointer=function() end,
            isRerenderingDelayed=function(self) return self.delayed end,
            getLatestDomVersion=function() return 20260812 end,
            getDomVersionWithNormalizedXPointers=function() return 20200223 end,
            getPageFlow=function() return 0 end,
            getPageNumberInFlow=function(_,p) return p end,
            getTotalPagesLeft=function(_,p) return 20-p end,
        },
        toc={getChapterPagesLeft=function(_,p) return 12-p end},
        handleEvent=function(_,event) events[#events+1]=event.name end,
    }
    return Plugin:new{ui=ui},ui,footer
end
local total=0
local function check(name, fn) fn();total=total+1; print("ok lifecycle "..total.." - "..name) end
local result={entries={{page=5,linear_page=5,xp="/body/p[2]",kind="single"}},rejected=0}
check("register, footer callback identity, enable once and native chapter coexist", function()
    local plugin,ui,footer=create()
    assert(ui.menu.plugin==plugin)
    local toc=ui.toc
    plugin:onReaderReady(); plugin:attach()
    assert(#footer.callbacks==1 and footer.callbacks[1]==plugin.content_func)
    assert(scheduled[plugin.start_task] and not plugin:footerText())
    plugin:startScan()
    jobs[#jobs].callback(result)
    assert(plugin:footerText()=="S:4 · —")
    assert(ui.toc==toc and ui.toc:getChapterPagesLeft(1)==11)
    ui.document.page=5; assert(plugin:footerText()=="S:0 · —")
    ui.document.page=6; assert(plugin:footerText()=="S:6 · —")
    ui.document.page=1; assert(plugin:footerText()=="S:4 · —")
    plugin:onCloseDocument(); assert(#footer.callbacks==0)
end)
check("independent indicators, compact mode, persistence and disable/re-enable", function()
    local plugin,_,footer=create()
    plugin:onReaderReady();plugin:startScan();jobs[#jobs].callback(result)
    plugin.settings.show_time=false;plugin:changed()
    assert(plugin:footerText()=="S:4")
    plugin.settings.show_pages=false;plugin:changed();assert(not plugin:footerText())
    plugin.settings.show_time=true;plugin.settings.compact=false;plugin:changed()
    assert(plugin:footerText()=="Scene: —")
    plugin.settings.enabled=false;plugin:changed()
    assert(#footer.callbacks==0 and not plugin:footerText())
    assert(Config.load(G_reader_settings).enabled==false)
    plugin.settings.enabled=true;plugin:changed();assert(#footer.callbacks==1)
    plugin:onCloseDocument()
    G_reader_settings.sceneprogress=nil
end)
check("reflow rejects old pages immediately and ignores stale worker", function()
    local plugin,ui=create()
    plugin:startScan();local first=jobs[#jobs];first.callback(result)
    assert(plugin:footerText())
    ui.document.hash=2
    assert(not plugin:footerText())
    plugin:onDocumentRerendered();assert(not plugin.index and scheduled[plugin.start_task])
    plugin:startScan();local second=jobs[#jobs]
    plugin:onDocumentRerendered();assert(second.cancelled)
    second.callback(result);assert(not plugin.index)
    plugin:onCloseDocument()
end)
check("cached index reused; file/layout/rules changes invalidate it", function()
    local plugin,ui=create()
    plugin:startScan();jobs[#jobs].callback(result)
    local n=#jobs
    plugin:startScan();assert(#jobs==n and plugin.index==result)
    ui.document.hash=9;plugin:startScan();assert(#jobs==n+1)
    jobs[#jobs].callback(result)
    plugin.settings.rules.single=false;plugin:startScan();assert(#jobs==n+2)
    plugin:onCloseDocument()
end)
check("close during scan, switch books without restart and no leaked callback", function()
    local plugin,ui,footer=create()
    plugin:onReaderReady();plugin:startScan();local old=jobs[#jobs]
    plugin:onCloseDocument();assert(old.cancelled and not scheduled[plugin.start_task])
    old.callback(result);assert(not plugin.index and #footer.callbacks==0)
    ui.document.file="second.epub";ui.doc_settings=store()
    plugin:onReaderReady();plugin:startScan();jobs[#jobs].callback({entries={},rejected=0})
    assert(plugin:footerText()=="S:11 · —" and #footer.callbacks==1)
    plugin:onCloseDocument();plugin:onCloseWidget();assert(#footer.callbacks==0)
end)
check("PDF and unsupported footer APIs remain inactive", function()
    local plugin,ui,footer=create()
    ui.document.file="sample.pdf";plugin:onReaderReady()
    assert(#footer.callbacks==0 and not scheduled[plugin.start_task])
    ui.document.file="sample.epub";footer.addAdditionalFooterContent=false
    plugin:onReaderReady();assert(#footer.callbacks==0)
    plugin:onCloseDocument()
end)
check("failed/malformed book scan and delayed layout do not show invented values", function()
    local plugin,ui=create()
    plugin:startScan();jobs[#jobs].callback(nil)
    assert(plugin.state=="failed" and not plugin:footerText())
    ui.document.delayed=true;plugin:startScan()
    assert(plugin.state=="partial" and not plugin.index)
    ui.document.delayed=false;plugin:onDocumentRerendered();plugin:startScan()
    jobs[#jobs].callback(result);assert(plugin:footerText())
    plugin:onDocumentPartiallyRerendered();assert(not plugin:footerText())
    plugin:onCloseDocument()
end)
check("menu exposes configuration and rescan", function()
    local plugin=create();local menu={};plugin:addToMainMenu(menu)
    assert(menu.sceneprogress.text=="Scene Progress" and #menu.sceneprogress.sub_item_table==7)
    local settings=menu.sceneprogress.sub_item_table
    assert(settings[1].checked_func())
    settings[1].callback();assert(not plugin.settings.enabled)
    settings[1].callback();assert(plugin.settings.enabled)
    assert(settings[6].enabled_func())
    plugin:onCloseDocument()
    G_reader_settings.sceneprogress=nil
end)
-- A cache containing binary key data must survive KOReader-style Lua serialization.
assert(type(buffer.encode({1,"test"}))=="string")
print("PASS: "..total.." lifecycle tests")
