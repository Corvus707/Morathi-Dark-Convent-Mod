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
local attrition_per_turn = 0.03
local attrition_turns = 3
-- Diplomatic attitude change, -6 to 6 (cm:apply_dilemma_diplomatic_bonus)
local kidnap_relations = -3
local mark_relations = 3
-- Gift of Slaanesh: the effects of vanilla's gift tag as a character bundle (db: build_morathi_rituals.py)
local gift_bundle = "corv_ritual_gift_of_slaanesh"
local kidnap_slaves = 300
local slaves_resource = "def_slaves"
local slaves_factor = "missions"

-- Saved: forces under Withering Curse attrition { force_cqi = turns left }
local attrition_forces = {}

cm:add_saving_game_callback(function (context)
    cm:save_named_value("corvus_morathi_ritual_attrition", attrition_forces, context)
end)

cm:add_loading_game_callback(function (context)
    attrition_forces = cm:load_named_value("corvus_morathi_ritual_attrition", {}, context)
end)

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

local function change_relations(target_faction, delta)
    if not target_faction or target_faction:is_null_interface() or target_faction:name() == faction_key then
        return
    end
    out("Morathi rituals: relations with "..target_faction:name().." "..delta)
    cm:apply_dilemma_diplomatic_bonus(faction_key, target_faction:name(), math.max(-6, math.min(6, delta)))
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
    morathi_dark_magic_withering_curse = function (faction, force)
        damage_force(force, light_damage)
        if force then
            attrition_forces[tostring(force:command_queue_index())] = attrition_turns
        end
        apply_to_morathi_force(faction, "corv_ritual_withering_haste", 3)
    end,
    -- Province effect on one of Morathi's regions: her armies across that province get the spell bonuses
    morathi_dark_magic_amplify_magic = function (_, _, region)
        if region then
            cm:apply_effect_bundle_to_region("corv_ritual_amplify_magic", region:name(), 3)
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
        end
        apply_to_morathi_force(faction, "corv_ritual_exhausted", 3)
    end,
    morathi_actions_kidnap_slaves = function (_, _, region)
        add_slaves(kidnap_slaves)
        if region then
            cm:apply_effect_bundle_to_region("corv_ritual_kidnap_growth", region:name(), 3)
            change_relations(region:owning_faction(), kidnap_relations)
        end
    end,
    morathi_actions_druchii_spies = function (_, _, region)
        if region then
            local revealed = province_regions(region)
            local adjacent = region:adjacent_region_list()
            for i = 0, adjacent:num_items() - 1 do
                table.insert(revealed, adjacent:item_at(i))
            end
            for _, r in ipairs(revealed) do
                pcall(cm.make_region_visible_in_shroud, cm, faction_key, r:name())
            end
        end
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
        end
    end,
    -- Not implemented yet: Shelter the Cult, Seduce Lord (their text says so in-game)
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
            -- Withering Curse attrition ticks
            local model = cm:model()
            for cqi, turns in pairs(attrition_forces) do
                local force = model:has_military_force_command_queue_index(tonumber(cqi)) and model:military_force_for_command_queue_index(tonumber(cqi))
                if force and not force:is_null_interface() and turns > 0 then
                    damage_force(force, attrition_per_turn)
                    attrition_forces[cqi] = turns - 1
                else
                    attrition_forces[cqi] = nil
                end
            end
            update_ritual_locks()
        end,
        true)

    core:add_listener(
        "corvus_morathi_rituals_rank_up",
        "CharacterRankUp",
        function (context)
            return context:character():faction():name() == faction_key
        end,
        update_ritual_locks,
        true)
end)
