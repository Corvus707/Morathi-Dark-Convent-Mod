-- Dark Convent trait effects that need script.
--
-- Diplomat: while a Diplomat stands in another faction's region, that region's owner slowly warms to Morathi.
-- The goodwill builds up per faction and is applied to them as a custom effect bundle with a relations effect.

local faction_key = "wh2_main_def_cult_of_pleasure"

local diplomat_traits = { "corv_trait_dark_convent_diplomat", "corv_trait_dark_convent_diplomat_hero" }
local relations_bundle_key = "corv_diplomat_relations"
local relations_effect_key = "corv_effect_relations_with_morathi"
local relations_scope = "faction_to_faction_own_unseen"
-- Relations gained per Diplomat per turn spent in another faction's region, and the most one faction can be swayed
local relations_per_turn = 1
local max_relations = 30

-- faction key -> relations built up with that faction
local diplomat_relations = {}

cm:add_saving_game_callback(function (context)
    cm:save_named_value("corvus_dark_convent_diplomat_relations", diplomat_relations, context)
end)

cm:add_loading_game_callback(function (context)
    diplomat_relations = cm:load_named_value("corvus_dark_convent_diplomat_relations", {}, context)
end)

local function is_diplomat(character)
    for _, trait in ipairs(diplomat_traits) do
        if character:has_trait(trait) then
            return true
        end
    end
    return false
end

local function apply_relations(target_faction_key, value)
    local target = cm:get_faction(target_faction_key)
    if not target or target:is_dead() then
        return
    end
    -- Replace the previous bundle so the value doesn't stack
    cm:remove_effect_bundle(relations_bundle_key, target_faction_key)
    local bundle = cm:create_new_custom_effect_bundle(relations_bundle_key)
    bundle:add_effect(relations_effect_key, relations_scope, value)
    bundle:set_duration(0)
    cm:apply_custom_effect_bundle_to_faction(bundle, target)
end

local function update_diplomat_relations(faction)
    local changed = {}
    local characters = faction:character_list()
    for i = 0, characters:num_items() - 1 do
        local character = characters:item_at(i)
        if is_diplomat(character) and character:has_region() then
            local owner = character:region():owning_faction()
            if not owner:is_null_interface() and not owner:is_dead() and owner:name() ~= faction_key then
                local owner_key = owner:name()
                local current = diplomat_relations[owner_key] or 0
                if current < max_relations then
                    diplomat_relations[owner_key] = math.min(max_relations, current + relations_per_turn)
                    changed[owner_key] = true
                end
            end
        end
    end
    for owner_key in pairs(changed) do
        out("Dark Convent: Diplomat relations with "..owner_key.." now "..diplomat_relations[owner_key])
        apply_relations(owner_key, diplomat_relations[owner_key])
    end
end

cm:add_first_tick_callback(function ()
    core:add_listener(
        "corvus_dark_convent_diplomat_turn_start",
        "FactionTurnStart",
        function (context)
            return context:faction():name() == faction_key
        end,
        function (context)
            local ok, err = pcall(update_diplomat_relations, context:faction())
            if not ok then
                out("Dark Convent: error updating Diplomat relations: "..tostring(err))
            end
        end,
        true)
end)
