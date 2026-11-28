-- The technology panel's "Morathi's Court" tab doesn't scroll.
-- All of a faction's tech tabs share one long tree (each tab's nodes in its own range of tiers, technology_ui_tabs
-- tier_offset scrolling the view to it), so on the Morathi's Court tab the player could scroll back through the Druchii
-- tree. While that tab is selected, its scrollbar is hidden and the tree is pinned where the tab put it.

local faction_key = "wh2_main_def_cult_of_pleasure"
local court_tab_id = "CcoTechnologyUiTabRecordcorv_morathi_court"
local tick_ms = 100
-- The tab scrolls the view to its tree when selected; the position is pinned once that has settled
local settle_ticks = 5

-- TESTING: writes what it finds to corvus_dark_convent_log.txt in the game folder. Set to false when done.
local debug_log_to_file = true
local function debug_log(text)
    out("Morathi tech panel: "..text)
    if not debug_log_to_file then
        return
    end
    local file = io.open("corvus_dark_convent_log.txt", "a")
    if file then
        file:write("[tech panel] "..text.."\n")
        file:close()
    end
end

local active_ticks = 0
local pinned_x, pinned_y = nil, nil
local hidden_slider = nil
local logged_tabs = false
local reported_error = false

local function tab_title(tab)
    local title = find_uicomponent(tab, "tx_tab_title")
    return title and title:GetStateText() or ""
end

local last_court_tab_state = nil

-- Whether the Morathi's Court tab is the selected one. The panel names each tab after its record
-- ("CcoTechnologyUiTabRecord<tab key>"); a selected tab's state is "selected" (or a variant of it).
local function court_tab_selected(panel)
    local tabs = find_uicomponent(panel, "tabs")
    if not tabs then
        return false
    end
    if not logged_tabs then
        logged_tabs = true
        for i = 0, tabs:ChildCount() - 1 do
            local tab = UIComponent(tabs:Find(i))
            debug_log("tab "..i..": id "..tab:Id()..", state "..tostring(tab:CurrentState())..", title '"..tab_title(tab).."'")
        end
    end
    local court_tab = find_uicomponent(tabs, court_tab_id)
    if not court_tab then
        return false
    end
    local state = tostring(court_tab:CurrentState())
    if state ~= last_court_tab_state then
        last_court_tab_state = state
        debug_log("Morathi's Court tab state: "..state)
    end
    return string.find(state, "selected", 1, true) ~= nil
end

local function release()
    if hidden_slider then
        hidden_slider:SetVisible(true)
        hidden_slider = nil
        debug_log("released the tree")
    end
    active_ticks = 0
    pinned_x, pinned_y = nil, nil
end

local function update(panel)
    local list = find_uicomponent(panel, "technology_list")
    local list_box = list and find_uicomponent(list, "list_box")
    local slider = list and find_uicomponent(list, "hslider")
    if not list_box or not court_tab_selected(panel) then
        release()
        return
    end
    active_ticks = active_ticks + 1
    if slider and slider:Visible() then
        slider:SetVisible(false)
        hidden_slider = slider
    end
    if active_ticks < settle_ticks then
        return
    end
    local x, y = list_box:Position()
    if not pinned_x then
        pinned_x, pinned_y = x, y
        debug_log("pinned the tree at "..x..","..y)
    elseif x ~= pinned_x or y ~= pinned_y then
        list_box:MoveTo(pinned_x, pinned_y)
    end
end

local function tick_unprotected()
    if cm:get_local_faction_name(true) ~= faction_key then
        return
    end
    local panel = find_uicomponent(core:get_ui_root(), "technology_panel")
    if not panel or not panel:Visible() then
        -- The panel and its scrollbar are gone once it closes: forget them rather than touching them
        hidden_slider = nil
        active_ticks = 0
        pinned_x, pinned_y = nil, nil
        logged_tabs = false
        last_court_tab_state = nil
        return
    end
    update(panel)
end

local function tick()
    local ok, err = pcall(tick_unprotected)
    if not ok and not reported_error then
        reported_error = true
        debug_log("error: "..tostring(err))
    end
end

-- TESTING: switched off. Right after this first ran on the open technology panel, every UI component started failing
-- vanilla's is_uicomponent check (script log, 2026-11-28) and the mod's buttons stopped working. Off until that's found.
local enabled = false

cm:add_first_tick_callback(function ()
    if not enabled then
        return
    end
    core:progress_on_loading_screen_dismissed(function ()
        cm:repeat_real_callback(tick, tick_ms, "corvus_morathi_tech_panel_tick")
    end)
end)
