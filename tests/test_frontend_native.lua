-- Exercise upstream ReaderFooter methods, gettext MO loading and Lua cache
-- serialization. Screen/device/widget dependencies are headless test doubles.
local upstream, project = assert(arg[1]), assert(arg[2])
package.path=upstream.."/frontend/?.lua;"..upstream.."/base/?.lua;"..package.path
local ffi=require("ffi")
require("ffi/posix_h")
ffi.cdef[[int chdir(const char *path);]]
assert(ffi.C.chdir(upstream)==0)
package.loaded.logger={dbg=function() end,warn=function() end}
G_reader_settings={readSetting=function(_,key,default) return key=="language" and "pl" or default end}
G_defaults={readSetting=function() return 15 end}
local global_gettext=require("gettext")
global_gettext.translation["Scene:"]="global sentinel"
local private=dofile(project.."/sceneprogress.koplugin/sceneprogress/i18n.lua")
assert(private("Scene:")=="Scena:" and private("p.")=="str.")
assert(private("Enable scene counter")=="Włącz licznik scen")
assert(global_gettext("Scene:")=="global sentinel", "plugin changed global translations")
print("ok frontend 1 - actual KOReader gettext reads private Polish MO catalogue")
local dump=require("dump")
local buffer=require("string.buffer")
local binary=buffer.encode({1,"key\0\255",{rule=true}})
local serialized=dump({key=binary,index={entries={{xp="/body[1]/p[2]",page=4}}}})
local restored=assert(loadstring("return "..serialized))()
assert(restored.key==binary and restored.index.entries[1].page==4)
print("ok frontend 2 - actual KOReader dump preserves binary cache keys and XPointers")

local Widget={extend=function(self, value) return setmetatable(value,{__index=self}) end}
local footer_path=upstream.."/frontend/apps/reader/modules/readerfooter.lua"
local source=assert(io.open(footer_path)):read("*a")
for name in source:gmatch('require%("([^"]+)"%)') do
    if not package.loaded[name] then package.loaded[name]={} end
end
package.loaded["ui/bidi"]={mirroredUILayout=function() return false end}
package.loaded.device=setmetatable({screen={scaleBySize=function(_,n) return n end}},
    {__index=function() return function() return false end end})
package.loaded["ui/size"]={span={horizontal_default=0},padding={tiny=0}}
package.loaded["ui/widget/container/widgetcontainer"]=Widget
local Footer=dofile(footer_path)
local footer=setmetatable({
    additional_footer_content={},settings={item_prefix="letters",all_at_once=true,pages_left=true,chapter_time_to_read=true},
    pageno=1,ui={
        toc={getChapterPagesLeft=function() return 11 end},
        statistics={getTimeForPages=function(_,pages) return pages.."m" end},
        document={getTotalPagesLeft=function() return 99 end},
    },
},{__index=Footer})
local callback=function() return "S:4 · 6m" end
footer:addAdditionalFooterContent(callback)
assert(footer.settings.additional_content and #footer.additional_footer_content==1)
assert(footer.textGeneratorMap.additional_content(footer)=="S:4 · 6m")
assert(footer.textGeneratorMap.pages_left(footer)=="=> 11")
assert(footer.textGeneratorMap.chapter_time_to_read(footer)=="TC: 11m")
local refreshes=0
footer.maybeUpdateFooter=function() refreshes=refreshes+1 end
footer:onRefreshAdditionalContent();assert(refreshes==1)
footer:removeAdditionalFooterContent(callback)
assert(#footer.additional_footer_content==0 and not footer.settings.additional_content)
assert(footer.textGeneratorMap.additional_content(footer)==nil)
assert(footer.textGeneratorMap.pages_left(footer)=="=> 11")
print("ok frontend 3 - actual ReaderFooter add/remove/refresh and native chapter/time generators coexist")
print("PASS: 3 tests against upstream frontend source")
