local Time = {}

function Time.estimate(statistics, pages)
    if not statistics or not statistics.settings or not statistics.settings.is_enabled then return end
    local samples = (statistics.book_read_pages or 0) + (statistics.mem_read_pages or 0)
    local average = statistics.avg_time
    -- KOReader seeds avg_time with a constant before collecting any pages.
    -- Do not present that seed as a measured reading speed.
    if samples < 3 or type(average) ~= "number" or average <= 0
            or average ~= average or average == math.huge then return end
    return statistics:getTimeForPages(pages)
end

return Time
