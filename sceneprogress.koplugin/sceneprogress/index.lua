local Detector = require("sceneprogress/detector")
local Index = { VERSION = 1 }

function Index.scan(document, rules, normalized, decode)
    -- Include stylesheet nodes so sibling indexes match the complete DOM;
    -- include computed render methods so CSS-hidden ancestors can be rejected.
    local html = document:getHTMLFromXPointer(".0", 0x4400)
    local candidates = Detector.scan(html, rules, normalized, decode)
    local result, seen = {}, {}
    for _, candidate in ipairs(candidates) do
        local xp = document:getNormalizedXPointer(candidate.xp)
        if xp and document:isXPointerInDocument(xp) and not seen[xp] then
            local page = document:getPageFromXPointer(xp)
            if page and page >= 1 and page <= document:getPageCount()
                    and document:getPageFlow(page) == 0 then
                seen[xp] = true
                result[#result + 1] = {
                    xp = xp, page = page, kind = candidate.kind,
                    linear_page = document:getPageNumberInFlow(page),
                }
            end
        end
    end
    table.sort(result, function(a, b) return a.page < b.page end)
    return { entries = result, candidates = #candidates, rejected = #candidates - #result }
end

-- First separator on/after this screen page. Binary search is independent of
-- reading direction and keeps page turns O(log separators), with no DOM scan.
function Index.next(entries, page)
    local low, high = 1, #entries
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if entries[middle].page < page then low = middle + 1 else high = middle - 1 end
    end
    return entries[low]
end

function Index.remaining(document, toc, entries, page)
    if document:getPageFlow(page) ~= 0 then return end
    local chapter_left = toc:getChapterPagesLeft(page, true)
        or document:getTotalPagesLeft(page)
    local next_scene = Index.next(entries, page)
    local left = math.max(0, chapter_left)
    if next_scene then
        left = math.min(left, math.max(0,
            next_scene.linear_page - document:getPageNumberInFlow(page)))
    end
    return left
end

return Index
