local faction_key = "wh2_main_def_cult_of_pleasure"

local panel_name = "corvus_morathi_court"
local panel_layout = "ui/campaign ui/corvus_morathi_court"
local button_holder_name = "corvus_morathi_court_button_holder"
local button_holder_layout = "ui/campaign ui/corvus_morathi_court_button"
local button_name = "button_corvus_morathi_court"
local button_icon = "ui/skins/default/icon_gift_of_slaanesh.png"
local button_tooltip = "The Dark Convent||Enter the Dark Convent to train spellcasters and acquire character traits."
local escape_key_name = "corvus_morathi_court_escape"

-- Top-level UI (HUD, other panels) hidden while the court is open, restored on close
local hidden_components = {}

local function get_panel()
    return find_uicomponent(core:get_ui_root(), panel_name)
end

-- ---- Dark Convent training -------------------------------------------------------------------------------------
-- The engine's character training (Kislev's Ice Court) can't be given to another faction, so training is scripted.
-- Groups, dilemmas, choices and traits come from corvus_dark_convent_data.lua, generated from the training TSVs.

-- Slots open from the start in each group; the rest show as locked
local unlocked_slots_per_group = 1
local num_choice_rows = 5
-- Prefix for UI-triggered actions, which go through the UITrigger event so every client in multiplayer applies them
local action_prefix = "corv_dark_convent"
local candidate_age = 22
-- TESTING: offer the next dilemma straight away instead of on the next turn. Set back to false when done.
local skip_dilemma_turn_wait = true
-- TESTING: finish training as soon as the last dilemma is answered, ignoring the turns left. Set back to false when done.
local skip_training_duration = true
-- Morathi's trait: Sorceress heroes recruitable in any of her provinces
local morathi_subtype = "wh2_main_def_morathi"
local morathi_trait = "corv_trait_morathi_dark_convent"
local old_convent_bundle_key = "corv_dark_convent"
local convent_trait_prefix = "corv_trait_dark_convent_"

-- training_state["<group>_<slot>"] = { group, slot, turns_left, resolved, pending, traits, subtype }
local training_state = {}
-- Training slot whose dilemma is shown in the dilemma box, { group, slot }
local selected_slot = nil

cm:add_saving_game_callback(function (context)
    cm:save_named_value("corvus_dark_convent_training", training_state, context)
end)

cm:add_loading_game_callback(function (context)
    training_state = cm:load_named_value("corvus_dark_convent_training", {}, context)
end)

local function get_training_groups()
    return corvus_dark_convent_data or {}
end

local function slot_key(group_index, slot_index)
    return group_index.."_"..slot_index
end

local function is_slot_unlocked(group, slot_index)
    return slot_index <= math.min(unlocked_slots_per_group, group.max_slots)
end

local function default_subtype(group)
    for _, dilemma in ipairs(group.dilemmas) do
        for _, choice in ipairs(dilemma.choices) do
            if choice.subtype then
                return choice.subtype
            end
        end
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

-- Vanilla bug, shown much more often now that Sorceress categories are usually empty: in the recruit panel the
-- "no candidates" reason text spans the panel, is interactive, and sits over the top of the last lore button.
-- Making it ignore the mouse lets clicks reach the button underneath.
local function fix_recruit_panel_reason_text()
    local panel = find_uicomponent(core:get_ui_root(), "character_panel")
    local reason = panel and find_descendant(panel, "no_candidates_panel")
    reason = reason and find_descendant(reason, "tx_reason")
    if reason then
        reason:SetInteractive(false)
    end
end

-- all_traits() isn't documented; accept a Lua table or a list interface, of trait keys or trait objects
local function trait_keys(character)
    local traits = character:all_traits()
    local keys = {}
    local function add(trait)
        if type(trait) == "string" then
            table.insert(keys, trait)
        elseif trait and trait.key then
            table.insert(keys, trait:key())
        end
    end
    if type(traits) == "table" then
        for _, trait in ipairs(traits) do
            add(trait)
        end
    elseif traits and traits.num_items then
        for i = 0, traits:num_items() - 1 do
            add(traits:item_at(i))
        end
    end
    return keys
end

-- Characters spawned to the pool get a random starting trait from the game; Dark Convent graduates keep only theirs
local function remove_non_convent_traits(character)
    local keys = trait_keys(character)
    local is_graduate = false
    for _, key in ipairs(keys) do
        if string.sub(key, 1, #convent_trait_prefix) == convent_trait_prefix then
            is_graduate = true
        end
    end
    if not is_graduate then
        return
    end
    local lookup = cm:char_lookup_str(character)
    for _, key in ipairs(keys) do
        if string.sub(key, 1, #convent_trait_prefix) ~= convent_trait_prefix then
            out("Dark Convent: removing starting trait "..key.." from recruited graduate")
            cm:force_remove_trait(lookup, key)
        end
    end
end

-- Morathi's trait lets Sorceress heroes be recruited in any of her provinces
local function give_morathi_convent_trait()
    local faction = cm:get_faction(faction_key)
    if not faction or faction:is_dead() then
        return
    end
    -- Replaced by the trait; remove it from saves made before the change
    if faction:has_effect_bundle(old_convent_bundle_key) then
        cm:remove_effect_bundle(old_convent_bundle_key, faction_key)
    end
    local characters = faction:character_list()
    for i = 0, characters:num_items() - 1 do
        local character = characters:item_at(i)
        if character:character_subtype_key() == morathi_subtype and not character:has_trait(morathi_trait) then
            out("Dark Convent: giving "..morathi_trait.." to Morathi")
            cm:force_add_trait(cm:char_lookup_str(character), morathi_trait)
        end
    end
end

local function finish_training(slot)
    local group = get_training_groups()[slot.group]
    local subtype = slot.subtype or default_subtype(group)
    out("Dark Convent: "..group.key.." slot "..slot.slot.." finished, spawning "..tostring(subtype).." with "..#slot.traits.." traits")
    -- Arguments: faction, forename, family name, clan name, other name, age, male, agent, subtype, immortal, art set.
    -- "male" must match the subtype's art sets (generated from vanilla data) or the game picks an unrelated model.
    local character_details = cm:spawn_character_to_pool(faction_key, "", "", "", "", candidate_age, group.male, group.agent, subtype, false, "")
    for _, trait in ipairs(slot.traits) do
        cm:force_add_trait_to_character_details(character_details, trait)
    end
    training_state[slot_key(slot.group, slot.slot)] = nil
end

local function try_finish_training(slot)
    local group = get_training_groups()[slot.group]
    if (slot.turns_left <= 0 or skip_training_duration) and not slot.pending and slot.resolved >= #group.dilemmas then
        finish_training(slot)
    end
end

local function start_training(group_index, slot_index)
    local group = get_training_groups()[group_index]
    local faction = cm:get_faction(faction_key)
    if not group or not faction or not is_slot_unlocked(group, slot_index) or training_state[slot_key(group_index, slot_index)] then
        return
    end
    if faction:treasury() < group.cost then
        return
    end
    out("Dark Convent: slot "..slot_key(group_index, slot_index).." started training ("..group.key..")")
    cm:treasury_mod(faction_key, -group.cost)
    -- The first dilemma is available straight away; the rest follow one per turn
    training_state[slot_key(group_index, slot_index)] = {
        group = group_index,
        slot = slot_index,
        turns_left = group.duration,
        resolved = 0,
        pending = #group.dilemmas > 0,
        traits = {},
    }
end

local function choose_dilemma_option(group_index, slot_index, choice_index)
    local slot = training_state[slot_key(group_index, slot_index)]
    local group = get_training_groups()[group_index]
    if not slot or not slot.pending then
        out("Dark Convent: choice ignored, slot "..slot_key(group_index, slot_index)..(slot and " has no pending decision" or " is not training"))
        return
    end
    local dilemma = group.dilemmas[slot.resolved + 1]
    local choice = dilemma and dilemma.choices[choice_index]
    if not choice then
        out("Dark Convent: choice ignored, no choice "..tostring(choice_index).." in dilemma "..tostring(dilemma and dilemma.key))
        return
    end
    out("Dark Convent: slot "..slot_key(group_index, slot_index).." chose "..choice.key)
    for _, trait in ipairs(choice.traits) do
        table.insert(slot.traits, trait)
    end
    if choice.subtype then
        slot.subtype = choice.subtype
    end
    slot.resolved = slot.resolved + 1
    slot.pending = skip_dilemma_turn_wait and slot.resolved < #group.dilemmas
    try_finish_training(slot)
end

local function advance_training()
    for _, slot in pairs(training_state) do
        local group = get_training_groups()[slot.group]
        slot.turns_left = math.max(slot.turns_left - 1, 0)
        if not slot.pending and slot.resolved < #group.dilemmas then
            slot.pending = true
        end
        try_finish_training(slot)
    end
end

local function send_action(action, group_index, slot_index, choice_index)
    local faction = cm:get_faction(faction_key)
    local trigger = table.concat({action_prefix, action, group_index, slot_index, choice_index or 0}, ":")
    out("Dark Convent: sending "..trigger)
    CampaignUI.TriggerCampaignScriptEvent(faction:command_queue_index(), trigger)
end

local function handle_action(trigger)
    local prefix, action, group_index, slot_index, choice_index = string.match(trigger, "^([%w_]+):(%a+):(%d+):(%d+):(%d+)$")
    if prefix ~= action_prefix then
        return false
    end
    group_index, slot_index, choice_index = tonumber(group_index), tonumber(slot_index), tonumber(choice_index)
    if action == "start" then
        start_training(group_index, slot_index)
    elseif action == "choose" then
        choose_dilemma_option(group_index, slot_index, choice_index)
    end
    return true
end

-- ---- Dark Convent UI ---------------------------------------------------------------------------------------------

local function loc(key, fallback)
    local text = common.get_localised_string(key)
    if not text or text == "" then
        return fallback or key
    end
    return text
end

-- Text belongs to a single state, so set it in every state or a state change brings back the layout's text
local function set_text(uic, text)
    local ok = pcall(function ()
        local current_state = uic:CurrentState()
        for i = 0, uic:NumStates() - 1 do
            uic:SetState(uic:GetStateByIndex(i))
            uic:SetStateText(text, "")
        end
        uic:SetState(current_state)
    end)
    if not ok then
        uic:SetStateText(text, "")
    end
end

-- Index n of the closest ancestor called "<prefix>_<n>"
local function ancestor_index(uic, prefix)
    local current = uic
    for _ = 1, 12 do
        local n = string.match(current:Id(), "^"..prefix.."_(%d+)$")
        if n then
            return tonumber(n)
        end
        local parent = current:Parent()
        if not parent then
            return nil
        end
        current = UIComponent(parent)
    end
end

local function trait_name(trait)
    return loc("character_trait_levels_onscreen_name_"..trait, trait)
end

local function subtype_name(subtype)
    return loc("agent_subtypes_onscreen_name_override_"..subtype, subtype)
end

local function update_selected_slot()
    if selected_slot and training_state[slot_key(selected_slot.group, selected_slot.slot)] then
        return
    end
    selected_slot = nil
    -- Prefer a candidate waiting on a decision, then any candidate in training
    for _, wants_pending in ipairs({true, false}) do
        for _, slot in pairs(training_state) do
            if not wants_pending or slot.pending then
                selected_slot = { group = slot.group, slot = slot.slot }
                return
            end
        end
    end
end

local function refresh_slot_card(card, group, group_index, slot_index, faction)
    local slot = training_state[slot_key(group_index, slot_index)]
    local unlocked = is_slot_unlocked(group, slot_index)

    card:SetVisible(slot_index <= group.max_slots)
    card:SetState(unlocked and "blank" or "locked")

    local holder = find_uicomponent(card, "holder")
    local purchase_holder = find_uicomponent(card, "button_purchase_holder")
    local cost_holder = find_uicomponent(card, "recruitment_cost_holder")
    holder:SetVisible(slot ~= nil)
    purchase_holder:SetVisible(unlocked and slot == nil)
    cost_holder:SetVisible(unlocked and slot == nil)

    if slot then
        local button = find_uicomponent(holder, "button")
        local is_selected = selected_slot and selected_slot.group == group_index and selected_slot.slot == slot_index
        set_text(find_uicomponent(button, "dy_name"), slot.subtype and subtype_name(slot.subtype) or "Candidate")
        set_text(find_uicomponent(button, "dy_time"), tostring(slot.turns_left))
        find_uicomponent(button, "alert"):SetVisible(slot.pending)
        button:SetState(is_selected and "selected" or "active")
        button:SetTooltipText(slot.pending and "A decision awaits||Select this candidate to choose how her training continues." or "In training||This candidate is training in the Dark Convent.", true)
    elseif unlocked then
        local affordable = faction:treasury() >= group.cost
        local cost = find_uicomponent(cost_holder, "recruitment_cost")
        set_text(cost, tostring(group.cost))
        cost:SetState(affordable and "normal" or "red")
        local purchase = find_uicomponent(purchase_holder, "button_purchase")
        purchase:SetState(affordable and "active" or "inactive")
        purchase:SetTooltipText(affordable and "Train a candidate||Send a candidate to the Dark Convent." or "Train a candidate||Not enough gold.", true)
    end
end

local function refresh_dilemma_box(panel)
    local dilemma_holder = find_uicomponent(panel, "panel", "dilemma_holder")
    local active_holder = find_uicomponent(dilemma_holder, "active_dilemma_holder")
    local no_dilemma = find_uicomponent(dilemma_holder, "tx_no_dilemma")

    local slot = selected_slot and training_state[slot_key(selected_slot.group, selected_slot.slot)]
    local group = slot and get_training_groups()[slot.group]
    -- nil (not false) when there's nothing to decide, so the visibility checks below work
    local dilemma = nil
    if slot and group and slot.pending then
        dilemma = group.dilemmas[slot.resolved + 1]
    end

    active_holder:SetVisible(dilemma ~= nil)
    no_dilemma:SetVisible(dilemma == nil)
    if not dilemma then
        local message = "Select a candidate in training to see the decisions she faces."
        if slot and group and slot.resolved >= #group.dilemmas then
            message = "Her training is decided. She will join your forces in "..slot.turns_left.." turn(s)."
        elseif slot then
            message = "She is considering her last lesson. Her next decision comes next turn."
        end
        set_text(no_dilemma, message)
        return
    end

    set_text(find_uicomponent(active_holder, "dy_header"), loc("character_training_dilemmas_localised_title_"..dilemma.key))
    set_text(find_uicomponent(active_holder, "dy_descr"), loc("character_training_dilemmas_localised_description_"..dilemma.key))

    local options_list = find_uicomponent(active_holder, "dilemma_options_list")
    for c = 1, num_choice_rows do
        local row = find_uicomponent(options_list, "choice_"..c)
        local choice = dilemma.choices[c]
        row:SetVisible(choice ~= nil)
        if choice then
            local choice_button = find_uicomponent(row, "choice_button")
            set_text(find_uicomponent(choice_button, "button_txt"), loc("character_training_dilemma_choices_localised_label_"..choice.key))
            choice_button:SetState("active")
            local payload = find_uicomponent(row, "dy_payload")
            local payload_text = choice.subtype and subtype_name(choice.subtype) or (choice.traits[1] and trait_name(choice.traits[1])) or ""
            set_text(payload, payload_text)
            payload:SetVisible(payload_text ~= "")
        end
    end
    options_list:Layout()
end

local function refresh_training_ui()
    local panel = get_panel()
    if not panel or not panel:Visible() then
        return
    end
    local ok, err = pcall(function ()
        local faction = cm:get_faction(faction_key)
        local groups_list = find_uicomponent(panel, "panel", "faction_training_groups")
        update_selected_slot()
        for group_index = 1, groups_list:ChildCount() do
            local group_uic = find_uicomponent(groups_list, "group_"..group_index)
            local group = get_training_groups()[group_index]
            if group_uic then
                group_uic:SetVisible(group ~= nil)
                if group then
                    set_text(find_uicomponent(group_uic, "tx_header"), loc("character_training_groups_localised_name_"..group.key))
                    local slot_list = find_uicomponent(group_uic, "training_slot_list")
                    for slot_index = 1, slot_list:ChildCount() do
                        local card = find_uicomponent(slot_list, "slot_"..slot_index)
                        if card then
                            refresh_slot_card(card, group, group_index, slot_index, faction)
                        end
                    end
                    slot_list:Layout()
                end
            end
        end
        groups_list:Layout()
        refresh_dilemma_box(panel)
    end)
    if not ok then
        out("Dark Convent: error refreshing UI: "..tostring(err))
    end
end

local function get_resource_bar()
    return find_uicomponent(core:get_ui_root(), "hud_campaign", "resources_bar_holder", "resources_bar")
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

local function open_panel()
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
    refresh_training_ui()
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
    give_morathi_convent_trait()

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

    -- ---- Dark Convent training ----

    -- Game state changes: run on every client, from the UI trigger sent by the clicking player
    core:add_listener(
        "corvus_dark_convent_action",
        "UITrigger",
        function (context)
            return string.sub(context:trigger(), 1, #action_prefix + 1) == action_prefix..":"
        end,
        function (context)
            out("Dark Convent: received "..context:trigger())
            handle_action(context:trigger())
            refresh_training_ui()
        end,
        true)

    core:add_listener(
        "corvus_dark_convent_turn_start",
        "FactionTurnStart",
        function (context)
            return context:faction():name() == faction_key
        end,
        function ()
            advance_training()
            refresh_training_ui()
        end,
        true)

    core:add_listener(
        "corvus_dark_convent_recruit_panel_opened",
        "PanelOpenedCampaign",
        function (context)
            return context.string == "character_panel"
        end,
        function ()
            -- Next tick, once the panel's contents exist
            cm:callback(function ()
                local ok, err = pcall(fix_recruit_panel_reason_text)
                if not ok then
                    out("Dark Convent: error fixing recruit panel: "..tostring(err))
                end
            end, 0.1)
        end,
        true)

    core:add_listener(
        "corvus_dark_convent_graduate_recruited",
        "CharacterRecruited",
        function (context)
            return context:character():faction():name() == faction_key
        end,
        function (context)
            local ok, err = pcall(remove_non_convent_traits, context:character())
            if not ok then
                out("Dark Convent: error removing starting traits: "..tostring(err))
            end
        end,
        true)

    core:add_listener(
        "corvus_dark_convent_purchase_clicked",
        "ComponentLClickUp",
        function (context)
            return context.string == "button_purchase" and is_panel_open() and uicomponent_descended_from(UIComponent(context.component), panel_name)
        end,
        function (context)
            local uic = UIComponent(context.component)
            if uic:CurrentState() == "inactive" then
                return
            end
            local group_index, slot_index = ancestor_index(uic, "group"), ancestor_index(uic, "slot")
            if group_index and slot_index then
                send_action("start", group_index, slot_index)
            end
        end,
        true)

    core:add_listener(
        "corvus_dark_convent_slot_selected",
        "ComponentLClickUp",
        function (context)
            return context.string == "button" and is_panel_open() and uicomponent_descended_from(UIComponent(context.component), "faction_training_groups")
        end,
        function (context)
            local uic = UIComponent(context.component)
            local group_index, slot_index = ancestor_index(uic, "group"), ancestor_index(uic, "slot")
            if group_index and slot_index then
                selected_slot = { group = group_index, slot = slot_index }
                refresh_training_ui()
            end
        end,
        true)

    core:add_listener(
        "corvus_dark_convent_choice_clicked",
        "ComponentLClickUp",
        function (context)
            return context.string == "choice_button" and is_panel_open() and uicomponent_descended_from(UIComponent(context.component), panel_name)
        end,
        function (context)
            local choice_index = ancestor_index(UIComponent(context.component), "choice")
            out("Dark Convent: choice "..tostring(choice_index).." clicked, selected slot "..(selected_slot and slot_key(selected_slot.group, selected_slot.slot) or "none"))
            if choice_index and selected_slot then
                send_action("choose", selected_slot.group, selected_slot.slot, choice_index)
            end
        end,
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
