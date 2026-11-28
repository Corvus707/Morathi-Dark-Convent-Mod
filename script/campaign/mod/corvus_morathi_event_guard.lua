-- Protects event listeners from each other.
-- The game runs event listeners unprotected (lib_core's event_unprotected_callback): when any listener's condition or
-- callback errors, the rest of that event's listeners don't run, and the error goes on to the game. After the
-- technology panel, script events stopped reaching the mod altogether (clicks, panels closing), so the Dark Convent and
-- Web of Power buttons stopped responding. Every listener now runs in protected mode, as vanilla's own
-- USE_PROTECTED_EVENT_CALLBACKS option does: a failing listener is logged by name and skipped, and the others still run.
-- Timers (real and game-time callbacks) run from event listeners too, so they're covered.

-- nil: every event. Set to a table of event names to protect only those.
local guarded_events = nil

-- TESTING: writes failing listeners to corvus_dark_convent_log.txt in the game folder (once each). Set to false when done.
local debug_log_to_file = true
local reported = {}

local function report(eventname, listener, part, err)
    local key = tostring(listener.name)..":"..part
    if reported[key] then
        return
    end
    reported[key] = true
    local text = "listener '"..tostring(listener.name).."' failed in its "..part.." for "..eventname..": "..tostring(err)
    out("Event guard: "..text)
    if debug_log_to_file then
        local file = io.open("corvus_dark_convent_log.txt", "a")
        if file then
            local ok, seconds = pcall(os.clock)
            file:write((ok and string.format("[%.1f] ", seconds) or "").."[event guard] "..text.."\n")
            file:close()
        end
    end
end

-- TESTING: after the technology panel opened, every UI component failed vanilla's is_uicomponent
-- (string.sub(tostring(value), 1, 12) == "UIComponent "), though they still printed as "UIComponent (...)". This watch
-- records, once, which of those functions changed and what the UI root looks like when the check first fails.
local original_tostring = tostring
local original_string = string
local original_sub = string.sub
local original_is_uicomponent = is_uicomponent
local watch_reported = false

local function watch_ui_check(eventname)
    if watch_reported then
        return
    end
    -- (core:get_ui_root() logs an error until the UI exists)
    local root = core.ui_root
    if not root then
        return
    end
    local ok, passes = pcall(is_uicomponent, root)
    if ok and passes then
        return
    end
    watch_reported = true
    local text = original_tostring(root)
    local codes = {}
    for i = 1, math.min(14, #text) do
        table.insert(codes, original_string.byte(text, i))
    end
    local lines = {
        "UI root failed is_uicomponent, first seen during event "..original_tostring(eventname).." (call ok: "..original_tostring(ok)..", result: "..original_tostring(passes)..")",
        "  tostring replaced: "..original_tostring(tostring ~= original_tostring)
            ..", string table replaced: "..original_tostring(string ~= original_string)
            ..", string.sub replaced: "..original_tostring(original_string.sub ~= original_sub)
            ..", global string.sub replaced: "..original_tostring(string and string.sub ~= original_sub)
            ..", is_uicomponent replaced: "..original_tostring(is_uicomponent ~= original_is_uicomponent),
        "  root as text: '"..text.."', bytes: "..table.concat(codes, " "),
        "  current tostring gives: '"..original_tostring(pcall(tostring, root) and tostring(root)).."'",
        "  original check now gives: "..original_tostring(original_sub(text, 1, 12) == "UIComponent "),
    }
    for _, line in ipairs(lines) do
        out("Event guard: "..line)
        local file = io.open("corvus_dark_convent_log.txt", "a")
        if file then
            file:write("[ui watch] "..line.."\n")
            file:close()
        end
    end
end

local original_event_callback = core.event_callback

-- Same as core_object:event_callback (lib_core), with each condition and callback protected
function core:event_callback(eventname, context)
    if not watch_reported then
        pcall(watch_ui_check, eventname)
    end
    if guarded_events and not guarded_events[eventname] then
        return original_event_callback(self, eventname, context)
    end
    local listeners = self.event_listeners[eventname]
    if not listeners then
        return
    end

    local callbacks_to_call = {}
    local should_rebuild = false
    for i = 1, #listeners do
        local listener = listeners[i]
        local wanted = true
        if listener.condition ~= true then
            local ok, result = pcall(listener.condition, context)
            if not ok then
                report(eventname, listener, "condition", result)
            end
            wanted = ok and result
        end
        if wanted then
            table.insert(callbacks_to_call, listener)
            if not listener.persistent then
                listener.to_remove = true
                should_rebuild = true
            end
        end
    end
    if should_rebuild then
        self:clean_listeners(eventname)
    end

    for i = 1, #callbacks_to_call do
        local listener = callbacks_to_call[i]
        local ok, err = pcall(listener.callback, context)
        if not ok then
            report(eventname, listener, "callback", err)
        end
    end
end
