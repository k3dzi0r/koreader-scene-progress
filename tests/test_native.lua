-- Requires the unmodified koreader-base cre.cpp module and its matching engine.
-- Usage: LUA_CPATH='/path/to/?.so;;' luajit tests/test_native.lua /path/to/font.ttf
package.path = "sceneprogress.koplugin/?.lua;" .. package.path
local cre = require("cre")
local Config = require("sceneprogress/config")
local Index = require("sceneprogress/index")
local Detector = require("sceneprogress/detector")
local font = assert(arg[1], "pass a TrueType test font")
cre.registerFont(font)
local font_face = assert(cre.getFontFaces()[1], "font registration failed")
local passed = 0
local function decode(s)
    -- In real DOM output, EPUB entities have already been decoded by CREngine.
    return s:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&amp;', '&')
end
local function open(name, version)
    local raw = cre.newDocView(600, 800, 1)
    raw:setIntProperty("crengine.render.requested_dom_version", version or cre.getLatestDomVersion())
    raw:setStringProperty("font.face.default", font_face)
    raw:setFontSize(24)
    assert(raw:loadDocument("tests/fixtures/" .. name .. ".epub"))
    raw:renderDocument()
    assert(raw:getDocumentFormat() == "EPUB")
    local doc = {
        getPageCount = function() return raw:getPages() end,
        getPageNumberInFlow = function(_, p) return p end,
    }
    return setmetatable(doc, {__index=function(_, key)
        return function(_, ...) return raw[key](raw, ...) end
    end}), raw
end
for _, case in ipairs({
    {"single", 2}, {"triple", 2}, {"none", 0}, {"footnotes", 0},
    {"midpage", 1}, {"split", 1}, {"semantic", 5},
}) do
    local doc, raw = open(case[1])
    local before = raw:getXPointer()
    local result = Index.scan(doc, Config.defaults().rules, true, decode)
    assert(#result.entries == case[2], case[1] .. ": expected " .. case[2] .. ", got " .. #result.entries)
    assert(result.rejected == 0, "unmapped native XPointer")
    assert(raw:getXPointer() == before, "scan changed reading position")
    for _, entry in ipairs(result.entries) do
        assert(raw:isXPointerInDocument(entry.xp))
        assert(raw:getPageFromXPointer(entry.xp) == entry.page)
    end
    if case[1] == "midpage" then assert(result.entries[1].page == 1) end
    if case[1] == "split" then
        assert(result.entries[1].xp:find("DocFragment[2]", 1, true))
        assert(#raw:getToc() == 2, "split XHTML must retain two true chapters")
    end
    passed = passed + 1
    print("ok native " .. passed .. " - " .. case[1] .. ": " .. #result.entries
        .. " separators / " .. raw:getPages() .. " pages")
    raw:close()
end

local doc, raw = open("single")
local original = Index.scan(doc, Config.defaults().rules, true, decode)
local old_hash, old_pages = raw:getDocumentRenderingHash(true), raw:getPages()
raw:setFontSize(36)
raw:renderDocument()
local larger = Index.scan(doc, Config.defaults().rules, true, decode)
assert(raw:getPages() > old_pages)
assert(raw:getDocumentRenderingHash(true) ~= old_hash)
assert(#larger.entries == #original.entries)
assert(larger.entries[1].xp == original.entries[1].xp)
assert(larger.entries[1].page > original.entries[1].page)
local toc = {getChapterPagesLeft=function(_, page)
    local next_chapter
    for _, item in ipairs(raw:getToc()) do
        if item.page > page and (not next_chapter or item.page < next_chapter) then next_chapter = item.page end
    end
    return next_chapter and next_chapter-page-1 or raw:getPages()-page
end}
for _, page in ipairs({1, larger.entries[1].page, larger.entries[1].page+1, 1}) do
    raw:gotoPage(page)
    assert(Index.remaining(doc, toc, larger.entries, page) >= 0)
end
raw:close()
passed = passed + 1
print("ok native " .. passed .. " - font reflow, hash, forward/backward, nonnegative pages")

for _, version in ipairs({20171225, 20200223}) do
    local legacy_doc, legacy_raw = open("semantic", version)
    local normalized = version >= cre.getDomVersionWithNormalizedXPointers()
    local result = Index.scan(legacy_doc, Config.defaults().rules, normalized, decode)
    assert(#result.entries == 5 and result.rejected == 0, "legacy DOM mapping")
    legacy_raw:close()
    passed = passed + 1
    print("ok native " .. passed .. " - DOM version " .. version)
end

local broken = cre.newDocView(600, 800, 1)
local loaded = broken:loadDocument("tests/fixtures/broken.epub")
assert(not loaded or broken:getDocumentFormat() ~= "EPUB", "corrupt input must not activate the EPUB counter")
broken:close()
passed = passed + 1
print("ok native " .. passed .. " - corrupt EPUB is rejected by format gating")

-- Exercise the performance-critical lookup at a much larger separator count.
local many = {}
for page=1,10000 do many[page]={page=page*3, linear_page=page*3} end
local started = os.clock()
for i=1,100000 do assert(Index.next(many, (i % 29998)+1)) end
print(string.format("100000 lookups / 10000 separators: %.3fs (host CPU)", os.clock()-started))
assert(Detector.scan)
print("PASS: " .. passed .. " native CREngine tests")
