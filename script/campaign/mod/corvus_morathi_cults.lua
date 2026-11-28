-- Morathi's Cults of Pleasure: her own foreign slot set (corv_morathi_slot_set_cult, 4 slots), founded by the Establish
-- Cult ritual. Each slot takes one building chain from 4 categories: Symbiotic, Parasitic, Utility and Empowerment.
-- Buildings, effects and discoverability are db (morathi_cults.py / build_morathi_rituals.py). This script does what
-- the db can't:
--   * new campaign: cults in starting_cult_regions
--   * Spreading Whispers: each turn, a chance to found a cult in a neighbouring region
--   * Rite of the Disciples (final level): raises a disciple army, corrupts the province and destroys the cult
--   * Ritual of Plunder (final level): loots the settlement, ruins it and corrupts the province
--   * Dark Conduit: Morathi's own extra spell intensity (a custom character bundle)
--   * Dark Elves' resource bar has no Devotees or Manipulation counter, so they are added
--     (corvus_morathi_devotees.twui.xml, corvus_morathi_manipulation.twui.xml: Total/Max like Neferata's)

local faction_key = "wh2_main_def_cult_of_pleasure"
local morathi_subtype = "wh2_main_def_morathi"
local cult_slot_set = "corv_morathi_slot_set_cult"
local slaanesh_corruption = "wh3_main_corruption_slaanesh"

-- Cults Morathi starts a new campaign with, and the building their first slot starts with (nil: empty slots)
local starting_cult_regions = {
    "wh3_main_combi_region_ghrond",
}
local starting_building = nil

-- TESTING: spreading always succeeds (matches CULT_TESTING in morathi_cults.py). Set to false before release.
local testing = false

-- Spreading Whispers
local spread_building = "corv_morathi_cult_util_spread_1"
local spread_chance = testing and 100 or 5             -- % per turn
local spread_chance_corrupted = testing and 100 or 10  -- % per turn while Slaanesh corruption in the province is 50 or more
-- "Queen of Pleasure" (Morathi's Court tech tab) adds to both chances; its effect text shows the same value
local spread_chance_tech = "corv_morathi_tech_morathi_followers"
local spread_chance_tech_bonus = 5

-- Rite of the Disciples
local army_building = "corv_morathi_cult_util_army_2"
local army_units = {
    "wh3_main_sla_inf_daemonette_0", "wh3_main_sla_inf_daemonette_0", "wh3_main_sla_inf_daemonette_0",
    "wh3_main_sla_inf_daemonette_0", "wh3_main_sla_inf_daemonette_0", "wh3_main_sla_inf_daemonette_0",
    "wh2_main_def_inf_witch_elves_0", "wh2_main_def_inf_witch_elves_0", "wh2_main_def_inf_witch_elves_0",
    "wh2_main_def_inf_witch_elves_0",
    "wh3_main_sla_cav_seekers_of_slaanesh_0", "wh3_main_sla_cav_seekers_of_slaanesh_0",
    "wh3_main_sla_mon_fiends_of_slaanesh_0", "wh3_main_sla_mon_fiends_of_slaanesh_0",
    "wh3_main_sla_veh_hellflayer_0", "wh3_main_sla_mon_keeper_of_secrets_0",
}

-- The disciple army: no upkeep and no replenishment from the start, attrition after disciple_attrition_turns turns
local disciple_bundle = "corv_morathi_bundle_cult_disciple_army"
local disciple_fading_bundle = "corv_morathi_bundle_cult_disciple_army_fading"
local disciple_attrition_turns = 3  -- matches DISCIPLE_ATTRITION_TURNS in morathi_cults.py
local disciple_armies_saved_key = "corv_morathi_cult_disciple_armies"  -- "force_cqi:turn_raised;..."

-- Ritual of Plunder
local loot_building = "corv_morathi_cult_util_loot_2"
local loot_gold_per_settlement_level = 1000
local loot_event_title = "event_feed_strings_text_corv_morathi_cult_plunder_title"
local loot_event_detail = "event_feed_strings_text_corv_morathi_cult_plunder_secondary_detail"
local loot_event_index = 126  -- vanilla's cult event picture (the Changeling's cult destroyed message)


-- Both rituals add this much Slaanesh corruption to the province
local ritual_corruption = 100

-- Dark Conduit: Morathi's spell intensity on top of the sorceress bonus the building gives every army
local magic_bundle = "corv_morathi_cult_morathi_magic"
local magic_buildings = {
    corv_morathi_cult_emp_winds_1 = 1,
    corv_morathi_cult_emp_winds_2 = 2,
}

local function log(text)
    out("Morathi cults: "..text)
end

local function safe(name, f, ...)
    local ok, err = pcall(f, ...)
    if not ok then
        log("error in "..name..": "..tostring(err))
    end
end

local function describe_cult(cult)
    local slots = cult:slots()
    local parts = {}
    for i = 0, slots:num_items() - 1 do
        local slot = slots:item_at(i)
        table.insert(parts, slot:has_building() and slot:building() or "empty")
    end
    return cult:region():name().." ["..table.concat(parts, ", ").."]"
end

local function cult_has_building(cult, building)
    local slots = cult:slots()
    for i = 0, slots:num_items() - 1 do
        local slot = slots:item_at(i)
        if slot:has_building() and slot:building() == building then
            return true
        end
    end
    return false
end

local function found_cult(faction, region, notify, building)
    local cult = cm:add_foreign_slot_set_to_region_for_faction(faction:command_queue_index(), region:cqi(), cult_slot_set)
    if building and cult and not cult:is_null_interface() then
        cm:foreign_slot_instantly_upgrade_building(cult:slots():item_at(0), building)
    end
    cm:make_region_visible_in_shroud(faction_key, region:name())
    if notify and faction:is_human() then
        cm:trigger_incident_with_targets(faction:command_queue_index(), "wh3_main_incident_cult_created", 0, 0, 0, 0, region:cqi(), region:settlement():cqi())
    end
    log("founded a cult in "..region:name())
end

local function spawn_starting_cults()
    local faction = cm:get_faction(faction_key)
    if not faction or faction:is_dead() then
        return
    end
    for _, region_key in ipairs(starting_cult_regions) do
        local region = cm:get_region(region_key)
        -- A cult can't sit in her own region or a ruin
        if region and not region:is_abandoned() and region:owning_faction():name() ~= faction_key then
            found_cult(faction, region, true, starting_building)
        else
            log("can't found a starting cult in "..region_key.." (missing, ruined or her own region)")
        end
    end
end

local function is_corrupted(region)
    return cm:get_corruption_value_in_region(region, slaanesh_corruption) >= 50
end

local function add_corruption(region, amount)
    cm:change_corruption_in_province_by(region:province_name(), slaanesh_corruption, amount, "events")
end

local function remove_cult(faction, region)
    cm:remove_faction_foreign_slots_from_region(faction:command_queue_index(), region:cqi())
end

-- ---- Spreading Whispers ----

local function can_host_cult(region)
    return not region:is_null_interface() and not region:is_abandoned()
        and not region:owning_faction():is_null_interface()
        and region:owning_faction():name() ~= faction_key
        and region:foreign_slot_manager_for_faction(faction_key):is_null_interface()
end

local function try_spread(faction, cult)
    local region = cult:region()
    local chance = is_corrupted(region) and spread_chance_corrupted or spread_chance
    if faction:has_technology(spread_chance_tech) then
        chance = chance + spread_chance_tech_bonus
    end
    if not cm:model():random_percent(chance) then
        return
    end
    local targets = {}
    local adjacent = region:adjacent_region_list()
    for i = 0, adjacent:num_items() - 1 do
        local target = adjacent:item_at(i)
        if can_host_cult(target) then
            table.insert(targets, target)
        end
    end
    if #targets == 0 then
        log("cult in "..region:name().." tried to spread but has no neighbour it can spread to")
        return
    end
    local target = targets[cm:random_number(#targets)]
    found_cult(faction, target, true)
    log("cult in "..region:name().." spread to "..target:name())
end

-- ---- Rituals ----

-- Disciple armies waiting for their attrition: { [force_cqi] = turn raised }, saved as "cqi:turn;cqi:turn"
local function load_disciple_armies()
    local armies = {}
    for cqi, turn in string.gmatch(cm:get_saved_value(disciple_armies_saved_key) or "", "(%d+):(%d+)") do
        armies[tonumber(cqi)] = tonumber(turn)
    end
    return armies
end

local function save_disciple_armies(armies)
    local parts = {}
    for cqi, turn in pairs(armies) do
        table.insert(parts, cqi..":"..turn)
    end
    cm:set_saved_value(disciple_armies_saved_key, table.concat(parts, ";"))
end

-- extra_bundle: an optional permanent bundle for the army (the upgraded Devotee Uprising's)
local function raise_disciple_army(region, units, extra_bundle)
    local x, y = cm:find_valid_spawn_location_for_character_from_settlement(faction_key, region:name(), false, true, 5)
    if x == -1 then
        log("no spawn location for the disciple army near "..region:name())
        return
    end
    cm:create_force(faction_key, table.concat(units or army_units, ","), region:name(), x, y, true,
        function (char_cqi, force_cqi)
            cm:apply_effect_bundle_to_force(disciple_bundle, force_cqi, 0)
            if extra_bundle then
                cm:apply_effect_bundle_to_force(extra_bundle, force_cqi, 0)
            end
            local armies = load_disciple_armies()
            armies[force_cqi] = cm:model():turn_number()
            save_disciple_armies(armies)
            log("raised a disciple army (general cqi "..tostring(char_cqi)..", force cqi "..tostring(force_cqi)..") at "..region:name())
        end)
end

-- Shared with the rituals script (Devotee Uprising): a disciple army near the region, with an optional unit list and
-- bundle
corvus_morathi_cults_api = corvus_morathi_cults_api or {}
corvus_morathi_cults_api.raise_disciple_army = raise_disciple_army

-- After disciple_attrition_turns turns, a disciple army's devotion fades and it starts suffering attrition
local function update_disciple_armies()
    local armies = load_disciple_armies()
    local turn = cm:model():turn_number()
    local changed = false
    for cqi, raised in pairs(armies) do
        local force = cm:model():military_force_for_command_queue_index(cqi)
        if not force or force:is_null_interface() then
            armies[cqi] = nil
            changed = true
        elseif turn - raised >= disciple_attrition_turns then
            cm:apply_effect_bundle_to_force(disciple_fading_bundle, cqi, 0)
            armies[cqi] = nil
            changed = true
            log("disciple army (force cqi "..cqi..") now suffers attrition")
        end
    end
    if changed then
        save_disciple_armies(armies)
    end
end

local function perform_army_ritual(faction, region)
    raise_disciple_army(region)
    add_corruption(region, ritual_corruption)
    remove_cult(faction, region)
    log("Rite of the Disciples completed in "..region:name())
end

local function perform_loot_ritual(faction, region)
    local level = 1
    local settlement = region:settlement()
    if not settlement:is_null_interface() and settlement:primary_slot():has_building() then
        level = settlement:primary_slot():building():building_level()
    end
    local gold = loot_gold_per_settlement_level * level
    local x, y = settlement:logical_position_x(), settlement:logical_position_y()
    cm:treasury_mod(faction_key, gold)
    add_corruption(region, ritual_corruption)
    remove_cult(faction, region)
    cm:set_region_abandoned(region:name())
    if faction:is_human() then
        cm:show_message_event_located(faction_key, loot_event_title, "regions_onscreen_"..region:name(), loot_event_detail,
            x, y, true, loot_event_index)
    end
    log("Ritual of Plunder completed in "..region:name()..": looted "..gold.." gold (settlement level "..level..") and ruined it")
end

-- ---- Dark Conduit: Morathi's own spell intensity ----

local function get_morathi(faction)
    local characters = faction:character_list()
    for i = 0, characters:num_items() - 1 do
        local character = characters:item_at(i)
        if character:character_subtype_key() == morathi_subtype then
            return character
        end
    end
end

local function update_morathi_magic(faction)
    local morathi = get_morathi(faction)
    if not morathi then
        return
    end
    local total = 0
    local cults = faction:foreign_slot_managers()
    for i = 0, cults:num_items() - 1 do
        local slots = cults:item_at(i):slots()
        for j = 0, slots:num_items() - 1 do
            local slot = slots:item_at(j)
            if slot:has_building() and magic_buildings[slot:building()] then
                total = total + magic_buildings[slot:building()]
            end
        end
    end
    cm:remove_effect_bundle_from_character(magic_bundle, morathi)
    if total > 0 then
        local bundle = cm:create_new_custom_effect_bundle(magic_bundle)
        bundle:add_effect("wh3_main_effect_spell_mastery", "character_to_character_own", total)
        bundle:set_duration(0)
        cm:apply_custom_effect_bundle_to_character(bundle, morathi)
    end
end

-- ---- Turn start ----

local function update_cults(faction)
    -- Collect first: founding cults while walking the list would change it
    local cults = {}
    local list = faction:foreign_slot_managers()
    for i = 0, list:num_items() - 1 do
        table.insert(cults, list:item_at(i))
    end
    for _, cult in ipairs(cults) do
        cm:make_region_visible_in_shroud(faction_key, cult:region():name())
        if cult_has_building(cult, spread_building) then
            safe("spreading", try_spread, faction, cult)
        end
    end
    safe("Morathi's magic", update_morathi_magic, faction)
    safe("disciple armies", update_disciple_armies)
end

-- ---- Devotees and Manipulation counters on the resource bar ----

local slaves_holder_name = "slave_holder"  -- hud_campaign_resource_bar_default
-- In bar order, each after the one before it (the first after the slaves counter)
local counters = {
    { name = "corvus_morathi_devotees_holder", layout = "ui/campaign ui/corvus_morathi_devotees", label = "Devotees" },
    { name = "corvus_morathi_manipulation_holder", layout = "ui/campaign ui/corvus_morathi_manipulation", label = "Manipulation" },
}

local function child_index(parent, id)
    for i = 0, parent:ChildCount() - 1 do
        if UIComponent(parent:Find(i)):Id() == id then
            return i
        end
    end
end

local function add_resource_counters()
    if cm:get_local_faction_name(true) ~= faction_key then
        return
    end
    local resource_bar = find_uicomponent(core:get_ui_root(), "hud_campaign", "resources_bar_holder", "resources_bar")
    if not resource_bar then
        log("could not find the resource bar")
        return
    end
    local after = slaves_holder_name
    for _, counter in ipairs(counters) do
        if not find_uicomponent(resource_bar, counter.name) then
            local holder = UIComponent(resource_bar:CreateComponent(counter.name, counter.layout))
            holder:SetVisible(true)
            -- The bar lays its children out in order
            local i = child_index(resource_bar, after)
            if i then
                local ok, err = pcall(function () resource_bar:Adopt(holder:Address(), i + 1) end)
                if not ok then
                    log("could not move the "..counter.label.." counter: "..tostring(err))
                end
            end
            log("added the "..counter.label.." counter")
        end
        after = counter.name
    end
    resource_bar:Layout()
end

cm:add_first_tick_callback(function ()
    core:progress_on_loading_screen_dismissed(function ()
        cm:real_callback(function ()
            safe("adding the resource counters", add_resource_counters)
        end, 600, "corvus_morathi_add_resource_counters")
    end)

    if cm:is_new_game() then
        -- A tick later, as vanilla does, so the regions are ready
        cm:callback(function ()
            safe("founding starting cults", spawn_starting_cults)
        end, 0.1)
    end

    core:add_listener(
        "corvus_morathi_cults_turn_start",
        "FactionTurnStart",
        function (context)
            return context:faction():name() == faction_key
        end,
        function (context)
            safe("updating cults", update_cults, context:faction())
        end,
        true)

    core:add_listener(
        "corvus_morathi_cults_building_complete",
        "ForeignSlotBuildingCompleteEvent",
        function (context)
            return context:slot_manager():faction():name() == faction_key
        end,
        function (context)
            local building = context:building()
            local cult = context:slot_manager()
            local faction = cult:faction()
            local region = cult:region()
            log("built "..building.." in "..describe_cult(cult))
            -- A moment later: the rituals remove the cult the event is about
            if building == army_building then
                cm:callback(function () safe("Rite of the Disciples", perform_army_ritual, faction, region) end, 0.1)
            elseif building == loot_building then
                cm:callback(function () safe("Ritual of Plunder", perform_loot_ritual, faction, region) end, 0.1)
            elseif magic_buildings[building] then
                safe("Morathi's magic", update_morathi_magic, faction)
            end
        end,
        true)
end)
