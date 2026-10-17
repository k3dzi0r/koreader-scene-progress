local Config = {}

function Config.defaults()
    return {
        enabled = true,
        show_pages = true,
        show_time = true,
        compact = true,
        rules = {
            single = true,
            multiple = true,
            ornaments = true,
            semantic = true,
            classes = "scene-break scenebreak scene_break asterism dinkus",
        },
    }
end

function Config.load(settings)
    local result = Config.defaults()
    local saved = settings:readSetting("sceneprogress", {})
    for key, value in pairs(result) do
        if type(value) == "boolean" and type(saved[key]) == "boolean" then
            result[key] = saved[key]
        end
    end
    for key, value in pairs(result.rules) do
        if type(saved.rules) == "table" and type(saved.rules[key]) == type(value) then
            result.rules[key] = saved.rules[key]
        end
    end
    return result
end

return Config
