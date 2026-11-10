local faction_key = "wh2_main_def_cult_of_pleasure"

local panel_name = "corvus_morathi_court"
local panel_layout = "ui/campaign ui/corvus_morathi_court"
local button_holder_name = "corvus_morathi_court_button_holder"
local button_holder_layout = "ui/campaign ui/corvus_morathi_court_button"
local button_name = "button_corvus_morathi_court"
local button_icon = "ui/skins/default/icon_gift_of_slaanesh.png"
local button_tooltip = "The Dark Convent||Enter the Dark Convent to train spellcasters and acquire character traits."
local escape_key_name = "corvus_morathi_court_escape"
-- Gives the faction its character training slots (effects in effect_bundles_to_effects_junctions)
local training_bundle_key = "corvus_dark_convent_training"

-- Top-level UI (HUD, other panels) hidden while the court is open, restored on close
local hidden_components = {}

local function get_resource_bar()
    return find_uicomponent(core:get_ui_root(), "hud_campaign", "resources_bar_holder", "resources_bar")
end

local function get_panel()
    return find_uicomponent(core:get_ui_root(), panel_name)
end

local function get_button()
    local resource_bar = get_resource_bar()
    return resource_bar and find_uicomponent(resource_bar, button_holder_name, button_name)
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

local function hide_other_ui()
    local root = core:get_ui_root()
    for i = 0, root:ChildCount() - 1 do
        local child = UIComponent(root:Find(i))
        local id = child:Id()
        -- Skip tooltips so the one under the cursor when the court opened doesn't come back stale
        if id ~= panel_name and child:Visible() and not string.find(string.lower(id), "tooltip") then
            child:SetVisible(false)
            table.insert(hidden_components, child)
        end
    end
end

local function restore_other_ui()
    for _, child in ipairs(hidden_components) do
        child:SetVisible(true)
    end
    hidden_components = {}
end

-- The zoomed-out map overlay menu is recreated by the game, so hiding it once isn't enough.
-- Its contents only show while this script value is 0.
local function set_spacebar_options_disabled(disabled)
    local ok, err = pcall(common.set_context_value, "disable_campaign_spacebar_options", disabled and 1 or 0)
    if not ok then
        out("Could not set disable_campaign_spacebar_options: "..tostring(err))
    end
end

-- The layout's dark backdrop is 1600x900; stretch it over the whole screen (inner panel stays centred)
local function fit_to_screen(panel)
    local width, height = core:get_ui_root():Dimensions()
    panel:SetCanResizeWidth(true)
    panel:SetCanResizeHeight(true)
    panel:Resize(width, height, false)
    panel:SetCanResizeWidth(false)
    panel:SetCanResizeHeight(false)
end

local function close_panel()
    local panel = get_panel()
    if panel then
        panel:RemoveTopMost()
        panel:SetVisible(false)
    end
    set_spacebar_options_disabled(false)
    restore_other_ui()
    set_button_selected(false)
    cm:release_escape_key_with_callback(escape_key_name)
end

local function apply_training_bundle()
    local faction = cm:get_faction(faction_key)
    if faction and not faction:is_dead() and not faction:has_effect_bundle(training_bundle_key) then
        out("Applying "..training_bundle_key.." to "..faction_key)
        cm:apply_effect_bundle(training_bundle_key, faction_key, 0)
    end
end

-- Logs what the training panel sees, to tell missing slots apart from missing groups
local function log_training_state()
    local faction = cm:get_faction(faction_key)
    out("Dark Convent: "..faction_key.." has "..training_bundle_key..": "..tostring(faction and faction:has_effect_bundle(training_bundle_key)))
    local ok, result = pcall(common.get_context_value, "CcoCampaignFaction", faction_key, "CharacterTrainingGroupList.Size")
    out("Dark Convent: training group count: "..(ok and tostring(result) or ("query failed: "..tostring(result))))
end

local function open_panel()
    log_training_state()
    local panel = get_panel()
    if not panel then
        out("Creating "..panel_name)
        panel = UIComponent(core:get_ui_root():CreateComponent(panel_name, panel_layout))
    end
    hide_other_ui()
    set_spacebar_options_disabled(true)
    fit_to_screen(panel)
    panel:SetVisible(true)
    -- Above map labels and anything the game shows later, like the vanilla full-screen panels
    panel:RegisterTopMost()
    set_button_selected(true)
    cm:steal_escape_key_with_callback(escape_key_name, close_panel)
end

local function get_or_create_button()
    local resource_bar = get_resource_bar()
    if not resource_bar then
        out("Could not find resource bar")
        return
    end
    if find_uicomponent(resource_bar, button_holder_name) then
        return
    end

    out("Creating "..button_holder_name)
    local holder = UIComponent(resource_bar:CreateComponent(button_holder_name, button_holder_layout))
    holder:SetVisible(true)
    local button = find_uicomponent(holder, button_name)
    button:SetImagePath(button_icon, 0)
    button:SetTooltipText(button_tooltip, true)
    resource_bar:Layout()
end

local function button_check_callback()
    if cm:get_local_faction_name(true) ~= faction_key then
        return
    end
    local ok, err = pcall(get_or_create_button)
    if not ok then
        out("Error in corvus_morathi_court button_check_callback: "..tostring(err))
    end
end

cm:add_first_tick_callback(function ()
    apply_training_bundle()

    core:progress_on_loading_screen_dismissed(function ()
        cm:real_callback(button_check_callback, 500, "corvus_morathi_add_court_button")
    end)

    core:add_listener(
        "corvus_morathi_court_button_check",
        "FactionTurnStart",
        function (context)
            return context:faction():name() == cm:get_local_faction_name(true)
        end,
        button_check_callback,
        true)

    core:add_listener(
        "corvus_morathi_court_button_clicked",
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
        "corvus_morathi_court_close_clicked",
        "ComponentLClickUp",
        function (context)
            return context.string == "button_close" and is_panel_open() and uicomponent_descended_from(UIComponent(context.component), panel_name)
        end,
        close_panel,
        true)

    core:add_listener(
        "corvus_morathi_court_other_panel_opened",
        "PanelOpenedCampaign",
        function (context)
            return context.string ~= panel_name and is_panel_open()
        end,
        function (context)
            out("Closing "..panel_name.." because "..context.string.." opened")
            close_panel()
        end,
        true)
end)
