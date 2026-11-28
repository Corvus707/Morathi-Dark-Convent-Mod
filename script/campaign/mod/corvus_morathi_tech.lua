-- Morathi's Court tech tab: the effects the db can't give through a technology (db: corvus_morathi_tech_script).
--   * Mastery of Death: "Unsettling Radiance" (Elspeth's skill: -25% battle healing cap for enemy armies in the region)
--     on every Sorceress and Supreme Sorceress of Death, as a character bundle
--   * Pleasure and Pain United: its Pain and Pleasure auras as a faction bundle (keeps unit portraits out of the tech
--     tooltip)
--   * Willing Thralls: allies and vassals spread Slaanesh corruption and their armies gain physical resistance, as a
--     bundle on each of those factions (like Azazel's and Sigvald's vassals, which vanilla handles in the engine)
--   * TESTING: Seductive Influence's Dominate ritual is free with no cooldown

local faction_key = "wh2_main_def_cult_of_pleasure"

-- TESTING: Dominate costs no Devotees and has no cooldown. Set to false before release (1000 Devotees, 10 turns).
local free_dominate = false
local free_dominate_bundle = "corv_testing_free_dominate"

local unsettling_radiance_tech = "corv_morathi_tech_magic_death"
local unsettling_radiance_bundle = "corv_tech_unsettling_radiance"

-- Pleasure and Pain United: the Pain and Pleasure auras come from a faction bundle rather than the tech, so the tech
-- tooltip doesn't list every unit (db: corvus_morathi_tech_abilities)
local tech_bundles = {
    corv_morathi_tech_followers_passive = "corv_tech_pleasure_and_pain_united",
}

-- Willing Thralls: every ally and vassal of Morathi's faction has this bundle while the tech is researched
-- (+4 Slaanesh corruption in each province it owns, +5% physical resistance for its armies)
local thralls_tech = "corv_morathi_tech_followers_vassals"
local thralls_bundle = "corv_tech_willing_thralls"

local function log(text)
    out("Morathi tech: "..text)
end

-- Gives the bundle to the factions that are allies or vassals now, and takes it from the ones that no longer are (or
-- every faction, if Morathi's faction is gone or hasn't the tech)
local function update_thralls()
    local faction = cm:get_faction(faction_key)
    local active = faction and not faction:is_dead() and faction:has_technology(thralls_tech)
    local factions = cm:model():world():faction_list()
    for i = 0, factions:num_items() - 1 do
        local other = factions:item_at(i)
        if other:name() ~= faction_key then
            local qualifies = active and not other:is_dead() and other:is_ally_vassal_or_client_state_of(faction)
            local has_bundle = other:has_effect_bundle(thralls_bundle)
            if qualifies and not has_bundle then
                cm:apply_effect_bundle(thralls_bundle, other:name(), 0)
                log(other:name().." is now one of Morathi's Willing Thralls")
            elseif has_bundle and not qualifies then
                cm:remove_effect_bundle(thralls_bundle, other:name())
                log(other:name().." is no longer one of Morathi's Willing Thralls")
            end
        end
    end
end

-- Vanilla, Dark Convent and Supreme Sorceresses of Death
local function is_death_sorceress(character)
    return string.find(character:character_subtype_key(), "sorceress_death") ~= nil
end

local function update_unsettling_radiance()
    local faction = cm:get_faction(faction_key)
    if not faction or faction:is_dead() or not faction:has_technology(unsettling_radiance_tech) then
        return
    end
    local characters = faction:character_list()
    for i = 0, characters:num_items() - 1 do
        local character = characters:item_at(i)
        if is_death_sorceress(character) and not character:has_effect_bundle(unsettling_radiance_bundle) then
            cm:apply_effect_bundle_to_character(unsettling_radiance_bundle, character, 0)
            log("Unsettling Radiance for "..character:character_subtype_key().." (cqi "..character:command_queue_index()..")")
        end
    end
end

local function update_tech_bundles()
    local faction = cm:get_faction(faction_key)
    if not faction or faction:is_dead() then
        return
    end
    for tech, bundle in pairs(tech_bundles) do
        if faction:has_technology(tech) and not faction:has_effect_bundle(bundle) then
            cm:apply_effect_bundle(bundle, faction_key, 0)
            log("applied "..bundle.." for "..tech)
        end
    end
end

local function update_free_dominate()
    local faction = cm:get_faction(faction_key)
    if not faction or faction:is_dead() then
        return
    end
    if free_dominate and not faction:has_effect_bundle(free_dominate_bundle) then
        cm:apply_effect_bundle(free_dominate_bundle, faction_key, 0)
    elseif not free_dominate and faction:has_effect_bundle(free_dominate_bundle) then
        cm:remove_effect_bundle(free_dominate_bundle, faction_key)
    end
end

local function safe(name, f)
    return function ()
        local ok, err = pcall(f)
        if not ok then
            log("error in "..name..": "..tostring(err))
        end
    end
end

cm:add_first_tick_callback(function ()
    safe("free_dominate", update_free_dominate)()
    safe("unsettling_radiance", update_unsettling_radiance)()
    safe("tech_bundles", update_tech_bundles)()

    core:add_listener(
        "corvus_morathi_tech_bundles",
        "ResearchCompleted",
        function (context)
            return context:faction():name() == faction_key
        end,
        safe("tech_bundles", update_tech_bundles),
        true)

    -- New Sorceresses of Death (recruited, from the Dark Convent, or spawned) are caught at turn start at the latest
    core:add_listener(
        "corvus_morathi_tech_turn_start",
        "FactionTurnStart",
        function (context)
            return context:faction():name() == faction_key
        end,
        safe("unsettling_radiance", update_unsettling_radiance),
        true)

    core:add_listener(
        "corvus_morathi_tech_research",
        "ResearchCompleted",
        function (context)
            return context:faction():name() == faction_key
        end,
        safe("unsettling_radiance", update_unsettling_radiance),
        true)

    core:add_listener(
        "corvus_morathi_tech_recruited",
        "CharacterRecruited",
        function (context)
            return context:character():faction():name() == faction_key
        end,
        safe("unsettling_radiance", update_unsettling_radiance),
        true)

    -- Willing Thralls: checked when the tech is researched, at the start of Morathi's turn, and whenever a faction
    -- becomes a vassal or an alliance is made or broken
    safe("thralls", update_thralls)()
    for _, event in ipairs({ "ResearchCompleted", "FactionTurnStart", "FactionBecomesVassal",
                             "PositiveDiplomaticEvent", "NegativeDiplomaticEvent" }) do
        core:add_listener(
            "corvus_morathi_tech_thralls_"..event,
            event,
            function (context)
                if event == "ResearchCompleted" or event == "FactionTurnStart" then
                    return context:faction():name() == faction_key
                elseif event == "FactionBecomesVassal" then
                    return true
                end
                return context:proposer():name() == faction_key or context:recipient():name() == faction_key
            end,
            safe("thralls", update_thralls),
            true)
    end
end)
