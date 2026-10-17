package.path = "sceneprogress.koplugin/?.lua;" .. package.path
local Detector = require("sceneprogress/detector")
local Config = require("sceneprogress/config")
local Index = require("sceneprogress/index")
local Time = require("sceneprogress/time")
local count = 0
local function check(name, fn)
    fn()
    count = count + 1
    print("ok " .. count .. " - " .. name)
end
local function decode(s)
    return s:gsub("&#42;", "*"):gsub("&#x2042;", "⁂"):gsub("&nbsp;", " ")
end
local function scan(body, rules, normalized)
    return Detector.scan('<RootNode><body ~B><DocFragment ~B><body ~B>'
        .. body .. '</body></DocFragment></body></RootNode>', rules or Config.defaults().rules,
        normalized ~= false, decode)
end

check("single, triple, spaced stars, numeric entity and ornaments", function()
    assert(#scan('<p ~F>*</p><p ~F>***</p><p ~F>* * *</p><p ~F>&#42;</p><p ~F>⁂</p>') == 5)
end)
check("no scenes and inline prose", function()
    assert(#scan('<p ~F>No stars.</p><p ~F>Word * word</p><p ~F>**bold**</p>') == 0)
end)
check("footnote references and ancestors", function()
    assert(#scan('<p ~F><a href="#n" ~i>*</a></p><p ~F><sup ~i>*</sup></p>'
        .. '<aside epub:type="footnote" ~B><p ~F>*</p></aside><p class="footnote" ~F>*</p>'
        .. '<p id="_doc_fragment_0_ fn2" ~F>*</p>') == 0)
end)
check("CSS-hidden ancestor and computed hidden nodes", function()
    assert(#scan('<div ~X><p ~F>*</p></div><p ~K>***</p>'
        .. '<p style="visibility: hidden" ~F>*</p><p ~X>*</p>'
        .. '<p hidden ~F>*</p><p hidden="hidden" ~F>*</p>') == 0)
end)
check("inline formatting does not duplicate block candidates", function()
    local entries = scan('<div ~B><p ~F><em ~i>*</em></p></div>')
    assert(#entries == 1 and entries[1].xp == '/body[1]/DocFragment[1]/body[1]/div[1]/p[1]')
end)
check("semantic classes, hr and conservative prose rejection", function()
    assert(#scan('<hr ~B/><div class="scene-break" ~B/><p class="scene-break" ~F>Prose</p>') == 2)
end)
check("rule toggles and custom exact CSS tokens", function()
    local rules = Config.defaults().rules
    rules.single, rules.semantic, rules.multiple, rules.ornaments = false, false, false, false
    assert(#scan('<p ~F>*</p><hr ~B/><p ~F>***</p><p ~F>⁂</p>', rules) == 0)
    rules.semantic, rules.classes = true, 'my-divider'
    assert(#scan('<div class="my-divider" ~B/><div class="not-my-divider" ~B/>', rules) == 1)
end)
check("boxing normalization preserves sibling indexes", function()
    local entries = scan('<p ~F>Prose</p><autoBoxing ~F><p ~F>*</p></autoBoxing><p ~F>***</p>')
    assert(entries[1].xp:match('/p%[2%]$') and entries[2].xp:match('/p%[3%]$'))
    assert(scan('<autoBoxing ~F><p ~F>*</p></autoBoxing>', nil, false)[1].xp:find('/autoBoxing[1]/', 1, true))
end)
check("quoted greater-than attributes and malformed DOM", function()
    assert(#scan('<p title="a > b" ~F>*</p>') == 1)
    assert(not pcall(Detector.scan, '<p>*', Config.defaults().rules, true, decode))
end)
local entries = { {page=5, linear_page=5}, {page=9, linear_page=9}, {page=17, linear_page=17} }
local doc = {
    getPageFlow = function() return 0 end,
    getPageNumberInFlow = function(_, p) return p end,
    getTotalPagesLeft = function(_, p) return 30-p end,
}
local toc = { getChapterPagesLeft = function(_, p) return p < 12 and 11-p or nil end }
check("forward, same-page and backward navigation", function()
    assert(Index.remaining(doc, toc, entries, 2) == 3)
    assert(Index.remaining(doc, toc, entries, 5) == 0)
    assert(Index.remaining(doc, toc, entries, 6) == 3)
    assert(Index.remaining(doc, toc, entries, 2) == 3)
end)
check("last scene falls back to real chapter and end of book", function()
    assert(Index.remaining(doc, toc, entries, 10) == 1)
    assert(Index.remaining(doc, toc, {}, 2) == 9)
    assert(Index.remaining(doc, toc, entries, 29) == 1)
    assert(Index.remaining(doc, toc, entries, 30) == 0)
end)
check("hidden-flow numbering and non-linear reading", function()
    local hidden_doc = {
        getPageFlow = function(_, p) return p == 3 and 1 or 0 end,
        getPageNumberInFlow = function(_, p) return p > 3 and p-1 or p end,
        getTotalPagesLeft = doc.getTotalPagesLeft,
    }
    assert(Index.remaining(hidden_doc, toc, {{page=5, linear_page=4}}, 2) == 2)
    assert(Index.remaining(hidden_doc, toc, entries, 3) == nil)
end)
check("time uses native measured rate and rejects default seed", function()
    local stats = { settings={is_enabled=true}, avg_time=60, book_read_pages=2, mem_read_pages=0,
        getTimeForPages=function(_, n) return n .. 'm' end }
    assert(Time.estimate(stats, 4) == nil)
    stats.mem_read_pages = 1
    assert(Time.estimate(stats, 4) == '4m')
    stats.avg_time = 0/0
    assert(Time.estimate(stats, 4) == nil)
    stats.avg_time, stats.settings.is_enabled = 60, false
    assert(Time.estimate(stats, 4) == nil)
end)
print("PASS: " .. count .. " core tests")
