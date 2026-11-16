-- Morathi's panel rituals (Dark Magic and Seduction pages). The rituals and their effect text are defined in the db
-- (build_morathi_rituals.py); their payloads are display-only, so the effects are applied here when a ritual completes.
-- Level requirements are enforced by locking each ritual until Morathi (or a Sorceress) is high enough level.
-- Values are placeholders.

local faction_key = "wh2_main_def_cult_of_pleasure"
local morathi_subtype = "wh2_main_def_morathi"

-- TESTING: unlock every ritual regardless of level. Set back to false before release.
local skip_level_requirements = true

-- Ritual key -> required level, and whether only Morathi counts (matches build_morathi_rituals.py)
local ritual_requirements = {
    morathi_dark_magic_withering_curse = { level = 1 },
    morathi_dark_magic_amplify_magic = { level = 5 },
    morathi_dark_magic_shadow_walk = { level = 1, morathi_only = true },
    morathi_dark_magic_lesser_summoning = { level = 5 },
    morathi_dark_magic_unholy_haste = { level = 10 },
    morathi_dark_magic_veil_of_shadows = { level = 15 },
    morathi_dark_magic_greater_summoning = { level = 20 },
    morathi_dark_magic_cataclysm = { level = 25, morathi_only = true },
    morathi_actions_kidnap_slaves = { level = 1 },
    morathi_actions_druchii_spies = { level = 1 },
    morathi_actions_easier_seduction = { level = 5 },
    morathi_actions_support_cult = { level = 1, morathi_only = true },
    morathi_actions_mark = { level = 10 },
    morathi_actions_corruption = { level = 15 },
    morathi_actions_seduce_lord = { level = 20 },
    morathi_actions_devotee_uprising = { level = 25 },
}

-- Damage as a fraction of each unit's full strength; units never drop below min_unit_strength
local light_damage = 0.1
local heavy_damage = 0.3
local major_damage = 0.4
local min_unit_strength = 0.05
-- Withering Curse: initial damage, then its bundle on the target army (attrition and its drawbacks) for curse_turns
local withering_damage = 0.15
local curse_turns = 3
-- Amplify Magic: turns a province stays amplified; armies in it get the bundle, and lose it when they leave
local amplify_turns = 3
local amplify_bundle = "corv_ritual_amplify_magic"
-- Diplomatic attitude change, -6 to 6 (cm:apply_dilemma_diplomatic_bonus)
local kidnap_relations = -3
local mark_relations = 3
-- Gift of Slaanesh: the effects of vanilla's gift tag as a character bundle (db: build_morathi_rituals.py)
local gift_bundle = "corv_ritual_gift_of_slaanesh"
local kidnap_slaves = 300
-- Devotee Uprising: wall breaches in every settlement of the province, and a disciple army of devotees (raised by
-- the cults script: no upkeep, no replenishment, attrition after a few turns)
local uprising_wall_breaches = 2
local uprising_units = {
    "wh3_dlc27_sla_inf_devotees_of_slaanesh", "wh3_dlc27_sla_inf_devotees_of_slaanesh",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh", "wh3_dlc27_sla_inf_devotees_of_slaanesh",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh", "wh3_dlc27_sla_inf_devotees_of_slaanesh",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh_crossbows", "wh3_dlc27_sla_inf_devotees_of_slaanesh_crossbows",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh_crossbows", "wh3_dlc27_sla_inf_devotees_of_slaanesh_crossbows",
}
-- Establish Cult also gives Devotees
local establish_cult_devotees = 200
local devotees_resource = "wh3_main_sla_devotees"
local devotees_factor = "cults"
-- Druchii Spies: the target faction's territory stays revealed this many turns
local spies_turns = 5
local slaves_resource = "def_slaves"
local slaves_factor = "missions"

-- Saved: factions under Druchii Spies { faction_key = turns left }
local spied_factions = {}
-- Saved: amplified provinces { province_key = turns left } and the armies that have the bundle { force_cqi = true }
local amplified_provinces = {}
local amplified_forces = {}

cm:add_saving_game_callback(function (context)
    cm:save_named_value("corvus_morathi_ritual_spied_factions", spied_factions, context)
    cm:save_named_value("corvus_morathi_ritual_amplified_provinces", amplified_provinces, context)
    cm:save_named_value("corvus_morathi_ritual_amplified_forces", amplified_forces, context)
end)

cm:add_loading_game_callback(function (context)
    spied_factions = cm:load_named_value("corvus_morathi_ritual_spied_factions", {}, context)
    amplified_provinces = cm:load_named_value("corvus_morathi_ritual_amplified_provinces", {}, context)
    amplified_forces = cm:load_named_value("corvus_morathi_ritual_amplified_forces", {}, context)
end)

-- Reveals every region the faction owns
local function reveal_faction(target_key)
    local target = cm:get_faction(target_key)
    if not target or target:is_dead() then
        return false
    end
    local regions = target:region_list()
    for i = 0, regions:num_items() - 1 do
        pcall(cm.make_region_visible_in_shroud, cm, faction_key, regions:item_at(i):name())
    end
    return true
end

-- ---- helpers -----------------------------------------------------------------------------------------------------

local function get_morathi(faction)
    local characters = faction:character_list()
    for i = 0, characters:num_items() - 1 do
        local character = characters:item_at(i)
        if character:character_subtype_key() == morathi_subtype then
            return character
        end
    end
end

local function morathi_force_cqi(faction)
    local morathi = get_morathi(faction)
    if morathi and morathi:has_military_force() then
        return morathi:military_force():command_queue_index()
    end
end

local function damage_force(force, fraction)
    if not force or force:is_null_interface() then
        return
    end
    local units = force:unit_list()
    for i = 0, units:num_items() - 1 do
        local unit = units:item_at(i)
        local strength = unit:percentage_proportion_of_full_strength() / 100
        cm:set_unit_hp_to_unary_of_maximum(unit, math.max(min_unit_strength, strength - fraction))
    end
end

-- Every region of the target region's province
local function province_regions(region)
    local regions = {}
    local list = region:province():regions()
    for i = 0, list:num_items() - 1 do
        table.insert(regions, list:item_at(i))
    end
    return regions
end

-- A settlement's garrison is an armed-citizenry force of the owner sitting in the settlement.
-- garrison_residence():army() is only a lord's army stationed there, which is damaged too.
local function damage_region_garrison(region, fraction)
    if region:is_abandoned() then
        return
    end
    local residence = region:garrison_residence()
    local forces = region:owning_faction():military_force_list()
    local damaged = 0
    for i = 0, forces:num_items() - 1 do
        local force = forces:item_at(i)
        if force:is_armed_citizenry() and force:has_garrison_residence()
            and force:garrison_residence():region():name() == region:name() then
            damage_force(force, fraction)
            damaged = damaged + 1
        end
    end
    if residence:has_army() then
        damage_force(residence:army(), fraction)
        damaged = damaged + 1
    end
    out("Morathi rituals: damaged "..damaged.." forces in "..region:name())
end

local function damage_province_garrisons(region, fraction)
    for _, r in ipairs(province_regions(region)) do
        local ok, err = pcall(damage_region_garrison, r, fraction)
        if not ok then
            out("Morathi rituals: garrison damage failed in "..r:name()..": "..tostring(err))
        end
    end
end

-- Every army (not garrisons) whose general is in the province
local function armies_in_province(province_key)
    local armies = {}
    local factions = cm:model():world():faction_list()
    for i = 0, factions:num_items() - 1 do
        local forces = factions:item_at(i):military_force_list()
        for j = 0, forces:num_items() - 1 do
            local force = forces:item_at(j)
            if not force:is_armed_citizenry() and force:has_general() then
                local general = force:general_character()
                if general:has_region() and general:region():province_name() == province_key then
                    table.insert(armies, force)
                end
            end
        end
    end
    return armies
end

-- Amplify Magic: armies in an amplified province have the bundle; armies that left lose it
local function refresh_amplified_armies()
    local wanted = {}
    for province_key in pairs(amplified_provinces) do
        for _, force in ipairs(armies_in_province(province_key)) do
            wanted[tostring(force:command_queue_index())] = true
        end
    end
    local model = cm:model()
    for cqi in pairs(amplified_forces) do
        if not wanted[cqi] then
            if model:has_military_force_command_queue_index(tonumber(cqi)) then
                cm:remove_effect_bundle_from_force(amplify_bundle, tonumber(cqi))
            end
            amplified_forces[cqi] = nil
        end
    end
    for cqi in pairs(wanted) do
        if not amplified_forces[cqi] then
            cm:apply_effect_bundle_to_force(amplify_bundle, tonumber(cqi), 0)
            amplified_forces[cqi] = true
        end
    end
end

local function safe_refresh_amplified_armies()
    local ok, err = pcall(refresh_amplified_armies)
    if not ok then
        out("Morathi rituals: error refreshing Amplify Magic: "..tostring(err))
    end
end

-- Wall breaches (as vanilla's Sayl manipulation does it); never repairs walls that are already more damaged
local function breach_walls(region, breaches)
    local settlement = region:settlement()
    if not settlement:is_null_interface() and settlement:is_walled_settlement()
        and settlement:number_of_wall_breaches() < breaches then
        cm:set_settlement_wall_health(settlement, breaches)
    end
end

local function change_relations(target_faction, delta)
    if not target_faction or target_faction:is_null_interface() or target_faction:name() == faction_key then
        return
    end
    out("Morathi rituals: relations with "..target_faction:name().." "..delta)
    cm:apply_dilemma_diplomatic_bonus(faction_key, target_faction:name(), math.max(-6, math.min(6, delta)))
end

-- Seduce Lord: the lord and their army defect to Morathi. Script can't move a character to another faction, so the
-- army is removed and recreated for Morathi with the same lord (subtype and name) and units, at the same place.
-- Faction leaders and legendary lords can't be recreated that way and resist: they only get the Gift of Slaanesh.
local function seduce_lord(force)
    local general = force:general_character()
    if general:is_faction_leader() or general:character_details():is_unique() then
        out("Morathi rituals: "..general:character_subtype_key().." resists Seduce Lord")
        cm:apply_effect_bundle_to_character(gift_bundle, general, 0)
        return
    end
    if not general:has_region() then
        out("Morathi rituals: Seduce Lord can't recreate an army at sea")
        return
    end
    local units = {}
    local unit_list = force:unit_list()
    for i = 0, unit_list:num_items() - 1 do
        local unit = unit_list:item_at(i)
        -- Characters (unit class "com") aren't recreated as units; the general comes with the new force
        if unit:unit_class() ~= "com" then
            table.insert(units, unit:unit_key())
        end
    end
    local subtype, forename, surname = general:character_subtype_key(), general:get_forename(), general:get_surname()
    local region_key = general:region():name()
    local x, y = general:logical_position_x(), general:logical_position_y()
    local old_faction = force:faction()
    cm:kill_character(general:command_queue_index(), true)
    cm:callback(function ()
        local spawn_x, spawn_y = cm:find_valid_spawn_location_for_character_from_position(faction_key, x, y, true)
        if spawn_x == -1 then
            spawn_x, spawn_y = x, y
        end
        cm:create_force_with_general(faction_key, table.concat(units, ","), region_key, spawn_x, spawn_y, "general",
            subtype, forename, "", surname, "", false,
            function (char_cqi)
                local character = cm:get_character_by_cqi(char_cqi)
                if character then
                    cm:apply_effect_bundle_to_character(gift_bundle, character, 0)
                end
                out("Morathi rituals: "..subtype.." seduced with "..#units.." units")
            end)
    end, 0.2)
    change_relations(old_faction, -6)
end

-- Daemonic Summoning: units added on vanilla's daemonic_summoning recruitment source get a summon button in the army
-- recruitment panel (like Warriors of Chaos). The unit groups (max counts) are in the db; there is no db pool for
-- Morathi's faction, as that showed up as a second, duplicate button.
local summon_source = "daemonic_summoning"
local summon_groups = {
    wh3_main_sla_inf_daemonette_0 = { group = "corv_morathi_summon_daemonette", max = 10 },
    wh3_main_sla_mon_keeper_of_secrets_0 = { group = "corv_morathi_summon_keeper_of_secrets", max = 4 },
}

local function add_to_mercenary_pool(faction, unit_key, count)
    local summon = summon_groups[unit_key]
    local ok, err = pcall(function ()
        cm:add_unit_to_faction_mercenary_pool(faction, unit_key, summon_source, count, 0, summon.max, 0, "", "", "", false, summon.group)
    end)
    out("Morathi rituals: adding "..count.." "..unit_key.." to Daemonic Summoning"..(ok and "" or (" failed: "..tostring(err))))
end

local function add_slaves(amount)
    local ok, err = pcall(cm.faction_add_pooled_resource, cm, faction_key, slaves_resource, slaves_factor, amount)
    out("Morathi rituals: adding "..amount.." slaves"..(ok and "" or (" failed: "..tostring(err))))
end

local function apply_to_morathi_force(faction, bundle, turns)
    local cqi = morathi_force_cqi(faction)
    if cqi then
        cm:apply_effect_bundle_to_force(bundle, cqi, turns)
    end
end

-- ---- ritual effects: key -> function(faction, target force, target region, target faction) ---------------------------

local ritual_effects = {
    -- Damage now, then the curse bundle on the target army: attrition, plus +movement and +physical resistance as the
    -- curse's drawbacks
    morathi_dark_magic_withering_curse = function (_, force)
        if force then
            damage_force(force, withering_damage)
            cm:apply_effect_bundle_to_force("corv_ritual_withering_curse", force:command_queue_index(), curse_turns)
        end
    end,
    -- Amplifies the target region's province: every army in it (friend or foe) has the spell bonuses while there
    morathi_dark_magic_amplify_magic = function (_, _, region)
        if region then
            amplified_provinces[region:province_name()] = amplify_turns
            refresh_amplified_armies()
        end
    end,
    morathi_dark_magic_shadow_walk = function (faction, _, region)
        local morathi = get_morathi(faction)
        if morathi and region then
            local x, y = cm:find_valid_spawn_location_for_character_from_settlement(faction_key, region:name(), false, true, 5)
            if x and x ~= -1 then
                cm:teleport_to(cm:char_lookup_str(morathi), x, y)
            end
        end
        apply_to_morathi_force(faction, "corv_ritual_tired_silenced", 2)
    end,
    morathi_dark_magic_lesser_summoning = function (faction, force)
        add_to_mercenary_pool(faction, "wh3_main_sla_inf_daemonette_0", 2)
        damage_force(force, light_damage)
    end,
    morathi_dark_magic_unholy_haste = function (_, force)
        if force and force:has_general() then
            cm:replenish_action_points(cm:char_lookup_str(force:general_character()))
            cm:apply_effect_bundle_to_force("corv_ritual_tired", force:command_queue_index(), 1)
        end
    end,
    morathi_dark_magic_veil_of_shadows = function (_, force)
        if force then
            cm:apply_effect_bundle_to_force("corv_ritual_veil_of_shadows", force:command_queue_index(), 2)
        end
    end,
    morathi_dark_magic_greater_summoning = function (faction, force)
        add_to_mercenary_pool(faction, "wh3_main_sla_mon_keeper_of_secrets_0", 1)
        damage_force(force, major_damage)
    end,
    morathi_dark_magic_cataclysm = function (faction, _, region)
        if region then
            damage_province_garrisons(region, heavy_damage)
            -- and every army in the province at war with Morathi
            local damaged = 0
            for _, force in ipairs(armies_in_province(region:province_name())) do
                if force:faction():at_war_with(faction) then
                    damage_force(force, heavy_damage)
                    damaged = damaged + 1
                end
            end
            out("Morathi rituals: Cataclysm damaged "..damaged.." enemy armies")
        end
        apply_to_morathi_force(faction, "corv_ritual_exhausted", 3)
    end,
    morathi_actions_kidnap_slaves = function (_, _, region)
        add_slaves(kidnap_slaves)
        if region then
            cm:apply_effect_bundle_to_region("corv_ritual_kidnap_control", region:name(), 3)
            change_relations(region:owning_faction(), kidnap_relations)
        end
    end,
    -- Reveals the target region's owner's territory now and at each of Morathi's turns for spies_turns turns
    morathi_actions_druchii_spies = function (_, _, region)
        if region and not region:owning_faction():is_null_interface() then
            local target_key = region:owning_faction():name()
            if reveal_faction(target_key) then
                spied_factions[target_key] = spies_turns
                out("Morathi rituals: spying on "..target_key.." for "..spies_turns.." turns")
            end
        end
    end,
    -- The cult itself is founded by the ritual's payload
    morathi_actions_support_cult = function ()
        local ok, err = pcall(cm.faction_add_pooled_resource, cm, faction_key, devotees_resource, devotees_factor, establish_cult_devotees)
        out("Morathi rituals: adding "..establish_cult_devotees.." Devotees"..(ok and "" or (" failed: "..tostring(err))))
    end,
    morathi_actions_easier_seduction = function (_, force)
        if force then
            cm:apply_effect_bundle_to_force("corv_ritual_easier_seduction", force:command_queue_index(), 3)
        end
    end,
    -- Gift of Slaanesh on the target lord (permanent, like vanilla's gift): its bundle generates Seductive Influence
    -- over their faction each turn
    morathi_actions_mark = function (_, force, _, target_faction)
        if force and force:has_general() then
            local general = force:general_character()
            out("Morathi rituals: giving the Gift of Slaanesh to "..general:character_subtype_key())
            cm:apply_effect_bundle_to_character(gift_bundle, general, 0)
        else
            out("Morathi rituals: Gift of Slaanesh found no target lord")
        end
        change_relations((force and force:faction()) or target_faction, mark_relations)
    end,
    morathi_actions_corruption = function (_, _, region)
        if region then
            cm:apply_effect_bundle_to_region("corv_ritual_corruption", region:name(), 5)
        end
    end,
    morathi_actions_devotee_uprising = function (_, _, region)
        if region then
            damage_province_garrisons(region, light_damage)
            for _, r in ipairs(province_regions(region)) do
                local ok, err = pcall(breach_walls, r, uprising_wall_breaches)
                if not ok then
                    out("Morathi rituals: breaching walls failed in "..r:name()..": "..tostring(err))
                end
            end
            if corvus_morathi_cults_api and corvus_morathi_cults_api.raise_disciple_army then
                corvus_morathi_cults_api.raise_disciple_army(region, uprising_units)
            else
                out("Morathi rituals: Devotee Uprising can't raise an army (cults script not loaded)")
            end
        end
    end,
    morathi_actions_seduce_lord = function (_, force)
        if force and force:has_general() then
            seduce_lord(force)
        else
            out("Morathi rituals: Seduce Lord found no target lord")
        end
    end,
}

local function on_ritual_completed(context)
    local ritual = context:ritual()
    local key = ritual:ritual_key()
    local effect = ritual_effects[key]
    if not ritual_requirements[key] then
        return
    end
    out("Morathi rituals: "..key.." completed")
    if not effect then
        out("Morathi rituals: "..key.." has no scripted effect yet")
        return
    end
    local target = ritual:ritual_target()
    local function valid(getter)
        local ok, value = pcall(getter)
        if ok and value and not value:is_null_interface() then
            return value
        end
    end
    local force = valid(function () return target:get_target_force() end)
    if not force then
        -- Army targets can come through as the commanding character
        local character = valid(function () return target:get_target_character() end)
        if character and character:has_military_force() then
            force = character:military_force()
        end
    end
    local region = valid(function () return target:get_target_region() end)
    local target_faction = valid(function () return target:get_target_faction() end)
    out("Morathi rituals: target force "..tostring(force and force:command_queue_index())..", region "..tostring(region and region:name())
        ..", faction "..tostring(target_faction and target_faction:name()))
    effect(cm:get_faction(faction_key), force, region, target_faction)
end

-- ---- level requirements --------------------------------------------------------------------------------------------

-- ritual key -> true when unlocked, so locks are only changed when they need to be
local unlocked = {}

-- Morathi and Sorceress heroes (vanilla and Dark Convent), the same characters the panel lists
local function is_caster(character)
    local subtype = character:character_subtype_key()
    return subtype == morathi_subtype or (character:character_type_key() == "wizard" and string.match(subtype, "sorceress") ~= nil)
end

local function update_ritual_locks()
    local faction = cm:get_faction(faction_key)
    if not faction or faction:is_dead() then
        return
    end
    local morathi_rank, caster_rank = 0, 0
    local characters = faction:character_list()
    for i = 0, characters:num_items() - 1 do
        local character = characters:item_at(i)
        if is_caster(character) then
            caster_rank = math.max(caster_rank, character:rank())
            if character:character_subtype_key() == morathi_subtype then
                morathi_rank = character:rank()
            end
        end
    end
    for key, requirement in pairs(ritual_requirements) do
        local rank = requirement.morathi_only and morathi_rank or caster_rank
        local should_unlock = skip_level_requirements or rank >= requirement.level
        if unlocked[key] ~= should_unlock then
            unlocked[key] = should_unlock
            if should_unlock then
                cm:unlock_ritual(faction, key, 0)
            else
                cm:lock_ritual(faction, key)
            end
        end
    end
end

-- ---- listeners -----------------------------------------------------------------------------------------------------

cm:add_first_tick_callback(function ()
    update_ritual_locks()

    core:add_listener(
        "corvus_morathi_rituals_completed",
        "RitualCompletedEvent",
        function (context)
            return context:performing_faction():name() == faction_key
        end,
        function (context)
            local ok, err = pcall(on_ritual_completed, context)
            if not ok then
                out("Morathi rituals: error applying ritual: "..tostring(err))
            end
        end,
        true)

    core:add_listener(
        "corvus_morathi_rituals_turn_start",
        "FactionTurnStart",
        function (context)
            return context:faction():name() == faction_key
        end,
        function ()
            -- Amplify Magic: count down the amplified provinces
            for province_key, turns in pairs(amplified_provinces) do
                amplified_provinces[province_key] = turns > 1 and turns - 1 or nil
            end
            safe_refresh_amplified_armies()
            -- Druchii Spies: keep the spied factions revealed
            for target_key, turns in pairs(spied_factions) do
                if turns > 1 and reveal_faction(target_key) then
                    spied_factions[target_key] = turns - 1
                else
                    spied_factions[target_key] = nil
                end
            end
            update_ritual_locks()
        end,
        true)

    -- Amplify Magic follows the armies: refresh whenever a general stops moving or any faction's turn starts
    for _, event in ipairs({ "CharacterFinishedMovingEvent", "FactionTurnStart" }) do
        core:add_listener(
            "corvus_morathi_rituals_amplify_"..event,
            event,
            function ()
                return next(amplified_provinces) ~= nil or next(amplified_forces) ~= nil
            end,
            safe_refresh_amplified_armies,
            true)
    end

    core:add_listener(
        "corvus_morathi_rituals_rank_up",
        "CharacterRankUp",
        function (context)
            return context:character():faction():name() == faction_key
        end,
        update_ritual_locks,
        true)
end)
