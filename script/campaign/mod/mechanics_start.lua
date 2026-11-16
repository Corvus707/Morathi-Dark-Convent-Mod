local faction_key = "wh2_main_def_cult_of_pleasure"

local panel_name = "corvus_morathi_panel"
local panel_layout = "ui/campaign ui/corvus_morathi_panel"
local button_name = "button_corvus_morathi_panel"
local button_icon = "ui/skins/default/icon_gift_of_slaanesh.png"
local button_tooltip = "Cult of Pleasure||Seduce enemies or manipulate the winds of magic to your advantage."
local escape_key_name = "corvus_morathi_panel_escape"

-- Vanilla panels that may open alongside ours without closing it. Clicking a settlement or army to pick a ritual
-- target opens its panel, and closing ours would turn targeting off and lose the target.
local panels_allowed_alongside = {
    settlement_panel = true,
    units_panel = true,
    events = true,
}

-- Both ritual lists are shown together in one scrolling list (set in the layout): Manipulations
-- (action_list_manipulations, morathi_actions_), the Dark Magic title, then Dark Magic (action_list, morathi_dark_magic_)
local ritual_lists = { "action_list_manipulations", "action_list" }

local function get_panel()
    return find_uicomponent(core:get_ui_root(), panel_name)
end

local function get_button()
    return find_uicomponent(core:get_ui_root(), "hud_campaign", "faction_buttons_docker", "button_group_management", button_name)
end

local function is_panel_open()
    local panel = get_panel()
    return panel and panel:Visible()
end

local function set_button_selected(selected)
    local button = get_button()
    if button then
        button:SetState(selected and "selected" or "active")
    end
end

-- Depth-first search for a descendant by id
local function find_descendant(uic, id)
    for i = 0, uic:ChildCount() - 1 do
        local child = UIComponent(uic:Find(i))
        if child:Id() == id then
            return child
        end
        local found = find_descendant(child, id)
        if found then
            return found
        end
    end
end

local function show_ritual_lists()
    local panel = get_panel()
    if not panel then
        return
    end
    local list_box
    for _, id in ipairs(ritual_lists) do
        local list = find_descendant(panel, id)
        if list then
            list:SetVisible(true)
            list_box = UIComponent(list:Parent())
        end
    end
    if list_box then
        list_box:Layout()
    end
end

local function close_panel()
    -- Hiding the panel fires its on_hide callback, which turns off map targeting
    local panel = get_panel()
    if panel then
        panel:SetVisible(false)
    end
    set_button_selected(false)
    cm:release_escape_key_with_callback(escape_key_name)
end

local function open_panel()
    local panel = get_panel()
    if not panel then
        out("Creating "..panel_name)
        panel = UIComponent(core:get_ui_root():CreateComponent(panel_name, panel_layout))
    end
    panel:SetVisible(true)
    set_button_selected(true)
    cm:steal_escape_key_with_callback(escape_key_name, close_panel)
    local ok, err = pcall(show_ritual_lists)
    if not ok then
        out("Error showing ritual lists: "..tostring(err))
    end
end

local function get_or_create_button()
    local button_group = find_uicomponent(core:get_ui_root(), "hud_campaign", "faction_buttons_docker", "button_group_management")
    if not button_group then
        out("Could not find button_group_management")
        return
    end
    if get_button() then
        return
    end

    out("Creating "..button_name)
    local button = UIComponent(button_group:CreateComponent(button_name, "ui/templates/round_hud_button_toggle"))
    button:SetImagePath(button_icon, 0)
    button:SetTooltipText(button_tooltip, true)
    button:SetVisible(true)
    button_group:Layout()
end

local function button_check_callback()
    if cm:get_local_faction_name(true) ~= faction_key then
        return
    end
    local ok, err = pcall(get_or_create_button)
    if not ok then
        out("Error in button_check_callback: "..tostring(err))
    end
end

cm:add_first_tick_callback(function ()
    core:progress_on_loading_screen_dismissed(function ()
        cm:real_callback(button_check_callback, 500, "corvus_morathi_add_panel_button")
    end)

    core:add_listener(
        "corvus_morathi_panel_button_check",
        "FactionTurnStart",
        function (context)
            return context:faction():name() == cm:get_local_faction_name(true)
        end,
        button_check_callback,
        true)

    core:add_listener(
        "corvus_morathi_panel_button_clicked",
        "ComponentLClickUp",
        function (context)
            return context.string == button_name
        end,
        function ()
            if is_panel_open() then
                close_panel()
            else
                open_panel()
            end
        end,
        true)

    core:add_listener(
        "corvus_morathi_panel_close_clicked",
        "ComponentLClickUp",
        function (context)
            return context.string == "button_close" and is_panel_open() and uicomponent_descended_from(UIComponent(context.component), panel_name)
        end,
        close_panel,
        true)

    core:add_listener(
        "corvus_morathi_panel_other_panel_opened",
        "PanelOpenedCampaign",
        function (context)
            return context.string ~= panel_name and not panels_allowed_alongside[context.string] and is_panel_open()
        end,
        function (context)
            out("Closing "..panel_name.." because "..context.string.." opened")
            close_panel()
        end,
        true)
end)
