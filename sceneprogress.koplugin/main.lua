local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local buffer = require("string.buffer")
local Config = require("sceneprogress/config")
local Index = require("sceneprogress/index")
local Time = require("sceneprogress/time")
local Worker = require("sceneprogress/worker")
local _ = require("sceneprogress/i18n")

local SceneProgress = WidgetContainer:extend{
    name = "sceneprogress",
    is_doc_only = true,
}

function SceneProgress:init()
    self.settings = Config.load(G_reader_settings)
    self.generation = 0
    self.content_func = function() return self:footerText() end
    self.start_task = function() self:startScan() end
    self.ui.menu:registerToMainMenu(self)
end

function SceneProgress:supported()
    local doc = self.ui.document
    local footer = self.ui.view and self.ui.view.footer
    return self.ui.rolling and doc and doc.file and doc.file:lower():match("%.epub$")
        and doc.getDocumentFormat and doc:getDocumentFormat() == "EPUB"
        and doc.getHTMLFromXPointer and doc.getNormalizedXPointer
        and doc.getDocumentRenderingHash and doc.isRerenderingDelayed
        and footer and footer.addAdditionalFooterContent and footer.removeAdditionalFooterContent
end

function SceneProgress:refresh()
    self.ui:handleEvent(Event:new("RefreshAdditionalContent"))
end

function SceneProgress:attach()
    if not self.attached and self.settings.enabled and self:supported() then
        self.ui.view.footer:addAdditionalFooterContent(self.content_func)
        self.attached = true
        self:refresh()
    end
end

function SceneProgress:detach()
    if self.attached then
        self.ui.view.footer:removeAdditionalFooterContent(self.content_func)
        self.attached = false
        self.ui:handleEvent(Event:new("UpdateFooter", true))
    end
end

function SceneProgress:cancelScan()
    self.generation = self.generation + 1
    UIManager:unschedule(self.start_task)
    if self.job then self.job:cancel(); self.job = nil end
end

function SceneProgress:cacheKey()
    local doc = self.ui.document
    local stat = lfs.attributes(doc.file)
    if not stat then return end
    return buffer.encode({
        Index.VERSION, doc.file, stat.size, stat.modification, stat.change,
        self.ui.doc_settings:readSetting("cre_dom_version"),
        doc:getDocumentRenderingHash(true), doc.hide_nonlinear_flows,
        doc._view_mode, self.settings.rules,
    })
end

function SceneProgress:startScan(force)
    if self.closed or not self.settings.enabled or not self:supported() then return end
    self:cancelScan()
    self.index = nil
    self.state = "scanning"
    if self.ui.document:isRerenderingDelayed() then
        self.state = "partial"
        return
    end
    self.render_hash = self.ui.document:getDocumentRenderingHash(true)
    local key = self:cacheKey()
    local cached = self.ui.doc_settings:readSetting("sceneprogress_cache")
    if not force and key and type(cached) == "table" and cached.key == key
            and type(cached.index) == "table" and type(cached.index.entries) == "table" then
        self.index, self.state = cached.index, "ready"
        self:refresh()
        return
    end
    local doc, generation = self.ui.document, self.generation
    local dom_version = self.ui.doc_settings:readSetting("cre_dom_version") or doc:getLatestDomVersion()
    local normalized = dom_version >= doc:getDomVersionWithNormalizedXPointers()
    self.job = Worker.start(function()
        return Index.scan(doc, self.settings.rules, normalized, util.htmlEntitiesToUtf8)
    end, function(result)
        if self.closed or generation ~= self.generation then return end
        self.job = nil
        self.index = result
        self.state = result and "ready" or "failed"
        if result and key then
            self.ui.doc_settings:saveSetting("sceneprogress_cache", { key = key, index = result })
        end
        self:refresh()
    end)
end

function SceneProgress:onReaderReady()
    self.closed = false
    self:attach()
    if self.settings.enabled and self:supported() then
        UIManager:scheduleIn(0.5, self.start_task)
    end
end

function SceneProgress:onDocumentRerendered()
    if self.closed then return end
    self:cancelScan()
    self.index = nil
    if self.settings.enabled and self:supported() then
        self.state = "scanning"
        UIManager:scheduleIn(0.5, self.start_task)
    end
end

-- Page mappings are unsafe while CREngine deliberately delays a full layout.
function SceneProgress:onDocumentPartiallyRerendered()
    self:cancelScan()
    self.index, self.state = nil, "partial"
    self:refresh()
end

function SceneProgress:onCloseDocument()
    self.closed = true
    self:cancelScan()
    self:detach()
    self.index = nil
end
SceneProgress.onCloseWidget = SceneProgress.onCloseDocument

function SceneProgress:onSaveSettings()
    G_reader_settings:saveSetting("sceneprogress", self.settings)
end

function SceneProgress:footerText()
    if self.closed or not self.settings.enabled or not self.index
            or not (self.settings.show_pages or self.settings.show_time) then return end
    local doc = self.ui.document
    if doc:getDocumentRenderingHash(true) ~= self.render_hash or doc:isRerenderingDelayed() then return end
    local page = doc:getCurrentPage()
    local left = Index.remaining(doc, self.ui.toc, self.index.entries, page)
    if not left then return end
    local parts = {}
    if self.settings.show_pages then
        parts[#parts + 1] = self.settings.compact and tostring(left) or (left .. " " .. _("p."))
    end
    if self.settings.show_time then
        -- Keep the same duration notation selected in KOReader's statistics.
        parts[#parts + 1] = Time.estimate(self.ui.statistics, left) or "—"
    end
    return (self.settings.compact and "S:" or _("Scene:") .. " ") .. table.concat(parts, " · ")
end

function SceneProgress:changed(rescan)
    self:onSaveSettings()
    if not self.settings.enabled then
        self:cancelScan()
        self:detach()
        self.index = nil
        self.state = nil
    else
        self:attach()
        if rescan or not self.index then self:startScan(rescan) end
        self:refresh()
    end
end

function SceneProgress:diagnostics()
    local messages = {
        _("Status:") .. " " .. (self.state == "ready" and _("Ready")
            or self.state == "scanning" and _("Scanning in background")
            or self.state == "partial" and _("Waiting for a full document layout")
            or self.state == "failed" and _("Scan failed; try rescanning") or _("Inactive")),
    }
    if self.index then
        messages[#messages + 1] = _("Detected separators:") .. " " .. #self.index.entries
        messages[#messages + 1] = _("Unmapped candidates:") .. " " .. self.index.rejected
        for i, entry in ipairs(self.index.entries) do
            if i > 30 then messages[#messages + 1] = "…"; break end
            messages[#messages + 1] = string.format("%d.  %s %d (%s)", i, _("Page"), entry.page, entry.kind)
        end
    end
    UIManager:show(InfoMessage:new{ text = table.concat(messages, "\n") })
end

function SceneProgress:addToMainMenu(menu_items)
    local function toggle(label, key, rules)
        local target = rules and self.settings.rules or self.settings
        return {
            text = label,
            checked_func = function() return target[key] end,
            callback = function() target[key] = not target[key]; self:changed(rules) end,
        }
    end
    menu_items.sceneprogress = {
        text = "Scene Progress",
        sorting_hint = "more_tools",
        sub_item_table = {
            toggle(_("Enable scene counter"), "enabled"),
            toggle(_("Show remaining pages"), "show_pages"),
            toggle(_("Show remaining time"), "show_time"),
            toggle(_("Compact format"), "compact"),
            {
                text = _("Separator types"),
                sub_item_table = {
                    toggle(_("Single asterisk (*)"), "single", true),
                    toggle(_("Multiple asterisks (***)"), "multiple", true),
                    toggle(_("Typographic ornaments"), "ornaments", true),
                    toggle(_("Semantic dividers (hr, CSS classes)"), "semantic", true),
                    {
                        text = _("CSS class names"),
                        callback = function()
                            local dialog
                            dialog = InputDialog:new{
                                title = _("Separator CSS classes (space separated)"),
                                input = self.settings.rules.classes,
                                buttons = {{
                                    { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
                                    { text = _("Save"), callback = function()
                                        self.settings.rules.classes = dialog:getInputText()
                                        UIManager:close(dialog)
                                        self:changed(true)
                                    end },
                                }},
                            }
                            UIManager:show(dialog)
                            dialog:onShowKeyboard()
                        end,
                    },
                },
            },
            { text = _("Rescan book"), enabled_func = function()
                return self.settings.enabled and self:supported()
            end, callback = function() self:startScan(true) end },
            { text = _("Diagnostics"), callback = function() self:diagnostics() end },
        },
    }
end

return SceneProgress
