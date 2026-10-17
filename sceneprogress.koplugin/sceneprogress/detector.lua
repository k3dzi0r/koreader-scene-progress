-- Parse CREngine's DOM serialization, not the EPUB source. The ~ render markers
-- are deliberately not XML attributes. No search/selection/navigation is used.
local Detector = {}
local boxing = {
    autoBoxing = true, tabularBox = true, rubyBox = true,
    mathBox = true, floatBox = true, inlineBox = true, pseudoElem = true,
}
local blocks = { p = true, div = true, section = true, hr = true }
local forbidden = {
    a = true, sup = true, sub = true, aside = true, script = true,
    style = true, stylesheet = true, head = true, nav = true,
}
local ornaments = {
    ["⁂"] = true, ["⁎"] = true, ["⁎⁎⁎"] = true, ["※"] = true,
    ["❦"] = true, ["❧"] = true, ["✦"] = true, ["✦✦✦"] = true,
    ["✧"] = true, ["✧✧✧"] = true, ["• • •"] = true,
    ["•••"] = true, ["···"] = true, ["*⁂*"] = true,
}

local function attributes(tag, decode)
    local attrs = {}
    for key, __quote, value in tag:gmatch("([%w_:%-]+)%s*=%s*(['\"])(.-)%2") do
        attrs[key:lower()] = decode(value)
    end
    return attrs
end

local function token_set(text)
    local result = {}
    for token in (text or ""):lower():gmatch("%S+") do result[token] = true end
    return result
end

local function is_note(attrs)
    local roles = token_set((attrs["epub:type"] or "") .. " " .. (attrs.role or ""))
    for role in pairs(roles) do
        if role:find("note", 1, true) then return true end
    end
    for token in (attrs.class or ""):lower():gmatch("[%w_-]+") do
        if token:find("footnote", 1, true) or token:find("endnote", 1, true)
                or token == "noteref" then return true end
    end
    local id = (attrs.id or ""):lower():gsub("^_doc_fragment_%d+_ *", "")
    return id:match("^fn[%d_-]") ~= nil
end

function Detector.kind(text, tag, attrs, rules, has_image)
    local compact = text:gsub("%s", ""):gsub(" ", ""):gsub(" ", ""):gsub(" ", "")
    if rules.single and compact == "*" then return "single" end
    if rules.multiple and compact:match("^%*%*%*+$") then return "multiple" end
    if rules.ornaments and ornaments[compact] then return "ornament" end
    if rules.semantic then
        local semantic = tag == "hr" or attrs.role == "separator"
        local classes = token_set(rules.classes)
        for class in (attrs.class or ""):lower():gmatch("%S+") do
            semantic = semantic or classes[class]
        end
        -- An explicit class may identify an empty/image divider, but must not
        -- turn an ordinary prose paragraph into a scene boundary.
        if semantic and (compact == "" or compact:match("^%*+$")
                or ornaments[compact]) then
            return has_image and "image" or "semantic"
        end
    end
end

function Detector.scan(html, rules, normalized, decode)
    assert(type(html) == "string" and #html <= 64 * 1024 * 1024, "DOM too large or unavailable")
    local root = { path = "", counts = {}, text = "", blocked = false }
    local stack, results = { root }, {}
    local cursor = 1
    local function text(value)
        local frame = stack[#stack]
        if not frame.blocked then
            frame.text = (frame.text .. decode(value)):sub(1, 256)
        end
    end
    local function close()
        assert(#stack > 1, "unbalanced DOM")
        local frame = table.remove(stack)
        local parent = stack[#stack]
        if not frame.blocked and not frame.block_child and blocks[frame.name] then
            local kind = Detector.kind(frame.text, frame.name, frame.attrs, rules, frame.image)
            if kind then
                assert(#results < 10000, "too many separators")
                results[#results + 1] = { xp = frame.path, kind = kind }
            end
        end
        if not frame.blocked then
            parent.text = (parent.text .. frame.text):sub(1, 256)
            parent.image = parent.image or frame.image
        end
        parent.block_child = parent.block_child or blocks[frame.name] or frame.block_child
    end
    while cursor <= #html do
        local first = html:find("<", cursor, true)
        if not first then text(html:sub(cursor)); break end
        text(html:sub(cursor, first - 1))
        local pos, quote = first + 1, nil
        while pos <= #html do
            local char = html:sub(pos, pos)
            if quote then
                if char == quote then quote = nil end
            elseif char == '"' or char == "'" then quote = char
            elseif char == ">" then break end
            pos = pos + 1
        end
        assert(pos <= #html, "unterminated DOM tag")
        local tag = html:sub(first + 1, pos - 1)
        if tag:sub(1, 1) == "/" then
            local name = tag:match("^/([^%s>]+)")
            assert(stack[#stack].name == name, "mismatched DOM tag")
            close()
        elseif not tag:match("^[!?]") then
            local full_name = assert(tag:match("^([^%s/>]+)"))
            local name = full_name:match("([^:]+)$")
            local parent = stack[#stack]
            local owner = parent.owner or parent
            local transparent = name == "RootNode" or (normalized and boxing[name])
            local path = owner.path
            if not transparent then
                owner.counts[name] = (owner.counts[name] or 0) + 1
                path = path .. "/" .. name .. "[" .. owner.counts[name] .. "]"
            end
            local attrs = attributes(tag, decode)
            local style = (attrs.style or ""):lower():gsub("%s", "")
            local render = tag:match("~([%a?]+)%s*/?$")
            local blocked = parent.blocked or forbidden[name] or is_note(attrs)
                or render == "X" or render == "K" or name == "cloneNode"
                or style:find("display:none", 1, true) or style:find("visibility:hidden", 1, true)
                or attrs["aria-hidden"] == "true" or attrs.hidden ~= nil
                or tag:match("%shidden[%s/]") or tag:match("%shidden$")
            local frame = {
                name = full_name, path = path, counts = {}, attrs = attrs,
                text = "", blocked = blocked, image = name == "img" or name == "image",
            }
            if transparent then frame.owner = owner end
            stack[#stack + 1] = frame
            if tag:match("/%s*$") then close() end
        end
        cursor = pos + 1
    end
    assert(#stack == 1, "unclosed DOM")
    return results
end

return Detector
