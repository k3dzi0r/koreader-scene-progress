-- KOReader exposes a singleton MO reader. Load once, synchronously, into a
-- temporary catalogue and restore all singleton state before returning. Loading
-- gettext.lua a second time is unsafe (its FFI structs cannot be redefined).
local gettext = require("gettext")
local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("^(.*)/sceneprogress/i18n.lua$")
local language = G_reader_settings:readSetting("language") or gettext.current_lang or "C"
local catalogue = {}
if language:match("^pl") then
    local translation, context, plural = gettext.translation, gettext.context, gettext.getPlural
    gettext.translation, gettext.context = {}, {}
    local loaded, ok = pcall(gettext.loadMO, root .. "/l10n/pl/sceneprogress.mo")
    if loaded and ok then catalogue = gettext.translation end
    gettext.translation, gettext.context, gettext.getPlural = translation, context, plural
end
return function(msgid)
    local value = catalogue[msgid]
    return value and (type(value) == "table" and value[0] or value) or gettext(msgid)
end
