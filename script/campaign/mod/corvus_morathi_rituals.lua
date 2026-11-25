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
    -- Shadow Walk can only target regions with one of Morathi's cults (db: corv_ritual_target_morathi_cult)
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
    morathi_actions_steal_secrets = { level = 20 },
    morathi_actions_devotee_uprising = { level = 25 },
}

-- Ritual upgrades (Morathi's Court tech tab): Rites of Dominion upgrades every ritual except Morathi's own Shadow Walk,
-- Establish Cult and Cataclysm, which Queen of Whispers upgrades. Each ritual's tooltip lists its upgrade
-- (corvus_morathi_ritual_upgrades).
local upgrade_tech = "corv_morathi_tech_manipulation_6"
local morathi_upgrade_tech = "corv_morathi_tech_morathi_manipulation"
local morathi_upgraded_rituals = {
    morathi_dark_magic_shadow_walk = true,
    morathi_actions_support_cult = true,
    morathi_dark_magic_cataclysm = true,
}

-- Damage as a fraction of each unit's full strength; units never drop below min_unit_strength
local light_damage = 0.1
local heavy_damage = 0.3
local major_damage = 0.4
local min_unit_strength = 0.05
-- Withering Curse: initial damage, then its bundle on the target army (attrition and its drawbacks) for curse_turns
local withering_damage = 0.15
local withering_damage_upgraded = 0.25
local curse_turns = 3
-- Amplify Magic: turns a province stays amplified; armies in it get the bundle, and lose it when they leave
local amplify_turns = 3
local amplify_bundle = "corv_ritual_amplify_magic"
local amplify_bundle_upgraded = "corv_ritual_amplify_magic_upgraded"
-- Shown in the province's effects (display only; db: corvus_morathi_amplify)
local amplify_province_bundle = "corv_ritual_amplify_magic_province"
local amplify_province_bundle_upgraded = "corv_ritual_amplify_magic_province_upgraded"
-- Cataclysm (upgraded): more damage, light attrition on the enemy armies it hits, enemy walls destroyed (breaches, as
-- vanilla's Sayl manipulation) and enemy buildings damaged (health lost, never below the minimum)
local cataclysm_damage_upgraded = 0.45
local cataclysm_attrition_bundle = "corv_ritual_cataclysm_attrition"
local cataclysm_attrition_turns = 3
local cataclysm_wall_breaches = 10
local cataclysm_building_damage = 50
local cataclysm_min_building_health = 10
-- Diplomatic attitude change, -6 to 6 (cm:apply_dilemma_diplomatic_bonus)
local kidnap_relations = -3
local mark_relations = 3
-- Mark (upgraded): the target's faction and each of Morathi's enemies fall out with each other. A vanilla AI diplomatic
-- event: PAST_EVENT_NEGATIVE_MODERATE is -25 relations (cai_personality_diplomatic_event_values)
local mark_enemy_event = "PAST_EVENT_NEGATIVE_MODERATE"
-- Kidnap Slaves (upgraded)
local kidnap_devotees = 100
-- Corruption (upgraded): enough Slaanesh corruption to max out the province (as vanilla's endgame scripts do)
local corruption_max = 100
local slaanesh_corruption = "wh3_main_corruption_slaanesh"
-- Establish Cult (upgraded): the new cult starts with this unique building (db: corvus_morathi_ritual_upgrades)
local sanctum_building = "corv_morathi_cult_unique_sanctum_1"
-- Gift of Slaanesh: the effects of vanilla's gift tag as a character bundle (db: build_morathi_rituals.py)
local gift_bundle = "corv_ritual_gift_of_slaanesh"
local kidnap_slaves = 300
-- Devotee Uprising: in every settlement of the province that isn't Morathi's, garrison damage, wall breaches and a
-- small disciple army of devotees (raised by the cults script: no upkeep, no replenishment, attrition after a few turns)
local uprising_damage = 0.3
local uprising_wall_breaches = 2
local uprising_units = {
    "wh3_dlc27_sla_inf_devotees_of_slaanesh", "wh3_dlc27_sla_inf_devotees_of_slaanesh",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh_crossbows", "wh3_dlc27_sla_inf_devotees_of_slaanesh_crossbows",
}
-- Upgraded: a larger army with a permanent combat bundle
local uprising_units_upgraded = {
    "wh3_dlc27_sla_inf_devotees_of_slaanesh", "wh3_dlc27_sla_inf_devotees_of_slaanesh",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh", "wh3_dlc27_sla_inf_devotees_of_slaanesh",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh", "wh3_dlc27_sla_inf_devotees_of_slaanesh",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh_crossbows", "wh3_dlc27_sla_inf_devotees_of_slaanesh_crossbows",
    "wh3_dlc27_sla_inf_devotees_of_slaanesh_crossbows",
}
local uprising_bundle_upgraded = "corv_ritual_uprising_empowered"
-- Steal Secrets: research for the faction and experience for the performer's army
local steal_secrets_turns = 4
local steal_secrets_research_bundle = "corv_ritual_steal_secrets_research"
local steal_secrets_experience_bundle = "corv_ritual_steal_secrets_experience"
-- Upgraded: research and experience for all of the faction's armies in one faction bundle
local steal_secrets_upgraded_bundle = "corv_ritual_steal_secrets_upgraded"
-- The performer of a Manipulation: the character picked in the panel's character list (sent by the panel script through
-- a UI trigger), or Morathi when none is picked. Experience and turns wounded per ritual
-- (matches PERFORMER in build_morathi_rituals.py).
local performer_trigger_prefix = "corv_morathi_ritual_performer:"
local performer_rewards = {
    morathi_actions_kidnap_slaves = { xp = 500 },
    morathi_actions_druchii_spies = { xp = 500 },
    morathi_actions_easier_seduction = { xp = 1000, wounded = 2 },
    morathi_actions_support_cult = { xp = 1000 },
    morathi_actions_mark = { xp = 2500, wounded = 3 },
    morathi_actions_corruption = { xp = 4000, wounded = 3 },
    morathi_actions_steal_secrets = { xp = 20000 },
    morathi_actions_devotee_uprising = { xp = 7000 },
}
-- Establish Cult also gives Devotees
local establish_cult_devotees = 200
local devotees_resource = "wh3_main_sla_devotees"
local devotees_factor = "cults"
-- Druchii Spies: the target faction's territory stays revealed this many turns
local spies_turns = 5
local slaves_resource = "def_slaves"
local slaves_factor = "missions"

-- Saved: the performer picked in the panel (character cqi), or nil for Morathi
local selected_performer_cqi = nil
-- Saved: factions under Druchii Spies { faction_key = turns left }, and those whose armies are revealed too (upgraded)
local spied_factions = {}
local spied_armies = {}
-- Saved: amplified provinces { province_key = turns left } and the armies that have a bundle { force_cqi = bundle key }
-- (true in older saves: the base bundle)
local amplified_provinces = {}
local amplified_forces = {}

cm:add_saving_game_callback(function (context)
    cm:save_named_value("corvus_morathi_ritual_performer", selected_performer_cqi or 0, context)
    cm:save_named_value("corvus_morathi_ritual_spied_factions", spied_factions, context)
    cm:save_named_value("corvus_morathi_ritual_spied_armies", spied_armies, context)
    cm:save_named_value("corvus_morathi_ritual_amplified_provinces", amplified_provinces, context)
    cm:save_named_value("corvus_morathi_ritual_amplified_forces", amplified_forces, context)
end)

cm:add_loading_game_callback(function (context)
    local performer = cm:load_named_value("corvus_morathi_ritual_performer", 0, context)
    selected_performer_cqi = performer ~= 0 and performer or nil
    spied_factions = cm:load_named_value("corvus_morathi_ritual_spied_factions", {}, context)
    spied_armies = cm:load_named_value("corvus_morathi_ritual_spied_armies", {}, context)
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

-- Reveals every army of the faction (not garrisons) for the given turns
local function reveal_faction_armies(target_key, turns)
    local target = cm:get_faction(target_key)
    if not target or target:is_dead() then
        return false
    end
    local forces = target:military_force_list()
    for i = 0, forces:num_items() - 1 do
        local force = forces:item_at(i)
        if not force:is_armed_citizenry() and force:has_general() then
            pcall(cm.make_character_seen_in_shroud, cm, cm:char_lookup_str(force:general_character()), faction_key, turns)
        end
    end
    return true
end

-- ---- helpers -----------------------------------------------------------------------------------------------------

local function is_upgraded(faction, ritual_key)
    return faction:has_technology(morathi_upgraded_rituals[ritual_key] and morathi_upgrade_tech or upgrade_tech)
end

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

-- Amplify Magic: armies in an amplified province have the bundle; armies that left lose it. Once Rites of Dominion is
-- researched, armies swap to the upgraded bundle.
local function refresh_amplified_armies()
    local wanted = {}
    for province_key in pairs(amplified_provinces) do
        for _, force in ipairs(armies_in_province(province_key)) do
            wanted[tostring(force:command_queue_index())] = true
        end
    end
    local faction = cm:get_faction(faction_key)
    local bundle = (faction and is_upgraded(faction, "morathi_dark_magic_amplify_magic")) and amplify_bundle_upgraded
        or amplify_bundle
    local model = cm:model()
    for cqi, applied in pairs(amplified_forces) do
        local applied_bundle = applied == true and amplify_bundle or applied
        if not wanted[cqi] or applied_bundle ~= bundle then
            if model:has_military_force_command_queue_index(tonumber(cqi)) then
                cm:remove_effect_bundle_from_force(applied_bundle, tonumber(cqi))
            end
            amplified_forces[cqi] = nil
        end
    end
    for cqi in pairs(wanted) do
        if not amplified_forces[cqi] then
            cm:apply_effect_bundle_to_force(bundle, tonumber(cqi), 0)
            amplified_forces[cqi] = bundle
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

-- Daemonic Summoning: units added on vanilla's daemonic_summoning recruitment source get a summon button in the army
-- recruitment panel (like Warriors of Chaos). The unit groups (max counts) are in the db; there is no db pool for
-- Morathi's faction, as that showed up as a second, duplicate button.
local summon_source = "daemonic_summoning"
local summon_groups = {
    wh3_main_sla_inf_daemonette_0 = { group = "corv_morathi_summon_daemonette", max = 10 },
    wh3_main_sla_mon_keeper_of_secrets_0 = { group = "corv_morathi_summon_keeper_of_secrets", max = 4 },
    -- the upgraded summonings' (Exalted Daemonettes, Pleasureseekers)
    wh3_main_sla_inf_daemonette_1 = { group = "corv_morathi_summon_exalted_daemonette", max = 10 },
    wh3_dlc27_sla_cav_pleasureseekers = { group = "corv_morathi_summon_pleasureseekers", max = 4 },
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

local function add_devotees(amount)
    local ok, err = pcall(cm.faction_add_pooled_resource, cm, faction_key, devotees_resource, devotees_factor, amount)
    out("Morathi rituals: adding "..amount.." Devotees"..(ok and "" or (" failed: "..tostring(err))))
end

-- Every building in the settlement loses health, never dropping below the minimum
local function damage_settlement_buildings(region, damage, min_health)
    local slots = region:slot_list()
    for i = 0, slots:num_items() - 1 do
        local slot = slots:item_at(i)
        if slot:has_building() then
            local building = slot:building()
            cm:instant_set_building_health_percent(region:name(), building:name(),
                math.max(min_health, building:percent_health() - damage))
        end
    end
end

-- Puts the building in the first empty slot of the faction's cult in the region; false if there is no cult (yet)
local function add_building_to_cult(region, building)
    local cult = region:foreign_slot_manager_for_faction(faction_key)
    if cult:is_null_interface() then
        return false
    end
    local slots = cult:slots()
    for i = 0, slots:num_items() - 1 do
        local slot = slots:item_at(i)
        if not slot:has_building() then
            cm:foreign_slot_instantly_upgrade_building(slot, building)
            out("Morathi rituals: built "..building.." in the cult in "..region:name())
            return true
        end
    end
    out("Morathi rituals: the cult in "..region:name().." has no empty slot for "..building)
    return true
end

local function apply_to_morathi_force(faction, bundle, turns)
    local cqi = morathi_force_cqi(faction)
    if cqi then
        cm:apply_effect_bundle_to_force(bundle, cqi, turns)
    end
end

-- ---- ritual effects: key -> function(faction, target force, target region, target faction, performer, upgraded) -----
-- upgraded: the faction has the ritual's upgrade tech (see upgrade_tech)

local ritual_effects = {
    -- Damage now, then the curse bundle on the target army: attrition, plus +movement and +physical resistance as the
    -- curse's drawbacks. Upgraded: more damage and +50% attrition casualties.
    morathi_dark_magic_withering_curse = function (_, force, _, _, _, upgraded)
        if force then
            damage_force(force, upgraded and withering_damage_upgraded or withering_damage)
            cm:apply_effect_bundle_to_force(upgraded and "corv_ritual_withering_curse_upgraded" or "corv_ritual_withering_curse",
                force:command_queue_index(), curse_turns)
        end
    end,
    -- Amplifies the target region's province: every army in it (friend or foe) has the spell bonuses while there
    -- (refresh_amplified_armies picks the upgraded bundle). Each region of the province shows it in its effects.
    morathi_dark_magic_amplify_magic = function (_, _, region, _, _, upgraded)
        if region then
            amplified_provinces[region:province_name()] = amplify_turns
            refresh_amplified_armies()
            local display = upgraded and amplify_province_bundle_upgraded or amplify_province_bundle
            for _, r in ipairs(province_regions(region)) do
                cm:remove_effect_bundle_from_region(amplify_province_bundle, r:name())
                cm:remove_effect_bundle_from_region(amplify_province_bundle_upgraded, r:name())
                cm:apply_effect_bundle_to_region(display, r:name(), amplify_turns)
            end
        end
    end,
    -- Upgraded (Queen of Whispers): no Tired/Silenced, +20% movement instead
    morathi_dark_magic_shadow_walk = function (faction, _, region, _, _, upgraded)
        -- The ritual targets any of Morathi's cults (db: corv_ritual_target_morathi_cult)
        local morathi = get_morathi(faction)
        if morathi and region then
            local x, y = cm:find_valid_spawn_location_for_character_from_settlement(faction_key, region:name(), false, true, 5)
            if x and x ~= -1 then
                cm:teleport_to(cm:char_lookup_str(morathi), x, y)
            end
        end
        if upgraded then
            apply_to_morathi_force(faction, "corv_ritual_shadow_walk_upgraded", 2)
        else
            apply_to_morathi_force(faction, "corv_ritual_tired_silenced", 2)
        end
    end,
    -- Upgraded: Exalted Daemonettes instead
    morathi_dark_magic_lesser_summoning = function (faction, force, _, _, _, upgraded)
        add_to_mercenary_pool(faction, upgraded and "wh3_main_sla_inf_daemonette_1" or "wh3_main_sla_inf_daemonette_0", 2)
        damage_force(force, light_damage)
    end,
    -- Upgraded: Active instead of Tired
    morathi_dark_magic_unholy_haste = function (_, force, _, _, _, upgraded)
        if force and force:has_general() then
            cm:replenish_action_points(cm:char_lookup_str(force:general_character()))
            cm:apply_effect_bundle_to_force(upgraded and "corv_ritual_active" or "corv_ritual_tired", force:command_queue_index(), 1)
        end
    end,
    -- Upgraded: also Unspottable, and a slower decay that stops at 50% health
    morathi_dark_magic_veil_of_shadows = function (_, force, _, _, _, upgraded)
        if force then
            cm:apply_effect_bundle_to_force(upgraded and "corv_ritual_veil_of_shadows_upgraded" or "corv_ritual_veil_of_shadows",
                force:command_queue_index(), 2)
        end
    end,
    -- Upgraded: also a Pleasureseekers
    morathi_dark_magic_greater_summoning = function (faction, force, _, _, _, upgraded)
        add_to_mercenary_pool(faction, "wh3_main_sla_mon_keeper_of_secrets_0", 1)
        if upgraded then
            add_to_mercenary_pool(faction, "wh3_dlc27_sla_cav_pleasureseekers", 1)
        end
        damage_force(force, major_damage)
    end,
    -- Upgraded (Queen of Whispers): more damage, light attrition on the armies hit, walls destroyed and buildings damaged
    morathi_dark_magic_cataclysm = function (faction, _, region, _, _, upgraded)
        local damage = upgraded and cataclysm_damage_upgraded or heavy_damage
        if region then
            -- Garrisons (and, upgraded, walls and buildings) of settlements owned by factions at war with Morathi
            for _, r in ipairs(province_regions(region)) do
                if not r:is_abandoned() and r:owning_faction():at_war_with(faction) then
                    local ok, err = pcall(function ()
                        damage_region_garrison(r, damage)
                        if upgraded then
                            breach_walls(r, cataclysm_wall_breaches)
                            damage_settlement_buildings(r, cataclysm_building_damage, cataclysm_min_building_health)
                        end
                    end)
                    if not ok then
                        out("Morathi rituals: Cataclysm failed in "..r:name()..": "..tostring(err))
                    end
                end
            end
            -- and every army in the province at war with Morathi
            local damaged = 0
            for _, force in ipairs(armies_in_province(region:province_name())) do
                if force:faction():at_war_with(faction) then
                    damage_force(force, damage)
                    if upgraded then
                        cm:apply_effect_bundle_to_force(cataclysm_attrition_bundle, force:command_queue_index(),
                            cataclysm_attrition_turns)
                    end
                    damaged = damaged + 1
                end
            end
            out("Morathi rituals: Cataclysm damaged "..damaged.." enemy armies")
        end
        apply_to_morathi_force(faction, "corv_ritual_exhausted", 3)
    end,
    -- Upgraded: also Devotees
    morathi_actions_kidnap_slaves = function (_, _, region, _, _, upgraded)
        add_slaves(kidnap_slaves)
        if upgraded then
            add_devotees(kidnap_devotees)
        end
        if region then
            cm:apply_effect_bundle_to_region("corv_ritual_kidnap_control", region:name(), 3)
            change_relations(region:owning_faction(), kidnap_relations)
        end
    end,
    -- Reveals the target region's owner's territory now and at each of Morathi's turns for spies_turns turns.
    -- Upgraded: their armies too.
    morathi_actions_druchii_spies = function (_, _, region, _, _, upgraded)
        if region and not region:owning_faction():is_null_interface() then
            local target_key = region:owning_faction():name()
            if reveal_faction(target_key) then
                spied_factions[target_key] = spies_turns
                if upgraded and reveal_faction_armies(target_key, spies_turns) then
                    spied_armies[target_key] = spies_turns
                end
                out("Morathi rituals: spying on "..target_key.." for "..spies_turns.." turns"..(upgraded and " (armies too)" or ""))
            end
        end
    end,
    -- The cult itself is founded by the ritual's payload. Upgraded: it starts with Morathi's Sanctum.
    morathi_actions_support_cult = function (_, _, region, _, _, upgraded)
        add_devotees(establish_cult_devotees)
        if upgraded and region then
            if not add_building_to_cult(region, sanctum_building) then
                -- In case the payload's cult isn't there yet when the event fires
                local region_key = region:name()
                cm:callback(function ()
                    if not add_building_to_cult(cm:get_region(region_key), sanctum_building) then
                        out("Morathi rituals: no cult in "..region_key.." for "..sanctum_building)
                    end
                end, 0.5)
            end
        end
    end,
    -- Upgraded: +2 units and -40% cost instead
    morathi_actions_easier_seduction = function (_, force, _, _, _, upgraded)
        if force then
            cm:apply_effect_bundle_to_force(upgraded and "corv_ritual_easier_seduction_upgraded" or "corv_ritual_easier_seduction",
                force:command_queue_index(), 3)
        end
    end,
    -- Gift of Slaanesh on the target lord (permanent, like vanilla's gift): its bundle generates Seductive Influence
    -- over their faction each turn. Upgraded: the target's faction also falls out with every faction at war with Morathi.
    morathi_actions_mark = function (faction, force, _, target_faction, _, upgraded)
        if force and force:has_general() then
            local general = force:general_character()
            out("Morathi rituals: giving the Gift of Slaanesh to "..general:character_subtype_key())
            cm:apply_effect_bundle_to_character(gift_bundle, general, 0)
        else
            out("Morathi rituals: Gift of Slaanesh found no target lord")
        end
        local target = (force and force:faction()) or target_faction
        change_relations(target, mark_relations)
        if upgraded and target and not target:is_null_interface() then
            local factions = cm:model():world():faction_list()
            for i = 0, factions:num_items() - 1 do
                local enemy = factions:item_at(i)
                if not enemy:is_dead() and enemy:name() ~= target:name() and enemy:at_war_with(faction) then
                    pcall(cm.cai_add_diplomatic_event, cm, target:name(), enemy:name(), mark_enemy_event)
                    pcall(cm.cai_add_diplomatic_event, cm, enemy:name(), target:name(), mark_enemy_event)
                end
            end
            out("Morathi rituals: "..target:name().." and Morathi's enemies lose 25 relations with each other")
        end
    end,
    -- Upgraded: Slaanesh corruption in the province to maximum
    morathi_actions_corruption = function (_, _, region, _, _, upgraded)
        if region then
            cm:apply_effect_bundle_to_region("corv_ritual_corruption", region:name(), 5)
            if upgraded then
                cm:change_corruption_in_province_by(region:province_name(), slaanesh_corruption, corruption_max, "events")
            end
        end
    end,
    -- Every settlement of the province that isn't Morathi's (or a ruin): heavy garrison damage, breached walls and a
    -- small disciple army next to it. Upgraded: larger armies with a combat bundle.
    morathi_actions_devotee_uprising = function (_, _, region, _, _, upgraded)
        if not region then
            return
        end
        local raise = corvus_morathi_cults_api and corvus_morathi_cults_api.raise_disciple_army
        if not raise then
            out("Morathi rituals: Devotee Uprising can't raise armies (cults script not loaded)")
        end
        for _, r in ipairs(province_regions(region)) do
            if not r:is_abandoned() and r:owning_faction():name() ~= faction_key then
                local ok, err = pcall(function ()
                    damage_region_garrison(r, uprising_damage)
                    breach_walls(r, uprising_wall_breaches)
                    if raise then
                        if upgraded then
                            raise(r, uprising_units_upgraded, uprising_bundle_upgraded)
                        else
                            raise(r, uprising_units)
                        end
                    end
                end)
                if not ok then
                    out("Morathi rituals: Devotee Uprising failed in "..r:name()..": "..tostring(err))
                end
            end
        end
    end,
    -- Upgraded: the experience bonus goes to every army (one faction bundle) instead of the performer's
    morathi_actions_steal_secrets = function (_, _, _, _, performer, upgraded)
        if upgraded then
            cm:apply_effect_bundle(steal_secrets_upgraded_bundle, faction_key, steal_secrets_turns)
            return
        end
        cm:apply_effect_bundle(steal_secrets_research_bundle, faction_key, steal_secrets_turns)
        if performer and performer:has_military_force() then
            cm:apply_effect_bundle_to_force(steal_secrets_experience_bundle,
                performer:military_force():command_queue_index(), steal_secrets_turns)
        else
            out("Morathi rituals: Steal Secrets' performer has no army")
        end
    end,
}

-- The character picked in the panel, if still one of Morathi's casters and not wounded; otherwise Morathi
local function get_performer(faction)
    if selected_performer_cqi then
        local character = cm:get_character_by_cqi(selected_performer_cqi)
        if character and not character:is_null_interface() and character:faction():name() == faction_key
            and not character:is_wounded() then
            return character
        end
    end
    return get_morathi(faction)
end

local function reward_performer(key, performer)
    local reward = performer_rewards[key]
    if not reward or not performer then
        return
    end
    local lookup = cm:char_lookup_str(performer)
    if reward.xp then
        cm:add_agent_experience(lookup, reward.xp)
    end
    if reward.wounded then
        cm:wound_character(lookup, reward.wounded)
    end
    out("Morathi rituals: performer "..performer:character_subtype_key().." +"..tostring(reward.xp or 0).." xp, wounded "
        ..tostring(reward.wounded or 0).." turns")
end

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
    local faction = cm:get_faction(faction_key)
    local performer = performer_rewards[key] and get_performer(faction)
    local upgraded = is_upgraded(faction, key)
    if upgraded then
        out("Morathi rituals: "..key.." is upgraded")
    end
    effect(faction, force, region, target_faction, performer, upgraded)
    -- After the effect, so a wounded performer's army still gets Steal Secrets' bundle
    reward_performer(key, performer)
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
            -- Druchii Spies: keep the spied factions revealed (and, upgraded, their armies, including new ones)
            for target_key, turns in pairs(spied_factions) do
                if turns > 1 and reveal_faction(target_key) then
                    spied_factions[target_key] = turns - 1
                else
                    spied_factions[target_key] = nil
                end
            end
            for target_key, turns in pairs(spied_armies) do
                if turns > 1 and reveal_faction_armies(target_key, turns - 1) then
                    spied_armies[target_key] = turns - 1
                else
                    spied_armies[target_key] = nil
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
        "corvus_morathi_rituals_performer",
        "UITrigger",
        function (context)
            return string.sub(context:trigger(), 1, #performer_trigger_prefix) == performer_trigger_prefix
        end,
        function (context)
            local cqi = tonumber(string.sub(context:trigger(), #performer_trigger_prefix + 1))
            selected_performer_cqi = cqi ~= 0 and cqi or nil
            out("Morathi rituals: performer is now "..tostring(selected_performer_cqi or "Morathi"))
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
